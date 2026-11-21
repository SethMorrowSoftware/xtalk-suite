cmake_minimum_required(VERSION 3.22)
project(oscxt LANGUAGES C)

# ---------------------------------------------------------------------------
# oscxt - Open Sound Control for OpenXTalk (OXT) and the xTalk family, also
# compatible with LiveCode 9.6.3+. The C shim (src/osc_shim.c) over the
# vendored tinyosc (ISC) is built into ONE loadable library named "oscxt":
#
#   oscxt.so (Linux, Android) / oscxt.dylib (macOS) / oscxt.dll (Windows)
#
# bundled inside the extension under src/code/<arch>-<platform>/, so the engine
# resolves the binding's "c:oscxt>" foreign handlers through the
# revLibraryMapping. Transport is the script's own UDP sockets: this library
# only builds and parses bytes, and never starts a thread.
#
# ShowControl's top-level CMakeLists.txt is this file's ancestor (its osc half).
#
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DOSCXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --build-config Release --output-on-failure
# ---------------------------------------------------------------------------

option(OSCXT_BUILD_TESTS "Build the C smoke, vectors and fuzz tests" OFF)
set(OSCXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# The Windows library carries the C runtime (static CRT): a PC without the
# Visual C++ Redistributable loads it. Nothing it allocates is freed by the
# engine (every buffer is caller-owned), so a private CRT is safe.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Hidden by default in every object, tinyosc's included: only OSC_API symbols
# leave the library.
set(CMAKE_C_VISIBILITY_PRESET hidden)

if(OSCXT_SANITIZE STREQUAL "address")
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# ---------------------------------------------------------------------------
# The library: our shim + vendored tinyosc, under its BARE name (no "lib"),
# which is the name the tree holds on every platform and, on Linux, the
# soname the engine's dlopen asks for.
# ---------------------------------------------------------------------------
add_library(oscxt SHARED
    src/osc_shim.c
    src/third_party/tinyosc/tinyosc.c)
target_include_directories(oscxt PRIVATE src src/third_party/tinyosc)

# tinyosc's <endian.h> use (htobe64/be64toh) needs a feature-test macro on
# glibc; without it the build fails with "implicit declaration".
target_compile_definitions(oscxt PRIVATE _DEFAULT_SOURCE)

set_target_properties(oscxt PROPERTIES
    C_STANDARD 17
    C_STANDARD_REQUIRED ON
    OUTPUT_NAME "oscxt"
    PREFIX "")

# tinyosc uses ntohl/htonl; on Windows those live in ws2_32.
if(WIN32)
    target_link_libraries(oscxt PRIVATE ws2_32)
endif()

# Keep our shim warning-clean; tinyosc's own (vendored) warnings are not ours
# to fix and must never fail or bury this build (box2dxt's lesson).
if(MSVC)
    target_compile_options(oscxt PRIVATE /W3)
    target_compile_definitions(oscxt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(oscxt PRIVATE -Wall -Wextra)
    set_source_files_properties(src/third_party/tinyosc/tinyosc.c PROPERTIES COMPILE_OPTIONS "-w")
endif()

# Export osc_* and nothing else (the family's rule since enetxt's release run
# 10 leaked a vendored library's symbols: the script, not the default,
# decides). src/oscxt.map is the one source for GNU ld and, by the pattern
# below, for ld64.
set(_osc_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/oscxt.map")
if(APPLE)
    set(_osc_exported "${CMAKE_CURRENT_BINARY_DIR}/oscxt.exported_symbols")
    file(WRITE "${_osc_exported}" "_osc_*\n")
    target_link_options(oscxt PRIVATE "-Wl,-exported_symbols_list,${_osc_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_osc_version_script}" OSC_HAVE_VERSION_SCRIPT)
    if(OSC_HAVE_VERSION_SCRIPT)
        target_link_options(oscxt PRIVATE "-Wl,--version-script=${_osc_version_script}")
        set_target_properties(oscxt PROPERTIES LINK_DEPENDS "${_osc_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The tests. Each links the shared library and reaches it only through its
# exports, as the engine does.
#   osc_smoke    every export, the caller-buffer contract, error paths
#   osc_vectors  the shared wire-format vectors (tests/vectors/osc.json,
#                projected into tests/vectors/vectors.h by tools/gen_vectors.py)
#   osc_fuzz     a deterministic mutation fuzzer over osc_parse and every
#                getter, seeded from the vectors (under the sanitizer build
#                every iteration is ASan/UBSan-checked; the coverage-guided
#                libFuzzer build of the same file runs in native-oscxt.yml)
# ---------------------------------------------------------------------------
if(OSCXT_BUILD_TESTS)
    enable_testing()
    find_package(Threads REQUIRED)     # osc_smoke runs its deep-pattern check on a small-stack thread
    foreach(_test smoke vectors)
        add_executable(osc_${_test} tests/osc_${_test}_test.c)
        target_include_directories(osc_${_test} PRIVATE src tests)
        set_target_properties(osc_${_test} PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
        target_link_libraries(osc_${_test} PRIVATE oscxt Threads::Threads)
        if(MSVC)
            target_compile_definitions(osc_${_test} PRIVATE _CRT_SECURE_NO_WARNINGS)
        else()
            target_link_libraries(osc_${_test} PRIVATE m)
        endif()
        add_test(NAME osc_${_test} COMMAND osc_${_test})
    endforeach()
    add_executable(osc_fuzz tests/fuzz/osc_fuzz.c)
    target_include_directories(osc_fuzz PRIVATE src tests)
    set_target_properties(osc_fuzz PROPERTIES C_STANDARD 17 C_STANDARD_REQUIRED ON)
    target_link_libraries(osc_fuzz PRIVATE oscxt)
    if(MSVC)
        target_compile_definitions(osc_fuzz PRIVATE _CRT_SECURE_NO_WARNINGS)
    endif()
    add_test(NAME osc_fuzz COMMAND osc_fuzz 100000 1)
endif()
