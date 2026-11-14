/* curl_smoke_test.cpp - the native gate for curlxt.
 *
 * Drives the exported cux_* surface (linked against the SHARED library, so
 * every call crosses the real export boundary) against a tiny HTTP/1.1
 * server this test runs itself on 127.0.0.1, so it needs no network. Also
 * unit-tests the carried handle table (header-only). Built and run by
 * `ctest` with CURLXT_BUILD_TESTS=ON; a shim change is done when this is
 * green under ASan/UBSan (CURLXT_SANITIZE=address).
 *
 * What it settles:
 *   - init/cleanup refcounting, and that a request needs init;
 *   - GET into memory, body and headers and info fields;
 *   - POST echo (binary-safe, with a NUL byte), PUT upload from memory and
 *     from a file, a custom method, request headers reaching the server;
 *   - download straight to a file;
 *   - redirects followed and not followed;
 *   - the async pump: several requests in flight, every one reported ONCE
 *     by cux_poll, and the lossless too-small-buffer contract;
 *   - cancel (reported with CUX_RESULT_CANCELLED), a timeout, a refused
 *     connection (a curl error, not a crash), the in-memory body cap;
 *   - stale handles are harmless no-ops; started requests refuse setters;
 *   - the exception firewall turns a throw into an error return.
 */

#include "cux_abi.h"
#include "cux_handle_table.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32)
#  include <winsock2.h>
#  include <ws2tcpip.h>
typedef SOCKET sock_t;
#  define CLOSESOCK closesocket
#else
#  include <arpa/inet.h>
#  include <netinet/in.h>
#  include <sys/socket.h>
#  include <unistd.h>
typedef int sock_t;
#  define CLOSESOCK close
#  define INVALID_SOCKET (-1)
#endif

static int g_fail = 0;
static int g_pass = 0;

#define CHECK(cond, what) do {                                              \
    if (cond) { ++g_pass; }                                                 \
    else { ++g_fail; std::fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, what); } \
} while (0)

/* ------------------------------------------------------- the test server */

static std::atomic<bool> g_stop(false);
static int g_port = 0;

static bool read_request(sock_t c, std::string &head, std::string &body) {
    std::string buf;
    char tmp[4096];
    size_t hdr_end = std::string::npos;
    while ((hdr_end = buf.find("\r\n\r\n")) == std::string::npos) {
        int n = static_cast<int>(recv(c, tmp, sizeof tmp, 0));
        if (n <= 0) return false;
        buf.append(tmp, static_cast<size_t>(n));
    }
    head = buf.substr(0, hdr_end);
    body = buf.substr(hdr_end + 4);
    size_t len = 0;
    std::string lower = head;
    for (char &ch : lower) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    size_t p = lower.find("content-length:");
    if (p != std::string::npos) len = static_cast<size_t>(std::atol(head.c_str() + p + 15));
    if (lower.find("expect: 100-continue") != std::string::npos) {
        const char *cont = "HTTP/1.1 100 Continue\r\n\r\n";
        send(c, cont, static_cast<int>(std::strlen(cont)), 0);
    }
    while (body.size() < len) {
        int n = static_cast<int>(recv(c, tmp, sizeof tmp, 0));
        if (n <= 0) return false;
        body.append(tmp, static_cast<size_t>(n));
    }
    return true;
}

static void respond(sock_t c, int code, const std::string &extra, const std::string &body) {
    std::string r = "HTTP/1.1 " + std::to_string(code) + " X\r\n" + extra +
                    "Content-Length: " + std::to_string(body.size()) +
                    "\r\nConnection: close\r\n\r\n" + body;
    send(c, r.data(), static_cast<int>(r.size()), 0);
}

static std::string header_value(const std::string &head, const std::string &name) {
    size_t p = head.find("\r\n" + name + ": ");
    if (p == std::string::npos) return "";
    p += name.size() + 4;
    size_t e = head.find("\r\n", p);
    return head.substr(p, e == std::string::npos ? std::string::npos : e - p);
}

