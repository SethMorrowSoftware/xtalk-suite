cmake_minimum_required(VERSION 3.22)
project(render3dxt LANGUAGES C)

# ---------------------------------------------------------------------------
# render3dxt - a textured 3D software renderer for OpenXTalk (OXT) and the
# xTalk family, also compatible with LiveCode 9.6.3+. This builds the C shim
# (src/render3d_shim.c), its renderer, and the two file readers it uses
# (stb_image, fast_obj: src/render3d_thirdparty.c) into ONE loadable library
# named "render3dxt", or for the web into a static archive (below).
# box3dxt/CMakeLists.txt in the suite is this file's model.
# ---------------------------------------------------------------------------

option(RENDER3DXT_BUILD_TESTS "Build the render3dxt smoke and random-call tests" OFF)
option(RENDER3DXT_PLACE_IN_SRC
       "Web build only: copy render3dxt.a into src/code/wasm32-emscripten/ after building" ON)
set(RENDER3DXT_SANITIZE "" CACHE STRING "Sanitizer: '' or 'address' (ASan + UBSan) or 'thread' (TSan)")

if(EMSCRIPTEN AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
# A renderer is a hot loop: an unoptimised build is ten times slower, so a
# configure with no build type is a Release one here too.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

if(NOT EMSCRIPTEN)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# The Windows libraries carry the C runtime (static CRT, as the suite's other
# members' do), so a PC without the Visual C++ Redistributable loads them.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(RENDER3DXT_SANITIZE STREQUAL "address")
    add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address,undefined)
elseif(RENDER3DXT_SANITIZE STREQUAL "thread")
    # The parallel drawing (render3d_shim.c, flush_queue) under ThreadSanitizer.
    add_compile_options(-fsanitize=thread -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=thread)
endif()

