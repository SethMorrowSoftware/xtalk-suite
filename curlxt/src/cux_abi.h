/* cux_abi.h - the stable C ABI surface of curlxt.
 *
 * The contract carried from the family (torrentxt btx_, enetxt enx_,
 * datachannelxt dcx_):
 *   - every exported symbol keeps the cux_ prefix forever (LCB binds by name);
 *   - no exception ever crosses extern "C" (the CUX_GUARD_* firewall below);
 *   - integers cross as int, reals (byte counts, times) as double, text as a
 *     NUL-terminated UTF-8 string in and a pointer+capacity buffer out, byte
 *     buffers as pointer+length;
 *   - CUX_ABI_VERSION bumps on ANY change; the LCB layer refuses skew.
 *
 * THE MODEL. One request = one integer handle. Script makes it
 * (cux_request_new), configures it (cux_set_*), starts it (cux_start), and
 * then either drives it to the end on the spot (cux_wait: the synchronous
 * calls) or lets cux_poll drive every running request a step at a time on a
 * timer and report which ones finished. Nothing moves between calls: like
 * enetxt, this shim starts no thread of its own and never calls script.
 * Results stay in the shim until script reads them (cux_info, cux_text,
 * cux_body) and frees the handle (cux_free).
 *
 * Every enum below is APPEND-ONLY and mirrored by a `constant k...` in
 * src/curl.lcb; tools/check-abi-registry.py proves the mirror.
 */
#ifndef CUX_ABI_H
#define CUX_ABI_H

/* v1: the first surface.
 * v2 (2026-11-20): WebSockets. Six cux_ws_* entry points, the CUX_WS_*
 *     values, one integer option, seven info fields and one text field, all
 *     APPENDED: every v1 symbol, number and behaviour is as it was. */
#define CUX_ABI_VERSION 2

#if defined(_WIN32)
#  define CUX_API __declspec(dllexport)
#  define CUX_CALL __cdecl
#else
#  define CUX_API __attribute__((visibility("default")))
#  define CUX_CALL
#endif

/* Error space (negative returns from action-style entry points). */
#define CUX_OK              0
#define CUX_ERR_GENERIC   (-1)
#define CUX_ERR_STALE     (-2)
#define CUX_ERR_ARG       (-3)
#define CUX_ERR_STATE     (-4)
#define CUX_ERR_NATIVE    (-5)
#define CUX_ERR_THROWN    (-6)
#define CUX_ERR_NOT_INIT  (-7)

/* Request states (CUI_STATE). */
#define CUX_STATE_NEW      0
#define CUX_STATE_RUNNING  1
#define CUX_STATE_DONE     2

/* Integer options (cux_set_int). */
#define CUO_TIMEOUT_MS          1   /* whole transfer; 0 = none            */
#define CUO_CONNECT_TIMEOUT_MS  2   /* 0 = curl's default (300 s)          */
#define CUO_FOLLOW_REDIRECTS    3   /* 0 / 1                               */
#define CUO_MAX_REDIRECTS       4   /* -1 = unlimited                      */
#define CUO_VERIFY_PEER         5   /* 0 / 1 (default 1)                   */
#define CUO_VERIFY_HOST         6   /* 0 / 1 (default 1)                   */
#define CUO_LOW_SPEED_LIMIT     7   /* bytes per second                    */
#define CUO_LOW_SPEED_TIME      8   /* seconds below the limit = abort     */
#define CUO_USE_SSL             9   /* 0 none, 1 try, 2 control, 3 all     */
#define CUO_FTP_PASSIVE        10   /* 0 / 1 (default 1)                   */
#define CUO_MAX_BODY_BYTES     11   /* in-memory body cap; 0 = no cap      */
#define CUO_HTTP_VERSION       12   /* 0 default, 1 = 1.0, 2 = 1.1, 3 = 2  */
#define CUO_DNS_CACHE_SECONDS  13   /* -1 = forever                        */
#define CUO_CREATE_DIRS        14   /* FTP/SFTP: create missing dirs, 0/1  */
#define CUO_WS_CLOSE_TIMEOUT_MS 15  /* WebSocket: wait this long for the   */
                                    /* peer's close; default 5000, 0 = no  */
                                    /* limit                               */

