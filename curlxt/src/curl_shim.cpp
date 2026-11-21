/* curl_shim.cpp - the flat extern "C" facade over libcurl's multi interface.
 *
 * The three family rules, in this binding's shape:
 *
 *   1. NEVER call script from a foreign thread - satisfied by construction:
 *      this shim starts no thread and installs no callback that reaches
 *      script. libcurl's own callbacks (write, read, seek, header) run INSIDE
 *      curl_multi_perform, which runs inside cux_poll or cux_wait, which run
 *      on the engine's script thread; they only copy bytes. (curl's threaded
 *      DNS resolver may run a resolver thread inside a transfer; it never
 *      touches anything of ours.) The flip side is enetxt's: PUMP OR NOTHING.
 *      A started request moves only while cux_poll or cux_wait runs.
 *
 *   2. THE EXCEPTION FIREWALL - every cux_* body runs inside CUX_GUARD_*
 *      (cux_abi.h carries the two paid-for sibling lessons). libcurl is C and
 *      never throws; the guard is for std::bad_alloc and our own code.
 *
 *   3. PAYLOAD AVOIDS THE FFI WHERE THE DESIGN ALLOWS: a download can go
 *      straight to a file (CUO_OUTPUT_FILE) and an upload can come straight
 *      from one (CUO_INPUT_FILE), so a large transfer never crosses into
 *      script. An in-memory body crosses ONCE, when script asks for it
 *      (cux_body), and can be capped (CUO_MAX_BODY_BYTES).
 *
 * Handles: one generation-tagged table of requests (cux_handle_table.h, the
 * family's carried copy). A request lives from cux_request_new to cux_free;
 * after that every use is a harmless no-op. The handle rides each easy
 * handle's CURLOPT_PRIVATE as an integer, never a pointer, so a message for
 * a request script already freed is simply not found.
 *
 * Finished requests are reported by cux_poll in a FIFO (g_done), as a comma
 * list of handles. The list is lossless: if the caller's buffer is too small
 * the queue is left intact and the needed size is returned negated.
 *
 * WEBSOCKETS (ABI 2) ride the same table and the same pump. A WebSocket is a
 * request whose easy handle has CURLOPT_CONNECT_ONLY 2: the multi handle
 * drives the HTTP upgrade, reports it DONE, and the connection then belongs
 * to curl_ws_recv / curl_ws_send, which never block. libcurl requires such a
 * handle to STAY in the multi handle for as long as it is used, so an open
 * socket is removed only when it ends. The pump services every live socket
 * after curl_multi_perform: write what is queued, read what has arrived.
 * Rule 3 in this shape: a message crosses into script once, when it is read
 * (cux_ws_read), and what is not read stays here and, past a high-water
 * mark, on the peer's side of the TCP connection.
 */

#include "cux_abi.h"
#include "cux_handle_table.h"

#include <curl/curl.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#if defined(_WIN32)
#  include <windows.h>
#endif
#if defined(__ANDROID__)
#  include <dirent.h>
#endif

namespace {

/* Everything runs on the engine's single script thread, so module state is
 * unguarded by design (as in enetxt). */
std::string g_last_error;

void set_error(const std::string &msg) { g_last_error = msg; }

int g_init_count = 0;
CURLM *g_multi = nullptr;

/* One whole received WebSocket message, and one queued for sending. */
struct WsMessage {
    int kind = 0;                      /* CUX_WS_KIND_TEXT or _BINARY         */
    std::vector<unsigned char> data;
};

struct WsOut {
    unsigned int flags = 0;            /* CURLWS_TEXT, _BINARY, _PING ...     */
    std::vector<unsigned char> data;
    size_t pos = 0;                    /* payload bytes curl has taken        */
    bool auto_pong = false;            /* ws_service's answer to a ping, not  */
                                       /* a pong script sent                  */
};

/* Received messages are read off the socket only while fewer than this many
 * bytes wait for script: past it the socket is left unread, so a peer that
 * sends faster than script reads is slowed by TCP itself rather than filling
 * memory. One message always completes, whatever its size. */
const size_t kWsInHighWater = 4u * 1024u * 1024u;
const size_t kWsInMaxMessages = 4096;   /* the same brake, for empty ones */

/* cux_ws_send refuses a message that would take the bytes queued for the
 * socket past this: a peer that has stopped reading must surface as an error
 * to the sender, not as memory that grows until the process dies. */
const size_t kWsOutMax = 16u * 1024u * 1024u;

/* Control frames (pings and pongs) one pass over one socket handles. They
 * put nothing in front of script, so the high-water mark above never stops
 * them: without this, a peer that sends them without pause would hold one
 * pump for as long as it kept them coming. The rest wait for the next
 * pass, and TCP slows the peer meanwhile. */
const int kWsControlPerPass = 1024;

struct Request {
    CURL *easy = nullptr;
    int state = CUX_STATE_NEW;
    int result = -1;               /* CURLcode, or CUX_RESULT_CANCELLED     */
    bool cancelled = false;
    bool quiet = false;            /* finished under cux_wait: not queued    */
    std::string method;
    std::string url;
    struct curl_slist *headers = nullptr;
    struct curl_slist *rcpt = nullptr;
    struct curl_slist *quote = nullptr;
    struct curl_slist *postquote = nullptr;
    std::vector<unsigned char> send;   /* request body from memory          */
    size_t send_pos = 0;
    bool has_body = false;
    std::string output_path;
    std::string input_path;
    FILE *out = nullptr;
    FILE *in = nullptr;
    long long in_size = -1;
    std::vector<unsigned char> body;   /* response body held for cux_body    */
    long long max_body = 0;           /* in memory OR to outputFile          */
    long long out_written = 0;        /* bytes handed to fwrite on `out`     */
    bool body_overflow = false;
    bool out_close_failed = false;    /* fclose lost buffered bytes          */
    std::string resp_headers;
    char errbuf[CURL_ERROR_SIZE];
    std::string file_error;

    /* ---- WebSocket (ABI 2); every field is idle on an ordinary request */
    bool ws = false;
    int ws_state = 0;                 /* CUX_WS_*; 0 = not a WebSocket       */
    std::deque<WsMessage> ws_in;      /* whole messages, oldest first        */
    size_t ws_in_bytes = 0;
    std::vector<unsigned char> ws_part;   /* the message being reassembled   */
    int ws_part_kind = 0;
    bool ws_part_open = false;
    std::vector<unsigned char> ws_ctl;    /* a close frame being received    */
    std::vector<unsigned char> ws_ping;   /* a ping being received           */
    std::deque<WsOut> ws_out;         /* whole frames waiting for the socket */
    size_t ws_out_bytes = 0;
    bool ws_close_sent = false;       /* a close frame was QUEUED by us      */
    int ws_close_code = 0;
    std::string ws_close_reason;
    long long ws_pongs = 0;
    long long ws_close_timeout_ms = 5000;
    std::chrono::steady_clock::time_point ws_close_deadline;
    bool ws_close_deadline_set = false;
    long long ws_timeout_ms = 0;          /* CUO_TIMEOUT_MS, kept for the    */
    long long ws_connect_timeout_ms = 0;  /* upgrade (see ws_service)        */
    std::chrono::steady_clock::time_point ws_open_deadline;
    bool ws_open_deadline_set = false;

