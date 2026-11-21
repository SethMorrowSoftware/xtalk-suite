#!/usr/bin/env python3
"""check-script-vectors.py - RUN curlxt's shipped script layers against the
real native library and a server on this machine, headlessly.

WHY THIS EXISTS. The two script libraries (src/curl-helpers.livecodescript
and src/tsnet.livecodescript) are where a tsNet-era stack meets curlxt, and
the static gate can only say they parse. This loads the SHIPPED text into
the family's headless interpreter (riptide's DemoInterp over the drift-gated
lcs-interp.py, the runner nocloud and coinxt's wallet gate use too), binds
every cu* handler of src/curl.lcb to the BUILT curlxt library through ctypes
- so each call goes through the real cux_* export, exactly what the .lcb
does - and drives the tsNet calls end to end against an HTTP server and an
SMTP server this file runs on 127.0.0.1, and the helpers' WebSocket calls
against a WebSocket server it runs there too (plain, and over TLS with a
certificate made for the run). Nothing touches the network.

WHERE THE LIBRARY COMES FROM: $CURLXT_LIB if set, else the committed
src/code/x86_64-linux/curlxt.so. With neither, this gate SKIPS and says so
(exit 0, the word SKIP), because its whole value is the real library; the
root native-curlxt.yml lane builds the library and runs this gate with
CURLXT_REQUIRE_LIB=1, which turns that skip into a failure.

WHAT IT MODELS, named so the divergences are read rather than discovered
(the runner's own header carries its contract; this adds four):
  - The .lcb layer is modelled in Python here (the LCB_* functions below):
    name-to-id tables, the out-buffer grow-and-retry, Data as Latin-1
    bytes. tools/check-abi-registry.py holds the .lcb's tables to the
    header, and this file's tables are read FROM the .lcb at load time, so
    the model cannot use a name the binding does not have.
  - `dispatch M to T with A` calls handler M with A; every handler of the
    three files lives in one namespace here, so the target is not used.
  - `the long id of me`, `of this card` and `of the target` evaluate to
    fixed object names (the model has no message path to name).
  - A handler's `@` parameter is passed back to Python by name (call_ref):
    the base interpreter has no by-reference parameters, and the tsNet
    synchronous calls return through them.
Nothing here promotes a label past "verified statically + headless run over
the native library; needs an OXT pass".
"""

import base64
import ctypes
import hashlib
import http.server
import importlib.util
import os
import re
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
FLOOR = 150


def sibling(name):
    """Path of a sibling member's checkout (docs/MEMBER-REPO-SPLIT.md), the
    family's one rule: XTALK_SIBLING_<NAME>, then XTALK_SIBLINGS, then the
    directory beside this member."""
    if name == os.path.basename(MEMBER):
        return MEMBER
    one = os.environ.get("XTALK_SIBLING_" + name.upper().replace("-", "_"))
    if one:
        return one
    return os.path.join(os.environ.get("XTALK_SIBLINGS")
                        or os.path.dirname(MEMBER), name)


RUNNER = os.path.join(sibling("riptide"), "tools", "check-demo-boot.py")
LCB = os.path.join(MEMBER, "src", "curl.lcb")
SOURCES = [os.path.join(MEMBER, "src", "curl-helpers.livecodescript"),
           os.path.join(MEMBER, "src", "tsnet.livecodescript")]


def find_library():
    env = os.environ.get("CURLXT_LIB")
    if env:
        return env
    committed = os.path.join(MEMBER, "src", "code", "x86_64-linux", "curlxt.so")
    return committed if os.path.isfile(committed) else None


# --------------------------------------------------------------- the servers

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    seen = {}

    def log_message(self, *a):
        pass

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _send(self, code, body, extra=()):
        self.send_response(code)
        for k, v in extra:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _route(self):
        body = self._body()
        p = self.path
        if p == "/hello":
            self._send(200, b"hello world", [("Content-Type", "text/plain"), ("X-Served", "yes")])
        elif p == "/echo":
            self._send(200, self.command.encode() + b":" + body)
        elif p == "/header":
            self._send(200, (self.headers.get("X-Test") or "").encode("latin-1"))
        elif p == "/agent":
            self._send(200, (self.headers.get("User-Agent") or "").encode("latin-1"))
        elif p == "/auth":
            self._send(200, (self.headers.get("Authorization") or "").encode("latin-1"))
        elif p == "/redirect":
            self._send(302, b"", [("Location", "/hello")])
        elif p == "/missing":
            self._send(404, b"nope")
        elif p == "/binary":
            self._send(200, bytes(range(256)))
        elif p == "/big":
            self._send(200, b"z" * 200000)
        elif p == "/slow":
            time.sleep(1.5)
            self._send(200, b"late")
        else:
            self._send(400, b"bad path")

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = _route


class SmtpHandler(socketserver.StreamRequestHandler):
    """Just enough SMTP for curl: greet, EHLO, MAIL, RCPT, DATA, QUIT.
    Records what arrived in SmtpHandler.got."""
    got = []

    def handle(self):
        w = self.wfile.write
        w(b"220 test ESMTP\r\n")
        rec = {"rcpt": []}
        while True:
            line = self.rfile.readline()
            if not line:
                return
            cmd = line.decode("latin-1").strip()
            up = cmd.upper()
            if up.startswith("EHLO") or up.startswith("HELO"):
                w(b"250 ok\r\n")
            elif up.startswith("MAIL FROM:"):
                rec["from"] = cmd[10:].strip()
                w(b"250 ok\r\n")
            elif up.startswith("RCPT TO:"):
                rec["rcpt"].append(cmd[8:].strip())
                w(b"250 ok\r\n")
            elif up == "DATA":
                w(b"354 go\r\n")
                data = b""
                while True:
                    ln = self.rfile.readline()
                    if ln in (b".\r\n", b""):
                        break
                    data += ln
                rec["data"] = data
                SmtpHandler.got.append(rec)
                rec = {"rcpt": []}
                w(b"250 queued\r\n")
            elif up == "QUIT":
                w(b"221 bye\r\n")
                return
            else:
                w(b"250 ok\r\n")


