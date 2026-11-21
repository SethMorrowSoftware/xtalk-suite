cmake_minimum_required(VERSION 3.22)
project(xlsxt LANGUAGES C)

# ---------------------------------------------------------------------------
# xlsxt - Excel .xlsx files for OpenXTalk (OXT) and the xTalk family, also
# compatible with LiveCode 9.6.3+: libxlsxwriter writes them, and a reader in
# the shim (over zlib's minizip and Expat) reads them back. This builds the C
# shim (src/xlsx_shim.c) and the three libraries into ONE loadable library
# named "xlsxt", or for the web into a static archive (below).
# box3dxt/CMakeLists.txt is this file's ancestor.
# ---------------------------------------------------------------------------

option(XLSXT_BUILD_TESTS "Build the xlsxt runtime smoke test and random-call test" OFF)
option(XLSXT_PLACE_IN_SRC
       "Web build only: copy xlsxt.a into src/code/wasm32-emscripten/ after building" ON)
set(XLSXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan, gcc or clang)")

# The web build (wasm32-emscripten, below) is a release archive: optimised
# unless a build type is given.
if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# The three libraries are compiled into a static library that is linked into
# our shared library, so every object must be position-independent (box2dxt's
# lesson: the manylinux toolchain does not default to PIE). Not for the web
# build, whose archive is linked into the engine.
if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# The Windows libraries carry the C runtime (static CRT, as curlxt's do), so a
# PC without the Visual C++ Redistributable loads them and a package needs no
# runtime DLLs beside them.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Hidden by default in EVERY object, the third-party ones included: the
# engine that loads this library has a zlib of its own, and a default-
# visibility `inflate` here would be bound to the engine's at load time.
set(CMAKE_C_VISIBILITY_PRESET hidden)

if(XLSXT_SANITIZE STREQUAL "address")
    # Applies to the three libraries too (the options precede their target),
    # so a bad read inside one that the shim caused is reported.
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
endif()

# ---------------------------------------------------------------------------
# The three libraries, each pinned to the COMMIT its release tag names (a tag
# can be moved; a commit id cannot). Bump one, then rebuild every platform
# (suite rule 5) and re-run both tests. THIRD-PARTY-LICENSES.md names the
# same three versions and tools/check-pins.py holds the two files together.
#
#   libxlsxwriter 1.2.4   BSD-2-Clause   John McNamara
#   zlib 1.4              zlib           Jean-loup Gailly, Mark Adler
#   Expat 2.10.0          MIT            the Expat maintainers
#
# -DFETCHCONTENT_SOURCE_DIR_<NAME>=<checkout> builds from a local copy with
# no network (NAME: LIBXLSXWRITER, ZLIB, EXPAT).
#
# WHY NONE OF THEIR CMAKE FILES RUNS. All three are fetched as SOURCE only
# (SOURCE_SUBDIR names a folder that does not exist, which is CMake's
# documented way to say "do not add_subdirectory") and compiled below from a
# stated list of files:
#   - libxlsxwriter's CMake enables C++ (it has none), looks for a system
#     zlib and compiles a 2010 copy of minizip. We want the zlib and the
#     minizip of the pinned zlib release instead: zlib 1.4 fixed "several
#     vulnerabilities in contrib/minizip", and the reader hands minizip
#     files from strangers.
#   - zlib's CMake builds a shared library, examples and tests beside the
#     static one.
#   - Expat's CMake probes the build machine for its entropy source; the
#     answers are fixed in src/expat_config.h instead.
# A stated list also means a new upstream file is a decision here, not a
# glob's.
# ---------------------------------------------------------------------------
set(XLSXT_LIBXLSXWRITER_COMMIT "2894634d65cee6021901a165bfc2bb0fad6da193")  # v1.2.4
set(XLSXT_ZLIB_COMMIT          "99623ef7097352da7993ba614161fd6a311e046e")  # v1.4
set(XLSXT_EXPAT_COMMIT         "a70841d9ffa64ddde29ab824ed6305035ebe4c47")  # R_2_10_0