    Request() { errbuf[0] = 0; }
    ~Request() {
        if (easy) curl_easy_cleanup(easy);
        if (headers) curl_slist_free_all(headers);
        if (rcpt) curl_slist_free_all(rcpt);
        if (quote) curl_slist_free_all(quote);
        if (postquote) curl_slist_free_all(postquote);
        if (out) fclose(out);
        if (in) fclose(in);
    }
    Request(const Request &) = delete;
    Request &operator=(const Request &) = delete;
};

cux::HandleTable<std::unique_ptr<Request>> g_requests;
std::deque<int> g_done;
std::vector<int> g_ws;   /* every live WebSocket handle, for the pump */

Request *lookup(int h) {
    std::unique_ptr<Request> *p = g_requests.get(h);
    return p ? p->get() : nullptr;
}

/* ---------------------------------------------------------- file helpers */

/* A path crosses as UTF-8. On Windows fopen reads the ANSI code page, so a
 * path with any non-ASCII character would open the wrong file (or none):
 * widen it and use _wfopen. Hoisted out of every guard body (no preprocessor
 * directive inside a guard: MSVC C2121). */
FILE *open_utf8(const std::string &path, const char *mode) {
#if defined(_WIN32)
    int n = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
    if (n <= 0) return nullptr;
    std::wstring wpath(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, &wpath[0], n);
    std::wstring wmode;
    for (const char *m = mode; *m; ++m) wmode.push_back(static_cast<wchar_t>(*m));
    return _wfopen(wpath.c_str(), wmode.c_str());
#else
    return std::fopen(path.c_str(), mode);
#endif
}

long long file_size(FILE *f) {
#if defined(_WIN32)
    if (_fseeki64(f, 0, SEEK_END) != 0) return -1;
    long long n = _ftelli64(f);
    _fseeki64(f, 0, SEEK_SET);
    return n;
#else
    if (fseeko(f, 0, SEEK_END) != 0) return -1;
    long long n = static_cast<long long>(ftello(f));
    fseeko(f, 0, SEEK_SET);
    return n;
#endif
}

int seek_file(FILE *f, long long offset) {
#if defined(_WIN32)
    return _fseeki64(f, offset, SEEK_SET);
#else
    return fseeko(f, static_cast<off_t>(offset), SEEK_SET);
#endif
}

/* ---------------------------------------------------- libcurl callbacks */
/* These run inside curl_multi_perform, on the script thread (rule 1). They
 * must not throw into C: each catches everything and reports a failure in
 * libcurl's own vocabulary, which ends the transfer with an error code. */

size_t on_write(char *ptr, size_t size, size_t nmemb, void *userdata) {
    Request *r = static_cast<Request *>(userdata);
    size_t n = size * nmemb;
    try {
        /* maxBodyBytes bounds a download to a file too: it is the one
         * limit tsNet's max_file_size maps to, and a file can fill a disk */
        long long have = r->out ? r->out_written : static_cast<long long>(r->body.size());
        if (r->max_body > 0 && have + static_cast<long long>(n) > r->max_body) {
            r->body_overflow = true;
            return 0;   /* CURLE_WRITE_ERROR ends the transfer */
        }
        if (r->out) {
            size_t w = fwrite(ptr, 1, n, r->out);
            r->out_written += static_cast<long long>(w);
            return w;   /* short: CURLE_WRITE_ERROR */
        }
        r->body.insert(r->body.end(), ptr, ptr + n);
        return n;
    } catch (...) {
        return 0;
    }
}

size_t on_read(char *buffer, size_t size, size_t nitems, void *userdata) {
    Request *r = static_cast<Request *>(userdata);
    size_t cap = size * nitems;
    if (r->in) return fread(buffer, 1, cap, r->in);
    size_t left = r->send.size() - r->send_pos;
    size_t n = std::min(cap, left);
    if (n) std::memcpy(buffer, r->send.data() + r->send_pos, n);
    r->send_pos += n;
    return n;
}

/* A redirect or an authentication round trip may rewind the upload. */
int on_seek(void *userdata, curl_off_t offset, int origin) {
    Request *r = static_cast<Request *>(userdata);
    if (origin != SEEK_SET || offset < 0) return CURL_SEEKFUNC_CANTSEEK;
    if (r->in) return seek_file(r->in, offset) == 0 ? CURL_SEEKFUNC_OK : CURL_SEEKFUNC_FAIL;
    if (static_cast<size_t>(offset) > r->send.size()) return CURL_SEEKFUNC_FAIL;
    r->send_pos = static_cast<size_t>(offset);
    return CURL_SEEKFUNC_OK;
}

/* Keep only the FINAL response's header block: a redirect or a 100-continue
 * starts a new block with its status line, so the earlier one is dropped. */
size_t on_header(char *buffer, size_t size, size_t nitems, void *userdata) {
    Request *r = static_cast<Request *>(userdata);
    size_t n = size * nitems;
    try {
        if (n >= 5 && std::memcmp(buffer, "HTTP/", 5) == 0) r->resp_headers.clear();
        r->resp_headers.append(buffer, n);
        return n;
    } catch (...) {
        return 0;
    }
}

/* -------------------------------------------------------------- helpers */

int copy_out(const std::string &s, char *out, int cap) {
    int need = static_cast<int>(s.size());
    if (!out || cap < need + 1) return -(need + 1);
    std::memcpy(out, s.data(), s.size());
    out[need] = 0;
    return need;
}

bool starts_with_ci(const std::string &s, const char *prefix) {
    size_t n = std::strlen(prefix);
    if (s.size() < n) return false;
    for (size_t i = 0; i < n; ++i)
        if (std::tolower(static_cast<unsigned char>(s[i])) != prefix[i]) return false;
    return true;
}

/* The system's CA bundle, for a libcurl built against OpenSSL on Linux,
 * where there is no single path every distribution agrees on. Probed once;
 * empty means "leave curl's built-in default alone". */
const std::string &linux_ca_bundle() {
    static std::string found;
    static bool probed = false;
    if (!probed) {
        probed = true;
        static const char *const candidates[] = {
            "/etc/ssl/certs/ca-certificates.crt",                 /* Debian, Ubuntu, Arch */
            "/etc/pki/tls/certs/ca-bundle.crt",                   /* Fedora, RHEL */
            "/etc/ssl/ca-bundle.pem",                             /* openSUSE */
            "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",  /* RHEL 7+ */
            "/etc/ssl/cert.pem",                                  /* Alpine */
        };
        for (const char *c : candidates) {
            FILE *f = std::fopen(c, "rb");
            if (f) { std::fclose(f); found = c; break; }
        }
    }
    return found;
}

#if defined(__ANDROID__)
/* Android's trusted roots (the <arch>-android libraries, 2026-11-18). There
 * is no bundle file on Android and no store OpenSSL can read in place: the
 * system keeps one PEM file per certificate, named for the OLD (MD5)
 * subject hash, which OpenSSL 1.0 and later do not look up, so pointing
 * CURLOPT_CAPATH at the folder finds nothing. The files themselves are
 * plain PEM, so they are read once into one blob and handed to libcurl as
 * CURLOPT_CAINFO_BLOB. Android 14 moved the store into the Conscrypt module
 * (so that a system update can change it); the first folder that yields a
 * certificate is the one in use, and before Android 14 that is the second.
 * Only the system's own roots: the certificates a user adds are kept
 * elsewhere and are not read here (Android's own TLS has not trusted them
 * for apps by default since Android 7). Empty means no folder could be read, and then, as on a
 * Linux with no bundle, curl is left with none and a verified transfer
 * fails rather than going unverified. */
struct AndroidCaStore {
    std::string pem;
    int count = 0;
};

const AndroidCaStore &android_ca_store() {
    static AndroidCaStore store;
    static bool probed = false;
    if (!probed) {
        probed = true;
        static const char *const folders[] = {
            "/apex/com.android.conscrypt/cacerts",  /* Android 14 and later */
            "/system/etc/security/cacerts",         /* every Android before */
        };
        static const char kBegin[] = "-----BEGIN CERTIFICATE-----";
        static const char kEnd[] = "-----END CERTIFICATE-----";
        for (const char *folder : folders) {
            DIR *d = opendir(folder);
            if (!d) continue;
            while (struct dirent *entry = readdir(d)) {
                if (entry->d_name[0] == '.') continue;
                std::string path = std::string(folder) + "/" + entry->d_name;
                FILE *f = std::fopen(path.c_str(), "rb");
                if (!f) continue;
                std::string text;
                char buf[4096];
                size_t n;
                /* A certificate is a few kilobytes; anything far larger in
                 * this folder is not one, and is not read to its end. */
                while (text.size() < (1u << 20) && (n = std::fread(buf, 1, sizeof buf, f)) > 0)
                    text.append(buf, n);
                std::fclose(f);
                /* Only the PEM block: the system's files carry the decoded
                 * text of the certificate after it. */
                size_t from = text.find(kBegin);
                size_t to = from == std::string::npos ? from : text.find(kEnd, from);
                if (to == std::string::npos) continue;
                store.pem.append(text, from, to + sizeof kEnd - 1 - from);
                store.pem.push_back('\n');
                ++store.count;
            }
            closedir(d);
            if (store.count > 0) break;
        }
    }
    return store;
}
#endif

void apply_default_ca(CURL *easy) {
#if defined(__ANDROID__)
    /* Before the Linux branch: Android's compilers define __linux__ too,
     * and none of a Linux system's bundle paths exists there. NOCOPY, since
     * the store lives as long as the process does. */
    const AndroidCaStore &store = android_ca_store();
    if (store.count > 0) {
        struct curl_blob blob;
        blob.data = const_cast<char *>(store.pem.data());
        blob.len = store.pem.size();
        blob.flags = CURL_BLOB_NOCOPY;
        curl_easy_setopt(easy, CURLOPT_CAINFO_BLOB, &blob);
    }
#elif defined(__linux__)
    const std::string &ca = linux_ca_bundle();
    if (!ca.empty()) curl_easy_setopt(easy, CURLOPT_CAINFO, ca.c_str());
#else
    /* Windows (Schannel) and macOS read the system store natively; asking
     * for it explicitly is harmless where it is already the default. */
    curl_easy_setopt(easy, CURLOPT_SSL_OPTIONS, static_cast<long>(CURLSSLOPT_NATIVE_CA));
#endif
}

/* CUO_CA_FILE, hoisted out of its guard body for the directive (MSVC C2121).
 * Everywhere the caller's file, or none for an empty value, becomes
 * CURLOPT_CAINFO, as it always has. On Android the default store is a blob
 * (apply_default_ca), and libcurl reads a blob in preference to a file: so
 * a caller's file takes the blob's place, and an empty value brings the
 * system's store back, as it leaves it in place on Windows and macOS. */
CURLcode set_ca_file(CURL *easy, const char *path) {
    CURLcode rc = curl_easy_setopt(easy, CURLOPT_CAINFO, *path ? path : nullptr);
#if defined(__ANDROID__)
    if (rc == CURLE_OK) {
        if (*path) rc = curl_easy_setopt(easy, CURLOPT_CAINFO_BLOB, nullptr);
        else apply_default_ca(easy);
    }
#endif
    return rc;
}

/* What cux_version_string adds on Android, and nothing anywhere else: how
 * many of the system's certificates the default store holds. It is the one
 * fact about that store a caller can see without a server to connect to, so
 * it is what the smoke test asserts on a device, and what a person reads
 * when HTTPS fails on a phone. */
std::string platform_version_suffix() {
#if defined(__ANDROID__)
    return "; Android CA store: " + std::to_string(android_ca_store().count) + " certificates";
#else
    return std::string();
#endif
}

/* Everything that must happen just before a request joins the multi handle:
 * the body or file source, the output file, the method. Returns CUX_OK or a
 * negative error with g_last_error set. */
int prepare(Request *r) {
    CURL *e = r->easy;
    const std::string &m = r->method;
    if (!r->output_path.empty()) {
        r->out = open_utf8(r->output_path, "wb");
        if (!r->out) { set_error("cannot open output file: " + r->output_path); return CUX_ERR_ARG; }
    }
    if (!r->input_path.empty()) {
        r->in = open_utf8(r->input_path, "rb");
        if (!r->in) { set_error("cannot open input file: " + r->input_path); return CUX_ERR_ARG; }
        r->in_size = file_size(r->in);
    }
    curl_easy_setopt(e, CURLOPT_HTTPHEADER, r->headers);
    if (r->rcpt) curl_easy_setopt(e, CURLOPT_MAIL_RCPT, r->rcpt);
    if (r->quote) curl_easy_setopt(e, CURLOPT_QUOTE, r->quote);
    if (r->postquote) curl_easy_setopt(e, CURLOPT_POSTQUOTE, r->postquote);

    /* The method decides the shape:
     *   GET            plain fetch (the default)
     *   HEAD           no body
     *   POST           body from memory as POSTFIELDS (or from the file)
     *   PUT, UPLOAD    curl's upload: HTTP PUT, FTP/SFTP STOR, SMTP DATA
     *   anything else  a custom request; a body, if set, goes as POSTFIELDS */
    bool upload = (m == "PUT" || m == "UPLOAD");
    if (m == "HEAD") {
        curl_easy_setopt(e, CURLOPT_NOBODY, 1L);
    } else if (upload) {
        curl_easy_setopt(e, CURLOPT_UPLOAD, 1L);
        curl_easy_setopt(e, CURLOPT_READFUNCTION, on_read);
        curl_easy_setopt(e, CURLOPT_READDATA, r);
        curl_easy_setopt(e, CURLOPT_SEEKFUNCTION, on_seek);
        curl_easy_setopt(e, CURLOPT_SEEKDATA, r);
        curl_off_t size = r->in ? static_cast<curl_off_t>(r->in_size)
                                : static_cast<curl_off_t>(r->send.size());
        if (size >= 0) curl_easy_setopt(e, CURLOPT_INFILESIZE_LARGE, size);
    } else if (r->in) {
        /* POST (or a custom method) whose body is a file: stream it. */
        curl_easy_setopt(e, CURLOPT_POST, 1L);
        curl_easy_setopt(e, CURLOPT_READFUNCTION, on_read);
        curl_easy_setopt(e, CURLOPT_READDATA, r);
        curl_easy_setopt(e, CURLOPT_SEEKFUNCTION, on_seek);
        curl_easy_setopt(e, CURLOPT_SEEKDATA, r);
        if (r->in_size >= 0)
            curl_easy_setopt(e, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(r->in_size));
    } else if (m == "POST" || r->has_body) {
        curl_easy_setopt(e, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(r->send.size()));
        curl_easy_setopt(e, CURLOPT_COPYPOSTFIELDS,
                         r->send.empty() ? "" : reinterpret_cast<const char *>(r->send.data()));
    }
    if (m != "GET" && m != "HEAD" && m != "POST" && !upload)
        curl_easy_setopt(e, CURLOPT_CUSTOMREQUEST, m.c_str());
    if (m == "POST" && r->has_body == false && !r->in)
        curl_easy_setopt(e, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(0));
    return CUX_OK;
}

/* A transfer ended (curl reported DONE, or script cancelled it): detach it
 * from the multi handle, close its files, and queue it for cux_poll unless a
 * cux_wait is collecting it synchronously. */
void finish(Request *r, int h, int result) {
    if (r->state != CUX_STATE_RUNNING) return;
    curl_multi_remove_handle(g_multi, r->easy);
    r->state = CUX_STATE_DONE;
    r->result = result;
    /* fclose flushes the last buffered bytes; when that fails (a full
     * disk) the file is short, so a transfer curl called a success is a
     * write error, never a silent truncation */
    if (r->out) {
        int closed = fclose(r->out);
        r->out = nullptr;
        if (closed != 0) {
            r->out_close_failed = true;
            if (r->result == CURLE_OK) r->result = CURLE_WRITE_ERROR;
        }
    }
    if (r->in) { fclose(r->in); r->in = nullptr; }
    if (!r->quiet) g_done.push_back(h);
}

/* ------------------------------------------------------------ WebSockets */

/* A WebSocket is over: closed by either side, failed, or cancelled. finish()
 * takes it out of the multi handle (which closes the connection) and, since
 * a WebSocket is always `quiet`, never queues it for cux_poll. What was
 * received and not yet read stays readable until cux_free; what was queued
 * for sending is dropped, since there is no longer anything to send it on. */
void ws_end(Request *r, int h, int result, int code, const std::string &reason) {
    if (r->ws_state == CUX_WS_CLOSED) return;
    r->ws_state = CUX_WS_CLOSED;
    r->ws_close_code = code;
    r->ws_close_reason = reason;
    r->ws_out.clear();
    r->ws_out_bytes = 0;
    r->ws_part.clear();
    r->ws_part_open = false;
    finish(r, h, result);
}

void ws_queue(Request *r, unsigned int flags, const unsigned char *p, size_t len) {
    r->ws_out.emplace_back();
    WsOut &m = r->ws_out.back();
    m.flags = flags;
    if (len) m.data.assign(p, p + len);
    r->ws_out_bytes += len;
}

/* Queue a close frame: the code in network order, then the reason, cut at
 * the 123 bytes a control frame leaves for it (on a UTF-8 boundary, so the
 * peer never reads half a character). A code of 0 sends an empty close. */
void ws_queue_close(Request *r, int code, const std::string &reason) {
    unsigned char frame[125];
    size_t n = 0;
    if (code > 0) {
        frame[0] = static_cast<unsigned char>((code >> 8) & 0xFF);
        frame[1] = static_cast<unsigned char>(code & 0xFF);
        n = 2;
        size_t take = std::min<size_t>(reason.size(), 123);
        while (take > 0 && take < reason.size() &&
               (static_cast<unsigned char>(reason[take]) & 0xC0) == 0x80) --take;
        std::memcpy(frame + 2, reason.data(), take);
        n += take;
    }
    ws_queue(r, CURLWS_CLOSE, frame, n);
    r->ws_close_sent = true;
}

/* Hand queued frames to the socket for as long as it takes them. Returns
 * false when the socket ended here (a write error). */
bool ws_flush(Request *r, int h) {
    while (!r->ws_out.empty()) {
        WsOut &m = r->ws_out.front();
        size_t sent = 0;
        const unsigned char *p = m.data.empty() ? reinterpret_cast<const unsigned char *>("")
                                                : m.data.data() + m.pos;
        size_t left = m.data.size() - m.pos;
        CURLcode rc = curl_ws_send(r->easy, p, left, &sent, 0, m.flags);
        m.pos += sent;
        if (rc == CURLE_AGAIN) return true;
        if (rc != CURLE_OK) {
            ws_end(r, h, static_cast<int>(rc), CUX_WS_CODE_ABNORMAL, "");
            return false;
        }
        if (m.pos >= m.data.size()) {
            r->ws_out_bytes -= m.data.size();
            r->ws_out.pop_front();
        } else if (sent == 0) {
            return true;   /* took nothing and did not say AGAIN: next pump */
        }
    }
    return true;
}

/* One whole close frame has arrived: answer it (unless ours is already on
 * its way) and end. The echo is best effort: it is a few bytes, the socket
 * almost always takes them at once, and the peer that sent a close is not
 * owed more than that. */
void ws_got_close(Request *r, int h) {
    int code = CUX_WS_CODE_NO_STATUS;
    std::string reason;
    if (r->ws_ctl.size() >= 2) {
        code = (static_cast<int>(r->ws_ctl[0]) << 8) | static_cast<int>(r->ws_ctl[1]);
        reason.assign(r->ws_ctl.begin() + 2, r->ws_ctl.end());
    }
    r->ws_ctl.clear();
    if (!r->ws_close_sent) {
        ws_queue_close(r, code == CUX_WS_CODE_NO_STATUS ? 0 : code, "");
        if (!ws_flush(r, h)) {
            /* the echo failed to send: the close itself still stands */
            r->ws_close_code = code;
            r->ws_close_reason = reason;
            r->result = CURLE_OK;
            return;
        }
    }
    ws_end(r, h, CURLE_OK, code, reason);
}

/* One pass over one live socket: write, then read until the socket has no
 * more or enough is waiting for script. */
void ws_service(Request *r, int h) {
    /* The upgrade's own clock. libcurl 8.22 does not apply CURLOPT_TIMEOUT
     * or CURLOPT_CONNECTTIMEOUT to the wait for a connect-only upgrade's
     * answer (measured: a server that accepts and then says nothing held a
     * socket with a 150 ms timeout until the server hung up), so the limit
     * script set is kept here. */
    if (r->ws_state == CUX_WS_CONNECTING && r->ws_open_deadline_set &&
        std::chrono::steady_clock::now() >= r->ws_open_deadline) {
        ws_end(r, h, static_cast<int>(CURLE_OPERATION_TIMEDOUT), 0, "");
        return;
    }
    if (r->ws_state != CUX_WS_OPEN && r->ws_state != CUX_WS_CLOSING) return;
    if (!ws_flush(r, h)) return;
    char buf[16384];
    int control = 0;   /* whole control frames handled in this pass */
    while (((r->ws_in_bytes < kWsInHighWater && r->ws_in.size() < kWsInMaxMessages) ||
            r->ws_part_open) && control < kWsControlPerPass) {
        size_t n = 0;
        const struct curl_ws_frame *meta = nullptr;
        CURLcode rc = curl_ws_recv(r->easy, buf, sizeof buf, &n, &meta);
        if (rc == CURLE_AGAIN) break;
        if (rc != CURLE_OK) {
            /* The connection ended with no close frame. After OUR close that
             * is a peer that hung up instead of answering: the close script
             * asked for has happened, so it is not a failure. */
            int result = (r->ws_state == CUX_WS_CLOSING) ? static_cast<int>(CURLE_OK)
                                                         : static_cast<int>(rc);
            ws_end(r, h, result, CUX_WS_CODE_ABNORMAL, "");
            return;
        }
        if (!meta) break;
        if (meta->flags & CURLWS_CLOSE) {
            r->ws_ctl.insert(r->ws_ctl.end(), buf, buf + n);
            if (meta->bytesleft == 0) {
                ws_got_close(r, h);
                return;
            }
        } else if (meta->flags & CURLWS_PONG) {
            if (meta->bytesleft == 0) {
                ++r->ws_pongs;
                ++control;
            }
        } else if (meta->flags & CURLWS_PING) {
            /* Answered here (CURLWS_NOAUTOPONG, see new_request). The pong
             * goes out NEXT, ahead of any backlog, but never ahead of the
             * frame at the head of the queue: libcurl may already hold part
             * of that one, and a frame cannot be split by another. At most
             * ONE answer waits behind that frame: a later ping replaces its
             * payload, as RFC 6455 5.5.3 allows (an endpoint may answer only
             * the most recent ping). So a peer that pings and never reads
             * cannot grow the queue, and the last pong out answers the last
             * ping. The head is never replaced, even when it is an answer
             * curl has reported nothing of: after CURLE_AGAIN, curl can hold
             * a whole frame it has not yet written. */
            r->ws_ping.insert(r->ws_ping.end(), buf, buf + n);
            if (meta->bytesleft == 0) {
                ++control;
                if (!r->ws_close_sent) {
                    if (r->ws_out.size() >= 2 && r->ws_out[1].auto_pong) {
                        WsOut &waiting = r->ws_out[1];
                        r->ws_out_bytes -= waiting.data.size();
                        waiting.data.swap(r->ws_ping);
                        r->ws_out_bytes += waiting.data.size();
                    } else {
                        WsOut pong;
                        pong.flags = CURLWS_PONG;
                        pong.auto_pong = true;
                        pong.data.swap(r->ws_ping);
                        r->ws_out_bytes += pong.data.size();
                        r->ws_out.insert(r->ws_out.begin() + (r->ws_out.empty() ? 0 : 1), std::move(pong));
                    }
                }
                r->ws_ping.clear();
                if (!ws_flush(r, h)) return;
            }
        } else if (meta->flags & (CURLWS_TEXT | CURLWS_BINARY)) {
            if (!r->ws_part_open) {
                r->ws_part_open = true;
                r->ws_part_kind = (meta->flags & CURLWS_TEXT) ? CUX_WS_KIND_TEXT : CUX_WS_KIND_BINARY;
                r->ws_part.clear();
            }
            if (r->max_body > 0 &&
                static_cast<long long>(r->ws_part.size() + n) > r->max_body) {
                /* above the limit script set: say so to the peer and stop */
                r->body_overflow = true;
                r->ws_out.clear();
                r->ws_out_bytes = 0;
                ws_queue_close(r, CUX_WS_CODE_TOO_BIG, "message too big");
                if (ws_flush(r, h))
                    ws_end(r, h, static_cast<int>(CURLE_WRITE_ERROR), CUX_WS_CODE_TOO_BIG, "");
                return;
            }
            r->ws_part.insert(r->ws_part.end(), buf, buf + n);
            if (meta->bytesleft == 0 && !(meta->flags & CURLWS_CONT)) {
                r->ws_in.emplace_back();
                WsMessage &m = r->ws_in.back();
                m.kind = r->ws_part_kind;
                m.data.swap(r->ws_part);
                r->ws_in_bytes += m.data.size();
                r->ws_part_open = false;
            }
        }
    }
    if (r->ws_state == CUX_WS_CLOSED) return;
    if (!ws_flush(r, h)) return;
    /* Our close went out and theirs never came: stop waiting. */
    if (r->ws_state == CUX_WS_CLOSING && r->ws_close_deadline_set &&
        std::chrono::steady_clock::now() >= r->ws_close_deadline)
        ws_end(r, h, CURLE_OK, CUX_WS_CODE_ABNORMAL, "");
}

/* The upgrade ended. Success turns the handle into an open socket, which
 * stays in the multi handle (libcurl's rule for a connect-only handle that
 * is still in use); anything else is the end of it. */
void ws_connected(Request *r, int h, int result) {
    if (r->ws_state != CUX_WS_CONNECTING) return;
    if (result == CURLE_OK) {
        r->ws_state = CUX_WS_OPEN;
        return;
    }
    ws_end(r, h, result, 0, "");
}

/* One step of the pump: let curl move every running transfer as far as it
 * can without blocking, collect the ones that ended, then service every
 * live WebSocket. */
void pump() {
    int running = 0;
    curl_multi_perform(g_multi, &running);
    int left = 0;
    CURLMsg *msg = nullptr;
    while ((msg = curl_multi_info_read(g_multi, &left)) != nullptr) {
        if (msg->msg != CURLMSG_DONE) continue;
        char *priv = nullptr;
        curl_easy_getinfo(msg->easy_handle, CURLINFO_PRIVATE, &priv);
        int h = static_cast<int>(reinterpret_cast<intptr_t>(priv));
        Request *r = lookup(h);
        if (!r || r->easy != msg->easy_handle) continue;
        if (r->ws) ws_connected(r, h, static_cast<int>(msg->data.result));
        else finish(r, h, static_cast<int>(msg->data.result));
    }
    /* By index: nothing in ws_service adds or removes a socket. */
    for (size_t i = 0; i < g_ws.size(); ++i) {
        Request *r = lookup(g_ws[i]);
        if (r) ws_service(r, g_ws[i]);
    }
}

void free_all() {
    std::vector<int> live;
    g_requests.collect_live(live);
    for (int h : live) {
        Request *r = lookup(h);
        if (r && r->state == CUX_STATE_RUNNING) curl_multi_remove_handle(g_multi, r->easy);
        g_requests.free(h);
    }
    g_done.clear();
    g_ws.clear();
}

/* The socket of an open WebSocket, for cux_ws_wait to sleep on: once the
 * upgrade is done curl_multi_poll no longer watches it. */
bool ws_waitfd(Request *r, struct curl_waitfd *fd) {
    if (r->ws_state != CUX_WS_OPEN && r->ws_state != CUX_WS_CLOSING) return false;
    curl_socket_t s = CURL_SOCKET_BAD;
    if (curl_easy_getinfo(r->easy, CURLINFO_ACTIVESOCKET, &s) != CURLE_OK) return false;
    if (s == CURL_SOCKET_BAD) return false;
    fd->fd = s;
    fd->events = CURL_WAIT_POLLIN;
    if (!r->ws_out.empty()) fd->events |= CURL_WAIT_POLLOUT;
    fd->revents = 0;
    return true;
}

/* The request-making code cux_request_new and cux_ws_new share. */
int new_request(const char *method, const char *url, bool ws) {
    if (g_init_count == 0) { set_error("not initialized: call cuInitialize"); return 0; }
    if (!url || !*url) { set_error("empty URL"); return 0; }
    std::unique_ptr<Request> r(new Request());
    r->method = (method && *method) ? method : "GET";
    for (char &c : r->method) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    r->url = url;
    if (ws) {
        if (!starts_with_ci(r->url, "ws://") && !starts_with_ci(r->url, "wss://")) {
            set_error("a WebSocket URL starts with ws:// or wss://");
            return 0;
        }
        r->ws = true;
        r->quiet = true;   /* never listed by cux_poll: see cux_abi.h */
    }
    r->easy = curl_easy_init();
    if (!r->easy) { set_error("curl_easy_init failed"); return 0; }
    CURL *e = r->easy;
    Request *raw = r.get();
    int h = g_requests.alloc(std::move(r));
    if (h == 0) { set_error("request table full"); return 0; }
    curl_easy_setopt(e, CURLOPT_URL, raw->url.c_str());
    curl_easy_setopt(e, CURLOPT_PRIVATE, reinterpret_cast<char *>(static_cast<intptr_t>(h)));
    curl_easy_setopt(e, CURLOPT_ERRORBUFFER, raw->errbuf);
    curl_easy_setopt(e, CURLOPT_WRITEFUNCTION, on_write);
    curl_easy_setopt(e, CURLOPT_WRITEDATA, raw);
    curl_easy_setopt(e, CURLOPT_HEADERFUNCTION, on_header);
    curl_easy_setopt(e, CURLOPT_HEADERDATA, raw);
    curl_easy_setopt(e, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(e, CURLOPT_NOPROGRESS, 1L);
    /* Only the protocols this library is for; a redirect may not wander
     * into file:// or anything else curl happens to be built with. */
    curl_easy_setopt(e, CURLOPT_PROTOCOLS_STR, "http,https,ftp,ftps,sftp,scp,smtp,smtps,ws,wss");
    curl_easy_setopt(e, CURLOPT_REDIR_PROTOCOLS_STR, "http,https,ftp,ftps");
    apply_default_ca(e);
    if (ws) {
        /* 2 = do the upgrade, then hand the connection to curl_ws_*. */
        curl_easy_setopt(e, CURLOPT_CONNECT_ONLY, 2L);
        /* Pings are answered by ws_service, not by libcurl: libcurl 8.22
         * holds its automatic pong until the NEXT frame is received or
         * sent, so a ping on an otherwise quiet socket would go unanswered
         * and a server's keep-alive would drop the connection. */
        curl_easy_setopt(e, CURLOPT_WS_OPTIONS, static_cast<long>(CURLWS_NOAUTOPONG));
        g_ws.push_back(h);
    }
    return h;
}

long long info_off(CURL *e, CURLINFO what) {
    curl_off_t v = 0;
    if (curl_easy_getinfo(e, what, &v) != CURLE_OK) return 0;
    return static_cast<long long>(v);
}

}  // namespace

/* ================================================================ exports */

extern "C" {

CUX_API int CUX_CALL cux_abi_version(void) { return CUX_ABI_VERSION; }

CUX_API int CUX_CALL cux_init(void) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        if (g_init_count == 0) {
            if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
                set_error("curl_global_init failed");
                return CUX_ERR_NATIVE;
            }
            g_multi = curl_multi_init();
            if (!g_multi) {
                curl_global_cleanup();
                set_error("curl_multi_init failed");
                return CUX_ERR_NATIVE;
            }
        }
        ++g_init_count;
        return g_init_count;
    )
}

