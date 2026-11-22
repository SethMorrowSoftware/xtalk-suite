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
 *   - the exception firewall turns a throw into an error return;
 *   - WebSockets (ABI 2), against a WebSocket server this test also runs:
 *     the upgrade and its headers, text, binary and empty messages both
 *     ways, 16-bit and 64-bit frame lengths, fragments reassembled around
 *     an interleaved ping, ping and pong, order, both directions of the
 *     close handshake with code and reason, a dropped connection, a peer
 *     that never answers a close, a peer that never reads, the message
 *     size limit, a refused upgrade, cancel, the read high-water mark, and
 *     that cux_poll never lists a socket; the bounds control frames have of
 *     their own: a peer that pings without reading cannot grow the send
 *     queue, and one that sends control frames without pause cannot hold
 *     one pump; and that cux_ws_wait, with a message already waiting, moves
 *     the socket once before it answers, so a loop waiting for the close
 *     with the message unread ends.
 */

#include "cux_abi.h"
#include "cux_handle_table.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
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

/* The loopback SERVER must not die of SIGPIPE when it writes to a client the
   library already dropped (a cancelled socket, a refused upgrade): macOS
   raised it on the first run of the WebSocket tests (2026-11-20). Asked for
   per socket and per send, never by ignoring the signal process-wide: a
   SIGPIPE out of the LIBRARY must still kill this test. */
#if defined(MSG_NOSIGNAL)
#  define SRV_SEND_FLAGS MSG_NOSIGNAL
#else
#  define SRV_SEND_FLAGS 0
#endif
static void srv_no_sigpipe(sock_t c) {
#if defined(SO_NOSIGPIPE)
    int one = 1;
    setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#else
    (void)c;
#endif
}

static int g_fail = 0;
static int g_pass = 0;

#define CHECK(cond, what) do {                                              \
    if (cond) { ++g_pass; }                                                 \
    else { ++g_fail; std::fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, what); } \
} while (0)

/* ------------------------------------------------------- the test server */

static std::atomic<bool> g_stop(false);
static std::atomic<bool> g_unmasked(false);   /* the server saw an unmasked client frame */
static std::atomic<bool> g_flood_read(false);  /* /ws/pingflood may start reading */
static int g_port = 0;
static int g_port_small = 0;   /* the same routes, on a 16 KB receive buffer */

/* The pings /ws/pingflood sends: 25 MB of them, far more than the client's
 * send buffer and the small-buffer listener's receive buffer hold, so a
 * client that answered every one would have to queue most of its answers. */
static const int kFloodPings = 200000;

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
        send(c, cont, static_cast<int>(std::strlen(cont)), SRV_SEND_FLAGS);
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
    send(c, r.data(), static_cast<int>(r.size()), SRV_SEND_FLAGS);
}

static std::string header_value(const std::string &head, const std::string &name) {
    size_t p = head.find("\r\n" + name + ": ");
    if (p == std::string::npos) return "";
    p += name.size() + 4;
    size_t e = head.find("\r\n", p);
    return head.substr(p, e == std::string::npos ? std::string::npos : e - p);
}

/* ------------------------------------------- the WebSocket side of it */

/* SHA-1 and base64, for the one thing the upgrade needs them for: the
 * Sec-WebSocket-Accept answer (RFC 6455 section 4.2.2). */
static std::string sha1(const std::string &in) {
    uint32_t h[5] = {0x67452301u, 0xEFCDAB89u, 0x98BADCFEu, 0x10325476u, 0xC3D2E1F0u};
    std::string m = in;
    uint64_t bits = static_cast<uint64_t>(in.size()) * 8u;
    m.push_back(static_cast<char>(0x80));
    while (m.size() % 64 != 56) m.push_back('\0');
    for (int i = 7; i >= 0; --i) m.push_back(static_cast<char>((bits >> (i * 8)) & 0xFF));
    for (size_t off = 0; off < m.size(); off += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; ++i) {
            const unsigned char *p = reinterpret_cast<const unsigned char *>(m.data()) + off + i * 4;
            w[i] = (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
                   (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
        }
        for (int i = 16; i < 80; ++i) {
            uint32_t x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
            w[i] = (x << 1) | (x >> 31);
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; ++i) {
            uint32_t f, k;
            if (i < 20) { f = (b & c) | (~b & d); k = 0x5A827999u; }
            else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1u; }
            else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDCu; }
            else { f = b ^ c ^ d; k = 0xCA62C1D6u; }
            uint32_t t = ((a << 5) | (a >> 27)) + f + e + k + w[i];
            e = d; d = c; c = (b << 30) | (b >> 2); b = a; a = t;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
    }
    std::string out;
    for (uint32_t v : h)
        for (int i = 3; i >= 0; --i) out.push_back(static_cast<char>((v >> (i * 8)) & 0xFF));
    return out;
}