static void serve_one(sock_t c) {
    std::string head, body;
    if (!read_request(c, head, body)) { CLOSESOCK(c); return; }
    std::string line = head.substr(0, head.find("\r\n"));
    std::string method = line.substr(0, line.find(' '));
    std::string path = line.substr(line.find(' ') + 1);
    path = path.substr(0, path.find(' '));
    if (path == "/hello") respond(c, 200, "Content-Type: text/plain\r\nX-Served: yes\r\n", "hello world");
    else if (path == "/echo") respond(c, 200, "", method + ":" + body);
    else if (path == "/header") respond(c, 200, "", header_value(head, "X-Test"));
    else if (path == "/redirect") respond(c, 302, "Location: /hello\r\n", "");
    else if (path == "/missing") respond(c, 404, "", "nope");
    else if (path == "/big") respond(c, 200, "", std::string(100000, 'b'));
    else if (path == "/slow") {
        for (int i = 0; i < 40 && !g_stop; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
        respond(c, 200, "", "late");
    } else respond(c, 400, "", "bad path");
    CLOSESOCK(c);
}

static void server_loop(sock_t ls) {
    std::vector<std::thread> workers;
    while (!g_stop) {
        sock_t c = accept(ls, nullptr, nullptr);
        if (c == INVALID_SOCKET) continue;
        if (g_stop) { CLOSESOCK(c); break; }
        workers.emplace_back(serve_one, c);
    }
    for (std::thread &t : workers) t.join();
}

static sock_t start_server() {
    sock_t ls = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in a;
    std::memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = 0;
    bind(ls, reinterpret_cast<sockaddr *>(&a), sizeof a);
    listen(ls, 16);
    socklen_t al = sizeof a;
    getsockname(ls, reinterpret_cast<sockaddr *>(&a), &al);
    g_port = ntohs(a.sin_port);
    return ls;
}

/* ---------------------------------------------------------------- helpers */

static std::string url(const char *path) {
    return "http://127.0.0.1:" + std::to_string(g_port) + path;
}

static std::string text(int h, int field) {
    int need = cux_text(h, field, nullptr, 0);
    if (need >= 0) return "";
    std::vector<char> b(static_cast<size_t>(-need));
    int n = cux_text(h, field, b.data(), static_cast<int>(b.size()));
    return n >= 0 ? std::string(b.data(), static_cast<size_t>(n)) : "";
}

static std::string body(int h) {
    int need = cux_body(h, nullptr, 0);
    if (need >= 0) return "";
    std::vector<char> b(static_cast<size_t>(-need));
    int n = cux_body(h, b.data(), static_cast<int>(b.size()));
    return n > 0 ? std::string(b.data(), static_cast<size_t>(n)) : "";
}

static int run_sync(int h) {
    if (cux_start(h) != CUX_OK) return -100;
    return cux_wait(h, 10000);
}

static std::string temp_path(const char *name) {
#if defined(_WIN32)
    const char *d = std::getenv("TEMP");
    return std::string(d ? d : ".") + "\\" + name;
#else
    return std::string("/tmp/") + name;
#endif
}

static std::string read_file(const std::string &p) {
    FILE *f = std::fopen(p.c_str(), "rb");
    if (!f) return "<missing>";
    std::string s;
    char b[4096];
    size_t n;
    while ((n = std::fread(b, 1, sizeof b, f)) > 0) s.append(b, n);
    std::fclose(f);
    return s;
}

/* ------------------------------------------------------------------ tests */

static void test_handle_table() {
    cux::HandleTable<int> t;
    int a = t.alloc(7);
    CHECK(a > 0 && t.get(a) && *t.get(a) == 7, "table alloc/get");
    CHECK(t.free(a), "table free");
    CHECK(!t.get(a), "freed handle is stale");
    CHECK(!t.free(a), "free is idempotent");
    int b = t.alloc(9);
    CHECK(b != a && !t.get(a) && *t.get(b) == 9, "slot reuse bumps the generation");
    CHECK(!t.get(0) && !t.get(-5) && !t.get(0x7FFF0000), "junk handles are stale");
}

static void test_lifecycle() {
    CHECK(cux_abi_version() == CUX_ABI_VERSION, "abi version");
    CHECK(cux_request_new("GET", "http://127.0.0.1/") == 0, "request refused before init");
    CHECK(cux_poll(nullptr, 0) == CUX_ERR_NOT_INIT, "poll refused before init");
    CHECK(cux_init() == 1, "first init");
    CHECK(cux_init() == 2, "second init counts");
    CHECK(cux_cleanup() == 1, "release one hold");
    char v[512];
    int n = cux_version_string(v, sizeof v);
    CHECK(n > 0 && std::strstr(v, "libcurl/8.22.0") != nullptr, "version names the pinned libcurl");
    CHECK(std::strstr(v, "libssh2") != nullptr, "version names libssh2 (SFTP)");
    CHECK(cux_version_string(v, 3) < 0, "too-small buffer asks for more");
}

static void test_get() {
    int h = cux_request_new("get", url("/hello").c_str());
    CHECK(h > 0, "request new");
    CHECK(cux_info(h, CUI_STATE) == CUX_STATE_NEW, "state new");
    CHECK(run_sync(h) == 1, "GET finishes");
    CHECK(cux_info(h, CUI_STATE) == CUX_STATE_DONE, "state done");
    CHECK(cux_info(h, CUI_RESULT) == 0, "GET result 0");
    CHECK(cux_info(h, CUI_RESPONSE_CODE) == 200, "GET 200");
    CHECK(body(h) == "hello world", "GET body");
    CHECK(cux_info(h, CUI_BODY_SIZE) == 11, "body size");
    CHECK(cux_info(h, CUI_BYTES_DOWN) == 11, "bytes down");
    CHECK(cux_info(h, CUI_LENGTH_DOWN) == 11, "content length");
    CHECK(text(h, CUT_HEADERS).find("X-Served: yes") != std::string::npos, "response headers");
    CHECK(text(h, CUT_CONTENT_TYPE) == "text/plain", "content type");
    CHECK(text(h, CUT_METHOD) == "GET", "method upper-cased");
    CHECK(text(h, CUT_ERROR).empty(), "no error text on success");
    CHECK(cux_set_int(h, CUO_TIMEOUT_MS, 5) == CUX_ERR_STATE, "setters refuse after start");
    CHECK(cux_start(h) == CUX_ERR_STATE, "start twice refused");
    CHECK(cux_free(h) == CUX_OK, "free");
    CHECK(cux_info(h, CUI_STATE) == -1.0, "stale info is -1");
    CHECK(cux_free(h) == CUX_ERR_STALE, "stale free is a no-op");
    CHECK(cux_start(h) == CUX_ERR_STALE && cux_body(h, nullptr, 0) == CUX_ERR_STALE, "stale everything");
}

static void test_methods() {
    int h = cux_request_new("POST", url("/echo").c_str());
    const char payload[] = {'a', '\0', 'b'};
    CHECK(cux_set_body(h, payload, 3) == CUX_OK, "set body");
    CHECK(run_sync(h) == 1, "POST finishes");
    CHECK(body(h) == std::string("POST:a\0b", 8), "POST echoes binary-safe");
    cux_free(h);

    h = cux_request_new("PUT", url("/echo").c_str());
    cux_set_body(h, "put-data", 8);
    CHECK(run_sync(h) == 1 && body(h) == "PUT:put-data", "PUT from memory");
    CHECK(cux_info(h, CUI_LENGTH_UP) == 8 && cux_info(h, CUI_BYTES_UP) == 8, "upload counts");
    cux_free(h);

    std::string in = temp_path("curlxt-smoke-in.txt");
    FILE *f = std::fopen(in.c_str(), "wb");
    std::fputs("from-file", f);
    std::fclose(f);
    h = cux_request_new("PUT", url("/echo").c_str());
    cux_set_text(h, CUO_INPUT_FILE, in.c_str());
    CHECK(run_sync(h) == 1 && body(h) == "PUT:from-file", "PUT from a file");
    cux_free(h);
    h = cux_request_new("POST", url("/echo").c_str());
    cux_set_text(h, CUO_INPUT_FILE, in.c_str());
    CHECK(run_sync(h) == 1 && body(h) == "POST:from-file", "POST from a file");
    cux_free(h);
    std::remove(in.c_str());

    h = cux_request_new("PATCH", url("/echo").c_str());
    cux_set_body(h, "p", 1);
    CHECK(run_sync(h) == 1 && body(h) == "PATCH:p", "custom method with a body");
    cux_free(h);
    h = cux_request_new("DELETE", url("/echo").c_str());
    CHECK(run_sync(h) == 1 && body(h) == "DELETE:", "DELETE");
    cux_free(h);
    h = cux_request_new("HEAD", url("/hello").c_str());
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESPONSE_CODE) == 200 && body(h).empty(), "HEAD has no body");
    cux_free(h);

    h = cux_request_new("GET", url("/header").c_str());
    CHECK(cux_set_header(h, "X-Test: carried") == CUX_OK, "set header");
    CHECK(run_sync(h) == 1 && body(h) == "carried", "request header reaches the server");
    cux_free(h);

    h = cux_request_new("GET", url("/missing").c_str());
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) == 0 && cux_info(h, CUI_RESPONSE_CODE) == 404,
          "a 404 is a finished transfer, not a curl error");
    cux_free(h);
}