/* Give back one hold. The release that reaches zero frees every request and
 * the multi handle: the same process-wide counting enetxt uses, so a window
 * may give back only the holds it took (enetxt gotcha 7). */
CUX_API int CUX_CALL cux_cleanup(void) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        if (g_init_count == 0) return 0;
        --g_init_count;
        if (g_init_count == 0) {
            free_all();
            curl_multi_cleanup(g_multi);
            g_multi = nullptr;
            curl_global_cleanup();
        }
        return g_init_count;
    )
}

CUX_API int CUX_CALL cux_version_string(char *out, int cap) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        std::string v = "curlxt ABI " + std::to_string(CUX_ABI_VERSION) + "; " + curl_version()
                        + platform_version_suffix();
        return copy_out(v, out, cap);
    )
}

CUX_API int CUX_CALL cux_last_error(char *out, int cap) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        return copy_out(g_last_error, out, cap);
    )
}

CUX_API void CUX_CALL cux_clear_error(void) {
    CUX_GUARD_VOID(
        g_last_error.clear();
    )
}

CUX_API int CUX_CALL cux_request_new(const char *method, const char *url) {
    CUX_GUARD_INT(0,
        return new_request(method, url, false);
    )
}

CUX_API int CUX_CALL cux_set_header(int h, const char *line) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state != CUX_STATE_NEW) { set_error("request already started"); return CUX_ERR_STATE; }
        if (!line || !*line) return CUX_ERR_ARG;
        struct curl_slist *n = curl_slist_append(r->headers, line);
        if (!n) return CUX_ERR_NATIVE;
        r->headers = n;
        return CUX_OK;
    )
}

