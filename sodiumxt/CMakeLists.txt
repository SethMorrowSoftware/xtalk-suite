# CMakeLists.txt - build the SodiumXT native shim.
#
# What this produces: ONE shared library, statically linking a PINNED libsodium,
# named with the bare token "sodiumxt" (no "lib" prefix), so the packaged
# extension can resolve "c:sodiumxt>" with no external runtime dependency. See
# CLAUDE.md ("FFI / C-ABI conventions", "Committed binaries") and
# docs/building.md; the implementation plan this line used to cite was retired
# on 2026-09-23 (git history: docs/archive/implementation-plan.md).
#
# libsodium's own build is autotools. On Linux and macOS we drive that via
# ExternalProject (the known-good path), then import the resulting static lib;
# cross builds (32-bit Linux, universal macOS) pass extra flags through the
# SODIUMXT_LIBSODIUM_CFLAGS / _CONFIGURE_EXTRA cache vars. On Windows/MSVC we
# link the libsodium that vcpkg provides (CI installs it and passes the vcpkg
# toolchain). Either way libsodium is static-linked into the one shared library.

cmake_minimum_required(VERSION 3.16)

project(SodiumXT
        VERSION 0.1.0
        DESCRIPTION "Modern cryptography for OpenXTalk / xTalk via libsodium"
        LANGUAGES C)

# ---------------------------------------------------------------------------
# Pinned libsodium.
#
# Re-pinning is a two-file change: bump these three values AND the
# SXT_PINNED_SODIUM known-answer string in tests/sodium_smoke_test.c, in the
# same commit. The sha256 is the integrity gate on the download.
# ---------------------------------------------------------------------------
set(SODIUMXT_LIBSODIUM_VERSION "1.0.20"
    CACHE STRING "Pinned libsodium release to build and static-link")
set(SODIUMXT_LIBSODIUM_URL
    "https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz"
    CACHE STRING "Download URL for the pinned libsodium source tarball")
set(SODIUMXT_LIBSODIUM_SHA256
    "ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19"
    CACHE STRING "Expected sha256 of the pinned libsodium tarball")

option(SODIUMXT_BUILD_TESTS "Build the C smoke test (ctest)" OFF)
option(SODIUMXT_SANITIZE    "Build the smoke test under gcc ASan + UBSan" OFF)

# Cross-build hooks for the libsodium autotools build (empty = native build,
# byte-identical to the default path). 32-bit Linux: set CFLAGS=-m32 and a
# --host. Universal macOS: set CFLAGS to both -arch flags.
set(SODIUMXT_LIBSODIUM_CFLAGS "" CACHE STRING
    "Extra CFLAGS for the libsodium build (e.g. -m32, or '-arch arm64 -arch x86_64')")
set(SODIUMXT_LIBSODIUM_CONFIGURE_EXTRA "" CACHE STRING
    "Extra args for libsodium ./configure (e.g. --host=i686-pc-linux-gnu)")

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# ---------------------------------------------------------------------------
# Acquire and build libsodium (static, PIC, no shared), then import it.
# ---------------------------------------------------------------------------
include(ExternalProject)

# libsodium's autotools build must be driven by `make`, NOT by the outer
# project's generator tool: ${CMAKE_MAKE_PROGRAM} is `ninja` under -G Ninja,
# which cannot build an autotools-generated Makefile (and `ninja -j` is a usage
# error). Resolve a real make and an explicit, portable job count.
find_program(SODIUMXT_MAKE NAMES gmake make)
if(NOT SODIUMXT_MAKE)
    set(SODIUMXT_MAKE make)
endif()
include(ProcessorCount)
ProcessorCount(SODIUMXT_NPROC)
if(SODIUMXT_NPROC EQUAL 0)
    set(SODIUMXT_NPROC 2)
endif()

set(_sodium_prefix  "${CMAKE_BINARY_DIR}/libsodium")
set(_sodium_install "${_sodium_prefix}/install")
set(_sodium_include "${_sodium_install}/include")
set(_sodium_lib
    "${_sodium_install}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}sodium${CMAKE_STATIC_LIBRARY_SUFFIX}")

