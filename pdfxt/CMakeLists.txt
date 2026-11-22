cmake_minimum_required(VERSION 3.22)
project(pdfxt LANGUAGES C)

# ---------------------------------------------------------------------------
# pdfxt - PDFium (the PDF engine of Chromium) for OpenXTalk (OXT) and the
# xTalk family, also compatible with LiveCode 9.6.3+. This builds the C shim
# (src/pdfium_shim.c) into a loadable library named "pdfxt" and puts the
# PINNED PREBUILT PDFium beside it under its bare name: TWO files a platform,
#
#     pdfxt.so   + pdfium.so        (Linux, Android)
#     pdfxt.dll  + pdfium.dll       (Windows)
#     pdfxt.dylib + pdfium.dylib    (macOS)
#
# WHY PREBUILT. PDFium has no CMake build: it builds with Google's gn inside
# a depot_tools checkout of several gigabytes, about an hour a platform. The
# suite's release run builds every member on every platform, so a source
# build would add hours to each run for a library nobody here changes.
# bblanchon/pdfium-binaries builds exactly that tree for every platform the
# suite ships, publishes each archive with its args.gn and licences, and is
# what most PDFium bindings ship. Each archive is pinned below by SHA-256, so
# what is compiled against and shipped is one known file, never "latest".
#
# WHAT THAT COSTS, said here and in README.md:
#   - two files a platform, the second loaded by the shim at run time from
#     its own folder (src/pdfium_shim.c says how and why);
#   - the floors are PDFium's builders', not the suite's: macOS 13 (the
#     suite builds for 10.15), Android 6.0 / API 23 (the suite: API 21),
#     glibc 2.16 on Linux (below the suite's 2.28, so no loss there);
#   - no web build: the archive's WebAssembly is a whole Emscripten program,
#     not an object the web engine could link.
# ---------------------------------------------------------------------------

option(PDFXT_BUILD_TESTS "Build the pdfxt runtime smoke test" OFF)
set(PDFXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")
set(PDFXT_PDFIUM_DIR "" CACHE PATH
    "An UNPACKED pdfium-binaries archive of the pinned release (include/, lib/ or bin/): builds with no network")

if(EMSCRIPTEN)
    message(FATAL_ERROR "pdfxt has no web build: the pinned PDFium ships no linkable WebAssembly object")
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# The Windows library carries the C runtime (static CRT, as the family's do).
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(PDFXT_SANITIZE STREQUAL "address")
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# ---------------------------------------------------------------------------
# THE PIN is src/pdfium.pin: one release of bblanchon/pdfium-binaries, and for
# each platform the SHA-256 of its archive and of the library inside it. Read
# here, so this file holds no hash of its own to drift from it.
# ---------------------------------------------------------------------------
set(_pdx_pin_file "${CMAKE_CURRENT_SOURCE_DIR}/src/pdfium.pin")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_pdx_pin_file}")
file(STRINGS "${_pdx_pin_file}" _pdx_pin_lines REGEX "^[a-z]")
set(PDFXT_PDFIUM_RELEASE "")
foreach(_line IN LISTS _pdx_pin_lines)
    if(_line MATCHES "^release +([A-Za-z0-9/._-]+) *$")
        set(PDFXT_PDFIUM_RELEASE "${CMAKE_MATCH_1}")
    elseif(_line MATCHES "^([a-z0-9_-]+) +([a-z0-9-]+) +([0-9a-f]+) +([0-9a-f]+) *$")
        string(LENGTH "${CMAKE_MATCH_3}" _pdx_len3)
        string(LENGTH "${CMAKE_MATCH_4}" _pdx_len4)
        if(NOT _pdx_len3 EQUAL 64 OR NOT _pdx_len4 EQUAL 64)
            message(FATAL_ERROR "pdfxt: src/pdfium.pin: a hash that is not 64 hex digits: ${_line}")
        endif()
        set(PDFXT_PDFIUM_ARCHIVE_SHA256_${CMAKE_MATCH_2} "${CMAKE_MATCH_3}")
        set(PDFXT_PDFIUM_LIBRARY_SHA256_${CMAKE_MATCH_2} "${CMAKE_MATCH_4}")
    else()
        message(FATAL_ERROR "pdfxt: src/pdfium.pin: a line this build cannot read: ${_line}")
    endif()