CUX_API int CUX_CALL cux_set_int(int h, int option, int value) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state != CUX_STATE_NEW) { set_error("request already started"); return CUX_ERR_STATE; }
        CURL *e = r->easy;
        long v = static_cast<long>(value);
        CURLcode rc = CURLE_OK;
        switch (option) {
        case CUO_TIMEOUT_MS:
            /* For a WebSocket this bounds the upgrade and nothing after it
             * (a socket is meant to stay open), so it is kept for
             * ws_service's clock and never given to libcurl, where a
             * whole-transfer limit could outlive the upgrade. */
            if (r->ws) {
                if (v < 0) return CUX_ERR_ARG;
                r->ws_timeout_ms = v;
            } else {
                rc = curl_easy_setopt(e, CURLOPT_TIMEOUT_MS, v);
            }
            break;
        case CUO_CONNECT_TIMEOUT_MS:
            rc = curl_easy_setopt(e, CURLOPT_CONNECTTIMEOUT_MS, v);
            if (rc == CURLE_OK) r->ws_connect_timeout_ms = v;
            break;
        case CUO_FOLLOW_REDIRECTS:   rc = curl_easy_setopt(e, CURLOPT_FOLLOWLOCATION, v ? 1L : 0L); break;
        case CUO_MAX_REDIRECTS:      rc = curl_easy_setopt(e, CURLOPT_MAXREDIRS, v); break;
        case CUO_VERIFY_PEER:        rc = curl_easy_setopt(e, CURLOPT_SSL_VERIFYPEER, v ? 1L : 0L); break;
        case CUO_VERIFY_HOST:        rc = curl_easy_setopt(e, CURLOPT_SSL_VERIFYHOST, v ? 2L : 0L); break;
        case CUO_LOW_SPEED_LIMIT:    rc = curl_easy_setopt(e, CURLOPT_LOW_SPEED_LIMIT, v); break;
        case CUO_LOW_SPEED_TIME:     rc = curl_easy_setopt(e, CURLOPT_LOW_SPEED_TIME, v); break;
        case CUO_USE_SSL:
            if (v < 0 || v > 3) return CUX_ERR_ARG;
            rc = curl_easy_setopt(e, CURLOPT_USE_SSL, v);
            break;
        case CUO_FTP_PASSIVE:        rc = curl_easy_setopt(e, CURLOPT_FTPPORT, v ? nullptr : "-"); break;
        case CUO_MAX_BODY_BYTES:
            if (v < 0) return CUX_ERR_ARG;
            r->max_body = v;
            break;
        case CUO_HTTP_VERSION: {
            long hv = CURL_HTTP_VERSION_NONE;
            if (v == 1) hv = CURL_HTTP_VERSION_1_0;
            else if (v == 2) hv = CURL_HTTP_VERSION_1_1;
            else if (v == 3) hv = CURL_HTTP_VERSION_2TLS;
            else if (v != 0) return CUX_ERR_ARG;
            rc = curl_easy_setopt(e, CURLOPT_HTTP_VERSION, hv);
            break;
        }
        case CUO_DNS_CACHE_SECONDS:  rc = curl_easy_setopt(e, CURLOPT_DNS_CACHE_TIMEOUT, v); break;
        case CUO_CREATE_DIRS:
            rc = curl_easy_setopt(e, CURLOPT_FTP_CREATE_MISSING_DIRS,
                                  v ? static_cast<long>(CURLFTP_CREATE_DIR) : static_cast<long>(CURLFTP_CREATE_DIR_NONE));
            break;
        case CUO_WS_CLOSE_TIMEOUT_MS:
            if (v < 0) return CUX_ERR_ARG;
            r->ws_close_timeout_ms = v;
            break;
        default:
            set_error("unknown integer option " + std::to_string(option));
            return CUX_ERR_ARG;
        }
        if (rc != CURLE_OK) { set_error(curl_easy_strerror(rc)); return CUX_ERR_NATIVE; }
        return CUX_OK;
    )
}