static std::string base64(const std::string &in) {
    static const char tbl[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    size_t i = 0;
    for (; i + 2 < in.size(); i += 3) {
        uint32_t v = (static_cast<unsigned char>(in[i]) << 16) | (static_cast<unsigned char>(in[i + 1]) << 8) |
                     static_cast<unsigned char>(in[i + 2]);
        out.push_back(tbl[(v >> 18) & 63]); out.push_back(tbl[(v >> 12) & 63]);
        out.push_back(tbl[(v >> 6) & 63]); out.push_back(tbl[v & 63]);
    }
    if (i + 1 == in.size()) {
        uint32_t v = static_cast<unsigned char>(in[i]) << 16;
        out.push_back(tbl[(v >> 18) & 63]); out.push_back(tbl[(v >> 12) & 63]);
        out += "==";
    } else if (i + 2 == in.size()) {
        uint32_t v = (static_cast<unsigned char>(in[i]) << 16) | (static_cast<unsigned char>(in[i + 1]) << 8);
        out.push_back(tbl[(v >> 18) & 63]); out.push_back(tbl[(v >> 12) & 63]);
        out.push_back(tbl[(v >> 6) & 63]); out.push_back('=');
    }
    return out;
}

static bool send_all(sock_t c, const std::string &s) {
    size_t off = 0;
    while (off < s.size()) {
        int n = static_cast<int>(send(c, s.data() + off, static_cast<int>(std::min<size_t>(s.size() - off, 65536)), SRV_SEND_FLAGS));
        if (n <= 0) return false;
        off += static_cast<size_t>(n);
    }
    return true;
}

static bool recv_all(sock_t c, std::string &pending, size_t want, std::string &out) {
    char tmp[16384];
    while (pending.size() < want) {
        int n = static_cast<int>(recv(c, tmp, sizeof tmp, 0));
        if (n <= 0) return false;
        pending.append(tmp, static_cast<size_t>(n));
    }
    out = pending.substr(0, want);
    pending.erase(0, want);
    return true;
}

/* One server-to-client frame (never masked). first: FIN bit and opcode. */
static bool ws_frame(sock_t c, int first, const std::string &payload) {
    std::string f;
    f.push_back(static_cast<char>(first));
    if (payload.size() < 126) f.push_back(static_cast<char>(payload.size()));
    else if (payload.size() < 65536) {
        f.push_back(126);
        f.push_back(static_cast<char>(payload.size() >> 8));
        f.push_back(static_cast<char>(payload.size() & 0xFF));
    } else {
        f.push_back(127);
        for (int i = 7; i >= 0; --i)
            f.push_back(static_cast<char>((static_cast<uint64_t>(payload.size()) >> (i * 8)) & 0xFF));
    }
    f += payload;
    return send_all(c, f);
}

static std::string close_payload(int code, const char *reason) {
    std::string p;
    p.push_back(static_cast<char>(code >> 8));
    p.push_back(static_cast<char>(code & 0xFF));
    return p + reason;
}

/* One client-to-server frame (always masked). */
static bool ws_read_frame(sock_t c, std::string &pending, int &first, std::string &payload) {
    std::string b;
    if (!recv_all(c, pending, 2, b)) return false;
    first = static_cast<unsigned char>(b[0]);
    bool masked = (static_cast<unsigned char>(b[1]) & 0x80) != 0;
    uint64_t len = static_cast<unsigned char>(b[1]) & 0x7F;
    if (len == 126) {
        if (!recv_all(c, pending, 2, b)) return false;
        len = (static_cast<uint64_t>(static_cast<unsigned char>(b[0])) << 8) | static_cast<unsigned char>(b[1]);
    } else if (len == 127) {
        if (!recv_all(c, pending, 8, b)) return false;
        len = 0;
        for (int i = 0; i < 8; ++i) len = (len << 8) | static_cast<unsigned char>(b[static_cast<size_t>(i)]);
    }
    std::string mask;
    if (masked && !recv_all(c, pending, 4, mask)) return false;
    if (!recv_all(c, pending, static_cast<size_t>(len), payload)) return false;
    if (masked)
        for (size_t i = 0; i < payload.size(); ++i) payload[i] = static_cast<char>(payload[i] ^ mask[i % 4]);
    else g_unmasked = true;   /* a client frame MUST be masked */
    return true;
}

static std::string big_payload(size_t n) {
    std::string s(n, '\0');
    for (size_t i = 0; i < n; ++i) s[i] = static_cast<char>((i * 31u + 7u) & 0xFF);
    return s;
}

/* The WebSocket routes.
 *   /ws-refuse   answers the upgrade with a plain 200
 *   /ws/hang     never answers the upgrade
 *   /ws/mute     upgrades, then neither reads nor writes
 *   /ws/pingflood  sends kFloodPings pings and "pings done", reads nothing
 *                until the test sets g_flood_read, then reads and counts
 *                the pongs; "!count" asks how many arrived and which ping
 *                the last one answered (asked of the small-buffer listener,
 *                g_port_small)
 *   /ws/echo     echoes every message; a text message starting with '!' is
 *                a command that makes the server do something a client
 *                cannot otherwise provoke (fragments, a close, a drop ...) */
static void serve_ws(sock_t c, const std::string &path, const std::string &head, std::string pending) {
    if (path == "/ws-refuse") { respond(c, 200, "", "no socket here"); return; }
    if (path == "/ws/hang") {
        for (int i = 0; i < 60 && !g_stop; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
        return;
    }
    std::string accept = base64(sha1(header_value(head, "Sec-WebSocket-Key") + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));
    std::string proto = header_value(head, "Sec-WebSocket-Protocol");
    std::string up = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                     "Sec-WebSocket-Accept: " + accept + "\r\n";
    if (!proto.empty()) up += "Sec-WebSocket-Protocol: " + proto + "\r\n";
    up += "X-Ws-Served: yes\r\n\r\n";
    if (!send_all(c, up)) return;
    if (path == "/ws/mute") {
        while (!g_stop) std::this_thread::sleep_for(std::chrono::milliseconds(20));
        return;
    }
    if (path == "/ws/pingflood") {
        /* each payload is the ping's number, padded to the 125 bytes a
         * control frame allows */
        for (int i = 0; i < kFloodPings; ++i) {
            std::string id = std::to_string(i);
            id.resize(125, '.');
            if (!ws_frame(c, 0x89, id)) return;
        }
        if (!ws_frame(c, 0x81, "pings done")) return;
        /* The kernel can hold the whole flood on its way out, so this end
         * is done long before the client has read it. Reading nothing
         * until the client has looked at its queue takes a flag, not a
         * frame: a frame from the client would wait behind its pongs. */
        while (!g_flood_read && !g_stop) std::this_thread::sleep_for(std::chrono::milliseconds(5));
        long long pongs = 0;
        std::string last = "none";
        for (;;) {
            int first = 0;
            std::string p;
            if (!ws_read_frame(c, pending, first, p)) return;
            int op = first & 0x0F;
            if (op == 0x8) { ws_frame(c, 0x88, p); return; }
            if (op == 0xA) { ++pongs; last = p.substr(0, p.find('.')); continue; }
            if (op == 0x1 && p == "!count")
                ws_frame(c, 0x81, "pongs:" + std::to_string(pongs) + " last:" + last);
        }
    }
    for (;;) {
        int first = 0;
        std::string p;
        if (!ws_read_frame(c, pending, first, p)) return;
        int op = first & 0x0F;
        if (op == 0x8) { ws_frame(c, 0x88, p); return; }            /* close: echo it */
        if (op == 0x9) { ws_frame(c, 0x8A, p); continue; }          /* ping: pong     */
        if (op == 0xA) { ws_frame(c, 0x81, "pong:" + p); continue; }  /* pong: report */
        if (op == 0x1 && !p.empty() && p[0] == '!') {
            if (p == "!frag") {
                /* "abcdef" in three frames, with a ping between two of them */
                ws_frame(c, 0x01, "ab");
                ws_frame(c, 0x89, "mid");
                ws_frame(c, 0x00, "cd");
                ws_frame(c, 0x80, "ef");
            } else if (p == "!ping") ws_frame(c, 0x89, "hi");
            else if (p == "!close") { ws_frame(c, 0x81, "last words"); ws_frame(c, 0x88, close_payload(4001, "bye")); return; }
            else if (p == "!close-empty") { ws_frame(c, 0x88, ""); return; }
            else if (p == "!close-later") {
                /* a message, then the close once the client says "!go": the
                 * client sees the message waiting with the socket still open
                 * however slowly it runs, and the "!go" leaves it only if
                 * something pumps */
                ws_frame(c, 0x81, "last words");
                for (;;) {
                    int f2 = 0;
                    std::string q;
                    if (!ws_read_frame(c, pending, f2, q)) return;
                    if ((f2 & 0x0F) == 0x1 && q == "!go") break;
                }
                ws_frame(c, 0x88, close_payload(4001, "bye"));
                return;
            }
            else if (p == "!drop") return;
            else if (p == "!big") ws_frame(c, 0x82, big_payload(200000));
            else if (p == "!empty") ws_frame(c, 0x81, "");
            else if (p == "!header") ws_frame(c, 0x81, header_value(head, "X-Test") + "|" + proto);
            else if (p == "!burst") { for (int i = 0; i < 5; ++i) ws_frame(c, 0x81, "m" + std::to_string(i)); }
            else if (p == "!pongs") {
                /* 5000 unsolicited empty pongs in ONE write, then a message */
                std::string burst;
                for (int i = 0; i < 5000; ++i) { burst.push_back(static_cast<char>(0x8A)); burst.push_back('\0'); }
                if (!send_all(c, burst)) return;
                ws_frame(c, 0x81, "pongs done");
            }
            else if (p == "!flood") {
                /* 8 MiB in 64 KiB messages: twice the shim's high-water mark */
                std::string chunk(65536, 'f');
                for (int i = 0; i < 128; ++i) if (!ws_frame(c, 0x82, chunk)) return;
                ws_frame(c, 0x81, "flood done");
            }
            continue;
        }
        ws_frame(c, 0x80 | op, p);
    }
}

static void serve_one(sock_t c) {
    std::string head, body;
    if (!read_request(c, head, body)) { CLOSESOCK(c); return; }
    std::string line = head.substr(0, head.find("\r\n"));
    std::string method = line.substr(0, line.find(' '));
    std::string path = line.substr(line.find(' ') + 1);
    path = path.substr(0, path.find(' '));
    if (path.compare(0, 3, "/ws") == 0) { serve_ws(c, path, head, body); CLOSESOCK(c); return; }
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
        srv_no_sigpipe(c);
        workers.emplace_back(serve_one, c);
    }
    for (std::thread &t : workers) t.join();
}

/* rcvbuf > 0 sets the listener's receive buffer BEFORE listen(), so every
 * connection it accepts starts with that window. Left alone, Linux grows a
 * receive buffer to tcp_rmem's limit (32 MB on some machines), and
 * shrinking an established connection's buffer instead stalled TCP for
 * minutes when it was tried here. */
static sock_t start_server(int &port, int rcvbuf = 0) {
    sock_t ls = socket(AF_INET, SOCK_STREAM, 0);
    if (rcvbuf > 0)
        setsockopt(ls, SOL_SOCKET, SO_RCVBUF, reinterpret_cast<const char *>(&rcvbuf), sizeof rcvbuf);
    sockaddr_in a;
    std::memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = 0;
    bind(ls, reinterpret_cast<sockaddr *>(&a), sizeof a);
    listen(ls, 16);
    socklen_t al = sizeof a;
    getsockname(ls, reinterpret_cast<sockaddr *>(&a), &al);
    port = ntohs(a.sin_port);
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
#elif defined(__ANDROID__)
    /* Android has no /tmp. The suite's tools/android-run.sh runs the test
     * with TMPDIR at its own folder under /data/local/tmp, the one place
     * the shell user may write. */
    const char *d = std::getenv("TMPDIR");
    return std::string(d ? d : "/data/local/tmp") + "/" + name;
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
    CHECK(cux_ws_new("ws://127.0.0.1/") == 0 && cux_ws_poll() == CUX_ERR_NOT_INIT, "WebSockets refused before init");
    CHECK(cux_poll(nullptr, 0) == CUX_ERR_NOT_INIT, "poll refused before init");
    CHECK(cux_init() == 1, "first init");
    CHECK(cux_init() == 2, "second init counts");
    CHECK(cux_cleanup() == 1, "release one hold");
    char v[512];
    int n = cux_version_string(v, sizeof v);
    CHECK(n > 0 && std::strstr(v, "libcurl/8.22.0") != nullptr, "version names the pinned libcurl");
    CHECK(std::strstr(v, "libssh2") != nullptr, "version names libssh2 (SFTP)");
    CHECK(cux_version_string(v, 3) < 0, "too-small buffer asks for more");
#if defined(__ANDROID__)
    {
        /* The default CA store (apply_default_ca in the shim): on Android
         * it is read out of the system's certificate folder, and the count
         * the version string reports is the one thing about it this test
         * can see without a TLS server. None read means every verified
         * HTTPS transfer on this device would fail. */
        CHECK(cux_version_string(v, sizeof v) > 0, "version string, read again");
        const char *at = std::strstr(v, "Android CA store: ");
        CHECK(at != nullptr, "version names the Android CA store");
        int count = at ? std::atoi(at + std::strlen("Android CA store: ")) : 0;
        std::printf("  Android CA store: %d certificates\n", count);
        CHECK(count > 0, "the Android system CA store was read (at least one certificate)");
    }
#else
    CHECK(std::strstr(v, "Android CA store") == nullptr, "no Android text in a desktop version string");
#endif
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

    /* The cap holds for a download to a file too (tsNet's max_file_size
     * maps to it; a file can fill a disk). */
    h = cux_request_new("GET", url("/big").c_str());
    cux_set_text(h, CUO_OUTPUT_FILE, out.c_str());
    cux_set_int(h, CUO_MAX_BODY_BYTES, 1000);
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) == 23, "body cap ends a file download");
    CHECK(text(h, CUT_ERROR).find("larger than the limit") != std::string::npos, "file cap says why");
    CHECK(read_file(out).size() <= 1000, "the file stops at the cap");
    cux_free(h);
    std::remove(out.c_str());

