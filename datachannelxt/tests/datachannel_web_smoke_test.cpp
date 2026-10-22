/* datachannel_web_smoke_test.cpp - the node smoke test for the web shim
 * (src/datachannel_web.cpp, wasm32-emscripten, EXPERIMENTAL 2026-10-21).
 *
 * Linked against the ARCHIVE that ships (src/code/wasm32-emscripten/
 * datachannelxt.a, built by CMakeLists.txt's web branch) and run by node, so
 * what is tested is the committed file. Node has no WebRTC, so this pins what
 * a page without RTCPeerConnection sees and every no-WebRTC-needed contract:
 *
 *   1. dcx_abi_version answers DCX_ABI_VERSION.
 *   2. dcx_init and dcx_peer_new fail (DCX_ERR_NATIVE, 0) and dcx_last_error
 *      says why, naming RTCPeerConnection.
 *   3. The stale-handle surface: every getter answers 0, empty or -1 and
 *      every action DCX_ERR_BAD_HANDLE, as datachannel_shim.cpp does, and the
 *      frees are harmless.
 *   4. The out-buffer convention: -needed when the buffer is short.
 *   5. dcx_poll on an empty queue writes the zero count and answers 0.
 *   6. dcx_cleanup is idempotent.
 *
 * The live half (a loopback: negotiation, both channels open, text, binary,
 * the cap-sized send and its dcBufferedLow) runs in a browser, where
 * OXT-Beyond's web IDE check runs tests/datachannel-selftest.livecodescript.
 */

#include "dcx_abi.h"

#include <cstdio>
#include <cstring>

static int g_failures = 0;

#define CHECK(cond)                                                      \
    do {                                                                 \
        if (cond) {                                                      \
            std::printf("ok    %s\n", #cond);                            \
        } else {                                                         \
            std::printf("FAIL  %s  (line %d)\n", #cond, __LINE__);       \
            ++g_failures;                                                \
        }                                                                \
    } while (0)

int main() {
    char buf[256];
    int n;

    /* 1 */
    CHECK(dcx_abi_version() == DCX_ABI_VERSION);

    /* 2 */
    CHECK(dcx_init() == DCX_ERR_NATIVE);
    n = dcx_last_error(buf, sizeof buf - 1);
    buf[n > 0 ? n : 0] = '\0';
    CHECK(std::strstr(buf, "RTCPeerConnection") != nullptr);
    CHECK(dcx_peer_new("") == 0);
    CHECK(dcx_peer_new("stun:stun.example.com:3478") == 0);

    /* 3 */
    CHECK(dcx_peer_close(0) == DCX_ERR_BAD_HANDLE);
    CHECK(dcx_peer_state(0) == -1);
    CHECK(dcx_gathering_state(0) == -1);
    CHECK(dcx_local_description(0, buf, sizeof buf) == 0);
    CHECK(dcx_local_description_type(0, buf, sizeof buf) == 0);
    CHECK(dcx_selected_candidate_pair(0, buf, sizeof buf) == 0);
    CHECK(dcx_set_local_description(0, "offer") == DCX_ERR_BAD_HANDLE);
    CHECK(dcx_set_remote_description(0, "v=0", "offer") == DCX_ERR_BAD_HANDLE);
    CHECK(dcx_add_remote_candidate(0, "candidate:1 1 UDP 1 10.0.0.1 9 typ host", "") ==
          DCX_ERR_BAD_HANDLE);
    CHECK(dcx_channel_new(0, "x") == 0);
    CHECK(dcx_channel_new_ex(0, "x", "proto", 0, -1, -1, 0, -1) == 0);
    CHECK(dcx_channel_close(0) == DCX_ERR_BAD_HANDLE);
    CHECK(dcx_send_text(0, "x") == DCX_ERR_BAD_HANDLE);
    CHECK(dcx_send_data(0, "x", 1) == DCX_ERR_BAD_HANDLE);
    CHECK(dcx_channel_label(0, buf, sizeof buf) == 0);
    CHECK(dcx_channel_protocol(0, buf, sizeof buf) == 0);
    CHECK(dcx_channel_stream_id(0) == -1);
    CHECK(dcx_channel_is_open(0) == 0);
    CHECK(dcx_channel_peer(0) == 0);
    CHECK(dcx_channel_max_message(0) == -1);
    CHECK(dcx_buffered_amount(0) == -1);
    CHECK(dcx_set_buffered_low_threshold(0, 4096) == DCX_ERR_BAD_HANDLE);
    dcx_peer_free(0);
    dcx_peer_free(12345);
    dcx_channel_free(0);
    dcx_channel_free(12345);
    CHECK(dcx_last_error(buf, sizeof buf) > 0);

    /* 4 */
    CHECK(dcx_last_error(buf, 2) < -2);
    dcx_clear_error();
    CHECK(dcx_last_error(buf, sizeof buf) == 0);
    n = dcx_library_version(buf, sizeof buf - 1);
    buf[n > 0 ? n : 0] = '\0';
    CHECK(std::strstr(buf, "libdatachannel") != nullptr);
    CHECK(dcx_library_version(buf, 4) < 0);

    /* 5 */
    buf[0] = buf[1] = 7;
    CHECK(dcx_poll(buf, sizeof buf) == 0);
    CHECK(buf[0] == 0 && buf[1] == 0);

    /* 6 */
    CHECK(dcx_cleanup() == DCX_OK);
    CHECK(dcx_cleanup() == DCX_OK);

    if (g_failures) {
        std::printf("datachannel_web_smoke_test: %d FAILURE(S)\n", g_failures);
        return 1;
    }
    std::printf("datachannel_web_smoke_test: all checks passed\n");
    return 0;
}
