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

# Export ONLY the enx_* ABI. Statically linked ENet objects otherwise inherit
# the .so's public visibility and export ~65 enet_* symbols, which another
# extension bundling its own ENet could interpose with. -fvisibility=hidden on
# this target cannot reach ENet (its own CMake target compiles it), so filter
# at link time instead. GNU ld / lld only: the Windows lane uses a .def file
# and macOS defaults, so probe before applying rather than breaking those.
# See src/enetxt.map for the full why.
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