include(FetchContent)
FetchContent_Declare(libxlsxwriter
    GIT_REPOSITORY https://github.com/jmcnamara/libxlsxwriter.git
    GIT_TAG        ${XLSXT_LIBXLSXWRITER_COMMIT}
    SOURCE_SUBDIR  xlsxt-builds-the-sources-itself)
FetchContent_Declare(zlib
    GIT_REPOSITORY https://github.com/madler/zlib.git
    GIT_TAG        ${XLSXT_ZLIB_COMMIT}
    SOURCE_SUBDIR  xlsxt-builds-the-sources-itself)
FetchContent_Declare(expat
    GIT_REPOSITORY https://github.com/libexpat/libexpat.git
    GIT_TAG        ${XLSXT_EXPAT_COMMIT}
    SOURCE_SUBDIR  xlsxt-builds-the-sources-itself)
FetchContent_MakeAvailable(libxlsxwriter zlib expat)

set(_lxw   "${libxlsxwriter_SOURCE_DIR}")
set(_zlib  "${zlib_SOURCE_DIR}")
set(_expat "${expat_SOURCE_DIR}/expat")

# zlib: deflate and inflate and what they stand on. Not the gz* file layer
# (nothing here reads a .gz) and not infback.
set(_xlx_zlib_sources
    ${_zlib}/adler32.c ${_zlib}/compress.c ${_zlib}/crc32.c ${_zlib}/deflate.c
    ${_zlib}/inffast.c ${_zlib}/inflate.c ${_zlib}/inftrees.c ${_zlib}/trees.c
    ${_zlib}/uncompr.c ${_zlib}/zutil.c)
# minizip, from the SAME zlib release: zip.c for libxlsxwriter, unzip.c for
# the reader, ioapi.c for both. Windows adds the wide-path file layer
# libxlsxwriter opens its output through.
set(_xlx_minizip_sources
    ${_zlib}/contrib/minizip/ioapi.c ${_zlib}/contrib/minizip/zip.c
    ${_zlib}/contrib/minizip/unzip.c)
if(WIN32)
    list(APPEND _xlx_minizip_sources ${_zlib}/contrib/minizip/iowin32.c)
endif()
# libxlsxwriter: every file of its src/, named, plus two of the small
# libraries it carries: tmpfileplus (its temp files, in a folder that can be
# chosen: tmpfile() on Windows writes to the drive root) and Openwall's MD5
# (one copy of an image used twice). NOT its third: third_party/dtoa.
# USE_DTOA_LIBRARY is still defined, because without it libxlsxwriter prints
# numbers with printf, which writes "1,5" once an engine built on GTK has
# called setlocale() - and a "1,5" in a sheet's XML is a file Excel calls
# corrupt. But the bundled emyg_dtoa.c reads past the end of a ten-entry
# table for some small numbers (kPow10[-kappa], kappa down to -17: UBSan,
# on 1e-7, in this member's first smoke run), so the one function it
# provides, emyg_dtoa(), is defined in src/xlsx_shim.c instead.
set(_xlx_lxw_sources
    ${_lxw}/src/app.c ${_lxw}/src/chart.c ${_lxw}/src/chartsheet.c
    ${_lxw}/src/comment.c ${_lxw}/src/content_types.c ${_lxw}/src/core.c
    ${_lxw}/src/custom.c ${_lxw}/src/drawing.c ${_lxw}/src/format.c
    ${_lxw}/src/hash_table.c ${_lxw}/src/metadata.c ${_lxw}/src/packager.c
    ${_lxw}/src/relationships.c ${_lxw}/src/rich_value.c
    ${_lxw}/src/rich_value_rel.c ${_lxw}/src/rich_value_structure.c
    ${_lxw}/src/rich_value_types.c ${_lxw}/src/shared_strings.c
    ${_lxw}/src/styles.c ${_lxw}/src/table.c ${_lxw}/src/theme.c
    ${_lxw}/src/utility.c ${_lxw}/src/vml.c ${_lxw}/src/workbook.c
    ${_lxw}/src/worksheet.c ${_lxw}/src/xmlwriter.c
    ${_lxw}/third_party/tmpfileplus/tmpfileplus.c
    ${_lxw}/third_party/md5/md5.c)
