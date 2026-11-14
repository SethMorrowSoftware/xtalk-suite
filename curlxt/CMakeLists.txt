# curlxt - libcurl (HTTP(S), FTP(S), SFTP, SMTP(S), WebSocket) for OpenXTalk /
# the xTalk family. The cux_* ABI over libcurl's multi interface, built as
# ONE bare-token shared library, with the smoke test driving the exported
# surface against a loopback HTTP server it runs itself. Both run clean under
# ASan/UBSan via the global CURLXT_SANITIZE knob below (which instruments the
# pinned libcurl and libssh2 too).
cmake_minimum_required(VERSION 3.16)
project(curlxt CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# libcurl and libssh2 build as static archives folded into ONE shared library,
# so everything must be position-independent, set BEFORE FetchContent
# (enetxt's lesson: non-PIC static code cannot link into the shared lib).
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(CURLXT_BUILD_TESTS "Build the smoke test" OFF)

# Windows: the STATIC C/C++ runtime (/MT) for every target, libcurl and
# libssh2 included, so curlxt.dll imports no MSVCP140/VCRUNTIME140 and loads on
# a PC without the Visual C++ Redistributable (enetxt and box2dxt need it
# bundled beside them; this library does not). Set before FetchContent so the
# dependencies inherit it; CMP0091 is NEW under cmake_minimum_required 3.16.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
# libssh2 asks for cmake 3.7, where CMP0091 would be OLD and the variable
# above ignored in its directory; this makes it NEW there too.
set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)
set(CURL_STATIC_CRT ON CACHE BOOL "" FORCE)

# The family's sanitizer knob, injected GLOBALLY before FetchContent so the
# dependencies are instrumented too. This shim starts no thread, so "address"
# is the lane that matters (curl's threaded resolver is curl's own).
set(CURLXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address'")
if(CURLXT_SANITIZE STREQUAL "address")
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -g)
  add_link_options(-fsanitize=address,undefined)
endif()

# ------------------------------------------------------------ dependencies ---
# Pin every version; bump deliberately. curl matches OXT-Beyond's own pin
# (prebuilt/versions/curl), so the engine and this extension agree on what
# "libcurl" means.
include(FetchContent)
set(CURLXT_CURL_VERSION "8.22.0")
set(CURLXT_LIBSSH2_VERSION "1.11.1")

# TLS: Schannel on Windows (the system certificate store, nothing to ship),
# OpenSSL elsewhere: whatever find_package finds. The release lanes point it
# at a pinned static OpenSSL 3.5.9 (64-bit Linux, both mac slices) or the
# system's (32-bit Linux); see THIRD-PARTY-LICENSES.md.
if(WIN32)
  set(_cux_crypto_backend "WinCNG")
else()
  find_package(OpenSSL REQUIRED)
  set(_cux_crypto_backend "OpenSSL")
endif()

# libssh2 first: curl's SFTP/SCP support is built over it.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(ENABLE_ZLIB_COMPRESSION OFF CACHE BOOL "" FORCE)
set(CRYPTO_BACKEND "${_cux_crypto_backend}" CACHE STRING "" FORCE)
set(LIBSSH2_NO_INSTALL ON CACHE BOOL "" FORCE)
FetchContent_Declare(libssh2
  URL      https://github.com/libssh2/libssh2/releases/download/libssh2-${CURLXT_LIBSSH2_VERSION}/libssh2-${CURLXT_LIBSSH2_VERSION}.tar.xz
  URL_HASH SHA256=9954cb54c4f548198a7cbebad248bdc87dd64bd26185708a294b2b50771e3769
)
FetchContent_MakeAvailable(libssh2)

# Hand curl the libssh2 we just built, by its target, so its finder neither
# searches the system nor picks up a different libssh2.
set(LIBSSH2_INCLUDE_DIR "${libssh2_SOURCE_DIR}/include" CACHE PATH "" FORCE)
set(LIBSSH2_LIBRARY libssh2_static CACHE STRING "" FORCE)