CUX_API int CUX_CALL cux_set_text(int h, int option, const char *value) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state != CUX_STATE_NEW) { set_error("request already started"); return CUX_ERR_STATE; }
        CURL *e = r->easy;
        const char *v = value ? value : "";
        CURLcode rc = CURLE_OK;
        struct curl_slist *n = nullptr;
        switch (option) {
        case CUO_USERNAME:        rc = curl_easy_setopt(e, CURLOPT_USERNAME, v); break;
        case CUO_PASSWORD:        rc = curl_easy_setopt(e, CURLOPT_PASSWORD, v); break;
        case CUO_PROXY:           rc = curl_easy_setopt(e, CURLOPT_PROXY, v); break;
        case CUO_CA_FILE:         rc = set_ca_file(e, v); break;
        case CUO_OUTPUT_FILE:     r->output_path = v; break;
        case CUO_INPUT_FILE:      r->input_path = v; break;
        case CUO_MAIL_FROM:       rc = curl_easy_setopt(e, CURLOPT_MAIL_FROM, v); break;
        case CUO_MAIL_RCPT:
            if (!*v) return CUX_ERR_ARG;
            n = curl_slist_append(r->rcpt, v);
            if (!n) return CUX_ERR_NATIVE;
            r->rcpt = n;
            break;
        case CUO_USER_AGENT:      rc = curl_easy_setopt(e, CURLOPT_USERAGENT, v); break;
        case CUO_SSH_PUBLIC_KEY:  rc = curl_easy_setopt(e, CURLOPT_SSH_PUBLIC_KEYFILE, v); break;
        case CUO_SSH_PRIVATE_KEY: rc = curl_easy_setopt(e, CURLOPT_SSH_PRIVATE_KEYFILE, v); break;
        case CUO_KEY_PASSWORD:    rc = curl_easy_setopt(e, CURLOPT_KEYPASSWD, v); break;
        case CUO_QUOTE:
            if (!*v) return CUX_ERR_ARG;
            n = curl_slist_append(r->quote, v);
            if (!n) return CUX_ERR_NATIVE;
            r->quote = n;
            break;
        case CUO_POST_QUOTE:
            if (!*v) return CUX_ERR_ARG;
            n = curl_slist_append(r->postquote, v);
            if (!n) return CUX_ERR_NATIVE;
            r->postquote = n;
            break;
        case CUO_PROXY_USERPWD:   rc = curl_easy_setopt(e, CURLOPT_PROXYUSERPWD, v); break;
        case CUO_REFERER:         rc = curl_easy_setopt(e, CURLOPT_REFERER, v); break;
        case CUO_ACCEPT_ENCODING: rc = curl_easy_setopt(e, CURLOPT_ACCEPT_ENCODING, v); break;
        default:
            set_error("unknown text option " + std::to_string(option));
            return CUX_ERR_ARG;
        }
        if (rc != CURLE_OK) { set_error(curl_easy_strerror(rc)); return CUX_ERR_NATIVE; }
        return CUX_OK;
    )
}