#ifdef __linux__
    /* A write the final fclose loses (here /dev/full, which takes nothing)
     * is a write error, never a success over a short file. */
    h = cux_request_new("GET", url("/hello").c_str());
    cux_set_text(h, CUO_OUTPUT_FILE, "/dev/full");
    CHECK(run_sync(h) == 1 && cux_info(h, CUI_RESULT) == 23, "a lost final write is CURLE_WRITE_ERROR");
    CHECK(text(h, CUT_ERROR).find("output file") != std::string::npos, "and says so");
    cux_free(h);
#endif
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

/* ------------------------------------------------------- WebSocket tests */

static std::string ws_url(const char *path, int port = 0) {
    return "ws://127.0.0.1:" + std::to_string(port ? port : g_port) + path;
}

static int ws_open(const char *path, int port = 0) {
    int h = cux_ws_new(ws_url(path, port).c_str());
    if (h <= 0) return 0;
    if (cux_start(h) != CUX_OK) return 0;
    if (cux_ws_wait(h, 10000) != 1) return 0;
    return cux_info(h, CUI_WS_STATE) == CUX_WS_OPEN ? h : 0;
}

static int ws_text(int h, const char *s) {
    return cux_ws_send(h, CUX_WS_KIND_TEXT, s, static_cast<int>(std::strlen(s)));
}