endforeach()
if(NOT PDFXT_PDFIUM_RELEASE)
    message(FATAL_ERROR "pdfxt: src/pdfium.pin names no release")
endif()

# Which archive this build wants. Decided from what is being COMPILED FOR
# (the pointer size, not the host's name: -m32 on a 64-bit machine is x86).
if(ANDROID)
    if(ANDROID_ABI STREQUAL "arm64-v8a")
        set(_pdx_arch "android-arm64")
    elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
        set(_pdx_arch "android-arm")
    elseif(ANDROID_ABI STREQUAL "x86_64")
        set(_pdx_arch "android-x64")
    elseif(ANDROID_ABI STREQUAL "x86")
        set(_pdx_arch "android-x86")
    endif()
elseif(WIN32)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(_pdx_arch "win-x64")
    else()
        set(_pdx_arch "win-x86")
    endif()
elseif(APPLE)
    set(_pdx_arch "mac-univ")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
    set(_pdx_arch "linux-arm64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64|i[3-6]86)$")
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(_pdx_arch "linux-x64")
    else()
        set(_pdx_arch "linux-x86")
    endif()
endif()
if(NOT _pdx_arch OR NOT DEFINED PDFXT_PDFIUM_ARCHIVE_SHA256_${_pdx_arch})
    message(FATAL_ERROR "pdfxt: no pinned PDFium archive for this target "
                        "(${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR}, ${CMAKE_SIZEOF_VOID_P}-byte pointers)")
endif()

if(PDFXT_PDFIUM_DIR)
    set(_pdx_root "${PDFXT_PDFIUM_DIR}")
    message(STATUS "pdfxt: PDFium from ${_pdx_root} (PDFXT_PDFIUM_DIR)")
else()
    string(REPLACE "/" "-" _pdx_tag "${PDFXT_PDFIUM_RELEASE}")
    set(_pdx_tgz "${CMAKE_CURRENT_BINARY_DIR}/pdfium-${_pdx_tag}-${_pdx_arch}.tgz")
    set(_pdx_root "${CMAKE_CURRENT_BINARY_DIR}/pdfium-${_pdx_tag}-${_pdx_arch}")
    if(NOT EXISTS "${_pdx_root}/include/fpdfview.h")
        set(_pdx_url "https://github.com/bblanchon/pdfium-binaries/releases/download/${PDFXT_PDFIUM_RELEASE}/pdfium-${_pdx_arch}.tgz")
        message(STATUS "pdfxt: fetching ${_pdx_url}")
        file(DOWNLOAD "${_pdx_url}" "${_pdx_tgz}"
             EXPECTED_HASH "SHA256=${PDFXT_PDFIUM_ARCHIVE_SHA256_${_pdx_arch}}"
             TLS_VERIFY ON STATUS _pdx_status)
        list(GET _pdx_status 0 _pdx_code)
        if(NOT _pdx_code EQUAL 0)
            file(REMOVE "${_pdx_tgz}")
            message(FATAL_ERROR "pdfxt: could not fetch the pinned PDFium (${_pdx_status}). "
                                "Fetch and unpack it by hand and pass -DPDFXT_PDFIUM_DIR=<folder>.")
        endif()
        file(ARCHIVE_EXTRACT INPUT "${_pdx_tgz}" DESTINATION "${_pdx_root}")
    endif()
endif()

if(WIN32)
    set(_pdx_pdfium "${_pdx_root}/bin/pdfium.dll")
    set(_pdx_pdfium_name "pdfium.dll")
elseif(APPLE)
    set(_pdx_pdfium "${_pdx_root}/lib/libpdfium.dylib")
    set(_pdx_pdfium_name "pdfium.dylib")
else()
    set(_pdx_pdfium "${_pdx_root}/lib/libpdfium.so")
    set(_pdx_pdfium_name "pdfium.so")
endif()
if(NOT EXISTS "${_pdx_pdfium}" OR NOT EXISTS "${_pdx_root}/include/fpdfview.h")
    message(FATAL_ERROR "pdfxt: ${_pdx_root} is not an unpacked pdfium-binaries archive for ${_pdx_arch}")