class WsHandler(socketserver.BaseRequestHandler):
    """A WebSocket server in the standard library: the upgrade, then an
    echo. A text message starting with '!' is a command that makes the
    server do what a client cannot otherwise provoke. Path /mute upgrades
    and then neither reads nor writes; /refuse answers the upgrade 404."""

    def _recv(self, n):
        buf = b""
        while len(buf) < n:
            part = self.request.recv(n - len(buf))
            if not part:
                raise ConnectionError("closed")
            buf += part
        return buf

    def _frame(self, first, payload):
        n = len(payload)
        if n < 126:
            head = bytes([first, n])
        elif n < 65536:
            head = bytes([first, 126]) + struct.pack(">H", n)
        else:
            head = bytes([first, 127]) + struct.pack(">Q", n)
        self.request.sendall(head + payload)

    def _read_frame(self):
        b = self._recv(2)
        n = b[1] & 0x7F
        if n == 126:
            n = struct.unpack(">H", self._recv(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", self._recv(8))[0]
        mask = self._recv(4) if b[1] & 0x80 else None
        data = self._recv(n)
        if mask:
            data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
        return b[0], data

    def handle(self):
        try:
            self._serve()
        except (ConnectionError, OSError, ssl.SSLError):
            pass

    def _serve(self):
        head = b""
        while b"\r\n\r\n" not in head:
            part = self.request.recv(4096)
            if not part:
                return
            head += part
        lines = head.decode("latin-1").split("\r\n")
        path = lines[0].split(" ")[1]
        hdr = {}
        for ln in lines[1:]:
            if ": " in ln:
                k, v = ln.split(": ", 1)
                hdr[k.lower()] = v
        if path == "/refuse":
            self.request.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            return
        key = hdr.get("sec-websocket-key", "")
        accept = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        up = ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
              "Connection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n" % accept)
        if "sec-websocket-protocol" in hdr:
            up += "Sec-WebSocket-Protocol: %s\r\n" % hdr["sec-websocket-protocol"]
        self.request.sendall((up + "\r\n").encode())
        if path == "/mute":
            time.sleep(4)
            return
        while True:
            first, data = self._read_frame()
            op = first & 0x0F
            if op == 0x8:
                self._frame(0x88, data)
                return
            if op == 0x9:
                self._frame(0x8A, data)
                continue
            if op == 0xA:
                continue
            if op == 0x1 and data.startswith(b"!"):
                if data == b"!close":
                    self._frame(0x81, b"last words")
                    self._frame(0x88, struct.pack(">H", 4001) + b"bye")
                    return
                if data == b"!drop":
                    return
                if data == b"!frag":
                    self._frame(0x01, b"ab")
                    self._frame(0x00, b"cd")
                    self._frame(0x80, b"ef")
                elif data == b"!burst":
                    for i in range(5):
                        self._frame(0x81, b"m%d" % i)
                elif data == b"!many":
                    for i in range(150):
                        self._frame(0x81, b"n%d" % i)
                elif data == b"!manyclose":
                    for i in range(150):
                        self._frame(0x81, b"c%d" % i)
                    self._frame(0x88, struct.pack(">H", 1000))
                    return
                elif data == b"!header":
                    self._frame(0x81, (hdr.get("x-test", "") + "|" + hdr.get("sec-websocket-protocol", "")).encode())
                elif data == b"!binary":
                    self._frame(0x82, bytes(range(256)))
                continue
            self._frame(0x80 | op, data)


class TWs(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        pass


class TWss(TWs):
    """The same server behind TLS. The handshake runs in the connection's
    own thread (a client that refuses the certificate must not stall the
    accept loop)."""
    context = None

    def get_request(self):
        sock, addr = self.socket.accept()
        return self.context.wrap_socket(sock, server_side=True, do_handshake_on_connect=False), addr

    def finish_request(self, request, client_address):
        request.settimeout(10)
        request.do_handshake()
        request.settimeout(None)
        WsHandler(request, client_address, self)


def make_certificate(tmp):
    """A self-signed certificate for 127.0.0.1, made with the openssl
    command (the standard library can serve TLS but cannot make a
    certificate). Returns (cert, key), or None when there is no openssl."""
    cert = os.path.join(tmp, "ws-cert.pem")
    key = os.path.join(tmp, "ws-key.pem")
    try:
        p = subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
             "-keyout", key, "-out", cert, "-subj", "/CN=127.0.0.1",
             "-addext", "subjectAltName=IP:127.0.0.1"],
            capture_output=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0 or not os.path.isfile(cert):
        return None
    return cert, key


class TServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        # A client that cancelled or timed out closes first; the late write
        # then fails with a broken pipe, which is the point of those checks.
        pass


class TSmtp(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True


# ------------------------------------------------- the .lcb layer, modelled

def lcb_tables():
    """name -> id for options, info and text fields, read from curl.lcb's
    own _optionId / _infoId / _textId and constants, so the model offers
    exactly the names the binding does."""
    with open(LCB, encoding="utf-8") as fh:
        src = fh.read()
    consts = {m.group(1): int(m.group(2))
              for m in re.finditer(r"^constant (k\w+) is (-?\d+)", src, re.M)}

    def table(handler):
        body = src[src.index("private handler %s(" % handler):]
        body = body[:body.index("end handler")]
        pairs = re.findall(r'pName is "(\w+)" then\s+return (k\w+)', body)
        if not pairs:
            raise SystemExit("check-script-vectors: no names parsed from %s" % handler)
        return {name: consts[k] for name, k in pairs}

    return consts, table("_optionId"), table("_infoId"), table("_textId")


class Lcb(object):
    def __init__(self, path):
        self.lib = ctypes.CDLL(path)
        L = self.lib
        L.cux_info.restype = ctypes.c_double
        for n in ("cux_request_new",):
            getattr(L, n).argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        L.cux_set_header.argtypes = [ctypes.c_int, ctypes.c_char_p]
        L.cux_set_text.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p]
        L.cux_set_body.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        L.cux_ws_new.argtypes = [ctypes.c_char_p]
        L.cux_ws_send.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        L.cux_ws_close.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p]
        L.cux_ws_read.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        self.consts, self.opt, self.info_ids, self.text_ids = lcb_tables()

    @staticmethod
    def b(v):
        s = v if isinstance(v, str) else str(v)
        try:
            return s.encode("latin-1")
        except UnicodeEncodeError:
            return s.encode("utf-8")

    def out(self, fn, *args):
        cap = 4096
        while True:
            buf = ctypes.create_string_buffer(cap)
            n = fn(*args, buf, cap)
            if n < -cap:
                cap = -n
                continue
            return buf.raw[:n] if n > 0 else b""

    def natives(self):
        L, S = self.lib, self

        def num(v):
            return int(float(v)) if str(v).strip() != "" else 0

        def init(a):
            if L.cux_abi_version() != S.consts["kABIVersion"]:
                raise RuntimeError("ABI skew")
            return L.cux_init()

        def set_option(a):
            oid = S.opt.get(str(a[1]), 0)
            if oid > 100:
                oid = 0
            return L.cux_set_int(num(a[0]), oid, num(a[2]))

        def set_text(a):
            oid = S.opt.get(str(a[1]), 0)
            if oid < 100:
                oid = 0
            return L.cux_set_text(num(a[0]), oid, S.b(a[2]))

        def body(a):
            h = num(a[0])
            size = int(L.cux_info(h, S.consts["kInfoBodySize"]))
            if size <= 0:
                return ""
            buf = ctypes.create_string_buffer(size)
            n = L.cux_body(h, buf, size)
            return buf.raw[:n].decode("latin-1") if n > 0 else ""

        def text_data(a):
            return self.out(L.cux_text, num(a[0]), S.text_ids.get(str(a[1]), 0)).decode("latin-1")

        def text(a):
            return self.out(L.cux_text, num(a[0]), S.text_ids.get(str(a[1]), 0)).decode("utf-8", "replace")

        def info(a):
            v = L.cux_info(num(a[0]), S.info_ids.get(str(a[1]), 0))
            return int(v) if v == int(v) else v

        def set_body(a):
            data = S.b(a[1])
            return L.cux_set_body(num(a[0]), data, len(data))

        K = S.consts

        def ws_send(a, kind, data):
            return L.cux_ws_send(num(a[0]), kind, data, len(data))

        def ws_read(a):
            # cuWsRead in the .lcb: ask how many wait and how big the next
            # is, then read into a block of exactly that size.
            h = num(a[0])
            if L.cux_info(h, K["kInfoWsMessages"]) < 1:
                return b""
            size = int(L.cux_info(h, K["kInfoWsNextSize"]))
            buf = ctypes.create_string_buffer(max(size, 1))
            n = L.cux_ws_read(h, buf, size)
            return buf.raw[:n] if n > 0 else b""

        return {
            "cuinitialize": init,
            "cucleanup": lambda a: L.cux_cleanup(),
            "culibraryversion": lambda a: self.out(L.cux_version_string).decode(),
            "culasterror": lambda a: self.out(L.cux_last_error).decode("utf-8", "replace"),
            "cuclearerror": lambda a: L.cux_clear_error() or "",
            "curequestnew": lambda a: L.cux_request_new(S.b(a[0]), S.b(a[1])),
            "cusetheader": lambda a: L.cux_set_header(num(a[0]), S.b(a[1])),
            "cusetoption": set_option,
            "cusettextoption": set_text,
            "cusetbody": set_body,
            "custart": lambda a: L.cux_start(num(a[0])),
            "cucancel": lambda a: L.cux_cancel(num(a[0])),
            "cufree": lambda a: L.cux_free(num(a[0])),
            "cupoll": lambda a: self.out(L.cux_poll).decode(),
            "cuwait": lambda a: L.cux_wait(num(a[0]), num(a[1])),
            "cuinfo": info,
            "cutext": text,
            "cutextdata": text_data,
            "cubody": body,
            "culivecount": lambda a: L.cux_live_count(),
            # WebSockets (ABI 2). cuWsSendText encodes UTF-8 and cuWsReadText
            # decodes it, as the .lcb does; Data stays Latin-1 bytes.
            "cuwsnew": lambda a: L.cux_ws_new(S.b(a[0])),
            "cuwssendtext": lambda a: ws_send(a, K["kWsKindText"], str(a[1]).encode("utf-8")),
            "cuwssenddata": lambda a: ws_send(a, K["kWsKindBinary"], S.b(a[1])),
            "cuwsping": lambda a: ws_send(a, K["kWsKindPing"], S.b(a[1])),
            "cuwsclose": lambda a: L.cux_ws_close(num(a[0]), num(a[1]), str(a[2]).encode("utf-8")),
            "cuwsread": lambda a: ws_read(a).decode("latin-1"),
            "cuwsreadtext": lambda a: ws_read(a).decode("utf-8", "replace"),
            "cuwspoll": lambda a: L.cux_ws_poll(),
            "cuwswait": lambda a: L.cux_ws_wait(num(a[0]), num(a[1])),
        }


