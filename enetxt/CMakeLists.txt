# enetxt - ENet (reliable UDP) for OpenXTalk / the xTalk family.
# PHASE 1 as-built (NEXT-EXTENSIONS-PLAN.md Part III.7): the full enx_ ABI
# (v2) - hosts, peers, send/broadcast, tuning, status records, the lossless
# poll drain - built as ONE bare-token shared library, with the smoke test
# driving the whole exported surface over a live loopback and the
# codec/handle-table unit test running header-only. Both run clean under
# ASan/UBSan via the global ENETXT_SANITIZE knob below (which instruments
# the pinned ENet dependency too).
cmake_minimum_required(VERSION 3.16)
project(enetxt CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ENet builds as a static archive that we fold into ONE shared library, so
# everything (the dependency included) must be position-independent — set it
# globally BEFORE FetchContent or the link fails with ld: "bad value".
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(ENETXT_BUILD_TESTS "Build the smoke test and the record/handle test" OFF)

# The family's sanitizer knob: a STRING ("address" or "thread"), injected
# GLOBALLY before FetchContent so the whole dependency is instrumented too
# (the datachannelxt lesson: per-target flags leave the dependency bare and
# the sanitizers false-positive on its internals). ENet has no threads, so
# "thread" is academic here - "address" is the lane that matters.
set(ENETXT_SANITIZE "" CACHE STRING "Sanitizer: '', 'address', or 'thread'")
if(ENETXT_SANITIZE STREQUAL "address")
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -g)
  add_link_options(-fsanitize=address,undefined)
elseif(ENETXT_SANITIZE STREQUAL "thread")
  add_compile_options(-fsanitize=thread -g)
  add_link_options(-fsanitize=thread)
endif()

# Pin the dependency (the family rule: pin every version; bump deliberately).
include(FetchContent)
FetchContent_Declare(enet
  GIT_REPOSITORY https://github.com/lsalzman/enet.git
  GIT_TAG        v1.3.18
)
FetchContent_MakeAvailable(enet)

