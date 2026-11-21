/*
 * render3d_thirdparty.c
 * ----------------------------------------------------------------------------
 * The two proven libraries render3dxt reads files with, compiled in ONE
 * translation unit of their own so that their warnings and their macros stay
 * out of the shim:
 *
 *   - stb_image (Sean Barrett, public domain / MIT; nothings/stb, pinned to a
 *     commit in CMakeLists.txt): PNG, JPEG, BMP and TGA textures. Only those
 *     four decoders are compiled: every decoder is code that reads a
 *     stranger's file, and a format nobody asked for is attack surface with
 *     no user. No HDR, no linear float path, and no image wider or taller
 *     than R3X_MAX_TEXTURE (the shim's limit, repeated here because the
 *     decoder must refuse BEFORE it allocates).
 *   - fast_obj (Richard Knight, MIT; thisistherk/fast_obj, tag v1.3): Wavefront
 *     OBJ and its MTL materials. fast_obj does NOT check that a face's indices
 *     name a vertex that exists; the shim does, for every index, before it
 *     reads one (r3x_mesh_load_obj's build_from_obj).
 *
 * On Windows stb_image reads its file names as UTF-8 (STBI_WINDOWS_UTF8),
 * which is what the binding passes; fast_obj is given the shim's own UTF-8
 * file callbacks for the same reason.
 * ----------------------------------------------------------------------------
 */

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_BMP
#define STBI_ONLY_TGA
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_WINDOWS_UTF8
#define STBI_MAX_DIMENSIONS 8192
#include "stb_image.h"

#define FAST_OBJ_IMPLEMENTATION
#include "fast_obj.h"
