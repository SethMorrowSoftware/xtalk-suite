/*
 * bcx_exports.h - the shim's exports, declared as the engine's FFI sees
 * them: plain C. Shared by tests/smoke_test.cpp and tests/fuzz_test.cpp.
 * tools/check-lcb-signatures.py holds src/barcodext.lcb to the definitions
 * in src/barcode_shim.cpp; a declaration here that disagreed with them
 * would fail the link (C names) or the tests.
 */
#ifndef BCX_EXPORTS_H
#define BCX_EXPORTS_H

#include <cstdint>
extern "C" {
int bcx_abi_version(void);
const char *bcx_library_version(void);
const char *bcx_last_error(void);
int bcx_text_length(const char *text);
const char *bcx_format_names(int writable);
int bcx_read_image(const unsigned char *pixels, int length, int width, int height, const char *formats, const char *options);
int bcx_result_count(void);
const char *bcx_result_text(int index);
const char *bcx_result_format(int index);
const char *bcx_result_content_type(int index);
const char *bcx_result_symbology_id(int index);
const char *bcx_result_position(int index);
const char *bcx_result_extra(int index, const char *key);
const char *bcx_result_error(int index);
int bcx_result_bytes(int index);
const unsigned char *bcx_bytes_pointer(void);
int bcx_result_orientation(int index);
int bcx_result_is_valid(int index);
int bcx_result_is_mirrored(int index);
int bcx_result_is_inverted(int index);
void bcx_results_release(void);
int bcx_create_symbol(const unsigned char *content, int length, int isText, const char *format, const char *options);
int bcx_render_image(int scale, int quietZone, int showText);
int bcx_render_width(void);
int bcx_render_height(void);
const unsigned char *bcx_render_pixels(void);
int bcx_render_pixels_length(void);
const char *bcx_svg_text(int scale, int quietZone, int showText);
const char *bcx_modules_text(void);
void bcx_created_release(void);
}

#endif