/* Text options (cux_set_text). The "append" ones add one more value. */
#define CUO_USERNAME          101
#define CUO_PASSWORD          102
#define CUO_PROXY             103
#define CUO_CA_FILE           104
#define CUO_OUTPUT_FILE       105   /* download straight to this file      */
#define CUO_INPUT_FILE        106   /* upload straight from this file      */
#define CUO_MAIL_FROM         107
#define CUO_MAIL_RCPT         108   /* append                              */
#define CUO_USER_AGENT        109
#define CUO_SSH_PUBLIC_KEY    110
#define CUO_SSH_PRIVATE_KEY   111
#define CUO_KEY_PASSWORD      112
#define CUO_QUOTE             113   /* append: FTP/SFTP command before     */
#define CUO_POST_QUOTE        114   /* append: FTP/SFTP command after      */
#define CUO_PROXY_USERPWD     115
#define CUO_REFERER           116
#define CUO_ACCEPT_ENCODING   117   /* "" = every encoding curl supports   */

/* Numeric fields (cux_info). */
#define CUI_STATE              1
#define CUI_RESULT             2   /* CURLcode; -1 while not finished     */
#define CUI_RESPONSE_CODE      3
#define CUI_BYTES_DOWN         4
#define CUI_BYTES_UP           5
#define CUI_LENGTH_DOWN        6   /* -1 = not known                      */
#define CUI_LENGTH_UP          7   /* -1 = not known                      */
#define CUI_TOTAL_TIME         8   /* seconds                             */
#define CUI_REDIRECT_COUNT     9
#define CUI_BODY_SIZE         10   /* bytes held for cux_body             */
#define CUI_CANCELLED         11   /* 1 if script cancelled it            */
#define CUI_WS_STATE          12   /* CUX_WS_*; 0 = not a WebSocket       */
#define CUI_WS_MESSAGES       13   /* whole messages waiting to be read   */
#define CUI_WS_NEXT_TYPE      14   /* CUX_WS_KIND_TEXT/_BINARY; 0 = none  */
#define CUI_WS_NEXT_SIZE      15   /* bytes in the next message           */
#define CUI_WS_CLOSE_CODE     16   /* the close code; 0 while not closed  */
#define CUI_WS_QUEUED_BYTES   17   /* accepted by cux_ws_send, not yet    */
                                   /* handed to the socket                */
#define CUI_WS_PONGS          18   /* pong frames received                */

/* Text fields (cux_text). */
#define CUT_HEADERS            1   /* the final response's header block   */
#define CUT_ERROR              2   /* curl's detailed error, or its name  */
#define CUT_EFFECTIVE_URL      3
#define CUT_CONTENT_TYPE       4
#define CUT_METHOD             5
#define CUT_WS_CLOSE_REASON    6   /* the reason text of the close frame  */

/* Our own result code for a request script cancelled. It sits outside
 * libcurl's CURLcode range so it can never be confused with one. */
#define CUX_RESULT_CANCELLED 1000

/* WEBSOCKETS (v2). A WebSocket is a request handle from the same table,
 * made by cux_ws_new instead of cux_request_new, configured with the same
 * cux_set_header / cux_set_int / cux_set_text, started with the same
 * cux_start and released with the same cux_free. It differs in what happens
 * after the start: the HTTP upgrade runs under the pump like any transfer,
 * and when it succeeds the handle stays RUNNING, now a two-way message
 * socket. Whole messages (fragments reassembled) queue in the shim until
 * cux_ws_read takes them; cux_ws_send queues a whole message and the pump
 * writes it out. PUMP OR NOTHING holds here too: a socket moves only inside
 * cux_poll, cux_ws_poll or cux_ws_wait.
 *
 * A WebSocket is NEVER listed by cux_poll: that list is consumed by whoever
 * reads it (the helpers' timer, for the requests it watches), and a handle
 * nobody there knows would be lost. Its state is read instead (CUI_WS_STATE),
 * so every existing cux_poll caller sees exactly what it saw before v2.
 *
 * States (CUI_WS_STATE). */
#define CUX_WS_CONNECTING    1   /* started; the upgrade has not finished */
#define CUX_WS_OPEN          2
#define CUX_WS_CLOSING       3   /* our close is sent; waiting for theirs */
#define CUX_WS_CLOSED        4   /* over: closed, failed or cancelled     */