# 32-bit x86: SSE2 arithmetic, as box3dxt's (x87's 80-bit intermediates would
# make the same scene round differently on one platform alone).
if(NOT EMSCRIPTEN AND NOT MSVC AND CMAKE_SIZEOF_VOID_P EQUAL 4)
    include(CheckCSourceCompiles)
    check_c_source_compiles("
        #if !defined(__i386__)
        #error not 32-bit x86
        #endif
        int main(void) { return 0; }" RENDER3DXT_IS_X86_32)
    if(RENDER3DXT_IS_X86_32)
        add_compile_options(-msse2 -mfpmath=sse)
    endif()
endif()

# ---------------------------------------------------------------------------
# The two readers, fetched at pinned revisions. Neither is built by its own
# CMake (SOURCE_SUBDIR names a folder that does not exist, so nothing is
# added): both are single headers, compiled once in render3d_thirdparty.c.
#   stb_image: nothings/stb has no tags; pinned to a COMMIT (2026-11-19, which
#              carries that day's BMP height fix). Bump it for a decoder fix.
#   fast_obj:  thisistherk/fast_obj, tag v1.3, pinned by its commit id.
# -DFETCHCONTENT_SOURCE_DIR_STB=<checkout> (and _FAST_OBJ) build offline.
# ---------------------------------------------------------------------------
set(RENDER3DXT_STB_COMMIT "6b5799bae8a1fe3792691ef4b72ae26434c3e799")
set(RENDER3DXT_FAST_OBJ_COMMIT "42629f744269e004907a6fb4f16c6c7f69acc586")   # v1.3
include(FetchContent)
FetchContent_Declare(stb
    GIT_REPOSITORY https://github.com/nothings/stb.git
    GIT_TAG        ${RENDER3DXT_STB_COMMIT}
    SOURCE_SUBDIR  render3dxt-no-cmake)
FetchContent_Declare(fast_obj
    GIT_REPOSITORY https://github.com/thisistherk/fast_obj.git
    GIT_TAG        ${RENDER3DXT_FAST_OBJ_COMMIT}
    SOURCE_SUBDIR  render3dxt-no-cmake)
FetchContent_MakeAvailable(stb fast_obj)

set(R3X_SOURCES src/render3d_shim.c src/render3d_thirdparty.c)
set(R3X_INCLUDES "${stb_SOURCE_DIR}" "${fast_obj_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/src")

# The readers' own warnings are theirs (pinned, unpatched); the shim's are ours.
# -fwrapv for them alone: fast_obj reads an index with `num = 10 * num + digit`
# in a signed int, so a face written with twenty digits is signed overflow,
# which is undefined behaviour unless the compiler is told that integers wrap.
# With -fwrapv the index is merely wrong, and the shim checks every index
# against its array before it reads one (build_from_obj). MSVC wraps already.
if(MSVC)
    set_source_files_properties(src/render3d_thirdparty.c PROPERTIES COMPILE_OPTIONS "/W0")
else()
    set_source_files_properties(src/render3d_thirdparty.c PROPERTIES COMPILE_OPTIONS "-w;-fwrapv")
endif()

# ---------------------------------------------------------------------------
# The web build: wasm32-emscripten, box3dxt's mechanism. The shim is linked
# INTO OXT-Beyond's web engine, which finds "c:render3dxt>r3x_..." in a table
# of the symbols the binding names: render3dxt_web_exports(), GENERATED from
# every `binds to "c:render3dxt>NAME"` of src/render3dxt.lcb and compiled in
# one translation unit with the shim, so a bind with no shim function is a
# compile error. The web build draws on one thread.
# ---------------------------------------------------------------------------
if(EMSCRIPTEN)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/render3dxt.lcb" _r3x_lcb)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
                 "${CMAKE_CURRENT_SOURCE_DIR}/src/render3dxt.lcb")
    string(REGEX MATCHALL "binds to \"c:render3dxt>[A-Za-z_][A-Za-z0-9_]*" _r3x_binds "${_r3x_lcb}")
    set(_r3x_symbols "")
    foreach(_bind IN LISTS _r3x_binds)
        string(REGEX REPLACE ".*>" "" _symbol "${_bind}")
        list(APPEND _r3x_symbols "${_symbol}")
    endforeach()
    list(REMOVE_DUPLICATES _r3x_symbols)
    list(SORT _r3x_symbols)
    list(LENGTH _r3x_symbols _r3x_count)
    if(_r3x_count EQUAL 0)
        message(FATAL_ERROR "src/render3dxt.lcb binds no c:render3dxt> symbol: is the regular expression stale?")
    endif()
    set(_r3x_rows "")
    foreach(_symbol IN LISTS _r3x_symbols)
        string(APPEND _r3x_rows "\t{ \"${_symbol}\", (void *)${_symbol} },\n")
    endforeach()
    set(_r3x_exports_c "${CMAKE_CURRENT_BINARY_DIR}/render3dxt_web_exports.c")
    file(CONFIGURE OUTPUT "${_r3x_exports_c}" @ONLY CONTENT
"/* GENERATED by CMakeLists.txt from src/render3dxt.lcb: the shim, and the
 * @_r3x_count@ symbols the binding binds to, for OXT-Beyond's web engine. */
#include \"render3d_shim.c\"

struct r3x_web_export { const char *symbol; void *address; };

static const struct r3x_web_export k_r3x_web_exports[] = {
@_r3x_rows@\t{ NULL, NULL },
};

LC_API const struct r3x_web_export *render3dxt_web_exports(void);
LC_API const struct r3x_web_export *render3dxt_web_exports(void)
{
\treturn k_r3x_web_exports;
}
")
    message(STATUS "render3dxt web exports: ${_r3x_count} symbols from src/render3dxt.lcb")

    add_library(render3dxt_web_objects OBJECT "${_r3x_exports_c}" src/render3d_thirdparty.c)
    target_include_directories(render3dxt_web_objects PRIVATE ${R3X_INCLUDES})
    set_target_properties(render3dxt_web_objects PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
    target_compile_options(render3dxt_web_objects PRIVATE
        -O2 -g0 -Werror=implicit-function-declaration
        "-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=render3dxt"
        "-ffile-prefix-map=${CMAKE_CURRENT_BINARY_DIR}=build"
        "-ffile-prefix-map=${stb_SOURCE_DIR}=stb"
        "-ffile-prefix-map=${fast_obj_SOURCE_DIR}=fast_obj")

    set(_r3x_web_object "${CMAKE_CURRENT_BINARY_DIR}/render3dxt-web.o")
    set(_r3x_web_archive "${CMAKE_CURRENT_BINARY_DIR}/render3dxt.a")
    add_custom_command(
        OUTPUT "${_r3x_web_archive}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${_r3x_web_object}" "${_r3x_web_archive}"
        COMMAND ${CMAKE_C_COMPILER} -r -o "${_r3x_web_object}" "$<TARGET_OBJECTS:render3dxt_web_objects>"
        COMMAND ${CMAKE_AR} rcsD "${_r3x_web_archive}" "${_r3x_web_object}"
        DEPENDS render3dxt_web_objects "$<TARGET_OBJECTS:render3dxt_web_objects>"
        COMMAND_EXPAND_LISTS
        COMMENT "Linking render3dxt.a for the web (one object)"
        VERBATIM)
    add_custom_target(render3dxt_web ALL DEPENDS "${_r3x_web_archive}")

    if(RENDER3DXT_BUILD_TESTS)
        enable_testing()
        find_program(RENDER3DXT_NODE node REQUIRED)
        foreach(_t smoke fuzz)
            add_executable(render3dxt_${_t} tests/${_t}_test.c)
            add_dependencies(render3dxt_${_t} render3dxt_web)
            set_target_properties(render3dxt_${_t} PROPERTIES SUFFIX ".js" C_STANDARD 11 C_STANDARD_REQUIRED ON)
            target_link_libraries(render3dxt_${_t} PRIVATE "${_r3x_web_archive}")
            target_link_options(render3dxt_${_t} PRIVATE -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node -sNODERAWFS=1)
            add_test(NAME ${_t} COMMAND "${RENDER3DXT_NODE}" "$<TARGET_FILE:render3dxt_${_t}>")
        endforeach()
    endif()

    if(RENDER3DXT_PLACE_IN_SRC)
        set(_r3x_bundle_dir "${CMAKE_CURRENT_SOURCE_DIR}/src/code/wasm32-emscripten")
        add_custom_command(TARGET render3dxt_web POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_r3x_bundle_dir}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_r3x_web_archive}" "${_r3x_bundle_dir}/render3dxt.a"
            COMMENT "Bundling render3dxt.a -> src/code/wasm32-emscripten/"
            VERBATIM)
    endif()
    return()
