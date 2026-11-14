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
 * src/curl.lcb; tools/check-record-registry.py proves the mirror.
 */
#ifndef CUX_ABI_H
#define CUX_ABI_H

/* v1: the first surface. */
#define CUX_ABI_VERSION 1

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

/* Text fields (cux_text). */
#define CUT_HEADERS            1   /* the final response's header block   */
#define CUT_ERROR              2   /* curl's detailed error, or its name  */
#define CUT_EFFECTIVE_URL      3
#define CUT_CONTENT_TYPE       4
#define CUT_METHOD             5

/* Our own result code for a request script cancelled. It sits outside
 * libcurl's CURLcode range so it can never be confused with one. */
#define CUX_RESULT_CANCELLED 1000

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

/* Test hook: throws inside the firewall, so the smoke test (and the harness)
 * can prove a throw becomes an error return. Not bound by the .lcb. */
CUX_API int    CUX_CALL cux_selftest_throw(void);

#ifdef __cplusplus
}
#endif

#endif /* CUX_ABI_H */