# Expat: its four sources and the one entropy source src/expat_config.h picks.
set(_xlx_expat_sources
    ${_expat}/lib/xcs.c ${_expat}/lib/xmlparse.c ${_expat}/lib/xmlrole.c
    ${_expat}/lib/xmltok.c)
if(WIN32)
    list(APPEND _xlx_expat_sources ${_expat}/lib/random_rand_s.c)
else()
    list(APPEND _xlx_expat_sources ${_expat}/lib/random_dev_urandom.c)
endif()

foreach(_f IN LISTS _xlx_zlib_sources _xlx_minizip_sources _xlx_lxw_sources _xlx_expat_sources)
    if(NOT EXISTS "${_f}")
        message(FATAL_ERROR "xlsxt: ${_f} is not in the pinned source: was a pin bumped without this list?")
    endif()
endforeach()

# The include paths and definitions the shim shares with the libraries (it
# includes their headers), kept in one INTERFACE target.
add_library(xlsxt_config INTERFACE)
target_include_directories(xlsxt_config SYSTEM INTERFACE
    "${_zlib}"                 # zlib.h, zconf.h
    "${_zlib}/contrib"         # minizip/zip.h, minizip/unzip.h
    "${_lxw}/include"          # xlsxwriter.h
    "${_expat}/lib")           # expat.h
