/* expat_config.h - Expat's build configuration, as xlsxt builds it.
 *
 * Expat's own CMake writes this file from probes of the build machine. xlsxt
 * compiles Expat's four sources itself (CMakeLists.txt says why), so the
 * answers are fixed here, one set for every platform the suite ships:
 *
 *   - no XML_DTD: an OOXML part may not carry a DTD, so the parser is built
 *     without parameter-entity and external-subset support at all (and the
 *     shim refuses any part that opens a DOCTYPE);
 *   - XML_GE 1: general-entity support stays in, because that is what turns
 *     on Expat's amplification accounting (the "billion laughs" guard);
 *   - no XML_NS: the shim matches element names by their local part;
 *   - the hash salt comes from /dev/urandom everywhere but Windows, where
 *     Expat uses rand_s (lib/random_rand_s.c). /dev/urandom exists on Linux,
 *     macOS, Android and under Emscripten; the newer calls (getrandom,
 *     arc4random_buf) do not exist on all of glibc 2.28, macOS 10.15 and
 *     Android API 21, which is where the release libraries are built for.
 *
 * Every target is little-endian (x86, x86-64, arm, arm64, wasm32).
 */
#ifndef EXPAT_CONFIG_H
#define EXPAT_CONFIG_H 1

#define BYTEORDER 1234
#define XML_CONTEXT_BYTES 1024
#define XML_GE 1

#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define STDC_HEADERS 1

#if !defined(_WIN32)
#define HAVE_FCNTL_H 1
#define HAVE_UNISTD_H 1
#define HAVE_SYS_TYPES_H 1
#define XML_DEV_URANDOM 1
#endif

#ifdef _MSC_VER
#define __func__ __FUNCTION__
#endif

#endif /* EXPAT_CONFIG_H */