set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
set(BUILD_LIBCURL_DOCS OFF CACHE BOOL "" FORCE)
set(BUILD_MISC_DOCS OFF CACHE BOOL "" FORCE)
set(ENABLE_CURL_MANUAL OFF CACHE BOOL "" FORCE)
set(CURL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(CURL_USE_LIBSSH2 ON CACHE BOOL "" FORCE)
set(CURL_USE_LIBSSH OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBPSL OFF CACHE BOOL "" FORCE)
set(USE_LIBIDN2 OFF CACHE BOOL "" FORCE)
set(USE_NGHTTP2 OFF CACHE BOOL "" FORCE)
set(CURL_ZLIB OFF CACHE BOOL "" FORCE)
set(CURL_BROTLI OFF CACHE BOOL "" FORCE)
set(CURL_ZSTD OFF CACHE BOOL "" FORCE)
set(CURL_USE_PKGCONFIG OFF CACHE BOOL "" FORCE)
set(CURL_USE_GSSAPI OFF CACHE BOOL "" FORCE)
# Only the protocols this library is for (the shim also refuses the rest at
# run time with CURLOPT_PROTOCOLS_STR, so a redirect cannot reach them).
foreach(_p LDAP LDAPS DICT TELNET TFTP GOPHER MQTT RTSP POP3 IMAP SMB IPFS FILE)
  set(CURL_DISABLE_${_p} ON CACHE BOOL "" FORCE)
endforeach()
if(WIN32)
  set(CURL_USE_SCHANNEL ON CACHE BOOL "" FORCE)
  set(CURL_USE_OPENSSL OFF CACHE BOOL "" FORCE)
else()
  set(CURL_USE_OPENSSL ON CACHE BOOL "" FORCE)
endif()
# No CA path from the BUILD machine baked into the library: the release Linux
# build runs in an AlmaLinux image whose bundle path is not Debian's. The shim
# finds the running system's bundle itself (linux_ca_bundle) or asks for the
# native store (CURLSSLOPT_NATIVE_CA).
set(CURL_CA_BUNDLE "none" CACHE STRING "" FORCE)
set(CURL_CA_PATH "none" CACHE STRING "" FORCE)
# macOS: OpenSSL has no idea where the Keychain is, so without SecTrust a Mac
# build would verify against NOTHING and refuse every https host. curl's
# USE_APPLE_SECTRUST hands verification to the OS (curl 8.17 and later), which
# is what CURLSSLOPT_NATIVE_CA asks for.
if(APPLE)
  set(USE_APPLE_SECTRUST ON CACHE BOOL "" FORCE)
endif()
FetchContent_Declare(curl
  URL      https://github.com/curl/curl/releases/download/curl-8_22_0/curl-${CURLXT_CURL_VERSION}.tar.xz
  URL_HASH SHA256=f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7
)
FetchContent_MakeAvailable(curl)

# Warning flags for OUR translation units only; the dependencies ride in as
# SYSTEM includes. MSVC gets /W3 (cl rejects -Wextra: enetxt's lesson).
add_library(curlxt_flags INTERFACE)
if(MSVC)
  target_compile_options(curlxt_flags INTERFACE /W3 /EHsc /permissive-)
  target_compile_definitions(curlxt_flags INTERFACE
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_options(curlxt_flags INTERFACE -Wall -Wextra)
endif()

# The shim: ONE shared library, bare token (no 'lib' prefix), the family's
# shipping shape - src/code/<arch>-<platform>/curlxt.so etc.
add_library(curlxt SHARED src/curl_shim.cpp)
set_target_properties(curlxt PROPERTIES PREFIX "" OUTPUT_NAME curlxt)
target_link_libraries(curlxt PRIVATE curlxt_flags)
target_compile_definitions(curlxt PRIVATE CURL_STATICLIB)
target_include_directories(curlxt SYSTEM PRIVATE ${curl_SOURCE_DIR}/include)
target_link_libraries(curlxt PRIVATE libcurl_static)

# --------------------------------------------- the macOS export-list bridge ---
# Derived from the .map, exactly as enetxt does (see its CMakeLists for why
# one source of truth matters: release run 10).
function(curlxt_apple_export_list target map_file)
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
    string(REPLACE ";" "" _tok "${_tok}")
    if(NOT _tok STREQUAL "")
      string(APPEND _lines "_${_tok}\n")
    endif()
  endforeach()
  if(_lines STREQUAL "")
    message(FATAL_ERROR "curlxt_apple_export_list: parsed NO symbols out of ${map_file}")
  endif()
  set(_exp "${CMAKE_CURRENT_BINARY_DIR}/curlxt.exported_symbols")
  file(WRITE "${_exp}" "${_lines}")
  target_link_options(${target} PRIVATE "-Wl,-exported_symbols_list,${_exp}")
  set_target_properties(${target} PROPERTIES LINK_DEPENDS "${map_file}")
endfunction()

include(CheckLinkerFlag OPTIONAL RESULT_VARIABLE _cux_have_check_linker_flag)
set(_cux_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/curlxt.map")
if(_cux_have_check_linker_flag AND UNIX AND NOT APPLE)
  check_linker_flag(CXX "-Wl,--version-script=${_cux_version_script}"
                    CUX_HAVE_VERSION_SCRIPT)
  if(CUX_HAVE_VERSION_SCRIPT)
    target_link_options(curlxt PRIVATE "-Wl,--version-script=${_cux_version_script}")
    set_target_properties(curlxt PROPERTIES LINK_DEPENDS "${_cux_version_script}")
  endif()
endif()
curlxt_apple_export_list(curlxt "${_cux_version_script}")

if(CURLXT_BUILD_TESTS)
  enable_testing()
  # The gate: the whole exported ABI against a loopback HTTP server the test
  # runs itself. Links ONLY the shared library - every call goes through the
  # real export surface. The handle table is tested here too (header-only).
  add_executable(curl_smoke_test tests/curl_smoke_test.cpp)
  target_link_libraries(curl_smoke_test PRIVATE curlxt_flags curlxt)
  target_include_directories(curl_smoke_test PRIVATE src)
  if(WIN32)
    target_link_libraries(curl_smoke_test PRIVATE ws2_32)
  else()
    find_package(Threads REQUIRED)
    target_link_libraries(curl_smoke_test PRIVATE Threads::Threads)
  endif()
  add_test(NAME curl_smoke_test COMMAND curl_smoke_test)
endif()