endif()
# The library itself is held to the pin whichever way it arrived: this is the
# file that ships, and the hash the suite's installer will ask for again.
file(SHA256 "${_pdx_pdfium}" _pdx_have)
if(NOT _pdx_have STREQUAL "${PDFXT_PDFIUM_LIBRARY_SHA256_${_pdx_arch}}")
    message(FATAL_ERROR "pdfxt: ${_pdx_pdfium} is not the pinned PDFium for ${_pdx_arch} "
                        "(${PDFXT_PDFIUM_RELEASE}): its SHA-256 is ${_pdx_have}")
endif()

# ---------------------------------------------------------------------------
# The shim. It includes PDFium's headers and links NOTHING of PDFium: every
# function is found by name at run time in the file beside it.
# ---------------------------------------------------------------------------
add_library(pdfxt SHARED src/pdfium_shim.c)
target_include_directories(pdfxt SYSTEM PRIVATE "${_pdx_root}/include")
target_compile_definitions(pdfxt PRIVATE "PDX_PDFIUM_PIN=\"${PDFXT_PDFIUM_RELEASE}\"")
if(PDFXT_SANITIZE)
    # The sanitizers' runtime refuses a library loaded with RTLD_DEEPBIND.
    target_compile_definitions(pdfxt PRIVATE PDX_NO_DEEPBIND)
endif()
if(NOT WIN32)
    target_link_libraries(pdfxt PRIVATE ${CMAKE_DL_LIBS} m)
endif()

set_target_properties(pdfxt PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS ON                 # __typeof__
    C_VISIBILITY_PRESET hidden      # export only the LC_API shim symbols
    PREFIX ""
    OUTPUT_NAME "pdfxt"
)

if(MSVC)
    target_compile_options(pdfxt PRIVATE /W3)
    target_compile_definitions(pdfxt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(pdfxt PRIVATE -Wall -Wextra)
endif()

# Export pdx_* and nothing else (the family's rule since enetxt's release run
# 10). src/pdfxt.map is the one source for GNU ld and, by the pattern below,
# for ld64.
set(_pdx_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/pdfxt.map")
if(APPLE)
    set(_pdx_exported "${CMAKE_CURRENT_BINARY_DIR}/pdfxt.exported_symbols")
    file(WRITE "${_pdx_exported}" "_pdx_*\n")
    target_link_options(pdfxt PRIVATE "-Wl,-exported_symbols_list,${_pdx_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_pdx_version_script}" PDX_HAVE_VERSION_SCRIPT)
    if(PDX_HAVE_VERSION_SCRIPT)
        target_link_options(pdfxt PRIVATE "-Wl,--version-script=${_pdx_version_script}")
        set_target_properties(pdfxt PROPERTIES LINK_DEPENDS "${_pdx_version_script}")
    endif()
endif()

# PDFium goes beside the library that loads it, under its bare name: what the
# tests run against is the pair that ships.
add_custom_command(TARGET pdfxt POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_pdx_pdfium}" "$<TARGET_FILE_DIR:pdfxt>/${_pdx_pdfium_name}"
    COMMENT "Placing the pinned PDFium beside pdfxt as ${_pdx_pdfium_name}"
    VERBATIM)

# ---------------------------------------------------------------------------
# The runtime smoke test: every export, over the PDF files that
# tools/build-test-pdfs.py writes (committed under tests/fixtures/).
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DPDFXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(PDFXT_BUILD_TESTS)
    enable_testing()
    add_executable(pdfxt_smoke tests/smoke_test.c)
    set_target_properties(pdfxt_smoke PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
    target_link_libraries(pdfxt_smoke PRIVATE pdfxt)
    if(MSVC)
        target_compile_definitions(pdfxt_smoke PRIVATE _CRT_SECURE_NO_WARNINGS)
    else()
        target_compile_options(pdfxt_smoke PRIVATE -Wall -Wextra)
        target_link_libraries(pdfxt_smoke PRIVATE m)
    endif()
    add_test(NAME smoke COMMAND pdfxt_smoke)
endif()
