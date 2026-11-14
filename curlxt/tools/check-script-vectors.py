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
SMTP server this file runs on 127.0.0.1. Nothing touches the network.

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

import ctypes
import http.server
import importlib.util
import os
import re
import socket
import socketserver
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
FLOOR = 90


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
        }


# ------------------------------------------------------------ the checks

class Checker(object):
    def __init__(self):
        self.n = 0
        self.failed = []

    def ck(self, label, got, want):
        self.n += 1
        if got != want:
            self.failed.append("  %s: got %r, want %r" % (label, got, want))

    def ok(self, label, cond):
        self.ck(label, bool(cond), True)


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


def drive(c, ip, base, smtp_port, tmp):
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
    args = [a for a in argv[1:] if a != "--check"]
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
        print("usage: check-script-vectors.py [--check] [--source NAME PATH]...")
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
    lcb = Lcb(lib)
    httpd = TServer(("127.0.0.1", 0), Handler)
    smtpd = TSmtp(("127.0.0.1", 0), SmtpHandler)
    for srv in (httpd, smtpd):
        threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % httpd.server_address[1]
    c = Checker()
    tmp = tempfile.mkdtemp(prefix="curlxt-vectors-")
    try:
        world = DB.World(tmp)
        DB.install_engine_functions(world)
        DB.LCS.HASHES.update(lcb.natives())
        ip = make_interp(DB, world, build_source())
        drive(c, ip, base, smtpd.server_address[1], tmp)
    finally:
        httpd.shutdown()
        smtpd.shutdown()
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    if c.failed:
        print("check-script-vectors: FAIL (%d of %d)\n%s" % (len(c.failed), c.n, "\n".join(c.failed)))
        return 1
    if c.n < FLOOR:
        print("check-script-vectors: FAIL - only %d checks ran (floor %d)" % (c.n, FLOOR))
        return 1
    print("check-script-vectors: OK (%d checks: the shipped helpers and tsNet layers over %s)"
          % (c.n, os.path.basename(lib)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