/* Wait for the next message and take it; kind comes back through *kind.
 * "<none>" when nothing arrived in time. */
static std::string ws_next(int h, int *kind = nullptr, int timeout_ms = 10000) {
    auto t0 = std::chrono::steady_clock::now();
    while (cux_info(h, CUI_WS_MESSAGES) < 1) {
        if (cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED) return "<none>";
        if (std::chrono::steady_clock::now() - t0 > std::chrono::milliseconds(timeout_ms)) return "<none>";
        cux_ws_wait(h, 100);
    }
    if (kind) *kind = static_cast<int>(cux_info(h, CUI_WS_NEXT_TYPE));
    int size = static_cast<int>(cux_info(h, CUI_WS_NEXT_SIZE));
    std::vector<char> b(static_cast<size_t>(size) + 1);
    int n = cux_ws_read(h, b.data(), size);
    return n >= 0 ? std::string(b.data(), static_cast<size_t>(n)) : "<error>";
}

static bool ws_until_closed(int h, int timeout_ms = 10000) {
    auto t0 = std::chrono::steady_clock::now();
    while (cux_info(h, CUI_WS_STATE) != CUX_WS_CLOSED) {
        if (std::chrono::steady_clock::now() - t0 > std::chrono::milliseconds(timeout_ms)) return false;
        cux_ws_poll();
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    return true;
}

static void test_ws_open_and_messages() {
    CHECK(cux_ws_new("http://127.0.0.1/") == 0, "a WebSocket URL must be ws:// or wss://");
    char e[160];
    CHECK(cux_last_error(e, sizeof e) > 0 && std::strstr(e, "ws://") != nullptr, "and the refusal says so");
    CHECK(cux_ws_new("") == 0, "empty WebSocket URL refused");

    int h = cux_ws_new(ws_url("/ws/echo").c_str());
    CHECK(h > 0, "ws new");
    CHECK(cux_info(h, CUI_WS_STATE) == 0 && cux_info(h, CUI_STATE) == CUX_STATE_NEW, "not started yet");
    CHECK(cux_ws_wait(h, 10) == CUX_ERR_STATE, "ws wait before start refused");
    CHECK(ws_text(h, "early") == CUX_ERR_STATE, "send before start refused");
    CHECK(cux_set_body(h, "x", 1) == CUX_ERR_STATE, "a WebSocket takes no request body");
    CHECK(cux_set_header(h, "X-Test: carried") == CUX_OK, "the ordinary header setter works on it");
    CHECK(cux_set_header(h, "Sec-WebSocket-Protocol: chat.v1") == CUX_OK, "a subprotocol is a header");
    CHECK(cux_set_int(h, CUO_CONNECT_TIMEOUT_MS, 5000) == CUX_OK, "the ordinary option setter works on it");
    CHECK(cux_start(h) == CUX_OK, "ws start");
    CHECK(cux_info(h, CUI_WS_STATE) == CUX_WS_CONNECTING, "connecting");
    CHECK(ws_text(h, "early") == CUX_ERR_STATE, "send while connecting refused");
    CHECK(cux_wait(h, 10) == CUX_ERR_STATE, "cux_wait refuses a WebSocket");
    CHECK(cux_ws_wait(h, 10000) == 1, "ws wait returns when it opens");
    CHECK(cux_info(h, CUI_WS_STATE) == CUX_WS_OPEN, "open");
    CHECK(cux_info(h, CUI_STATE) == CUX_STATE_RUNNING, "an open socket is a running request");
    CHECK(cux_info(h, CUI_RESPONSE_CODE) == 101, "the upgrade answered 101");
    CHECK(text(h, CUT_HEADERS).find("X-Ws-Served: yes") != std::string::npos, "the upgrade's response headers");
    CHECK(text(h, CUT_HEADERS).find("Sec-WebSocket-Protocol: chat.v1") != std::string::npos, "the subprotocol agreed");
    CHECK(cux_set_header(h, "X-Late: 1") == CUX_ERR_STATE, "setters refuse after start");
    char buf[64];
    CHECK(cux_poll(buf, sizeof buf) == 0, "cux_poll never lists a WebSocket");
    CHECK(cux_ws_read(h, buf, sizeof buf) == CUX_ERR_STATE, "read with nothing waiting");
    CHECK(cux_ws_wait(h, 60) == 0, "ws wait times out when nothing happens");

    int kind = 0;
    CHECK(ws_text(h, "hello") == CUX_OK, "send text");
    CHECK(ws_next(h, &kind) == "hello" && kind == CUX_WS_KIND_TEXT, "text echoes as text");
    const char bin[] = {'a', '\0', 'b', '\xff'};
    CHECK(cux_ws_send(h, CUX_WS_KIND_BINARY, bin, 4) == CUX_OK, "send binary");
    CHECK(ws_next(h, &kind) == std::string(bin, 4) && kind == CUX_WS_KIND_BINARY, "binary echoes binary-safe");
    CHECK(cux_ws_send(h, CUX_WS_KIND_TEXT, nullptr, 0) == CUX_OK, "send an empty message");
    CHECK(ws_next(h, &kind) == "" && kind == CUX_WS_KIND_TEXT, "an empty message arrives, and is a message");
    CHECK(cux_info(h, CUI_WS_MESSAGES) == 0, "and reading it took it");

    /* frame lengths: 125 and 126 (the 7-bit / 16-bit edge), 65535 and 65536
     * (the 16-bit / 64-bit edge), and well past it */
    for (size_t n : {size_t(125), size_t(126), size_t(65535), size_t(65536), size_t(300000)}) {
        std::string big = big_payload(n);
        CHECK(cux_ws_send(h, CUX_WS_KIND_BINARY, big.data(), static_cast<int>(n)) == CUX_OK, "send a sized message");
        CHECK(ws_next(h, &kind) == big, "a sized message round trips");
    }
    CHECK(ws_text(h, "!big") == CUX_OK && ws_next(h, &kind) == big_payload(200000) && kind == CUX_WS_KIND_BINARY,
          "a 64-bit-length frame from the server");
    CHECK(ws_text(h, "!empty") == CUX_OK && ws_next(h, &kind) == "", "an empty message from the server");
    CHECK(ws_text(h, "!header") == CUX_OK && ws_next(h) == "carried|chat.v1", "request headers reached the server");

    /* the too-small read contract: nothing is taken */
    ws_text(h, "twelve bytes");
    while (cux_info(h, CUI_WS_MESSAGES) < 1) cux_ws_wait(h, 100);
    CHECK(cux_info(h, CUI_WS_NEXT_SIZE) == 12 && cux_info(h, CUI_WS_NEXT_TYPE) == CUX_WS_KIND_TEXT, "next size and type");
    CHECK(cux_ws_read(h, buf, 5) == -12, "a too-small read asks for more");
    CHECK(cux_info(h, CUI_WS_MESSAGES) == 1, "and takes nothing");
    CHECK(cux_ws_read(h, buf, sizeof buf) == 12 && std::memcmp(buf, "twelve bytes", 12) == 0, "then reads");

    /* fragments are one message, whatever arrives between them */
    CHECK(ws_text(h, "!frag") == CUX_OK && ws_next(h, &kind) == "abcdef" && kind == CUX_WS_KIND_TEXT,
          "three fragments and an interleaved ping arrive as one message");
    /* the ping in the middle of that was answered by libcurl: the server
     * reports every pong it receives as a text message */
    CHECK(ws_next(h) == "pong:mid", "a ping from the server is answered with its payload");
    CHECK(ws_text(h, "!ping") == CUX_OK && ws_next(h) == "pong:hi", "and again outside a fragmented message");

    CHECK(cux_info(h, CUI_WS_PONGS) == 0, "no pong received yet");
    CHECK(cux_ws_send(h, CUX_WS_KIND_PING, "p1", 2) == CUX_OK, "send a ping");
    ws_text(h, "after-ping");
    CHECK(ws_next(h) == "after-ping" && cux_info(h, CUI_WS_PONGS) == 1, "the server's pong is counted, not queued");
    CHECK(cux_ws_send(h, CUX_WS_KIND_PONG, "u", 1) == CUX_OK && ws_next(h) == "pong:u", "an unsolicited pong can be sent");
    std::string long_ping(126, 'p');
    CHECK(cux_ws_send(h, CUX_WS_KIND_PING, long_ping.data(), 126) == CUX_ERR_ARG, "a ping above 125 bytes refused");
    CHECK(cux_ws_send(h, 9, "x", 1) == CUX_ERR_ARG, "unknown kind refused");
    CHECK(cux_ws_send(h, CUX_WS_KIND_TEXT, nullptr, 3) == CUX_ERR_ARG, "null bytes with a length refused");

    /* order, and cux_ws_poll's count */
    ws_text(h, "!burst");
    int waiting = 0;
    for (int i = 0; i < 400 && waiting < 5; ++i) {
        waiting = cux_ws_poll();
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    CHECK(waiting == 5 && cux_info(h, CUI_WS_MESSAGES) == 5, "cux_ws_poll counts the waiting messages");
    bool ordered = true;
    for (int i = 0; i < 5; ++i) ordered = ordered && ws_next(h) == "m" + std::to_string(i);
    CHECK(ordered, "messages are read in the order they were sent");
    CHECK(cux_info(h, CUI_WS_QUEUED_BYTES) == 0, "nothing left queued for sending");

    /* a second socket at the same time, and an ordinary request beside both */
    int h2 = ws_open("/ws/echo");
    CHECK(h2 > 0 && h2 != h, "a second socket");
    ws_text(h, "to-one");
    ws_text(h2, "to-two");
    int g = cux_request_new("GET", url("/hello").c_str());
    CHECK(run_sync(g) == 1 && body(g) == "hello world", "an ordinary request runs beside open sockets");
    cux_free(g);
    CHECK(ws_next(h2) == "to-two" && ws_next(h) == "to-one", "each socket gets its own messages");
    g = cux_request_new("GET", url("/hello").c_str());
    cux_start(g);
    int n = 0;
    for (int i = 0; i < 400 && n == 0; ++i) {
        n = cux_poll(buf, sizeof buf);
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    CHECK(n > 0 && std::atoi(buf) == g, "cux_poll still lists the request, and only it");
    cux_free(g);
    CHECK(cux_free(h2) == CUX_OK && cux_info(h2, CUI_WS_STATE) == -1.0, "freeing an open socket drops it");

    /* the polite close, from this side */
    CHECK(cux_ws_close(h, 1005, "") == CUX_ERR_ARG, "a reserved close code refused");
    CHECK(cux_ws_close(h, 1000, "done") == CUX_OK, "close");
    CHECK(cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSING, "closing");
    CHECK(ws_text(h, "late") == CUX_ERR_STATE, "send after close refused");
    CHECK(cux_ws_close(h, 1000, "again") == CUX_OK, "close twice is a no-op");
    CHECK(cux_ws_wait(h, 10000) == 1 && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED, "the peer's close ends it");
    CHECK(cux_info(h, CUI_WS_CLOSE_CODE) == 1000 && text(h, CUT_WS_CLOSE_REASON) == "done", "close code and reason");
    CHECK(cux_info(h, CUI_STATE) == CUX_STATE_DONE && cux_info(h, CUI_RESULT) == 0, "a clean close is result 0");
    CHECK(text(h, CUT_ERROR).empty(), "and no error text");
    CHECK(cux_ws_wait(h, 10) == 1, "ws wait on a closed socket returns at once");
    CHECK(cux_poll(buf, sizeof buf) == 0, "a closed socket is not listed by cux_poll either");
    CHECK(cux_ws_close(h, 1000, "") == CUX_OK && cux_cancel(h) == CUX_OK, "close and cancel after the end are no-ops");
    CHECK(cux_free(h) == CUX_OK, "free");
    CHECK(cux_ws_send(h, CUX_WS_KIND_TEXT, "x", 1) == CUX_ERR_STALE && cux_ws_close(h, 1000, "") == CUX_ERR_STALE &&
          cux_ws_read(h, buf, 4) == CUX_ERR_STALE && cux_ws_wait(h, 1) == CUX_ERR_STALE, "stale socket calls are no-ops");

    g = cux_request_new("GET", url("/hello").c_str());
    CHECK(cux_ws_send(g, CUX_WS_KIND_TEXT, "x", 1) == CUX_ERR_STATE && cux_ws_close(g, 1000, "") == CUX_ERR_STATE &&
          cux_ws_read(g, buf, 4) == CUX_ERR_STATE && cux_ws_wait(g, 1) == CUX_ERR_STATE,
          "an ordinary request refuses the WebSocket calls");
    CHECK(cux_info(g, CUI_WS_STATE) == 0, "and its wsState is 0");
    cux_free(g);
}

static void test_ws_endings() {
    char buf[64];
    /* the server closes, after one last message */
    int h = ws_open("/ws/echo");
    CHECK(h > 0, "open for the server's close");
    ws_text(h, "!close");
    CHECK(ws_until_closed(h), "the server's close ends it");
    CHECK(cux_info(h, CUI_WS_CLOSE_CODE) == 4001 && text(h, CUT_WS_CLOSE_REASON) == "bye", "the server's code and reason");
    CHECK(cux_info(h, CUI_RESULT) == 0, "a close from the peer is result 0");
    CHECK(cux_info(h, CUI_WS_MESSAGES) == 1 && ws_next(h) == "last words", "what arrived before the close is still readable");
    CHECK(ws_next(h, nullptr, 50) == "<none>", "and then nothing");
    cux_free(h);

    h = ws_open("/ws/echo");
    ws_text(h, "!close-empty");
    CHECK(ws_until_closed(h) && cux_info(h, CUI_WS_CLOSE_CODE) == CUX_WS_CODE_NO_STATUS, "a close with no code is 1005");
    cux_free(h);

    /* A cux_ws_wait loop that waits for the close with a message unread still
     * ends: the wait moves the socket once before it answers for a waiting
     * message. Before 2026-11-21 it answered without moving anything, and
     * this loop spun until its deadline. The server closes only after the
     * "!go" sent here, so the first check never races the close. */
    h = ws_open("/ws/echo");
    ws_text(h, "!close-later");
    CHECK(cux_ws_wait(h, 10000) == 1 && cux_info(h, CUI_WS_MESSAGES) == 1 &&
              cux_info(h, CUI_WS_STATE) == CUX_WS_OPEN,
          "a message waits, unread, the socket still open");
    ws_text(h, "!go");
    auto tw = std::chrono::steady_clock::now();
    while (cux_info(h, CUI_WS_STATE) != CUX_WS_CLOSED &&
           std::chrono::steady_clock::now() - tw < std::chrono::seconds(5))
        cux_ws_wait(h, 100);
    CHECK(cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED && cux_info(h, CUI_WS_MESSAGES) == 1,
          "a cux_ws_wait loop waiting for the close ends, the message still unread");
    CHECK(ws_next(h) == "last words" && cux_info(h, CUI_WS_CLOSE_CODE) == 4001, "and the message and the close are both there");
    cux_free(h);

    /* the server just hangs up */
    h = ws_open("/ws/echo");
    ws_text(h, "!drop");
    CHECK(ws_until_closed(h), "a dropped connection ends it");
    CHECK(cux_info(h, CUI_WS_CLOSE_CODE) == CUX_WS_CODE_ABNORMAL, "with close code 1006");
    CHECK(cux_info(h, CUI_RESULT) > 0 && !text(h, CUT_ERROR).empty(), "and a curl error that says why");
    cux_free(h);

    /* a peer that never answers our close */
    h = cux_ws_new(ws_url("/ws/mute").c_str());
    CHECK(cux_set_int(h, CUO_WS_CLOSE_TIMEOUT_MS, 150) == CUX_OK, "wsCloseTimeout");
    CHECK(cux_set_int(h, CUO_WS_CLOSE_TIMEOUT_MS, -1) == CUX_ERR_ARG, "a negative one refused");
    cux_start(h);
    CHECK(cux_ws_wait(h, 10000) == 1 && cux_info(h, CUI_WS_STATE) == CUX_WS_OPEN, "mute server opens");
    auto t0 = std::chrono::steady_clock::now();
    cux_ws_close(h, 1000, "");
    CHECK(cux_ws_wait(h, 5000) == 1 && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED, "the close timeout ends the wait");
    long long took = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    CHECK(took >= 100 && took < 4000, "after about the time set");
    CHECK(cux_info(h, CUI_WS_CLOSE_CODE) == CUX_WS_CODE_ABNORMAL && cux_info(h, CUI_RESULT) == 0,
          "an unanswered close is 1006, and not an error: the close was asked for");
    cux_free(h);

    /* a peer that never reads: the send queue refuses rather than grows */
    h = ws_open("/ws/mute");
    std::string mb(1024 * 1024, 'q');
    int accepted = 0;
    int rc = CUX_OK;
    for (; accepted < 200 && rc == CUX_OK; ++accepted)
        rc = cux_ws_send(h, CUX_WS_KIND_BINARY, mb.data(), static_cast<int>(mb.size()));
    CHECK(rc == CUX_ERR_STATE && accepted < 200, "a peer that never reads fills the send queue, which then refuses");
    CHECK(cux_info(h, CUI_WS_QUEUED_BYTES) > 0 && cux_info(h, CUI_WS_QUEUED_BYTES) <= 16.0 * 1024 * 1024,
          "wsQueuedBytes reports the backlog, within its bound");
    CHECK(cux_last_error(buf, sizeof buf) < 0 || std::strstr(buf, "not reading") != nullptr, "and the refusal says why");
    CHECK(cux_cancel(h) == CUX_OK && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED, "cancel drops an open socket");
    CHECK(cux_info(h, CUI_RESULT) == CUX_RESULT_CANCELLED && cux_info(h, CUI_WS_QUEUED_BYTES) == 0, "result 1000, backlog dropped");
    CHECK(cux_poll(buf, sizeof buf) == 0, "a cancelled socket is not listed by cux_poll");
    cux_free(h);

    /* the message size limit */
    h = cux_ws_new(ws_url("/ws/echo").c_str());
    cux_set_int(h, CUO_MAX_BODY_BYTES, 1000);
    cux_start(h);
    cux_ws_wait(h, 10000);
    ws_text(h, "small");
    CHECK(ws_next(h) == "small", "a message under the limit passes");
    ws_text(h, "!big");
    CHECK(ws_until_closed(h), "a message over the limit ends the socket");
    CHECK(cux_info(h, CUI_WS_CLOSE_CODE) == CUX_WS_CODE_TOO_BIG && cux_info(h, CUI_RESULT) == 23, "with 1009 and a write error");
    CHECK(text(h, CUT_ERROR).find("larger than the limit") != std::string::npos, "and says why");
    CHECK(cux_info(h, CUI_WS_MESSAGES) == 0, "no part of it is handed to script");
    cux_free(h);

    /* the upgrade refused, and nobody listening */
    h = cux_ws_new(ws_url("/ws-refuse").c_str());
    cux_start(h);
    CHECK(cux_ws_wait(h, 10000) == 1 && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED, "a refused upgrade ends it");
    CHECK(cux_info(h, CUI_RESULT) > 0 && cux_info(h, CUI_RESPONSE_CODE) == 200, "with a curl error and the server's status");
    CHECK(cux_info(h, CUI_WS_CLOSE_CODE) == 0 && !text(h, CUT_ERROR).empty(), "no close code: it never opened");
    CHECK(ws_text(h, "x") == CUX_ERR_STATE, "send on a socket that never opened refused");
    cux_free(h);
    h = cux_ws_new("ws://127.0.0.1:1/");
    cux_start(h);
    CHECK(cux_ws_wait(h, 10000) == 1 && cux_info(h, CUI_RESULT) == 7, "nobody listening is CURLE_COULDNT_CONNECT");
    cux_free(h);

    /* cancel and close while still connecting */
    h = cux_ws_new(ws_url("/ws/hang").c_str());
    cux_start(h);
    CHECK(cux_ws_wait(h, 80) == 0 && cux_info(h, CUI_WS_STATE) == CUX_WS_CONNECTING, "ws wait times out while connecting");
    CHECK(cux_cancel(h) == CUX_OK && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED && cux_info(h, CUI_RESULT) == CUX_RESULT_CANCELLED,
          "cancel while connecting");
    cux_free(h);
    h = cux_ws_new(ws_url("/ws/hang").c_str());
    cux_start(h);
    cux_ws_poll();
    CHECK(cux_ws_close(h, 1000, "") == CUX_OK && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED && cux_info(h, CUI_RESULT) == 0,
          "close while connecting just ends it");
    cux_free(h);
    h = cux_ws_new(ws_url("/ws/echo").c_str());
    CHECK(cux_ws_close(h, 1000, "") == CUX_OK && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED, "close before start");
    CHECK(cux_start(h) == CUX_ERR_STATE, "and it cannot be started after");
    cux_free(h);
    h = cux_ws_new(ws_url("/ws/echo").c_str());
    CHECK(cux_cancel(h) == CUX_OK && cux_info(h, CUI_WS_STATE) == CUX_WS_CLOSED, "cancel before start");
    CHECK(cux_poll(buf, sizeof buf) == 0, "not listed by cux_poll");
    cux_free(h);
    h = cux_ws_new(ws_url("/ws/hang").c_str());
    cux_set_int(h, CUO_TIMEOUT_MS, 150);
    cux_start(h);
    CHECK(cux_ws_wait(h, 10000) == 1 && cux_info(h, CUI_RESULT) == 28, "the request's own timeout bounds the upgrade");
    cux_free(h);
    /* and it bounds ONLY the upgrade: an open socket outlives it */
    h = cux_ws_new(ws_url("/ws/echo").c_str());
    cux_set_int(h, CUO_TIMEOUT_MS, 150);
    cux_start(h);
    CHECK(cux_ws_wait(h, 10000) == 1 && cux_info(h, CUI_WS_STATE) == CUX_WS_OPEN, "opens within its timeout");
    std::this_thread::sleep_for(std::chrono::milliseconds(400));
    cux_ws_poll();
    ws_text(h, "still here");
    CHECK(ws_next(h) == "still here" && cux_info(h, CUI_WS_STATE) == CUX_WS_OPEN, "an open socket outlives the timeout");
    cux_free(h);
}

/* A server that sends faster than script reads is slowed by TCP, not held
 * in memory: the shim stops reading the socket at its high-water mark. */
static void test_ws_backpressure() {
    int h = ws_open("/ws/echo");
    ws_text(h, "!flood");
    /* Pump without reading until the count has stood still for a while: on
     * a slow machine (an emulator, a sanitizer build) the flood takes its
     * time to arrive, and a fixed number of passes would measure the
     * machine, not the mark. */
    double count = 0;
    auto t0 = std::chrono::steady_clock::now();
    auto changed = t0;
    while (std::chrono::steady_clock::now() - t0 < std::chrono::seconds(20)) {
        cux_ws_poll();
        double now = cux_info(h, CUI_WS_MESSAGES);
        if (now != count) { count = now; changed = std::chrono::steady_clock::now(); }
        else if (count > 0 && std::chrono::steady_clock::now() - changed > std::chrono::milliseconds(500)) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(4));
    }
    double held = count * 65536.0;
    CHECK(count >= 32 && held <= 4.0 * 1024 * 1024 + 65536.0, "unread messages stop at the high-water mark");
    long long total = 0;
    std::string last;
    for (int i = 0; i < 200 && last != "flood done"; ++i) {
        last = ws_next(h);
        if (last == "<none>") break;
        if (last != "flood done") total += static_cast<long long>(last.size());
    }
    CHECK(last == "flood done" && total == 128LL * 65536, "and reading lets every byte of the rest through");
    cux_ws_close(h, 1000, "");
    CHECK(ws_until_closed(h), "closes after the flood");
    cux_free(h);
    CHECK(!g_unmasked, "every frame this client sent was masked");
}

/* Control frames have no message waiting for script to hold them back, so
 * they get bounds of their own. A peer that pings and never reads cannot
 * grow the send queue: one automatic pong waits behind the frame in
 * flight, and a later ping takes its place (RFC 6455 5.5.3 allows answering
 * only the most recent), so the last pong out answers the last ping. And a
 * peer that sends control frames without pause cannot hold one pump. */
static void test_ws_control_floods() {
    int h = ws_open("/ws/pingflood", g_port_small);
    CHECK(h > 0 && ws_next(h, nullptr, 120000) == "pings done", "a peer that pings and never reads: every ping arrives");
    CHECK(cux_info(h, CUI_WS_QUEUED_BYTES) <= 250.0, "the pongs waiting for the socket stay bounded (two at most)");
    CHECK(cux_info(h, CUI_WS_STATE) == CUX_WS_OPEN, "and the socket stays open");
    g_flood_read = true;
    ws_text(h, "!count");
    std::string tally = ws_next(h, nullptr, 60000);
    CHECK(tally.rfind("pongs:", 0) == 0 &&
              tally.find(" last:" + std::to_string(kFloodPings - 1)) != std::string::npos,
          "once the peer reads, the last pong it gets answers the last ping");
    cux_ws_close(h, 1000, "");
    CHECK(ws_until_closed(h), "and the socket closes cleanly");
    cux_free(h);

    h = ws_open("/ws/echo");
    ws_text(h, "!pongs");
    /* let the whole burst reach this end, then count what ONE pump takes */
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    double one = 0;
    auto t0 = std::chrono::steady_clock::now();
    while (one == 0 && std::chrono::steady_clock::now() - t0 < std::chrono::seconds(10)) {
        cux_ws_poll();
        one = cux_info(h, CUI_WS_PONGS);
        if (one == 0) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    CHECK(one >= 1 && one <= 1024, "one pump handles at most 1024 control frames");
    CHECK(ws_next(h) == "pongs done" && cux_info(h, CUI_WS_PONGS) == 5000,
          "the rest are handled by the pumps that follow, none lost");
    cux_ws_close(h, 1000, "");
    CHECK(ws_until_closed(h), "and that socket closes cleanly too");
    cux_free(h);
    CHECK(!g_unmasked, "every frame this client sent was masked");
}

static void test_teardown() {
    int h = cux_request_new("GET", url("/slow").c_str());
    cux_start(h);
    CHECK(cux_live_count() == 1, "one live request");
    int w = ws_open("/ws/echo");
    int w2 = cux_ws_new(ws_url("/ws/hang").c_str());
    cux_start(w2);
    cux_ws_poll();
    CHECK(w > 0 && cux_live_count() == 3, "an open socket and a connecting one are live too");
    CHECK(cux_cleanup() == 0, "last release");
    CHECK(cux_live_count() == 0, "the last release frees every request");
    CHECK(cux_info(h, CUI_STATE) == -1.0, "its handle is stale");
    CHECK(cux_info(w, CUI_WS_STATE) == -1.0 && cux_ws_poll() == CUX_ERR_NOT_INIT, "the sockets went with it");
    CHECK(cux_init() == 1 && cux_ws_poll() == 0, "and a new start has no socket left over");
    CHECK(cux_cleanup() == 0, "released again");
    CHECK(cux_cleanup() == 0, "extra release is a no-op");
}

int main() {
#if defined(_WIN32)
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
    sock_t ls = start_server(g_port);
    std::thread server(server_loop, ls);
    sock_t ls_small = start_server(g_port_small, 16384);
    std::thread server_small(server_loop, ls_small);

    test_handle_table();
    test_lifecycle();
    test_get();
    test_methods();
    test_files_and_redirects();
    test_async();
    test_failures();
    test_ws_open_and_messages();
    test_ws_endings();
    test_ws_backpressure();
    test_ws_control_floods();
    test_teardown();

    g_stop = true;
    /* Wake each accept() with one last connection, then close. */
    for (int port : {g_port, g_port_small}) {
        sock_t k = socket(AF_INET, SOCK_STREAM, 0);
        sockaddr_in a;
        std::memset(&a, 0, sizeof a);
        a.sin_family = AF_INET;
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        a.sin_port = htons(static_cast<unsigned short>(port));
        connect(k, reinterpret_cast<sockaddr *>(&a), sizeof a);
        CLOSESOCK(k);
    }
    server.join();
    server_small.join();
    CLOSESOCK(ls);
    CLOSESOCK(ls_small);

    std::printf("curl_smoke_test: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
