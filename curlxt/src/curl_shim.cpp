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

/* One step of the pump: let curl move every running transfer as far as it
 * can without blocking, then collect the ones that ended. */
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
        if (r && r->easy == msg->easy_handle) finish(r, h, static_cast<int>(msg->data.result));
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
        if (g_init_count == 0) { set_error("not initialized: call cuInitialize"); return 0; }
        if (!url || !*url) { set_error("empty URL"); return 0; }
        std::unique_ptr<Request> r(new Request());
        r->method = (method && *method) ? method : "GET";
        for (char &c : r->method) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        r->url = url;
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
        return h;
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
        case CUO_TIMEOUT_MS:         rc = curl_easy_setopt(e, CURLOPT_TIMEOUT_MS, v); break;
        case CUO_CONNECT_TIMEOUT_MS: rc = curl_easy_setopt(e, CURLOPT_CONNECTTIMEOUT_MS, v); break;
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
        int rc = prepare(r);
        if (rc != CUX_OK) return rc;
        CURLMcode mc = curl_multi_add_handle(g_multi, r->easy);
        if (mc != CURLM_OK) { set_error(curl_multi_strerror(mc)); return CUX_ERR_NATIVE; }
        r->state = CUX_STATE_RUNNING;
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
            if (!r->quiet) g_done.push_back(h);
            return CUX_OK;
        }
        finish(r, h, CUX_RESULT_CANCELLED);
        return CUX_OK;
    )
}

CUX_API int CUX_CALL cux_free(int h) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        Request *r = lookup(h);
        if (!r) return CUX_ERR_STALE;
        if (r->state == CUX_STATE_RUNNING) curl_multi_remove_handle(g_multi, r->easy);
        g_done.erase(std::remove(g_done.begin(), g_done.end(), h), g_done.end());
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
            else if (r->body_overflow) s = "response body is larger than the limit set";
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

CUX_API int CUX_CALL cux_selftest_throw(void) {
    CUX_GUARD_INT(CUX_ERR_THROWN,
        throw std::runtime_error("cux_selftest_throw");
    )
}

}  // extern "C"