target_include_directories(xlsxt_config INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/src")  # expat_config.h
# src/quiet/R.h: how libxlsxwriter's stderr warnings are switched off (the
# file says why, and why this is upstream's own switch and not a patch).
target_include_directories(xlsxt_config INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/src/quiet")
target_compile_definitions(xlsxt_config INTERFACE
    # zlib's own switch: every zlib name becomes z_<name>. The library hides
    # its symbols on the desktop, but the WEB archive is linked into an
    # engine that has a zlib of its own, where two `inflate`s cannot both
    # link. One spelling on every platform, so what is tested is what ships.
    Z_PREFIX
    # libxlsxwriter: "system" minizip means "not my 2010 copy": it includes
    # minizip/zip.h, which the include path above points at zlib's.
    USE_SYSTEM_MINIZIP USE_DTOA_LIBRARY NOCRYPT NOUNCRYPT
    # libxlsxwriter again: its messages go to REprintf, which src/quiet/R.h
    # defines to print nothing.
    USE_R_LANG
    # Expat: a static library, configured by src/expat_config.h.
    XML_STATIC HAVE_EXPAT_CONFIG_H)
if(EMSCRIPTEN)
    # musl's off_t is 64-bit and it has no fopen64 family to call.
    target_compile_definitions(xlsxt_config INTERFACE MINIZIP_FOPEN_NO_64)
endif()
if(MSVC)
    target_compile_definitions(xlsxt_config INTERFACE _CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_DEPRECATE)
endif()

add_library(xlsxt_deps STATIC
    ${_xlx_zlib_sources} ${_xlx_minizip_sources} ${_xlx_lxw_sources} ${_xlx_expat_sources})
target_link_libraries(xlsxt_deps PUBLIC xlsxt_config)
target_include_directories(xlsxt_deps PRIVATE "${_zlib}/contrib/minizip")
set_target_properties(xlsxt_deps PROPERTIES C_STANDARD 99)
# The libraries are pinned to known-good commits, so an upstream warning on a
# newer compiler must never fail or bury this build (box2dxt's lesson).
if(MSVC)
    target_compile_options(xlsxt_deps PRIVATE /w)
else()
    target_compile_options(xlsxt_deps PRIVATE -w)
endif()

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten. A browser loads no library, so for
# OXT-Beyond's web IDE the shim is linked INTO the engine, which keeps a table
# of the libraries compiled into it and finds "c:xlsxt>xlx_..." there by
# name. What is built is a static archive, xlsxt.a, holding ONE relocatable
# object: the shim and the members of the three libraries it uses, linked
# together (emcc -r), plus a table of the symbols the binding names:
#
#     const struct { const char *symbol; void *address; } *
#     xlsxt_web_exports(void);       /* ends with { NULL, NULL } */
#
# The table is GENERATED from every `binds to "c:xlsxt>NAME"` of
# src/xlsxt.lcb, so it cannot drift from the binding, and compiled in ONE
# translation unit with src/xlsx_shim.c (which it includes), so a bind with
# no shim function is a compile error, never a missing symbol found in a
# browser. This is box2dxt's mechanism, unchanged.
#
# ONE THING IS NEW HERE: names. box2dxt's archive defines only Box2D's own
# names. This one carries a zlib, a minizip, an Expat and an MD5, and the
# engine it is linked into has libraries of its own that may define the same
# names. src/xlsx_web_names.h (generated and held by
# tools/check-web-names.py) renames every one of them to xlxw_<name> for the
# web build, and the `web` lane fails if the archive defines any global name
# that is not xlx_*, xlxw_* or the table.
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/xlsxt.lcb" _xlx_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/xlsxt.lcb")
    string(REGEX MATCHALL "binds to \"c:xlsxt>[A-Za-z_][A-Za-z0-9_]*" _xlx_binds "${_xlx_lcb}")
    set(_xlx_symbols "")
    foreach(_bind IN LISTS _xlx_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _xlx_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _xlx_symbols)
    list(SORT _xlx_symbols)
    list(LENGTH _xlx_symbols _xlx_count)
    if(_xlx_count EQUAL 0)
        message(FATAL_ERROR "src/xlsxt.lcb binds no c:xlsxt> symbol: is the regular expression stale?")
    endif()
    set(_xlx_rows "")
    foreach(_symbol IN LISTS _xlx_symbols)
        string(APPEND _xlx_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_xlx_exports_c "${CMAKE_CURRENT_BINARY_DIR}/xlsxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_xlx_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/xlsxt.lcb: the shim, and the
 * @_xlx_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"xlsx_shim.c\"

struct xlx_web_export { const char *symbol; void *address; };

static const struct xlx_web_export k_xlx_web_exports[] = {
@_xlx_rows@\t{ NULL, NULL },
};

LC_API const struct xlx_web_export *xlsxt_web_exports(void);
LC_API const struct xlx_web_export *xlsxt_web_exports(void)
{
\treturn k_xlx_web_exports;
}
")
    message(STATUS "xlsxt web exports: ${_xlx_count} symbols from src/xlsxt.lcb")

    # The rename header goes into EVERY translation unit, first.
    set(_xlx_names_h "${CMAKE_CURRENT_SOURCE_DIR}/src/xlsx_web_names.h")
    target_compile_options(xlsxt_config INTERFACE -include "${_xlx_names_h}")

    # -g0 and the prefix maps keep the build folder's path out of the object,
    # so the same source and Emscripten give the same archive anywhere.
    add_library(xlsxt_web_objects OBJECT "${_xlx_exports_c}")
    target_include_directories(xlsxt_web_objects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(xlsxt_web_objects PRIVATE xlsxt_config)
    set_target_properties(xlsxt_web_objects PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
    target_compile_options(xlsxt_web_objects PRIVATE
        -Os -g0 -Wall -Wextra -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=xlsxt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")
    target_compile_options(xlsxt_deps PRIVATE -g0
        "-ffile-prefix-map=${_lxw}=libxlsxwriter"
        "-ffile-prefix-map=${_zlib}=zlib"
        "-ffile-prefix-map=${expat_SOURCE_DIR}=expat"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build")

    set(_xlx_web_object "${CMAKE_CURRENT_BINARY_DIR}/xlsxt-web.o")
    set(_xlx_web_archive "${CMAKE_CURRENT_BINARY_DIR}/xlsxt.a")
    add_custom_command(
        OUTPUT "${_xlx_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_xlx_web_object}" "${_xlx_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_xlx_web_object}"
                "$<TARGET_OBJECTS:xlsxt_web_objects>" "$<TARGET_FILE:xlsxt_deps>"
        COMMAND ${CMAKE_AR} rcsD "${_xlx_web_archive}" "${_xlx_web_object}"
        DEPENDS xlsxt_web_objects xlsxt_deps "$<TARGET_OBJECTS:xlsxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking xlsxt.a for the web (shim + libxlsxwriter + zlib + Expat, one object)"
        VERBATIM)
    add_custom_target(xlsxt_web ALL DEPENDS "${_xlx_web_archive}")

    # The web tests: the same two programs, linked against the ARCHIVE and
    # run by node (ctest), so what is tested is the file that would ship.
    # NODERAWFS gives them the real file system: both write and read files.
    if(XLSXT_BUILD_TESTS)
        enable_testing()
        find_program(XLSXT_NODE node REQUIRED)
        foreach(_test smoke fuzz)
            add_executable(xlsxt_${_test} tests/${_test}_test.c)
            add_dependencies(xlsxt_${_test} xlsxt_web)
            set_target_properties(xlsxt_${_test} PROPERTIES SUFFIX ".js"
                                  C_STANDARD 11 C_STANDARD_REQUIRED ON)
            target_link_libraries(xlsxt_${_test} PRIVATE "${_xlx_web_archive}")
            target_link_options(xlsxt_${_test} PRIVATE
                -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node -sNODERAWFS=1 -sSTACK_SIZE=1048576)
            add_test(NAME ${_test} COMMAND "${XLSXT_NODE}" "$<TARGET_FILE:xlsxt_${_test}>")
        endforeach()
    endif()

    if(XLSXT_PLACE_IN_SRC)
        set(_xlx_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET xlsxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_xlx_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_xlx_web_archive}" "${_xlx_bundle_dir}/xlsxt.a"
            COMMENT "Bundling xlsxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# The shim and the three libraries, linked into a single shared library under
# its BARE name: xlsxt.so (Linux, Android), xlsxt.dylib (macOS), xlsxt.dll
# (Windows). The bare name is the one the tree holds on every platform and,
# on Linux, the soname the engine's dlopen asks for. The LCB bind string
# "c:xlsxt>..." resolves to it.
# ---------------------------------------------------------------------------
add_library(xlsxt SHARED src/xlsx_shim.c)
target_link_libraries(xlsxt PRIVATE xlsxt_deps)

set_target_properties(xlsxt PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    PREFIX ""
    OUTPUT_NAME "xlsxt"
)

# Keep the shim warning-clean (these flags apply only to xlsx_shim.c).
if(MSVC)
    target_compile_options(xlsxt PRIVATE /W3)
else()
    target_compile_options(xlsxt PRIVATE -Wall -Wextra)
endif()

# Export xlx_* and nothing else. Everything is compiled with hidden
# visibility, so this changes little on ELF, but it is the family's rule
# since enetxt's release run 10 leaked a vendored library's symbols: the
# script, not the default, decides. src/xlsxt.map is the one source for GNU
# ld and, by the pattern below, for ld64.
set(_xlx_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/xlsxt.map")
if(APPLE)
    set(_xlx_exported "${CMAKE_CURRENT_BINARY_DIR}/xlsxt.exported_symbols")
    file(WRITE "${_xlx_exported}" "_xlx_*\n")
    target_link_options(xlsxt PRIVATE "-Wl,-exported_symbols_list,${_xlx_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_xlx_version_script}" XLX_HAVE_VERSION_SCRIPT)
    if(XLX_HAVE_VERSION_SCRIPT)
        target_link_options(xlsxt PRIVATE "-Wl,--version-script=${_xlx_version_script}")
        set_target_properties(xlsxt PROPERTIES LINK_DEPENDS "${_xlx_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The two tests. Both link the shared library and reach it only through its
# exports, as the engine does.
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DXLSXT_BUILD_TESTS=ON
#   cmake --build build --config Release
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(XLSXT_BUILD_TESTS)
    enable_testing()
    foreach(_test smoke fuzz)
        add_executable(xlsxt_${_test} tests/${_test}_test.c)
        set_target_properties(xlsxt_${_test} PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
        target_link_libraries(xlsxt_${_test} PRIVATE xlsxt)
        if(MSVC)
            target_compile_definitions(xlsxt_${_test} PRIVATE _CRT_SECURE_NO_WARNINGS)
        else()
            target_link_libraries(xlsxt_${_test} PRIVATE m)
        endif()
        add_test(NAME ${_test} COMMAND xlsxt_${_test})
    endforeach()
endif()