# ------------------------------------------------------------ the checks

class StopAtFirst(Exception):
    pass


class Checker(object):
    def __init__(self, fail_fast=False):
        self.n = 0
        self.failed = []
        self.fail_fast = fail_fast

    def ck(self, label, got, want):
        self.n += 1
        if got != want:
            self.failed.append("  %s: got %r, want %r" % (label, got, want))
            if self.fail_fast:
                raise StopAtFirst()

    def ok(self, label, cond):
        self.ck(label, bool(cond), True)


# Handlers of a STACK that uses the helpers, written here because the two
# things they prove can only be seen from inside a message: that a handler
# may free its socket from within "text", and may open another from within
# "closed", without the timer losing its place.
TEST_HANDLERS = '''
local sCuTestLog
local sCuTestNext

function cuTestLog
   return sCuTestLog
end cuTestLog

command cuTestReset pNextUrl
   put empty into sCuTestLog
   put pNextUrl into sCuTestNext
end cuTestReset

on cuTestFreesInside pSocket, pWhat, pValue
   put pWhat & ";" after sCuTestLog
   if pWhat is "text" then
      get cuFree(pSocket)
   end if
end cuTestFreesInside

on cuTestReopens pSocket, pWhat, pValue
   put pWhat & ":" & pValue & ";" after sCuTestLog
   if pWhat is "closed" then
      get cuFree(pSocket)
      if sCuTestNext is not empty then
         get cuWsOpen(sCuTestNext, empty, empty, "card 1", "cuTestSecond")
         put empty into sCuTestNext
      end if
   end if
end cuTestReopens

on cuTestSecond pSocket, pWhat, pValue
   put "second-" & pWhat & ";" after sCuTestLog
   if pWhat is "open" then
      get cuWsClose(pSocket, 1000, empty)
   end if
   if pWhat is "closed" then
      get cuFree(pSocket)
   end if
end cuTestSecond
'''