static void test_files_and_redirects() {
    std::string out = temp_path("curlxt-smoke-out.txt");
    int h = cux_request_new("GET", url("/big").c_str());
    cux_set_text(h, CUO_OUTPUT_FILE, out.c_str());
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) == 0, "download to file");
    CHECK(cux_info(h, CUI_BODY_SIZE) == 0, "a file download holds no body");
    CHECK(read_file(out) == std::string(100000, 'b'), "file content");
    cux_free(h);
    std::remove(out.c_str());

    h = cux_request_new("GET", url("/big").c_str());
    cux_set_text(h, CUO_OUTPUT_FILE, "/nonexistent-dir-curlxt/x");
    CHECK(cux_start(h) == CUX_ERR_ARG, "unopenable output file refused at start");
    cux_free(h);

    h = cux_request_new("GET", url("/redirect").c_str());
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESPONSE_CODE) == 302, "redirect not followed by default");
    cux_free(h);
    h = cux_request_new("GET", url("/redirect").c_str());
    cux_set_int(h, CUO_FOLLOW_REDIRECTS, 1);
    CHECK(run_sync(h) == 1 && body(h) == "hello world" && cux_info(h, CUI_REDIRECT_COUNT) == 1,
          "redirect followed");
    CHECK(text(h, CUT_EFFECTIVE_URL) == url("/hello"), "effective URL");
    CHECK(text(h, CUT_HEADERS).find("302") == std::string::npos, "headers are the final response's");
    cux_free(h);

    h = cux_request_new("GET", url("/big").c_str());
    cux_set_int(h, CUO_MAX_BODY_BYTES, 1000);
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) != 0, "body cap ends the transfer");
    CHECK(text(h, CUT_ERROR).find("larger than the limit") != std::string::npos, "body cap says why");
    cux_free(h);
}