endif()

# ---------------------------------------------------------------------------
# One shared library under its BARE name: render3dxt.so (Linux, Android),
# render3dxt.dylib (macOS), render3dxt.dll (Windows). The LCB bind string
# "c:render3dxt>..." resolves to it.
# ---------------------------------------------------------------------------
add_library(render3dxt SHARED ${R3X_SOURCES})
target_include_directories(render3dxt PRIVATE ${R3X_INCLUDES})

# The parallel drawing uses threads; at glibc 2.28 (the release lanes) they
# live in libpthread (box3dxt's lesson, 2026-11-20).
if(NOT MSVC)
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads REQUIRED)
    target_link_libraries(render3dxt PRIVATE Threads::Threads)
    target_link_libraries(render3dxt PRIVATE m)
endif()

set_target_properties(render3dxt PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_VISIBILITY_PRESET hidden
    PREFIX ""
    OUTPUT_NAME "render3dxt"
)

if(MSVC)
    target_compile_options(render3dxt PRIVATE /W3)
    target_compile_definitions(render3dxt PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(render3dxt PRIVATE -Wall -Wextra)
endif()

# Export r3x_* and nothing else (the enetxt lesson: a vendored library's
# symbols must not leak). src/render3dxt.map for GNU ld; the same pattern for
# ld64.
set(_r3x_version_script "${CMAKE_CURRENT_SOURCE_DIR}/src/render3dxt.map")
if(APPLE)
    set(_r3x_exported "${CMAKE_CURRENT_BINARY_DIR}/render3dxt.exported_symbols")
    file(WRITE "${_r3x_exported}" "_r3x_*\n")
    target_link_options(render3dxt PRIVATE "-Wl,-exported_symbols_list,${_r3x_exported}")
elseif(UNIX)
    include(CheckLinkerFlag)
    check_linker_flag(C "-Wl,--version-script=${_r3x_version_script}" R3X_HAVE_VERSION_SCRIPT)
    if(R3X_HAVE_VERSION_SCRIPT)
        target_link_options(render3dxt PRIVATE "-Wl,--version-script=${_r3x_version_script}")
        set_target_properties(render3dxt PROPERTIES LINK_DEPENDS "${_r3x_version_script}")
    endif()
endif()

# ---------------------------------------------------------------------------
# The tests: tests/smoke_test.c (every export, pixels checked) and
# tests/fuzz_test.c (every export, any argument, any order). Both carry the
# model and picture files of tests/assets/ inside them (tests/test_assets.h,
# generated by tools/build-test-assets.py), so they run from any folder and
# on a device that has no checkout.
#   cmake -S . -B build -DRENDER3DXT_BUILD_TESTS=ON && cmake --build build
#   ctest --test-dir build --output-on-failure
# ---------------------------------------------------------------------------
if(RENDER3DXT_BUILD_TESTS)
    enable_testing()
    foreach(_t smoke fuzz)
        add_executable(render3dxt_${_t} tests/${_t}_test.c)
        set_target_properties(render3dxt_${_t} PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
        target_link_libraries(render3dxt_${_t} PRIVATE render3dxt)
        if(MSVC)
            target_compile_definitions(render3dxt_${_t} PRIVATE _CRT_SECURE_NO_WARNINGS)
        else()
            target_link_libraries(render3dxt_${_t} PRIVATE m)
        endif()
        add_test(NAME ${_t} COMMAND render3dxt_${_t})
    endforeach()
endif()