/* Message kinds (cux_ws_send; CUI_WS_NEXT_TYPE answers the first two). */
#define CUX_WS_KIND_TEXT     1   /* UTF-8 text                            */
#define CUX_WS_KIND_BINARY   2
#define CUX_WS_KIND_PING     3   /* at most 125 bytes                     */
#define CUX_WS_KIND_PONG     4   /* at most 125 bytes                     */

/* The close codes this shim itself reports (RFC 6455 section 7.4.1): the
 * peer's own code is passed through. */
#define CUX_WS_CODE_NORMAL     1000
#define CUX_WS_CODE_NO_STATUS  1005  /* a close frame that carried no code  */
#define CUX_WS_CODE_ABNORMAL   1006  /* the connection ended with no close  */
#define CUX_WS_CODE_TOO_BIG    1009  /* a message above CUO_MAX_BODY_BYTES  */

/* THE EXCEPTION FIREWALL. Every entry point body goes through one of these;
 * a throw becomes a recorded error + error return, never an unwind into the
 * engine. Two lessons are baked in from the siblings, keep them:
 *   - one declaration per line inside a guard body (the macro-comma trap:
 *     the preprocessor only protects commas inside parentheses);
 *   - NO preprocessor directive inside a guard body (a '#' inside a macro
 *     argument is gcc-tolerated but MSVC-rejected, C2121 - hoist any
 *     conditional into a plain helper first). */
#define CUX_GUARD_INT(errval, body)                                     \
    try { body } catch (const std::exception &e) {                      \
        set_error(e.what()); return (errval);                           \
    } catch (...) { set_error("unknown native exception"); return (errval); }

#define CUX_GUARD_DOUBLE(errval, body)                                  \
    try { body } catch (const std::exception &e) {                      \
        set_error(e.what()); return (errval);                           \
    } catch (...) { set_error("unknown native exception"); return (errval); }

#define CUX_GUARD_VOID(body)                                            \
    try { body } catch (const std::exception &e) {                      \
        set_error(e.what());                                            \
    } catch (...) { set_error("unknown native exception"); }

#ifdef __cplusplus
extern "C" {
#endif

CUX_API int    CUX_CALL cux_abi_version(void);
CUX_API int    CUX_CALL cux_init(void);
CUX_API int    CUX_CALL cux_cleanup(void);
CUX_API int    CUX_CALL cux_version_string(char *out, int cap);
CUX_API int    CUX_CALL cux_last_error(char *out, int cap);
CUX_API void   CUX_CALL cux_clear_error(void);

CUX_API int    CUX_CALL cux_request_new(const char *method, const char *url);
CUX_API int    CUX_CALL cux_set_header(int h, const char *line);
CUX_API int    CUX_CALL cux_set_int(int h, int option, int value);
CUX_API int    CUX_CALL cux_set_text(int h, int option, const char *value);
CUX_API int    CUX_CALL cux_set_body(int h, const void *bytes, int len);
CUX_API int    CUX_CALL cux_start(int h);
CUX_API int    CUX_CALL cux_cancel(int h);
CUX_API int    CUX_CALL cux_free(int h);

CUX_API int    CUX_CALL cux_poll(char *out, int cap);
CUX_API int    CUX_CALL cux_wait(int h, int timeout_ms);

CUX_API double CUX_CALL cux_info(int h, int field);
CUX_API int    CUX_CALL cux_text(int h, int field, char *out, int cap);
CUX_API int    CUX_CALL cux_body(int h, char *out, int cap);
CUX_API int    CUX_CALL cux_live_count(void);

/* WebSockets (v2). */
CUX_API int    CUX_CALL cux_ws_new(const char *url);
CUX_API int    CUX_CALL cux_ws_send(int h, int kind, const void *bytes, int len);
CUX_API int    CUX_CALL cux_ws_close(int h, int code, const char *reason);
CUX_API int    CUX_CALL cux_ws_read(int h, char *out, int cap);
CUX_API int    CUX_CALL cux_ws_poll(void);
CUX_API int    CUX_CALL cux_ws_wait(int h, int timeout_ms);

/* Test hook: throws inside the firewall, so the smoke test (and the harness)
 * can prove a throw becomes an error return. Not bound by the .lcb. */
CUX_API int    CUX_CALL cux_selftest_throw(void);

#ifdef __cplusplus
}
#endif

#endif /* CUX_ABI_H */