CUX_API int CUX_CALL cux_set_body(int h, const void *bytes, int len) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state != CUX_STATE_NEW) { set_error("request already started"); return CUX_ERR_STATE; }
        if (r->ws) { set_error("a WebSocket has no request body: send with cuWsSend"); return CUX_ERR_STATE; }
        if (len < 0 || (len > 0 && !bytes)) return CUX_ERR_ARG;
        const unsigned char *p = static_cast<const unsigned char *>(bytes);
        r->send.assign(p, p + len);
        r->send_pos = 0;
        r->has_body = true;
        return CUX_OK;
    )
}

CUX_API int CUX_CALL cux_start(int h) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state != CUX_STATE_NEW) { set_error("request already started"); return CUX_ERR_STATE; }
        /* A WebSocket has no body and no files to prepare: only its headers
         * (a subprotocol, a token) ride the upgrade request. */
        int rc = CUX_OK;
        if (r->ws) curl_easy_setopt(r->easy, CURLOPT_HTTPHEADER, r->headers);
        else rc = prepare(r);
        if (rc != CUX_OK) return rc;
        CURLMcode mc = curl_multi_add_handle(g_multi, r->easy);
        if (mc != CURLM_OK) { set_error(curl_multi_strerror(mc)); return CUX_ERR_NATIVE; }
        r->state = CUX_STATE_RUNNING;
        if (r->ws) {
            r->ws_state = CUX_WS_CONNECTING;
            long long limit = r->ws_timeout_ms;
            if (r->ws_connect_timeout_ms > 0 && (limit <= 0 || r->ws_connect_timeout_ms < limit))
                limit = r->ws_connect_timeout_ms;
            if (limit > 0) {
                r->ws_open_deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(limit);
                r->ws_open_deadline_set = true;
            }
        }
        return CUX_OK;
    )
}