static void test_async() {
    int a = cux_request_new("GET", url("/hello").c_str());
    int b = cux_request_new("POST", url("/echo").c_str());
    int c = cux_request_new("GET", url("/big").c_str());
    cux_set_body(b, "x", 1);
    CHECK(cux_start(a) == 0 && cux_start(b) == 0 && cux_start(c) == 0, "three started");
    std::vector<int> seen;
    char small[2];
    bool saw_too_small = false;
    for (int i = 0; i < 400 && seen.size() < 3; ++i) {
        int n = cux_poll(small, sizeof small);
        if (n < 0) {
            saw_too_small = true;
            std::vector<char> buf(static_cast<size_t>(-n));
            n = cux_poll(buf.data(), static_cast<int>(buf.size()));
            std::string list(buf.data(), n > 0 ? static_cast<size_t>(n) : 0);
            size_t p = 0;
            while (p < list.size()) {
                size_t e = list.find(',', p);
                if (e == std::string::npos) e = list.size();
                seen.push_back(std::atoi(list.substr(p, e - p).c_str()));
                p = e + 1;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    CHECK(saw_too_small, "a too-small poll buffer asks for more (handles are 5+ digits)");
    CHECK(seen.size() == 3, "every async request reported");
    bool all = true;
    for (int h : {a, b, c}) {
        int k = 0;
        for (int s : seen) k += (s == h);
        all = all && k == 1;
    }
    CHECK(all, "each reported exactly once");
    char buf[64];
    CHECK(cux_poll(buf, sizeof buf) == 0, "nothing left to report");
    CHECK(body(a) == "hello world" && body(b) == "POST:x" && body(c).size() == 100000, "async bodies");
    cux_free(a);
    cux_free(b);
    cux_free(c);
}

static void test_failures() {
    int h = cux_request_new("GET", url("/slow").c_str());
    cux_start(h);
    char buf[64];
    cux_poll(buf, sizeof buf);
    CHECK(cux_cancel(h) == CUX_OK, "cancel running");
    CHECK(cux_info(h, CUI_RESULT) == CUX_RESULT_CANCELLED && cux_info(h, CUI_CANCELLED) == 1, "cancel result");
    int n = cux_poll(buf, sizeof buf);
    CHECK(n > 0 && std::atoi(buf) == h, "a cancel is reported by poll");
    CHECK(text(h, CUT_ERROR) == "cancelled", "cancel text");
    CHECK(cux_cancel(h) == CUX_OK, "cancel done is a no-op");
    cux_free(h);

    h = cux_request_new("GET", url("/hello").c_str());
    CHECK(cux_cancel(h) == CUX_OK && cux_info(h, CUI_STATE) == CUX_STATE_DONE, "cancel before start");
    CHECK(cux_poll(buf, sizeof buf) > 0, "reported too");
    cux_free(h);

    h = cux_request_new("GET", url("/slow").c_str());
    cux_set_int(h, CUO_TIMEOUT_MS, 200);
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) == 28, "request timeout is CURLE_OPERATION_TIMEDOUT");
    CHECK(!text(h, CUT_ERROR).empty(), "timeout explained");
    cux_free(h);

    h = cux_request_new("GET", url("/slow").c_str());
    cux_start(h);
    CHECK(cux_wait(h, 100) == 0, "wait timeout leaves it running");
    CHECK(cux_info(h, CUI_STATE) == CUX_STATE_RUNNING, "still running");
    cux_free(h);   /* freeing a running request detaches it */
    CHECK(cux_poll(buf, sizeof buf) == 0, "a freed request is never reported");

    h = cux_request_new("GET", "http://127.0.0.1:1/");
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) == 7, "refused connection is CURLE_COULDNT_CONNECT");
    cux_free(h);
    h = cux_request_new("GET", "file:///etc/passwd");
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) != 0, "file:// is not allowed");
    cux_free(h);

    CHECK(cux_request_new("GET", "") == 0, "empty URL refused");
    h = cux_request_new("GET", url("/hello").c_str());
    CHECK(cux_set_int(h, 9999, 1) == CUX_ERR_ARG && cux_set_text(h, 9999, "x") == CUX_ERR_ARG,
          "unknown options refused");
    CHECK(cux_set_body(h, nullptr, 5) == CUX_ERR_ARG, "null body with a length refused");
    CHECK(cux_wait(h, 10) == CUX_ERR_STATE, "wait before start refused");
    cux_free(h);
    CHECK(cux_selftest_throw() == CUX_ERR_THROWN, "firewall catches a throw");
    char e[128];
    CHECK(cux_last_error(e, sizeof e) > 0 && std::strcmp(e, "cux_selftest_throw") == 0, "throw text recorded");
    cux_clear_error();
    CHECK(cux_last_error(e, sizeof e) == 0, "clear error");
}

static void test_teardown() {
    int h = cux_request_new("GET", url("/slow").c_str());
    cux_start(h);
    CHECK(cux_live_count() == 1, "one live request");
    CHECK(cux_cleanup() == 0, "last release");
    CHECK(cux_live_count() == 0, "the last release frees every request");
    CHECK(cux_info(h, CUI_STATE) == -1.0, "its handle is stale");
    CHECK(cux_cleanup() == 0, "extra release is a no-op");
}

int main() {
#if defined(_WIN32)
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
    sock_t ls = start_server();
    std::thread server(server_loop, ls);

    test_handle_table();
    test_lifecycle();
    test_get();
    test_methods();
    test_files_and_redirects();
    test_async();
    test_failures();
    test_teardown();

    g_stop = true;
    /* Wake the accept() with one last connection, then close. */
    sock_t k = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in a;
    std::memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = htons(static_cast<unsigned short>(g_port));
    connect(k, reinterpret_cast<sockaddr *>(&a), sizeof a);
    CLOSESOCK(k);
    server.join();
    CLOSESOCK(ls);

    std::printf("curl_smoke_test: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