# Warning flags for OUR translation units only (the shim + the tests); ENet
# rides in as a SYSTEM include so its warnings stay mute. MSVC does not
# understand the GCC spellings - `cl` rejects -Wextra outright with
# "D8021: invalid numeric argument '/Wextra'" - so it gets /W3, matching the
# sibling members. (This surfaced the first time the Windows lanes actually
# ran: the member workflow that defines them is inert in the monorepo, so the
# unconditional flags below had never been exercised by a real MSVC build.)
add_library(enetxt_flags INTERFACE)
if(MSVC)
  target_compile_options(enetxt_flags INTERFACE /W3 /EHsc /permissive-)
  target_compile_definitions(enetxt_flags INTERFACE
    WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_options(enetxt_flags INTERFACE -Wall -Wextra)
endif()

# The shim: ONE shared library, bare token (no 'lib' prefix), same shipping
# shape as torrentxt/datachannelxt - src/code/<arch>-<platform>/enetxt.so etc.
add_library(enetxt SHARED src/enet_shim.cpp)
set_target_properties(enetxt PROPERTIES PREFIX "" OUTPUT_NAME enetxt)
target_link_libraries(enetxt PRIVATE enetxt_flags)
# ENet's headers are SYSTEM headers to us: their warnings are not our warnings.
target_include_directories(enetxt SYSTEM PRIVATE ${enet_SOURCE_DIR}/include)
target_link_libraries(enetxt PRIVATE enet)

# Winsock + the multimedia timer, on Windows. ENet's own CMakeLists links these
# ONLY under MINGW (`if (MINGW) target_link_libraries(enet winmm ws2_32)`), so
# under MSVC nothing does - and because we fold ENet in as a STATIC archive, the
# unresolved imports land on OUR shared library: 28 unresolved __imp_htonl /
# __imp_ntohl / socket externals at link time. Pre-existing, and invisible until
# a real MSVC build ran for the first time under the root CI matrix.
if(WIN32)
  target_link_libraries(enetxt PRIVATE ws2_32 winmm)
endif()

# --------------------------------------------- the macOS export-list bridge ---
# ld64 has no --version-script. Its equivalent is -exported_symbols_list, which
# takes literal names and globs, and Mach-O decorates every C symbol with a
# leading underscore (enx_* becomes _enx_*).
#
# The list is DERIVED from the .map at configure time rather than maintained
# beside it. Two hand-kept lists is how a symbol reaches one platform and
# misses the other - which is exactly the divergence this replaces: the version
# script has filtered the ELF .so since it was written, nothing filtered
# Mach-O, and release run 10 (2026-08-26) measured the result at 70 undefined-
# by-the-shim exports in the universal dylib. One source of truth, two flags.
#
# Unconditional on Apple, unlike torrentxt's, and the difference is real rather
# than an oversight: torrentxt skips its script when a SYSTEM (shared)
# libtorrent is linked, because hiding a statically linked libstdc++ would give
# this library a private C++ runtime while the shared dependency uses the
# process's. enetxt has no system path at all (ENet is FetchContent-only, and
# it is C), so there is no second C++ runtime to disagree with.
function(enetxt_apple_export_list target map_file)
  if(NOT APPLE)
    return()
  endif()
  file(READ "${map_file}" _txt)
  string(REGEX REPLACE "/\\*([^*]|\\*+[^*/])*\\*+/" "" _txt "${_txt}")
  string(REGEX MATCH "global:(.*)local:" _unused "${_txt}")
  set(_globals "${CMAKE_MATCH_1}")
  string(REPLACE "\n" ";" _globals "${_globals}")
  set(_lines "")
  foreach(_tok IN LISTS _globals)
    string(STRIP "${_tok}" _tok)
    if(NOT _tok STREQUAL "")
      string(APPEND _lines "_${_tok}\n")
    endif()
  endforeach()
  if(_lines STREQUAL "")
    message(FATAL_ERROR
      "enetxt_apple_export_list: parsed NO symbols out of ${map_file}. An empty "
      "-exported_symbols_list would hide the whole ABI and the library "
      "would load with nothing bound, so this refuses rather than "
      "shipping it.")
  endif()
  set(_exp "${CMAKE_CURRENT_BINARY_DIR}/enetxt.exported_symbols")
  file(WRITE "${_exp}" "${_lines}")
  target_link_options(${target} PRIVATE "-Wl,-exported_symbols_list,${_exp}")
  set_target_properties(${target} PROPERTIES LINK_DEPENDS "${map_file}")
endfunction()

# Export ONLY the enx_* ABI. Statically linked ENet objects otherwise inherit
# the .so's public visibility and export ~65 enet_* symbols, which another
# extension bundling its own ENet could interpose with. -fvisibility=hidden on
# this target cannot reach ENet (its own CMake target compiles it), so filter
# at link time instead. GNU ld / lld for the .so, -exported_symbols_list for
# the dylib, a .def file on Windows. See src/enetxt.map for the full why.
include(CheckLinkerFlag OPTIONAL RESULT_VARIABLE _enx_have_check_linker_flag)
set(_enx_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/enetxt.map")
if(_enx_have_check_linker_flag AND UNIX AND NOT APPLE)
  check_linker_flag(CXX "-Wl,--version-script=${_enx_version_script}"
                    ENX_HAVE_VERSION_SCRIPT)
  if(ENX_HAVE_VERSION_SCRIPT)
    target_link_options(enetxt PRIVATE
                        "-Wl,--version-script=${_enx_version_script}")
    # Relink when the map changes; it is part of the ABI, not a loose input.
    set_target_properties(enetxt PROPERTIES LINK_DEPENDS "${_enx_version_script}")
  endif()
endif()
enetxt_apple_export_list(enetxt "${_enx_version_script}")

if(ENETXT_BUILD_TESTS)
  enable_testing()

  # The Phase 1 gate: the whole exported ABI over a live loopback. Links ONLY
  # the shared library — every call goes through the real export surface.
  add_executable(enet_smoke_test tests/enet_smoke_test.cpp)
  target_link_libraries(enet_smoke_test PRIVATE enetxt_flags)
  target_link_libraries(enet_smoke_test PRIVATE enetxt)
  add_test(NAME enet_smoke_test COMMAND enet_smoke_test)

  # Codec + handle-table unit test: header-only, no ENet, runs anywhere.
  add_executable(record_handle_test tests/record_handle_test.cpp)
  target_link_libraries(record_handle_test PRIVATE enetxt_flags)
  add_test(NAME record_handle_test COMMAND record_handle_test)
endif()