def load_runner():
    spec = importlib.util.spec_from_file_location("cux_demo_boot", RUNNER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_source():
    parts = []
    for p in SOURCES:
        with open(p, encoding="utf-8") as fh:
            src = fh.read()
        src = re.sub(r'^script\s+"[^"]*"[^\n]*\n', "", src, count=1)
        parts.append(src)
    parts.append(TEST_HANDLERS)
    src = "\n".join(parts)
    # The three object names (header: modelled).
    src = re.sub(r"the long id of me\b", '"stack tsNetCompat"', src)
    src = re.sub(r"the long id of this card\b", '"card 1"', src)
    src = re.sub(r"the long id of the target\b", '"card 1"', src)
    return src


def make_interp(DB, world, src):
    LCS = DB.LCS

    class CuInterp(DB.DemoInterp):
        def __init__(self, s, w):
            self.callbacks = []
            super().__init__(s, w)

        def _exec_stmt(self, body, i, env):
            line = body[i].strip()
            m = re.match(r"dispatch\s+(.+?)\s+to\s+(.+?)(?:\s+with\s+(.*))?$", line, re.I)
            if m:
                name = str(LCS._disp(self.eval_expr(m.group(1), env)))
                args = []
                if m.group(3):
                    p = DB.DemoExpr(self, env)
                    p.s, p.i = m.group(3), 0
                    while True:
                        args.append(p.p_or())
                        p.ws()
                        if p.i < len(p.s) and p.s[p.i] == ",":
                            p.i += 1
                            continue
                        break
                if name.lower() in self.handlers:
                    self.call(name, args)
                else:
                    self.callbacks.append((name, [LCS._disp(a) for a in args]))
                return i + 1
            return super()._exec_stmt(body, i, env)

        def call_ref(self, name, args):
            """Call a handler whose parameters may be `@` references; returns
            (result, {param: final value}) for every `@` parameter."""
            params, body = self.handlers[name.lower()]
            refs = self.ref_params.get(name.lower(), [])
            env = {}
            for idx, p in enumerate(params):
                env[p.lower()] = LCS._copy(args[idx]) if idx < len(args) else ""
            result = ""
            try:
                self._exec(body, env)
            except LCS._Return as r:
                result = r.value
            return result, {k: env.get(k, "") for k in refs}

    # `@` parameters must be stripped for ordinary calls too: an `@` name
    # left in the parameter list would never bind (an undeclared name
    # evaluates to its own spelling).
    ip = CuInterp(src, world)
    ip.ref_params = {}
    for key, (params, body) in list(ip.handlers.items()):
        ip.ref_params[key] = [p[1:].lower() for p in params if p.startswith("@")]
        ip.handlers[key] = ([p.lstrip("@") for p in params], body)
    return ip


def pump_until(ip, done, limit=400):
    """Deliver queued sends (the timer) with real time passing, until
    done() or the limit."""
    for _ in range(limit):
        if done():
            return True
        if ip.world.sends:
            ip.deliver_sends(rounds=1)
        time.sleep(0.01)
    return done()


def drive_ws(c, ip, call, base, ws, wss, cert):
    """The helpers' WebSocket calls: cuWsOpen's messages through the timer,
    cuWsOpenSync, and what the timer does around them."""
    ck = c.ck

    def s(v):
        return str(v)

    def events(name="wsEvt"):
        return [(s(a[1]), s(a[2])) for n, a in ip.callbacks if n == name]

    def kinds(name="wsEvt"):
        return [k for k, _ in events(name)]

    def until(what, name="wsEvt", limit=600):
        return pump_until(ip, lambda: what in kinds(name), limit)

    # ---- the everyday path: open, talk, close
    ip.callbacks.clear()
    sock = call("cuWsOpen", [ws + "/echo", "X-Test: carried\nSec-WebSocket-Protocol: chat.v1", "", "card 1", "wsEvt"])
    c.ok("cuWsOpen returns a handle", s(sock).isdigit() and int(sock) > 0)
    ck("one socket watched", s(call("cuWsWatchedCount", [])), "1")
    ck("a socket is not a waiting request", s(call("cuWaitingCount", [])), "0")
    c.ok("the timer is armed for it", bool(ip.world.sends))
    until("open")
    ck("the first message is open", events()[:1], [("open", "")])
    ck("it carries the socket handle", [s(a[0]) for n, a in ip.callbacks if n == "wsEvt"][:1], [s(sock)])
    ck("wsState is open", s(call("cuInfo", [sock, "wsState"])), "2")
    ck("send text", s(call("cuWsSendText", [sock, "hello"])), "0")
    pump_until(ip, lambda: len(events()) >= 2)
    ck("text arrives as a text message", events()[1:2], [("text", "hello")])
    uni = "h\u00e9llo \u2713 \u65e5\u672c"
    call("cuWsSendText", [sock, uni])
    pump_until(ip, lambda: len(events()) >= 3)
    ck("text is UTF-8 on the wire and text again here", events()[2:3], [("text", uni)])
    raw = bytes(range(256)).decode("latin-1")
    ck("send data", s(call("cuWsSendData", [sock, raw])), "0")
    pump_until(ip, lambda: len(events()) >= 4)
    ck("bytes arrive as a binary message, unchanged", events()[3:4], [("binary", raw)])
    call("cuWsSendText", [sock, "!header"])
    pump_until(ip, lambda: len(events()) >= 5)
    ck("pHeaders reached the server (a header and a subprotocol)", events()[4:5], [("text", "carried|chat.v1")])
    call("cuWsSendText", [sock, "!frag"])
    pump_until(ip, lambda: len(events()) >= 6)
    ck("a fragmented message arrives whole", events()[5:6], [("text", "abcdef")])
    call("cuWsSendText", [sock, "!burst"])
    pump_until(ip, lambda: len(events()) >= 11)
    ck("a burst arrives in order", [v for _, v in events()[6:11]], ["m0", "m1", "m2", "m3", "m4"])
    call("cuWsSendText", [sock, ""])
    pump_until(ip, lambda: len(events()) >= 12)
    ck("an empty message is still a message", events()[11:12], [("text", "")])
    ck("ping", s(call("cuWsPing", [sock, "p"])), "0")
    pump_until(ip, lambda: int(call("cuInfo", [sock, "wsPongs"])) >= 1)
    ck("the pong is counted", s(call("cuInfo", [sock, "wsPongs"])), "1")
    ck("and is not a message", len(events()), 12)
    ck("close", s(call("cuWsClose", [sock, 1000, "done"])), "0")
    until("closed")
    ck("closed is the last message, with the code", events()[-1:], [("closed", "1000")])
    ck("closed arrives once", kinds().count("closed"), 1)
    ck("open arrived once", kinds().count("open"), 1)
    ck("the reason is readable after", s(call("cuText", [sock, "wsCloseReason"])), "done")
    ck("nothing watched after closed", s(call("cuWsWatchedCount", [])), "0")
    pump_until(ip, lambda: not ip.world.sends, 50)
    c.ok("the timer stops when no socket is watched", not ip.world.sends)
    ck("the handler frees it", s(call("cuFree", [sock])), "0")

    # ---- more messages than one pass hands over: none lost, order kept
    ip.callbacks.clear()
    sock = call("cuWsOpen", [ws + "/echo", "", "", "card 1", "wsEvt"])
    until("open")
    call("cuWsSendText", [sock, "!many"])
    pump_until(ip, lambda: len(events()) >= 151)
    ck("150 messages, each once, in order", [v for _, v in events()[1:]], ["n%d" % i for i in range(150)])

    # ---- the server closes, after a last message
    ip.callbacks.clear()
    call("cuWsSendText", [sock, "!close"])
    until("closed")
    ck("what arrived before the close comes first", events(), [("text", "last words"), ("closed", "4001")])
    ck("the server's reason", s(call("cuText", [sock, "wsCloseReason"])), "bye")
    ck("a close is not a failure", s(call("cuInfo", [sock, "result"])), "0")
    call("cuFree", [sock])

    # ---- a close behind more messages than one pass hands over: closed
    # waits for the last of them
    ip.callbacks.clear()
    sock = call("cuWsOpen", [ws + "/echo", "", "", "card 1", "wsEvt"])
    until("open")
    call("cuWsSendText", [sock, "!manyclose"])
    # moved by hand, with the timer held still, so that all 150 and the
    # close are waiting when the timer's next pass comes
    for _ in range(500):
        call("cuWsPoll", [])
        if int(call("cuInfo", [sock, "wsState"])) == 4:
            break
        time.sleep(0.01)
    ck("all of it is waiting, and the socket has closed",
       [s(call("cuInfo", [sock, "wsMessages"])), s(call("cuInfo", [sock, "wsState"]))], ["150", "4"])
    until("closed")
    ck("closed comes after every message that arrived before it",
       events()[1:], [("text", "c%d" % i) for i in range(150)] + [("closed", "1000")])
    call("cuFree", [sock])

    # ---- the connection is lost
    ip.callbacks.clear()
    sock = call("cuWsOpen", [ws + "/echo", "", "", "card 1", "wsEvt"])
    until("open")
    call("cuWsSendText", [sock, "!drop"])
    until("closed")
    ck("a lost connection is closed 1006", events()[-1:], [("closed", "1006")])
    c.ok("and the socket says why", s(call("cuText", [sock, "error"])) != "")
    call("cuFree", [sock])

    # ---- it never opens
    ip.callbacks.clear()
    sock = call("cuWsOpen", ["ws://127.0.0.1:1/", "", "", "card 1", "wsEvt"])
    until("closed")
    ck("a socket that never opened sends closed 0 and no open", events(), [("closed", "0")])
    ck("its result is curl's could-not-connect", s(call("cuInfo", [sock, "result"])), "7")
    call("cuFree", [sock])
    ip.callbacks.clear()
    sock = call("cuWsOpen", [ws + "/refuse", "", "", "card 1", "wsEvt"])
    until("closed")
    ck("a refused upgrade sends closed 0 and no open", events(), [("closed", "0")])
    ck("and the server's status is readable", s(call("cuInfo", [sock, "responseCode"])), "404")
    call("cuFree", [sock])
    ck("a URL that is not ws:// is refused", s(call("cuWsOpen", ["http://127.0.0.1/", "", "", "card 1", "wsEvt"])), "0")
    c.ok("and cuHelpersError says why", "ws://" in s(call("cuHelpersError", [])))
    bad = DB_LCS.LcsArray()
    bad["wsCloseTimeout"] = "soon"
    ck("a non-integer wsCloseTimeout is refused", s(call("cuWsOpen", [ws + "/echo", "", bad, "card 1", "wsEvt"])), "0")

    # ---- options reach the socket: a peer that never answers a close
    ip.callbacks.clear()
    opts = DB_LCS.LcsArray()
    opts["wsCloseTimeout"] = 200
    sock = call("cuWsOpen", [ws + "/mute", "", opts, "card 1", "wsEvt"])
    until("open")
    t0 = time.time()
    call("cuWsClose", [sock, 1000, ""])
    until("closed")
    ck("an unanswered close ends as 1006", events()[-1:], [("closed", "1006")])
    c.ok("after the wsCloseTimeout, not the default five seconds", time.time() - t0 < 3)
    call("cuFree", [sock])

    # ---- a socket and a request share the timer
    ip.callbacks.clear()
    sock = call("cuWsOpen", [ws + "/echo", "", "", "card 1", "wsEvt"])
    until("open")
    req = call("cuRequestAsync", ["GET", base + "/hello", "", "", "", "card 1", "gotIt"])
    call("cuWsSendText", [sock, "beside"])
    pump_until(ip, lambda: ("text", "beside") in events() and any(n == "gotIt" for n, _ in ip.callbacks))
    c.ok("the socket's message arrives", ("text", "beside") in events())
    ck("the request reports once, with its own handle", [s(a[0]) for n, a in ip.callbacks if n == "gotIt"], [s(req)])
    call("cuFree", [req])
    ck("nothing waits", s(call("cuWaitingCount", [])), "0")
    pump_until(ip, lambda: False, 10)
    c.ok("the timer keeps running while a socket is watched", bool(ip.world.sends))
    call("cuWsUnwatch", [sock])
    pump_until(ip, lambda: not ip.world.sends, 50)
    c.ok("and stops once it is unwatched", not ip.world.sends)
    n_before = len(ip.callbacks)
    call("cuWsSendText", [sock, "unheard"])
    ck("an unwatched socket still moves under cuWsWait", s(call("cuWsWait", [sock, 5000])), "1")
    ck("and is read by hand", s(call("cuWsReadText", [sock])), "unheard")
    ck("with no message sent for it", len(ip.callbacks), n_before)
    call("cuFree", [sock])

    # ---- cuWsOpenSync, then by hand
    sock = call("cuWsOpenSync", [ws + "/echo", "", "", 5000])
    c.ok("cuWsOpenSync returns an open socket", s(sock).isdigit() and int(sock) > 0)
    ck("it is open on return", s(call("cuInfo", [sock, "wsState"])), "2")
    ck("it is not watched", s(call("cuWsWatchedCount", [])), "0")
    call("cuWsSendText", [sock, "sync"])
    ck("cuWsWait sees the answer", s(call("cuWsWait", [sock, 5000])), "1")
    ck("wsNextType is text", s(call("cuInfo", [sock, "wsNextType"])), "1")
    ck("cuWsReadText", s(call("cuWsReadText", [sock])), "sync")
    ck("nothing left", s(call("cuInfo", [sock, "wsMessages"])), "0")
    ck("cuWsRead with nothing waiting is empty", s(call("cuWsRead", [sock])), "")
    call("cuWsSendText", [sock, "!binary"])
    call("cuWsWait", [sock, 5000])
    ck("wsNextType is binary", s(call("cuInfo", [sock, "wsNextType"])), "2")
    ck("cuWsRead", s(call("cuWsRead", [sock])), raw)
    ck("cuWsPoll with nothing waiting", s(call("cuWsPoll", [])), "0")
    # handed to the timer afterwards: "open" is sent, late but once
    ip.callbacks.clear()
    call("cuWsWatch", [sock, "card 1", "wsEvt"])
    call("cuWsSendText", [sock, "watched now"])
    pump_until(ip, lambda: len(events()) >= 2)
    ck("a socket watched after it opened still gets open first", events(), [("open", ""), ("text", "watched now")])
    call("cuWsClose", [sock, 3999, ""])
    until("closed")
    ck("an application close code comes back", events()[-1:], [("closed", "3999")])
    call("cuFree", [sock])
    ck("cuWsOpenSync of a dead port is 0", s(call("cuWsOpenSync", ["ws://127.0.0.1:1/", "", "", 5000])), "0")
    c.ok("with the reason", s(call("cuHelpersError", [])) != "")
    ck("cuWsOpenSync that runs out of time is 0", s(call("cuWsOpenSync", [ws + "/mute-not", "", "", 0])), "0")
    c.ok("and says so", s(call("cuHelpersError", [])) != "")
    ck("and leaves no socket behind", s(call("cuLiveCount", [])), "0")

    # ---- a handler may free its socket inside a message
    call("cuTestReset", [""])
    sock = call("cuWsOpen", [ws + "/echo", "", "", "card 1", "cuTestFreesInside"])
    pump_until(ip, lambda: "open" in s(call("cuTestLog", [])))
    call("cuWsSendText", [sock, "!burst"])
    pump_until(ip, lambda: "text" in s(call("cuTestLog", [])))
    pump_until(ip, lambda: not ip.world.sends, 100)
    ck("freed inside its first message: no more messages, no closed", s(call("cuTestLog", [])), "open;text;")
    ck("it is unwatched", s(call("cuWsWatchedCount", [])), "0")
    c.ok("and the timer stops", not ip.world.sends)
    ck("no pump failure recorded", s(call("cuPollLastError", [])), "")

    # ---- and may open another inside "closed"
    call("cuTestReset", [ws + "/echo"])
    sock = call("cuWsOpen", [ws + "/echo", "", "", "card 1", "cuTestReopens"])
    pump_until(ip, lambda: "open" in s(call("cuTestLog", [])))
    call("cuWsClose", [sock, 1000, ""])
    pump_until(ip, lambda: "second-closed" in s(call("cuTestLog", [])))
    ck("a socket opened inside closed lives its own whole life",
       s(call("cuTestLog", [])), "open:;closed:1000;second-open;second-closed;")
    ck("nothing watched", s(call("cuWsWatchedCount", [])), "0")
    ck("no socket left", s(call("cuLiveCount", [])), "0")

    # ---- cuHelpersRelease forgets the watched sockets
    ip.callbacks.clear()
    sock = call("cuWsOpen", [ws + "/echo", "", "", "card 1", "wsEvt"])
    until("open")
    call("cuHelpersRelease", [])
    ck("release forgets them", s(call("cuWsWatchedCount", [])), "0")
    ck("and the last hold freed the socket", s(call("cuLiveCount", [])), "0")
    ck("helpers init again", s(call("cuHelpersInit", [])), "")

    # ---- wss://, against a certificate made for this run
    if wss is None:
        return
    ip.callbacks.clear()
    opts = DB_LCS.LcsArray()
    opts["caFile"] = cert
    sock = call("cuWsOpen", [wss + "/echo", "", opts, "card 1", "wsEvt"])
    until("open")
    ck("wss opens when the certificate is trusted (caFile)", kinds()[:1], ["open"])
    call("cuWsSendText", [sock, "over tls"])
    pump_until(ip, lambda: len(events()) >= 2)
    ck("and carries messages", events()[1:2], [("text", "over tls")])
    big = "t" * 100000
    call("cuWsSendText", [sock, big])
    pump_until(ip, lambda: len(events()) >= 3)
    ck("a large message over TLS", events()[2:3], [("text", big)])
    call("cuWsClose", [sock, 1000, ""])
    until("closed")
    ck("and closes cleanly", events()[-1:], [("closed", "1000")])
    call("cuFree", [sock])
    ip.callbacks.clear()
    sock = call("cuWsOpen", [wss + "/echo", "", "", "card 1", "wsEvt"])
    until("closed")
    ck("wss refuses a certificate nobody vouches for", events(), [("closed", "0")])
    ck("with curl's certificate error", s(call("cuInfo", [sock, "result"])), "60")
    call("cuFree", [sock])
    ip.callbacks.clear()
    opts = DB_LCS.LcsArray()
    opts["verifyPeer"] = 0
    opts["verifyHost"] = 0
    sock = call("cuWsOpen", [wss + "/echo", "", opts, "card 1", "wsEvt"])
    until("open")
    ck("verifyPeer 0 is honoured for a socket too", kinds()[:1], ["open"])
    call("cuFree", [sock])
    pump_until(ip, lambda: not ip.world.sends, 50)
    ck("a freed socket is dropped from the watch", s(call("cuWsWatchedCount", [])), "0")


def drive(c, ip, base, smtp_port, tmp, ws=None, wss=None, cert=None):
    def call(name, args):
        # A script handler, or one of the modelled .lcb natives.
        if name.lower() in ip.handlers:
            return ip.call(name, args)
        return DB_LCS.HASHES[name.lower()](args)

    def s(v):
        return str(v)

    # ---- helpers: the everyday calls
    ck = c.ck
    ck("helpers init", call("cuHelpersInit", []), "")
    req = call("cuRequestSync", ["GET", base + "/hello", "", "", "", 5000])
    c.ok("cuRequestSync returns a handle", s(req).isdigit() and int(req) > 0)
    resp = call("cuResponse", [req])
    ck("cuResponse ok", s(resp["ok"]).lower(), "true")
    ck("cuResponse code", s(resp["responseCode"]), "200")
    ck("cuResponse body", s(resp["body"]), "hello world")
    ck("cuResponse content type", s(resp["contentType"]), "text/plain")
    c.ok("cuResponse headers", "X-Served: yes" in s(resp["headers"]))
    ck("free", s(call("cuFree", [req])), "0")

    opts = DB_LCS.LcsArray()
    opts["userAgent"] = "curlxt-test/1"
    opts["followRedirects"] = 0
    req = call("cuRequestSync", ["GET", base + "/agent", "X-Test: one\nX-Other: two", "", opts, 5000])
    ck("text option reaches the server", s(call("cuResponse", [req])["body"]), "curlxt-test/1")
    call("cuFree", [req])
    req = call("cuRequestSync", ["GET", base + "/redirect", "", "", opts, 5000])
    ck("followRedirects 0 is honoured", s(call("cuResponse", [req])["responseCode"]), "302")
    call("cuFree", [req])
    bad = DB_LCS.LcsArray()
    bad["timeout"] = "soon"
    ck("a non-integer integer option is refused", s(call("cuRequestSync", ["GET", base + "/hello", "", "", bad, 5000])), "0")
    c.ok("and says why", "whole number" in s(call("cuHelpersError", [])))
    bad = DB_LCS.LcsArray()
    bad["noSuchOption"] = "x"
    ck("an unknown option is refused", s(call("cuRequestSync", ["GET", base + "/hello", "", "", bad, 5000])), "0")
    ck("a bad URL is refused at start", s(call("cuRequestSync", ["GET", "", "", "", "", 5000])), "0")

    # async through the timer
    ip.callbacks.clear()
    a1 = call("cuRequestAsync", ["GET", base + "/hello", "", "", "", "card 1", "gotIt"])
    a2 = call("cuRequestAsync", ["POST", base + "/echo", "", "x\x00y", "", "card 1", "gotIt"])
    ck("two watched", s(call("cuWaitingCount", [])), "2")
    pump_until(ip, lambda: len(ip.callbacks) >= 2)
    got = sorted(int(args[0]) for name, args in ip.callbacks if name == "gotIt")
    ck("each async request reports once", got, sorted([int(a1), int(a2)]))
    ck("binary-safe async body", s(call("cuResponse", [a2])["body"]), "POST:x\x00y")
    ck("nothing left waiting", s(call("cuWaitingCount", [])), "0")
    c.ok("the timer stops when nothing waits", not ip.world.sends)
    call("cuFree", [a1])
    call("cuFree", [a2])
    ip.callbacks.clear()
    a3 = call("cuRequestAsync", ["GET", base + "/slow", "", "", "", "card 1", "gotIt"])
    call("cuCancel", [a3])
    pump_until(ip, lambda: len(ip.callbacks) >= 1)
    ck("a cancelled request still calls back", [n for n, _ in ip.callbacks], ["gotIt"])
    ck("its result is 1000", s(call("cuResponse", [a3])["result"]), "1000")
    call("cuFree", [a3])
    ck("no pump failure recorded", s(call("cuPollLastError", [])), "")

    # ---- helpers: WebSockets
    if ws is not None:
        drive_ws(c, ip, call, base, ws, wss, cert)

    # ---- tsNet: synchronous calls
    r, out = ip.call_ref("tsNetGetSync", [base + "/hello", "", "", "", ""])
    ck("tsNetGetSync data", s(r), "hello world")
    ck("tsNetGetSync rResult", s(out["rresult"]), "200")
    ck("tsNetGetSync rBytes", s(out["rbytes"]), "11")
    c.ok("tsNetGetSync rOutHeaders", "X-Served: yes" in s(out["routheaders"]))
    r, out = ip.call_ref("tsNetGetSync", [base + "/header", "X-Test: carried\r\n", "", "", "", ""])
    ck("tsNetGetSync sends xHeaders (CRLF tolerated)", s(r), "carried")
    r, out = ip.call_ref("tsNetGetSync", [base + "/missing", "", "", "", "", ""])
    ck("a 404 is data, not tsneterr", s(r), "nope")
    ck("its rResult is 404", s(out["rresult"]), "404")
    r, out = ip.call_ref("tsNetGetSync", [base + "/binary", "", "", "", "", ""])
    ck("binary download round trips", s(r), bytes(range(256)).decode("latin-1"))
    r, out = ip.call_ref("tsNetGetSync", [base + "/redirect", "", "", "", "", ""])
    ck("tsNet follows redirects", s(r), "hello world")
    r, out = ip.call_ref("tsNetGetSync", ["http://127.0.0.1:1/", "", "", "", "", ""])
    c.ok("a refused connection is tsneterr", s(r).startswith("tsneterr:"))
    ck("and rResult says the same", s(out["rresult"]), s(r))
    r, out = ip.call_ref("tsNetPostSync", [base + "/echo", "", "a=1&b=2", "", "", "", ""])
    ck("tsNetPostSync", s(r), "POST:a=1&b=2")
    r, out = ip.call_ref("tsNetUploadSync", [base + "/echo", "", "put-this", "", "", "", ""])
    ck("tsNetUploadSync is an HTTP PUT", s(r), "PUT:put-this")
    ck("tsNetUploadSync rBytes counts the upload", s(out["rbytes"]), "8")
    r, out = ip.call_ref("tsNetCustomSync", [base + "/echo", "DELETE", "", "", "", "", ""])
    ck("tsNetCustomSync method", s(r), "DELETE:")
    r, out = ip.call_ref("tsNetHeadSync", [base + "/hello", "", "", "", ""])
    c.ok("tsNetHeadSync returns headers", "X-Served: yes" in s(r))
    ck("tsNetHeadSync rResult", s(out["rresult"]), "200")

    settings = DB_LCS.LcsArray()
    settings["username"] = "ann"
    settings["password"] = "pw"
    r, out = ip.call_ref("tsNetGetSync", [base + "/auth", "", "", "", "", settings])
    ck("settings username/password become Basic auth", s(r), "Basic YW5uOnB3")
    settings = DB_LCS.LcsArray()
    settings["user_agent"] = "Legacy/9"
    r, out = ip.call_ref("tsNetGetSync", [base + "/agent", "", "", "", "", settings])
    ck("settings user_agent", s(r), "Legacy/9")

    dl = os.path.join(tmp, "dl.bin")
    r, out = ip.call_ref("tsNetGetFileSync", [dl, base + "/big", "", "", "", ""])
    ck("tsNetGetFileSync returns the status", s(r), "200")
    ck("tsNetGetFileSync rBytes", s(out["rbytes"]), "200000")
    with open(dl, "rb") as fh:
        ck("the file holds the download", fh.read(), b"z" * 200000)
    capped = DB_LCS.LcsArray()
    capped["max_file_size"] = "1000"
    r, out = ip.call_ref("tsNetGetFileSync", [dl, base + "/big", "", "", "", capped])
    c.ok("max_file_size stops a download to a file", s(r).startswith("tsneterr:"))
    c.ok("and the file stays within it", os.path.getsize(dl) <= 1000)
    up = os.path.join(tmp, "up.txt")
    with open(up, "wb") as fh:
        fh.write(b"file-body")
    r, out = ip.call_ref("tsNetUploadFileSync", [up, base + "/echo", "", "", "", "", ""])
    ck("tsNetUploadFileSync", s(r), "PUT:file-body")
    r, out = ip.call_ref("tsNetGetFileSync", [os.path.join(tmp, "no", "such", "dir", "x"), base + "/hello", "", "", "", ""])
    c.ok("an unwritable file is tsneterr", s(r).startswith("tsneterr:"))

    # timeouts
    ip.call("tsNetSetTimeouts", [60, 300, 5000, 60000, 0, 0])
    r, out = ip.call_ref("tsNetGetSync", [base + "/slow", "", "", "", "", ""])
    c.ok("tsNetSetTimeouts' request timeout applies", s(r).startswith("tsneterr:"))
    ip.call("tsNetSetTimeouts", [60, 0, 5000, 60000, 0, 0])
    r, out = ip.call_ref("tsNetGetSync", [base + "/slow", "", "", "", "", ""])
    ck("and 0 lifts it", s(r), "late")

    # SMTP
    SmtpHandler.got[:] = []
    msg = "Subject: hi\r\n\r\nbody line\r\n"
    smtp = "smtp://127.0.0.1:%d" % smtp_port
    r, out = ip.call_ref("tsNetSmtpSync", [smtp, "<a@x.test>", "<b@x.test>,<c@x.test>", msg, "", "", ""])
    ck("tsNetSmtpSync returns the server's code", s(r), "250")
    ck("one message arrived", len(SmtpHandler.got), 1)
    if SmtpHandler.got:
        g = SmtpHandler.got[0]
        ck("MAIL FROM", g.get("from"), "<a@x.test>")
        ck("both recipients (comma list)", g.get("rcpt"), ["<b@x.test>", "<c@x.test>"])
        c.ok("the message body", b"body line" in g.get("data", b""))

    # ---- tsNet: background calls
    ip.callbacks.clear()
    ck("tsNetGet starts", s(ip.call("tsNetGet", ["c1", base + "/hello", "", "doneMsg"])), "")
    ck("a busy ID is refused", s(ip.call("tsNetGet", ["c1", base + "/hello", "", "doneMsg"]))[:9], "tsneterr:")
    ck("tsNetPost starts", s(ip.call("tsNetPost", ["c2", base + "/echo", "", "pp", "doneMsg"])), "")
    ck("tsNetUpload starts (callback before data)", s(ip.call("tsNetUpload", ["c3", base + "/echo", "", "doneMsg", "up"])), "")
    ck("tsNetSmtp starts", s(ip.call("tsNetSmtp", ["c4", smtp, "<a@x.test>", "<d@x.test>", "doneMsg", msg])), "")
    ck("tsNetCustom starts", s(ip.call("tsNetCustom", ["c5", base + "/echo", "PATCH", "", "doneMsg"])), "")
    pump_until(ip, lambda: len(ip.callbacks) >= 5)
    calls = {args[0]: args for name, args in ip.callbacks if name == "doneMsg"}
    ck("five callbacks, one per ID", sorted(calls), ["c1", "c2", "c3", "c4", "c5"])
    if "c1" in calls:
        ck("callback params: id, status, bytes, curl code", [s(x) for x in calls["c1"]], ["c1", "200", "11", "0"])
    if "c3" in calls:
        ck("an upload's callback counts bytes sent", s(calls["c3"][2]), "2")
    if "c4" in calls:
        ck("SMTP callback status", s(calls["c4"][1]), "250")
    r, out = ip.call_ref("tsNetRetrData", ["c1", "x"])
    ck("tsNetRetrData", s(r), "hello world")
    ck("and rError is empty", s(out["rerror"]), "")
    r, out = ip.call_ref("tsNetRetrData", ["c2", ""])
    ck("tsNetRetrData of a POST", s(r), "POST:pp")
    ck("tsNetRetrData of a custom method", s(ip.call_ref("tsNetRetrData", ["c5", ""])[0]), "PATCH:")
    c.ok("tsNetHeaders", "X-Served: yes" in s(ip.call("tsNetHeaders", ["c1"])))
    ck("tsNetGetStatus when done", s(ip.call("tsNetGetStatus", ["c1"])), "completed 11 11 0 0")
    ck("tsNetRetrError of a success", s(ip.call("tsNetRetrError", ["c1"])), "")
    ck("a finished ID can be reused", s(ip.call("tsNetGet", ["c1", base + "/missing", "", "doneMsg"])), "")
    ip.callbacks.clear()
    pump_until(ip, lambda: len(ip.callbacks) >= 1)
    ck("the reused ID reports its own transfer", s(ip.call_ref("tsNetRetrData", ["c1", ""])[0]), "nope")

    # OXT-Beyond's dropbox library (LiveCode's, written against tsNet) is
    # the one inherited caller of the background calls: tsNetPost with a
    # uuid ID and headers, then in the callback tsNetRetrData(ID, error)
    # and tsNetCloseConn. Replayed here so its names cannot drift again
    # (this layer first spelled the second one tsNetRetrieveData).
    ip.callbacks.clear()
    ck("dropbox: tsNetPost starts", s(ip.call("tsNetPost", ["db-1", base + "/echo", "Content-Type: application/json", "{}", "dbMsg"])), "")
    pump_until(ip, lambda: len(ip.callbacks) >= 1)
    r, out = ip.call_ref("tsNetRetrData", ["db-1", ""])
    ck("dropbox: tsNetRetrData", s(r), "POST:{}")
    ck("dropbox: its error is empty", s(out["rerror"]), "")
    ck("dropbox: tsNetCloseConn", s(ip.call("tsNetCloseConn", ["db-1"])), "")
    r, out = ip.call_ref("tsNetRetrData", ["db-1", ""])
    c.ok("dropbox: a closed ID has no data", s(out["rerror"]).startswith("tsneterr:"))

    ip.callbacks.clear()
    ck("tsNetGet of a dead port starts", s(ip.call("tsNetGet", ["dead", "http://127.0.0.1:1/", "", "doneMsg"])), "")
    pump_until(ip, lambda: len(ip.callbacks) >= 1)
    if ip.callbacks:
        ck("its curl code is 7 (could not connect)", s(ip.callbacks[0][1][3]), "7")
    r, out = ip.call_ref("tsNetRetrData", ["dead", ""])
    c.ok("tsNetRetrData's rError is tsneterr", s(out["rerror"]).startswith("tsneterr:"))
    c.ok("tsNetRetrError explains", s(ip.call("tsNetRetrError", ["dead"])) != "")
    ck("tsNetGetStatus of a failure", s(ip.call("tsNetGetStatus", ["dead"])).split()[0], "error")

    ip.callbacks.clear()
    gf = os.path.join(tmp, "async.bin")
    ck("tsNetGetFile starts", s(ip.call("tsNetGetFile", ["f1", gf, base + "/big", "", "doneMsg"])), "")
    ck("tsNetUploadFile starts", s(ip.call("tsNetUploadFile", ["f2", up, base + "/echo", "", "doneMsg"])), "")
    pump_until(ip, lambda: len(ip.callbacks) >= 2)
    with open(gf, "rb") as fh:
        ck("tsNetGetFile wrote the file", len(fh.read()), 200000)
    ck("tsNetUploadFile", s(ip.call_ref("tsNetRetrData", ["f2", ""])[0]), "PUT:file-body")

    # status callback and close
    ip.callbacks.clear()
    ip.call("tsNetSetStatusCallback", ["statusMsg"])
    ck("slow transfer starts", s(ip.call("tsNetGet", ["s1", base + "/slow", "", "doneMsg"])), "")
    pump_until(ip, lambda: any(n == "doneMsg" for n, _ in ip.callbacks))
    statuses = [a for n, a in ip.callbacks if n == "statusMsg"]
    c.ok("status messages while loading", any(s(a[1]) == "loading" for a in statuses))
    c.ok("and a final completed one", statuses and s(statuses[-1][1]) == "completed")
    c.ok("status has six parameters", statuses and len(statuses[-1]) == 6)
    ip.call("tsNetSetStatusCallback", [""])

    ip.callbacks.clear()
    ck("cancel target starts", s(ip.call("tsNetGet", ["x1", base + "/slow", "", "doneMsg"])), "")
    ck("tsNetCloseConn of a live ID", s(ip.call("tsNetCloseConn", ["x1"])), "")
    pump_until(ip, lambda: False, limit=30)
    ck("a closed connection sends no callback", ip.callbacks, [])
    c.ok("tsNetCloseConn of an unknown ID is tsneterr", s(ip.call("tsNetCloseConn", ["nobody"])).startswith("tsneterr:"))
    c.ok("tsNetGetStatus of an unknown ID is tsneterr", s(ip.call("tsNetGetStatus", ["nobody"])).startswith("tsneterr:"))
    ck("tsNetVersion", s(ip.call("tsNetVersion", [])), "1.4.5")
    ck("tsNetInit's result", s(ip.call("tsNetInit", [])), "")
    ip.call("tsNetClose", [])
    ck("tsNetClose frees every request", s(call("cuLiveCount", [])), "0")
    c.ok("tsNetGetStatus after close is tsneterr", s(ip.call("tsNetGetStatus", ["c1"])).startswith("tsneterr:"))
    r, out = ip.call_ref("tsNetGetSync", [base + "/hello", "", "", "", "", ""])
    ck("tsNet works again after tsNetClose", s(r), "hello world")
    ip.call("tsNetClose", [])


DB_LCS = None


def main(argv):
    global DB_LCS
    # `--source NAME PATH` drives a mutated copy of one shipped file in its
    # place (tools/test-script-vectors.py's whole mechanism); `--check` is
    # what a gate walker passes, and the check is the default run.
    # `--fail-fast` stops at the first failed check: the mutation test only
    # asks WHETHER a broken copy fails, and a broken copy otherwise waits
    # out every later check that depends on the one it broke.
    fail_fast = "--fail-fast" in argv[1:]
    args = [a for a in argv[1:] if a not in ("--check", "--fail-fast")]
    while len(args) >= 3 and args[0] == "--source":
        for i, p in enumerate(SOURCES):
            if os.path.basename(p) == args[1]:
                SOURCES[i] = args[2]
                break
        else:
            print("check-script-vectors: no shipped file named %s" % args[1])
            return 2
        args = args[3:]
    if args:
        print("usage: check-script-vectors.py [--check] [--fail-fast] [--source NAME PATH]...")
        return 2
    lib = find_library()
    if lib is None:
        msg = ("check-script-vectors: SKIP - no built curlxt library (set CURLXT_LIB, "
               "or commit src/code/x86_64-linux/curlxt.so); the tsNet layer did not run")
        print(msg)
        return 1 if os.environ.get("CURLXT_REQUIRE_LIB") == "1" else 0
    if not os.path.isfile(RUNNER):
        print("check-script-vectors: %s is not present: clone "
              "https://github.com/SethMorrowSoftware/RipTide beside this checkout "
              "as ../riptide, or point XTALK_SIBLING_RIPTIDE / XTALK_SIBLINGS at it."
              % RUNNER, file=sys.stderr)
        return 2
    DB = load_runner()
    DB_LCS = DB.LCS
    # A library older than the binding (a committed binary that predates an
    # ABI change) fails here, by name, rather than as a missing symbol
    # somewhere below. It is a failure, not a skip: the layers did not run.
    have = ctypes.CDLL(lib).cux_abi_version()
    want = lcb_tables()[0]["kABIVersion"]
    if have != want:
        print("check-script-vectors: FAIL - %s is ABI %d and src/curl.lcb is ABI %d: the "
              "library predates the binding (the suite's release-binaries dispatch "
              "rebuilds the committed ones); the script layers did not run"
              % (lib, have, want))
        return 1
    lcb = Lcb(lib)
    httpd = TServer(("127.0.0.1", 0), Handler)
    smtpd = TSmtp(("127.0.0.1", 0), SmtpHandler)
    wsd = TWs(("127.0.0.1", 0), WsHandler)
    servers = [httpd, smtpd, wsd]
    base = "http://127.0.0.1:%d" % httpd.server_address[1]
    ws = "ws://127.0.0.1:%d" % wsd.server_address[1]
    c = Checker(fail_fast)
    tmp = tempfile.mkdtemp(prefix="curlxt-vectors-")
    wss = cert = None
    note = ""
    try:
        # wss:// needs a certificate, and making one needs the openssl
        # command. Without it the TLS checks do not run and the last line
        # says so; where a skip is a failure (CURLXT_REQUIRE_LIB=1, the
        # native lane) this one is too.
        made = make_certificate(tmp)
        if made is None:
            if os.environ.get("CURLXT_REQUIRE_LIB") == "1":
                print("check-script-vectors: FAIL - no openssl command to make the wss:// "
                      "test certificate, and CURLXT_REQUIRE_LIB=1 allows no skip")
                return 1
            note = "; wss:// NOT run: no openssl command to make a certificate"
        else:
            cert = made[0]
            wssd = TWss(("127.0.0.1", 0), WsHandler)
            wssd.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            wssd.context.load_cert_chain(made[0], made[1])
            servers.append(wssd)
            wss = "wss://127.0.0.1:%d" % wssd.server_address[1]
        for srv in servers:
            threading.Thread(target=srv.serve_forever, daemon=True).start()
        world = DB.World(tmp)
        DB.install_engine_functions(world)
        DB.LCS.HASHES.update(lcb.natives())
        ip = make_interp(DB, world, build_source())
        try:
            drive(c, ip, base, smtpd.server_address[1], tmp, ws, wss, cert)
        except StopAtFirst:
            pass
    finally:
        for srv in servers:
            srv.shutdown()
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    if c.failed:
        print("check-script-vectors: FAIL (%d of %d)\n%s" % (len(c.failed), c.n, "\n".join(c.failed)))
        return 1
    if c.n < FLOOR:
        print("check-script-vectors: FAIL - only %d checks ran (floor %d)" % (c.n, FLOOR))
        return 1
    print("check-script-vectors: OK (%d checks: the shipped helpers and tsNet layers over %s%s)"
          % (c.n, os.path.basename(lib), note))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