# SODIUMXT_SODIUM_LINK is the libsodium target our shim links against;
# SODIUMXT_USE_EXTPROJ says whether we built it ourselves (so targets must depend
# on libsodium_ext) or imported it from vcpkg (MSVC).
set(SODIUMXT_USE_EXTPROJ TRUE)

if(MSVC)
    # vcpkg supplies libsodium via its CONFIG package. CI installs
    # libsodium:<triplet>-static and passes the vcpkg toolchain file.
    set(SODIUMXT_USE_EXTPROJ FALSE)
    find_package(unofficial-sodium CONFIG REQUIRED)
    set(SODIUMXT_SODIUM_LINK unofficial-sodium::sodium)
else()
    # Build the pinned source via autotools. Assemble the configure command as a
    # list so the cross-build knobs only appear when set (empty = the verified
    # native invocation, unchanged).
    set(_sodium_configure <SOURCE_DIR>/configure
                          --prefix=<INSTALL_DIR>
                          --enable-static --disable-shared
                          --with-pic                 # static objects link into our .so
                          --disable-dependency-tracking)
    if(EMSCRIPTEN)
        # The web build (wasm32-emscripten, below): libsodium's own recipe for
        # Emscripten (dist-build/emscripten.sh), run through emconfigure so
        # its configure finds emcc. No assembly (there is none for wasm), no
        # threads (OXT-Beyond's web engine has none), no stack protector and
        # no PIE (the archive links statically into the engine).
        find_program(SODIUMXT_EMCONFIGURE emconfigure
                     HINTS "${EMSCRIPTEN_ROOT_PATH}" "$ENV{EMSDK}/upstream/emscripten" REQUIRED)
        list(PREPEND _sodium_configure "${SODIUMXT_EMCONFIGURE}")
        # Not position-independent either: the archive is linked statically.
        # The prefix map keeps the build folder's path out of libsodium's
        # assertion messages, so the archive is the same wherever it is built.
        list(REMOVE_ITEM _sodium_configure --with-pic)
        list(APPEND _sodium_configure --without-pthreads --disable-ssp --disable-asm --disable-pie
                                      "CFLAGS=-Os -g0 -ffile-prefix-map=${_sodium_prefix}=libsodium")
    endif()
    if(SODIUMXT_LIBSODIUM_CFLAGS)
        list(APPEND _sodium_configure "CFLAGS=${SODIUMXT_LIBSODIUM_CFLAGS}")
    endif()
    if(SODIUMXT_LIBSODIUM_CONFIGURE_EXTRA)
        separate_arguments(_sodium_extra UNIX_COMMAND "${SODIUMXT_LIBSODIUM_CONFIGURE_EXTRA}")
        list(APPEND _sodium_configure ${_sodium_extra})
    endif()
    ExternalProject_Add(libsodium_ext
        URL              "${SODIUMXT_LIBSODIUM_URL}"
        URL_HASH         "SHA256=${SODIUMXT_LIBSODIUM_SHA256}"
        PREFIX           "${_sodium_prefix}"
        CONFIGURE_COMMAND ${_sodium_configure}
        BUILD_COMMAND     ${SODIUMXT_MAKE} -j ${SODIUMXT_NPROC}
        INSTALL_COMMAND   ${SODIUMXT_MAKE} install
        INSTALL_DIR       "${_sodium_install}"
        BUILD_BYPRODUCTS  "${_sodium_lib}"
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    # Import the not-yet-built static lib. The include dir must exist at configure
    # time for the INTERFACE include to be valid, so create it up front. SYSTEM so
    # libsodium's headers never pollute our -Wall -Wextra.
    file(MAKE_DIRECTORY "${_sodium_include}")
    add_library(sodiumxt::libsodium STATIC IMPORTED GLOBAL)
    set_target_properties(sodiumxt::libsodium PROPERTIES IMPORTED_LOCATION "${_sodium_lib}")
    target_include_directories(sodiumxt::libsodium SYSTEM INTERFACE "${_sodium_include}")
    set(SODIUMXT_SODIUM_LINK sodiumxt::libsodium)
endif()

# ---------------------------------------------------------------------------
# Warning flags applied to OUR code only (libsodium headers are SYSTEM above).
# ---------------------------------------------------------------------------
function(sodiumxt_apply_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W3)
    else()
        target_compile_options(${target} PRIVATE -Wall -Wextra)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten (2026-10-21). A browser loads no library,
# so for OXT-Beyond's web IDE the shim is linked INTO the engine, which keeps a
# table of the libraries compiled into it and finds "c:sodiumxt>sxt_..." there
# by name (OXT-Beyond's engine/src/em-xtalk-web.cpp). What ships is therefore
# a static archive, src/code/wasm32-emscripten/sodiumxt.a, holding ONE
# relocatable object: the shim, the vendored SHA3 and the members of
# libsodium they use, linked together (emcc -r), plus a table of the symbols
# the binding names, which the engine registers:
#
#     const struct { const char *symbol; void *address; } *
#     sodiumxt_web_exports(void);      /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:sodiumxt>NAME"` of
# src/sodium.lcb, so it cannot drift from the binding, and compiled against
# sodium_shim.h, so a bind with no shim function is a compile error
# (implicit declarations are errors here), never a missing symbol found in a
# browser. Declared with its real prototype, each address is the function
# itself: WebAssembly checks a call's type, and an address taken through a
# declaration of another type would be a stub that traps.
#
# No folder name of the IDE's code-folder matcher reads "wasm32", so the
# desktop IDE and its HTML5 builder both pass this folder by.
# ---------------------------------------------------------------------------
option(SODIUMXT_PLACE_IN_SRC
       "Copy the built library into src/code/<id>/ after building" ON)

if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/sodium.lcb" _sxt_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/sodium.lcb")
    string(REGEX MATCHALL "binds to \"c:sodiumxt>[A-Za-z_][A-Za-z0-9_]*" _sxt_binds "${_sxt_lcb}")
    set(_sxt_symbols "")
    foreach(_bind IN LISTS _sxt_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _sxt_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _sxt_symbols)
    list(SORT _sxt_symbols)
    list(LENGTH _sxt_symbols _sxt_count)
    if(_sxt_count EQUAL 0)
        message(FATAL_ERROR "src/sodium.lcb binds no c:sodiumxt> symbol: is the regular expression stale?")
    endif()
    set(_sxt_rows "")
    foreach(_symbol IN LISTS _sxt_symbols)
        string(APPEND _sxt_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_sxt_exports_c "${CMAKE_CURRENT_BINARY_DIR}/sodiumxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_sxt_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/sodium.lcb: the @_sxt_count@ symbols the
 * binding binds to, for OXT-Beyond's web engine. */
#include <stddef.h>
#include \"sodium_shim.h\"

struct sxt_web_export { const char *symbol; void *address; };

static const struct sxt_web_export k_sxt_web_exports[] = {
@_sxt_rows@\t{ NULL, NULL },
};

SXT_API const struct sxt_web_export *sodiumxt_web_exports(void);
SXT_API const struct sxt_web_export *sodiumxt_web_exports(void)
{
\treturn k_sxt_web_exports;
}
")
    message(STATUS "sodiumxt web exports: ${_sxt_count} symbols from src/sodium.lcb")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(sodiumxt_web_objects OBJECT
                src/sodium_shim.c src/vendor/sha3.c src/vendor/memzero.c "${_sxt_exports_c}")
    add_dependencies(sodiumxt_web_objects libsodium_ext)
    set_target_properties(sodiumxt_web_objects PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
    target_include_directories(sodiumxt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(sodiumxt_web_objects PRIVATE ${SODIUMXT_SODIUM_LINK})
    target_compile_options(sodiumxt_web_objects PRIVATE
        -Os -g0 -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=sodiumxt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")
    sodiumxt_apply_warnings(sodiumxt_web_objects)

    set(_sxt_web_object "${CMAKE_CURRENT_BINARY_DIR}/sodiumxt-web.o")
    set(_sxt_web_archive "${CMAKE_CURRENT_BINARY_DIR}/sodiumxt.a")
    add_custom_command(
        OUTPUT "${_sxt_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_sxt_web_object}" "${_sxt_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_sxt_web_object}"
                "$<TARGET_OBJECTS:sodiumxt_web_objects>" "${_sodium_lib}"
        COMMAND ${CMAKE_AR} rcsD "${_sxt_web_archive}" "${_sxt_web_object}"
        DEPENDS sodiumxt_web_objects "$<TARGET_OBJECTS:sodiumxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking sodiumxt.a for the web (shim + libsodium, one object)"
        VERBATIM)
    add_custom_target(sodiumxt_web ALL DEPENDS "${_sxt_web_archive}")

    # The web smoke test: tests/sodium_smoke_test.c, the same KATs and
    # firewall checks, linked against the ARCHIVE that ships and run by
    # node (ctest), so what is tested is the file that is committed.
    if(SODIUMXT_BUILD_TESTS)
        enable_testing()
        add_executable(sodium_smoke_test tests/sodium_smoke_test.c)
        add_dependencies(sodium_smoke_test sodiumxt_web)
        set_target_properties(sodium_smoke_test PROPERTIES
            C_STANDARD 11 C_STANDARD_REQUIRED ON SUFFIX ".js")
        target_include_directories(sodium_smoke_test PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/src" "${_sodium_include}")
        target_link_libraries(sodium_smoke_test PRIVATE "${_sxt_web_archive}")
        target_link_options(sodium_smoke_test PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node)
        sodiumxt_apply_warnings(sodium_smoke_test)
        find_program(SODIUMXT_NODE node REQUIRED)
        add_test(NAME sodium_smoke_test
                 COMMAND "${SODIUMXT_NODE}" "$<TARGET_FILE:sodium_smoke_test>")
    endif()

    if(SODIUMXT_PLACE_IN_SRC)
        set(_sxt_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET sodiumxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_sxt_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_sxt_web_archive}" "${_sxt_bundle_dir}/sodiumxt.a"
            COMMENT "Bundling sodiumxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# The shim: ONE shared library, bare token "sodiumxt", hidden visibility so
# only the SXT_API-tagged sxt_* symbols are exported.
# ---------------------------------------------------------------------------
# src/vendor: the trezor-crypto/RHash SHA3-256 (the one primitive libsodium
# does not provide; ABI 7). Compiled into the same single shared library; the
# hidden default visibility keeps every vendored symbol internal.
add_library(sodiumxt SHARED src/sodium_shim.c src/vendor/sha3.c src/vendor/memzero.c)
if(SODIUMXT_USE_EXTPROJ)
    add_dependencies(sodiumxt libsodium_ext)
endif()
set_target_properties(sodiumxt PROPERTIES
    PREFIX ""                 # no "lib" prefix: the engine resolves the bare token
    OUTPUT_NAME "sodiumxt"
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON)
target_include_directories(sodiumxt PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(sodiumxt PRIVATE ${SODIUMXT_SODIUM_LINK})
sodiumxt_apply_warnings(sodiumxt)

# Export ONLY the sxt_* ABI. Hidden visibility (above) governs our own code, but
# symbols pulled from the static libsodium archive would otherwise be re-exported
# from the shared library. A stray exported sodium_init/randombytes_buf is untidy
# and can collide with another library the host has loaded, so we strip them.
if(APPLE)
    target_link_options(sodiumxt PRIVATE
        "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/cmake/sodiumxt.exp")
elseif(NOT MSVC)
    # GNU ld / lld: do not re-export symbols brought in from static archives.
    target_link_options(sodiumxt PRIVATE "-Wl,--exclude-libs,ALL")
endif()

# ---------------------------------------------------------------------------
# Place the built library where the packaged extension expects it:
#     src/code/<arch>-<platform>/sodiumxt.{so,dll,dylib}
# so a plain `cmake --build` is SELF-SUFFICIENT: the engine can resolve
# "c:sodiumxt>" with no separate step. tools/package-extension.py still does the
# same copy for a build tree you would rather not reconfigure, but the easy-to-
# miss second step is no longer on the normal local path (it bit us on Windows,
# where the .dll was left in build/ and never reached src/code/).
# ---------------------------------------------------------------------------
# (SODIUMXT_PLACE_IN_SRC is declared above, before the web build, which reads
# it too.)

# Architecture-first id; Windows is -win32 for BOTH bitnesses; macOS files under
# the canonical universal-mac (a local dylib is single-arch; the CI build is the
# lipo'd universal one). Bitness is the TARGET pointer width, so a -m32 cross
# build correctly resolves to x86. Override with -DSODIUMXT_PLATFORM_ID=<id>.
if(APPLE)
    set(_sxt_default_id "universal-mac")
elseif(WIN32)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(_sxt_default_id "x86_64-win32")
    else()
        set(_sxt_default_id "x86-win32")
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    # 64-bit ARM (Raspberry Pi 3/4/5 on a 64-bit OS, the ubuntu-24.04-arm
    # runner) is its own id, never the x86_64 one its pointer width matches.
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        set(_sxt_default_id "arm64-linux")
    elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(_sxt_default_id "x86_64-linux")
    else()
        set(_sxt_default_id "x86-linux")
    endif()
else()
    set(_sxt_default_id "")
endif()
set(SODIUMXT_PLATFORM_ID "${_sxt_default_id}" CACHE STRING
    "Platform id for the src/code/<id>/ bundle (override for cross builds)")

if(SODIUMXT_PLACE_IN_SRC AND SODIUMXT_PLATFORM_ID)
    set(_sxt_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/${SODIUMXT_PLATFORM_ID}")
    add_custom_command(TARGET sodiumxt POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${_sxt_bundle_dir}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE:sodiumxt>"
                "${_sxt_bundle_dir}/$<TARGET_FILE_NAME:sodiumxt>"
        COMMENT "Bundling sodiumxt -> src/code/${SODIUMXT_PLATFORM_ID}/"
        VERBATIM)
elseif(SODIUMXT_PLACE_IN_SRC AND NOT SODIUMXT_PLATFORM_ID)
    message(WARNING
        "SODIUMXT_PLACE_IN_SRC is ON but the platform id could not be detected "
        "(system='${CMAKE_SYSTEM_NAME}'). Pass -DSODIUMXT_PLATFORM_ID=<id> to "
        "place the built library under src/code/<id>/.")
endif()

# ---------------------------------------------------------------------------
# Smoke test (KATs + the out-buffer round trip + the firewall negative paths).
# The test links the shim SOURCE directly (not the .so), so it exercises the
# same objects under the sanitizers.
# ---------------------------------------------------------------------------
if(SODIUMXT_BUILD_TESTS)
    enable_testing()
    add_executable(sodium_smoke_test tests/sodium_smoke_test.c src/sodium_shim.c
                   src/vendor/sha3.c src/vendor/memzero.c)
    if(SODIUMXT_USE_EXTPROJ)
        add_dependencies(sodium_smoke_test libsodium_ext)
    endif()
    set_target_properties(sodium_smoke_test PROPERTIES
        C_STANDARD 11 C_STANDARD_REQUIRED ON)
    target_include_directories(sodium_smoke_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(sodium_smoke_test PRIVATE ${SODIUMXT_SODIUM_LINK})
    sodiumxt_apply_warnings(sodium_smoke_test)

    if(SODIUMXT_SANITIZE AND NOT MSVC)
        # A crypto binding is exactly where an off-by-one in buffer sizing hides,
        # so the sanitizers are part of the suite, not an afterthought.
        target_compile_options(sodium_smoke_test PRIVATE
            -fsanitize=address,undefined -fno-sanitize-recover=all)
        target_link_options(sodium_smoke_test PRIVATE
            -fsanitize=address,undefined -fno-sanitize-recover=all)
    endif()

    add_test(NAME sodium_smoke_test COMMAND sodium_smoke_test)
endif()