/* Stop a running request. It is reported by cux_poll like any other ending,
 * with result CUX_RESULT_CANCELLED, so a caller waiting on its callback
 * always gets one. Cancelling a request that has not started finishes it on
 * the spot; cancelling a finished one is a no-op. */
CUX_API int CUX_CALL cux_cancel(int h) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state == CUX_STATE_DONE) return CUX_OK;
        r->cancelled = true;
        if (r->state == CUX_STATE_NEW) {
            r->state = CUX_STATE_DONE;
            r->result = CUX_RESULT_CANCELLED;
            if (r->ws) r->ws_state = CUX_WS_CLOSED;
            if (!r->quiet) g_done.push_back(h);
            return CUX_OK;
        }
        /* A WebSocket is dropped on the spot, with no close handshake: the
         * polite ending is cux_ws_close. */
        if (r->ws) ws_end(r, h, CUX_RESULT_CANCELLED, r->ws_state == CUX_WS_CONNECTING ? 0 : CUX_WS_CODE_ABNORMAL, "");
        else finish(r, h, CUX_RESULT_CANCELLED);
        return CUX_OK;
    )
}

CUX_API int CUX_CALL cux_free(int h) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state == CUX_STATE_RUNNING) curl_multi_remove_handle(g_multi, r->easy);
        g_done.erase(std::remove(g_done.begin(), g_done.end(), h), g_done.end());
        if (r->ws) g_ws.erase(std::remove(g_ws.begin(), g_ws.end(), h), g_ws.end());
        g_requests.free(h);
        return CUX_OK;
    )
}

/* The pump. Moves every running request one step, then writes the handles
 * that have ended since the last poll as a comma list ("12,65547"). Returns
 * the bytes written (0 = nothing ended), or -(bytes needed) when the list
 * does not fit, leaving the queue intact so the next call loses nothing. */
CUX_API int CUX_CALL cux_poll(char *out, int cap) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        if (g_init_count == 0) return CUX_ERR_NOT_INIT;
        pump();
        std::string list;
        for (int h : g_done) {
            if (!list.empty()) list.push_back(',');
            list += std::to_string(h);
        }
        if (list.empty()) {
            if (out && cap > 0) out[0] = 0;
            return 0;
        }
        int n = copy_out(list, out, cap);
        if (n >= 0) g_done.clear();
        return n;
    )
}

/* Drive ONE request to its end, blocking: the synchronous calls. Other
 * running requests move too (they share the pump) and are queued for
 * cux_poll as usual; this request is not, because its caller collects it
 * here. Returns 1 when it has ended, 0 on timeout (it keeps running and is
 * reported by cux_poll), or a negative error. timeout_ms < 0 waits for the
 * request's own timeouts alone. */
CUX_API int CUX_CALL cux_wait(int h, int timeout_ms) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state == CUX_STATE_NEW) { set_error("request not started"); return CUX_ERR_STATE; }
        /* A WebSocket does not "end" the way a transfer does, and this wait
         * would hand it to cux_poll's list on a timeout. */
        if (r->ws) { set_error("a WebSocket is waited on with cuWsWait"); return CUX_ERR_STATE; }
        bool was_queued = (r->state == CUX_STATE_DONE);
        r->quiet = true;
        auto start = std::chrono::steady_clock::now();
        while (r->state == CUX_STATE_RUNNING) {
            int slice = 50;
            if (timeout_ms >= 0) {
                long long spent = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - start).count();
                if (spent >= timeout_ms) { r->quiet = false; return 0; }
                slice = static_cast<int>(std::min<long long>(slice, timeout_ms - spent));
            }
            pump();
            if (r->state != CUX_STATE_RUNNING) break;
            curl_multi_poll(g_multi, nullptr, 0, slice, nullptr);
            r = lookup(h);
            if (!r) return CUX_ERR_STALE;
        }
        /* It ended before this wait began: it was queued for cux_poll, and
         * this caller is collecting it now, so take it back off the queue. */
        if (was_queued) g_done.erase(std::remove(g_done.begin(), g_done.end(), h), g_done.end());
        return 1;
    )
}

CUX_API double CUX_CALL cux_info(int h, int field) {
    CUX_GUARD_DOUBLE(-1.0,
        Request *r = lookup(h);
        if (!r) return -1.0;
        CURL *e = r->easy;
        long code = 0;
        double secs = 0;
        switch (field) {
        case CUI_STATE:         return r->state;
        case CUI_RESULT:        return r->result;
        case CUI_RESPONSE_CODE:
            curl_easy_getinfo(e, CURLINFO_RESPONSE_CODE, &code);
            return static_cast<double>(code);
        case CUI_BYTES_DOWN:    return static_cast<double>(info_off(e, CURLINFO_SIZE_DOWNLOAD_T));
        case CUI_BYTES_UP:      return static_cast<double>(info_off(e, CURLINFO_SIZE_UPLOAD_T));
        case CUI_LENGTH_DOWN: {
            curl_off_t v = -1;
            if (curl_easy_getinfo(e, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &v) != CURLE_OK) v = -1;
            return static_cast<double>(v);
        }
        case CUI_LENGTH_UP: {
            if (r->in_size >= 0) return static_cast<double>(r->in_size);
            if (r->has_body) return static_cast<double>(r->send.size());
            return -1.0;
        }
        case CUI_TOTAL_TIME:
            curl_easy_getinfo(e, CURLINFO_TOTAL_TIME, &secs);
            return secs;
        case CUI_REDIRECT_COUNT:
            curl_easy_getinfo(e, CURLINFO_REDIRECT_COUNT, &code);
            return static_cast<double>(code);
        case CUI_BODY_SIZE:     return static_cast<double>(r->body.size());
        case CUI_CANCELLED:     return r->cancelled ? 1.0 : 0.0;
        case CUI_WS_STATE:      return r->ws_state;
        case CUI_WS_MESSAGES:   return static_cast<double>(r->ws_in.size());
        case CUI_WS_NEXT_TYPE:  return r->ws_in.empty() ? 0.0 : r->ws_in.front().kind;
        case CUI_WS_NEXT_SIZE:  return r->ws_in.empty() ? 0.0 : static_cast<double>(r->ws_in.front().data.size());
        case CUI_WS_CLOSE_CODE: return r->ws_close_code;
        case CUI_WS_QUEUED_BYTES: return static_cast<double>(r->ws_out_bytes);
        case CUI_WS_PONGS:      return static_cast<double>(r->ws_pongs);
        default:
            set_error("unknown info field " + std::to_string(field));
            return -1.0;
        }
    )
}

CUX_API int CUX_CALL cux_text(int h, int field, char *out, int cap) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        std::string s;
        char *p = nullptr;
        switch (field) {
        case CUT_HEADERS: s = r->resp_headers; break;
        case CUT_ERROR:
            if (r->result == CUX_RESULT_CANCELLED) s = "cancelled";
            else if (r->body_overflow) s = r->ws ? "a message was larger than the limit set"
                                                 : "response body is larger than the limit set";
            else if (r->out_close_failed) s = "could not finish writing the output file";
            else if (r->errbuf[0]) s = r->errbuf;
            else if (r->result > 0) s = curl_easy_strerror(static_cast<CURLcode>(r->result));
            break;
        case CUT_EFFECTIVE_URL:
            if (curl_easy_getinfo(r->easy, CURLINFO_EFFECTIVE_URL, &p) == CURLE_OK && p) s = p;
            break;
        case CUT_CONTENT_TYPE:
            if (curl_easy_getinfo(r->easy, CURLINFO_CONTENT_TYPE, &p) == CURLE_OK && p) s = p;
            break;
        case CUT_METHOD: s = r->method; break;
        case CUT_WS_CLOSE_REASON: s = r->ws_close_reason; break;
        default:
            set_error("unknown text field " + std::to_string(field));
            return CUX_ERR_ARG;
        }
        return copy_out(s, out, cap);
    )
}

/* The held response body, as bytes. Returns the bytes written, or
 * -(bytes needed) when it does not fit (an empty body writes 0). Reading it
 * does not consume it; cux_free releases it. */
CUX_API int CUX_CALL cux_body(int h, char *out, int cap) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->body.size() > 0x7FFFFFF0u) { set_error("body too large to return"); return CUX_ERR_GENERIC; }
        int need = static_cast<int>(r->body.size());
        if (need == 0) return 0;
        if (!out || cap < need) return -need;
        std::memcpy(out, r->body.data(), r->body.size());
        return need;
    )
}

CUX_API int CUX_CALL cux_live_count(void) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        return static_cast<int>(g_requests.live_count());
    )
}

/* ============================================================ WebSockets */

/* Make a WebSocket: a request handle like any other until it is started.
 * Headers and options are set with the ordinary setters; cux_start begins
 * the upgrade. Returns the handle, or 0 with the reason recorded. */
CUX_API int CUX_CALL cux_ws_new(const char *url) {
    CUX_GUARD_INT(0,
        return new_request("GET", url, true);
    )
}

/* Queue one whole message (or a ping or pong) and write as much of it as
 * the socket takes now; the pump writes the rest. Returns CUX_OK, or
 * CUX_ERR_STATE when the socket is not open or too much is already queued. */
CUX_API int CUX_CALL cux_ws_send(int h, int kind, const void *bytes, int len) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (!r->ws) { set_error("not a WebSocket"); return CUX_ERR_STATE; }
        if (len < 0 || (len > 0 && !bytes)) return CUX_ERR_ARG;
        unsigned int flags = 0;
        if (kind == CUX_WS_KIND_TEXT) flags = CURLWS_TEXT;
        else if (kind == CUX_WS_KIND_BINARY) flags = CURLWS_BINARY;
        else if (kind == CUX_WS_KIND_PING) flags = CURLWS_PING;
        else if (kind == CUX_WS_KIND_PONG) flags = CURLWS_PONG;
        else { set_error("unknown WebSocket message kind " + std::to_string(kind)); return CUX_ERR_ARG; }
        if ((kind == CUX_WS_KIND_PING || kind == CUX_WS_KIND_PONG) && len > 125) {
            set_error("a ping or pong carries at most 125 bytes");
            return CUX_ERR_ARG;
        }
        if (r->ws_state != CUX_WS_OPEN) { set_error("the WebSocket is not open"); return CUX_ERR_STATE; }
        if (r->ws_out_bytes + static_cast<size_t>(len) > kWsOutMax) {
            set_error("too much is waiting to be sent: the peer is not reading");
            return CUX_ERR_STATE;
        }
        ws_queue(r, flags, static_cast<const unsigned char *>(bytes), static_cast<size_t>(len));
        ws_flush(r, h);
        return CUX_OK;
    )
}

/* Close politely: queue a close frame and wait (under the pump) for the
 * peer's. A socket still connecting is simply ended. Closing twice, or
 * closing a closed socket, is a no-op. code 0 sends a close with no code;
 * otherwise 1000, or 3000..4999 (the ranges RFC 6455 gives an application). */
CUX_API int CUX_CALL cux_ws_close(int h, int code, const char *reason) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (!r->ws) { set_error("not a WebSocket"); return CUX_ERR_STATE; }
        if (code != 0 && code != 1000 && code != 1001 && !(code >= 3000 && code <= 4999)) {
            set_error("a close code is 0, 1000, 1001 or 3000 to 4999");
            return CUX_ERR_ARG;
        }
        if (r->ws_state == CUX_WS_CLOSED || r->ws_state == CUX_WS_CLOSING) return CUX_OK;
        if (r->state == CUX_STATE_NEW) {
            r->state = CUX_STATE_DONE;
            r->result = CURLE_OK;
            r->ws_state = CUX_WS_CLOSED;
            return CUX_OK;
        }
        if (r->ws_state == CUX_WS_CONNECTING) {
            ws_end(r, h, CURLE_OK, 0, "");
            return CUX_OK;
        }
        ws_queue_close(r, code, reason ? reason : "");
        r->ws_state = CUX_WS_CLOSING;
        if (r->ws_close_timeout_ms > 0) {
            r->ws_close_deadline = std::chrono::steady_clock::now() +
                                   std::chrono::milliseconds(r->ws_close_timeout_ms);
            r->ws_close_deadline_set = true;
        }
        ws_flush(r, h);
        return CUX_OK;
    )
}

/* Take the oldest received message. Returns its bytes written (0 for an
 * empty message, which is taken too), -(bytes needed) when it does not fit
 * (nothing is taken), or CUX_ERR_STATE when none is waiting: a caller asks
 * CUI_WS_MESSAGES and CUI_WS_NEXT_SIZE first, as it asks CUI_BODY_SIZE
 * before cux_body. Messages stay readable after the socket has closed. */
CUX_API int CUX_CALL cux_ws_read(int h, char *out, int cap) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (!r->ws) { set_error("not a WebSocket"); return CUX_ERR_STATE; }
        if (r->ws_in.empty()) return CUX_ERR_STATE;
        WsMessage &m = r->ws_in.front();
        if (m.data.size() > 0x7FFFFFF0u) { set_error("message too large to return"); return CUX_ERR_GENERIC; }
        int need = static_cast<int>(m.data.size());
        if (need > 0 && (!out || cap < need)) return -need;
        if (need > 0) std::memcpy(out, m.data.data(), m.data.size());
        r->ws_in_bytes -= m.data.size();
        r->ws_in.pop_front();
        return need;
    )
}

/* The pump, for a caller that has only WebSockets: it moves everything
 * cux_poll moves and consumes NOTHING of cux_poll's list, so it cannot take
 * a finished request away from whoever is waiting on that list. Returns how
 * many received messages are waiting across every socket. */
CUX_API int CUX_CALL cux_ws_poll(void) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        if (g_init_count == 0) return CUX_ERR_NOT_INIT;
        pump();
        size_t waiting = 0;
        for (int h : g_ws) {
            Request *r = lookup(h);
            if (r) waiting += r->ws_in.size();
        }
        return static_cast<int>(std::min<size_t>(waiting, 0x7FFFFFFF));
    )
}

/* Block until something happens on ONE socket: a message is waiting, it has
 * closed, or it has left the state it was in when the wait began (so a wait
 * on a connecting socket returns when it opens). Returns 1 then, 0 on
 * timeout, or a negative error. timeout_ms < 0 waits without limit. Other
 * requests and sockets move meanwhile, as under cux_wait.
 *
 * A message already waiting answers 1 at once, but after ONE pass of the
 * pump (no sleep): before 2026-11-21 it answered without moving anything,
 * so a loop that waited for a LATER state (the close, a count of messages)
 * with messages unread spun in place and the socket never moved (curlxt
 * gotcha 6). A closed socket cannot move, so it still answers untouched. */
CUX_API int CUX_CALL cux_ws_wait(int h, int timeout_ms) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (!r->ws) { set_error("not a WebSocket"); return CUX_ERR_STATE; }
        if (r->state == CUX_STATE_NEW) { set_error("request not started"); return CUX_ERR_STATE; }
        if (!r->ws_in.empty() && r->ws_state != CUX_WS_CLOSED) {
            pump();
            if (!lookup(h)) return CUX_ERR_STALE;
            return 1;
        }
        int entered = r->ws_state;
        auto start = std::chrono::steady_clock::now();
        for (;;) {
            if (!r->ws_in.empty() || r->ws_state == CUX_WS_CLOSED || r->ws_state != entered) return 1;
            int slice = 50;
            if (timeout_ms >= 0) {
                long long spent = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - start).count();
                if (spent >= timeout_ms) return 0;
                slice = static_cast<int>(std::min<long long>(slice, timeout_ms - spent));
            }
            pump();
            r = lookup(h);
            if (!r) return CUX_ERR_STALE;
            if (!r->ws_in.empty() || r->ws_state == CUX_WS_CLOSED || r->ws_state != entered) return 1;
            struct curl_waitfd fd;
            bool have = ws_waitfd(r, &fd);
            curl_multi_poll(g_multi, have ? &fd : nullptr, have ? 1u : 0u, slice, nullptr);
            r = lookup(h);
            if (!r) return CUX_ERR_STALE;
        }
    )
}

CUX_API int CUX_CALL cux_selftest_throw(void) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        throw std::runtime_error("cux_selftest_throw");
    )
}

}  // extern "C"
