#!/usr/bin/env python3
"""check-script-vectors.py - run the SHIPPED src/nocloudquickshare.livecodescript
against tests/fileserver_golden.py's mirrors, headlessly, through the family's
interpreter.

WHY THIS EXISTS. Until this file, nocloud's whole correctness net was the golden:
a pure-Python MIRROR of each security- and framing-critical helper, pinned to
vectors. The golden proves the mirror; nothing proved the SCRIPT. The only tool
that had ever read src/nocloudquickshare.livecodescript was the static checker,
which validates balance, quoting and the token traps and cannot tell whether
qsEditSafePath refuses "../etc/passwd" or qsHttpParseHead takes the LAST of two
Content-Lengths. Every other member with a script layer closed that gap with a
gate shaped like this one (coinxt, nostrxt, riptide, and coinxt's wallet); the
member's CLAUDE.md still said "there is no headless way to compile or run a
.livecodescript", which was true of the engine and no longer true of the tree.

WHAT IT DOES. It loads the shipped script through riptide's DemoInterp (the
stack-shaped runner over the drift-gated lcs-interp.py; coinxt's wallet gate
imports it the same way), and for every helper the golden mirrors it calls the
SCRIPT on the golden's own inputs and requires the golden's MIRROR to give the
same answer. The inputs are listed here once; the expected values are never
typed - they are whatever the mirror computes, and the golden separately holds
the mirror to its pinned vectors. So the chain is: vector -> mirror (golden),
mirror -> script (here). A hand-copied expected value would be a third copy of
the truth, which is this tree's recorded way for numbers to go stale.

WHAT IT IS NOT. An approximation of the engine, not the engine. Nothing here
promotes a handler out of "verified statically; needs an OXT pass" - what it
settles is LOGIC, not parser behaviour. The interpreter's header carries the
modelled subset and its named divergences; the one that matters most here is
that `is`, `contains`, `begins with` and `ends with` are modelled CASE-SENSITIVE
where the engine folds case. Every helper driven here is either
case-indifferent by construction or compares through toLower first.

THE SPELLINGS THIS FILE TEACHES, AND WHERE. nocloud writes nine forms the
shared interpreter has never modelled: `repeat for each char`, a bare `repeat`
(the engine's `repeat forever`), `delete char N of X` / `delete the last char
of X`, `the last item|char|line|word of X`, `the round of X`, `the number of
bytes IN X` (the base accepts only `of`), `^`, text ORDERING under `<` and `>`
(the runner refuses a non-numeric operand), and the engine functions toUpper /
toLower / urlDecode / byteOffset. They are modelled in a SUBCLASS in this file
rather than in lcs-interp.py, following the precedent coinxt's wallet gate set
for `the number of controls`: the shared interpreter is byte-identical in two
members and re-verified by four gates, so a change there rides on all of them,
and a spelling only this member writes does not earn that. If a second member
starts writing one of these, promote it to the base then. Each model states
its engine rule beside it; `the round of` rounds half AWAY from zero, which is
the engine's rule and the golden's _round1, and NOT python's round().

WHAT IS DELIBERATELY NOT DRIVEN, each with the reason - a partial gate read as
a whole one is worse than none:
  - qsFsServePath  (traversal_ok)     a serving COMMAND over a Tor stream: the
                                       ".." decision sits between an access log
                                       and the whole route/static pipeline
  - qsCwServe      (capability_route) the clearweb accept handler, same shape,
                                       over the socket state
  - qsFileSizeSeek (file_size_probe)  `open file` / `seek` / `read from file`:
                                       real file I/O the interpreter models
                                       nowhere, and the golden's mirror is of
                                       the ARITHMETIC, not the I/O
  - {{now}} in qsTemplateValue        the mirror returns "" for the clock token
                                       by its own comment; here it is asserted
                                       against the modelled clock directly
The two send commands (qsFsSendText / qsCwSendText, the golden's
http_text_response) ARE driven: their writes are intercepted at statement
level and compared byte for byte, HEAD suppression included.

Mutation-tested on 2026-09-11 by editing a copy of the shipped script and
driving it with --source: qsHasDotSegment answering false for "/.git/config",
qsHttpParseHead keeping the FIRST Content-Length, qsEditSafePath admitting a
".." segment, and qsFsSendText sending a body for HEAD were each caught. The
same four are held by tools/test-script-vectors.py so the discrimination is
re-proven on every push rather than remembered.

Run from the member directory or anywhere:  python3 tools/check-script-vectors.py
"""
import importlib.util
import os
import re
import sys
import tempfile
from urllib.parse import unquote_plus

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
SUITE = os.path.dirname(MEMBER)
DEMO = os.path.join(MEMBER, "src", "nocloudquickshare.livecodescript")
GOLDEN = os.path.join(MEMBER, "tests", "fileserver_golden.py")
RUNNER = os.path.join(SUITE, "riptide", "tools", "check-demo-boot.py")

# The floor is a ratchet, not a target: a run that finds FEWER checks than this
# is a run where a section silently stopped executing (a helper renamed, an
# import failing inside a try) and must fail rather than print OK.
FLOOR = 380


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DB = _load("nc_demo_boot", RUNNER)
LCS = DB.LCS
G = _load("nc_golden", GOLDEN)
Thrown = LCS.Thrown


# --------------------------------------------------------------------------
# the spellings nocloud writes beyond the shared subset (see the header)

class NcExpr(DB.DemoExpr):
    def p_unary(self):
        # `^` - exponentiation, one tier above `*`; the base does not model
        # it because coinxt's layer avoids the operator (some OXT parsers
        # reject it inside a compound expression). nocloud writes it
        # parenthesised, `(2 ^ tExp)`, in the login backoff.
        v = super().p_unary()
        while True:
            self.ws()
            if self.i < len(self.s) and self.s[self.i] == "^":
                self.i += 1
                r = super().p_unary()
                v = LCS._exact(LCS._n(v) ** LCS._n(r))
                continue
            return v

    def p_cmp(self):
        # The runner's comparator, restated with ONE extension: `<` / `>` and
        # friends over operands that are NOT both numbers compare as TEXT,
        # case-insensitively (the engine's default; `the caseSensitive` is
        # never set in this app). The runner refuses those with a ValueError
        # out of _n, which is stricter than the engine - and qsUserRouteFind
        # breaks a specificity tie on `tKey < tBestKey`, two route keys.
        # Restated rather than delegated for the reason the runner gives for
        # restating the base: the operand is consumed before the operator is
        # seen, so a partial override cannot hand the tail back to super().
        v = self.p_concat()
        while True:
            save = self.i
            if self.kw("contains"):
                r = self.p_concat()
                v = str(LCS._disp(r)) in str(LCS._disp(v))
                continue
            if self.kw("begins"):
                assert self.kw("with"), "expected `with` in %r" % self.s
                r = self.p_concat()
                v = str(LCS._disp(v)).startswith(str(LCS._disp(r)))
                continue
            if self.kw("ends"):
                assert self.kw("with"), "expected `with` in %r" % self.s
                r = self.p_concat()
                v = str(LCS._disp(v)).endswith(str(LCS._disp(r)))
                continue
            if self.kw("is"):
                neg = bool(self.kw("not"))
                if self.kw("among"):
                    assert self.kw("the"), "expected `the` in %r" % self.s
                    word = self.kw("keys", "items", "lines")
                    assert word and self.kw("of"), \
                        "expected keys/items/lines `of` in %r" % self.s
                    target = self.p_concat()
                    if word == "keys":
                        hit = (isinstance(target, dict)
                               and str(LCS._disp(v)) in target)
                    else:
                        delim = (LCS.ITEM_DELIMITER[0] if word == "items"
                                 else LCS.LINE_DELIMITER[0])
                        parts = LCS._split_chunks(str(LCS._disp(target)), delim)
                        hit = str(LCS._disp(v)) in parts
                    v = (not hit) if neg else hit
                    continue
                save2 = self.i
                if self.kw("an", "a"):
                    word = self.kw("integer", "number", "array")
                    if word == "array":
                        hit = isinstance(v, dict)
                        v = (not hit) if neg else hit
                        continue
                    if word:
                        hit = LCS._is_numeric(v, word == "integer")
                        v = (not hit) if neg else hit
                        continue
                    self.i = save2
                r = self.p_concat()
                v = (not LCS._eq(v, r)) if neg else LCS._eq(v, r)
                continue
            self.ws()
            for op in (">=", "<=", "<>", ">", "<"):
                if self.s[self.i:self.i + len(op)] == op:
                    self.i += len(op)
                    r = self.p_concat()
                    if LCS._is_numeric(v, False) and LCS._is_numeric(r, False):
                        a, b = LCS._n(v), LCS._n(r)
                    else:
                        a, b = str(LCS._disp(v)).lower(), str(LCS._disp(r)).lower()
                    v = {">=": a >= b, "<=": a <= b, ">": a > b,
                         "<": a < b, "<>": a != b}[op]
                    break
            else:
                self.i = save
                return v

    def p_atom(self):
        self.ws()
        rest = self.s[self.i:]
        # `the last item|char|line|word of X` - the engine's last-chunk form.
        # The target binds tightly (an atom), so `the last char of X is Y`
        # leaves `is Y` to the comparator above.
        m = re.match(r'the\s+last\s+(item|char|line|word)\s+of\s+', rest, re.I)
        if m:
            self.i += m.end()
            unit = m.group(1).lower()
            s = str(LCS._disp(self.p_atom()))
            if unit == "char":
                return s[-1:]
            if unit == "word":
                w = s.split()
                return w[-1] if w else ""
            delim = LCS.ITEM_DELIMITER[0] if unit == "item" else LCS.LINE_DELIMITER[0]
            parts = LCS._split_chunks(s, delim)
            return parts[-1] if parts else ""
        # `the number of bytes IN X` - the base models `of`; `in` is the same
        # count (the engine accepts both prepositions).
        m = re.match(r'the\s+number\s+of\s+(bytes|chars|characters|items|lines|words)'
                     r'\s+in\s+', rest, re.I)
        if m:
            self.i += m.end()
            unit = m.group(1).lower()
            s = str(LCS._disp(self.p_concat()))
            if unit in ("bytes", "chars", "characters"):
                return len(s)
            if unit == "words":
                return len(s.split())
            if unit == "items":
                return len(LCS._split_chunks(s, LCS.ITEM_DELIMITER[0]))
            return len(LCS._split_chunks(s, LCS.LINE_DELIMITER[0]))
        # `the round of X` - half AWAY from zero (the engine's rule; python's
        # round() is banker's and would answer 2 for 2.5). Binds to the atom.
        m = re.match(r'the\s+round\s+of\s+', rest, re.I)
        if m:
            self.i += m.end()
            x = LCS._n(self.p_atom())
            import math
            r = math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)
            return LCS._exact(int(r))
        return super().p_atom()


class NcInterp(DB.DemoInterp):
    def __init__(self, src, world):
        self.sent = []          # (handler, [args]) for every intercepted write
        super().__init__(src, world)

    def eval_expr(self, expr, env):
        return NcExpr(self, env).parse(expr)

    def _args(self, rest, env):
        args = []
        rest = rest.strip()
        if rest:
            p = NcExpr(self, env)
            p.s, p.i = rest, 0
            while True:
                args.append(p.p_or())
                p.ws()
                if p.i < len(p.s) and p.s[p.i] == ",":
                    p.i += 1
                    continue
                break
            if p.i < len(p.s):
                raise SyntaxError("trailing input in call %r" % rest)
        return args

    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        low = line.lower()
        # ---- repeat for each char VAR in EXPR (a snapshot, like the base's
        # item form: the engine iterates the container as it was)
        m = re.match(r'repeat\s+for\s+each\s+char\s+(\w+)\s+in\s+(.+)$', line, re.I)
        if m:
            var = m.group(1).lower()
            inner, after = self._block(body, i, None, None)
            for ch in str(LCS._disp(self.eval_expr(m.group(2), env))):
                env[var] = ch
                try:
                    self._exec(inner, env)
                except LCS._Next:
                    pass
                except LCS._Exit:
                    break
            return after
        # ---- a bare `repeat` is `repeat forever`; the same runaway guard as
        # the base's, because an interpreter that can hang is one whose
        # failures nobody reads
        if low == "repeat":
            inner, after = self._block(body, i, None, None)
            guard = 0
            while True:
                guard += 1
                if guard > 2_000_000:
                    raise RuntimeError("repeat did not terminate")
                try:
                    self._exec(inner, env)
                except LCS._Next:
                    pass
                except LCS._Exit:
                    break
            return after
        # ---- delete the last char of X / delete char N of X (one index,
        # negative counted from the end; the base models only the N to M form)
        m = re.match(r'delete\s+the\s+last\s+char\s+of\s+(\w+)$', line, re.I)
        if m:
            tgt = m.group(1)
            s = str(LCS._disp(self.eval_expr(tgt, env)))
            self.assign(tgt, s[:-1], env)
            return i + 1
        m = re.match(r'delete\s+char\s+(.+?)\s+of\s+(\w+)$', line, re.I)
        if m and not re.search(r'\s+to\s+', m.group(1)):
            n = int(LCS._n(self.eval_expr(m.group(1), env)))
            tgt = m.group(2)
            s = str(LCS._disp(self.eval_expr(tgt, env)))
            if n < 0:
                n = len(s) + 1 + n
            if 1 <= n <= len(s):
                s = s[:n - 1] + s[n:]
            self.assign(tgt, s, env)
            return i + 1
        # ---- the transport writes, intercepted: OnionXT's stream write and
        # close, and the clearweb twin's two socket writers. Everything the
        # command computed is in the bytes it hands over, which is what the
        # golden's http_text_response pins.
        m = re.match(r'(oxWrite|oxCloseStream|qsCwWriteContinue|qsCwWriteClose|'
                     r'qsFsCleanup)\b\s*(.*)$', line, re.I)
        if m:
            self.sent.append((m.group(1), self._args(m.group(2), env)))
            return i + 1
        return super()._exec_stmt(body, i, env)


def install_engine_functions():
    """The engine functions nocloud calls that neither the base nor the runner
    models. byteOffset is the native scan qsHttpHeaderEnd probes for; modelling
    it means the FAST path runs here, and the driver forces the loop path too."""
    def _s(a):
        return str(LCS._disp(a))
    LCS.HASHES.update({
        "toupper": lambda a: _s(a[0]).upper(),
        "tolower": lambda a: _s(a[0]).lower(),
        # LiveCode's urlDecode turns '+' into a space as well as %xx (the golden's
        # query_param mirror says so and uses unquote_plus for the same reason)
        "urldecode": lambda a: unquote_plus(_s(a[0])),
        "byteoffset": lambda a: _s(a[1]).find(_s(a[0])) + 1,
    })


# --------------------------------------------------------------------------
# comparison

class Checker:
    def __init__(self):
        self.n = 0
        self.failed = []

    def ck(self, label, got, want):
        self.n += 1
        g, w = norm(got), norm(want)
        if g != w:
            self.failed.append("%s:\n    script %r\n    mirror %r" % (label, g, w))


def norm(v):
    """One shape for both sides: bools stay bools, numbers become their
    engine display, bytes become the latin-1 text the interpreter carries,
    None becomes empty, dicts and lists recurse."""
    if isinstance(v, bool):
        return v
    if v is None:
        return ""
    if isinstance(v, (bytes, bytearray)):
        return v.decode("latin-1")
    if isinstance(v, (int, float)):
        return str(LCS._disp(v))
    if isinstance(v, dict):
        return dict((str(k), norm(x)) for k, x in v.items())
    if isinstance(v, (list, tuple)):
        return [norm(x) for x in v]
    return str(v)


def b(s):
    """bytes fixture -> the str the interpreter carries."""
    return s.decode("latin-1") if isinstance(s, (bytes, bytearray)) else s


def boolish(v):
    if isinstance(v, bool):
        return v
    return str(v).lower() == "true"


# --------------------------------------------------------------------------
# the drive, section by section in the golden's order

def drive(c, ip, world, sandbox):
    call = ip.call
    total = 1000

    # -- byte ranges --
    for rng in ["", "bytes=0-499", "bytes=500-999", "bytes=500-", "bytes=0-",
                "bytes=999-", "bytes=-500", "bytes=-5000", "bytes=0-100000",
                "bytes=1000-", "bytes=1500-2000", "bytes=5-3", "bytes=abc-10",
                "bytes=10-xyz", "bytes=-", "bytes=0-499,600-799", "chunks=0-1",
                "bytes=0-0"]:
        c.ck("qsFsParseRange(%r)" % rng, call("qsFsParseRange", [rng, total]),
             G.parse_range(rng, total))
    for rng in ["", "bytes=0-"]:
        c.ck("qsFsParseRange(%r) on an empty file" % rng,
             call("qsFsParseRange", [rng, 0]), G.parse_range(rng, 0))

    # -- dotfile guard --
    for path in ["/", "", "/file.txt", "/notes.d/file", "/a/b.txt", "/.git/config",
                 "/a/.env", "/dir/.hidden/", "/.", "/.well-known/x"]:
        c.ck("qsHasDotSegment(%r)" % path, boolish(call("qsHasDotSegment", [path])),
             G.has_dot_segment(path))

    # -- MIME and the listing icon --
    for path in ["index.html", "a.PNG", "movie.mp4", "song.MP3", "doc.pdf",
                 "archive.zip", "data.bin", "noextension", "a.tar.gz", "app.wasm",
                 "module.mjs", "feed.xml", "bundle.js.map", "site.webmanifest",
                 "f.woff", "font.WOFF2", "f.ttf", "f.otf", "f.eot", "pic.avif",
                 "data.csv"]:
        c.ck("qsFsMime(%r)" % path, call("qsFsMime", [path]), G.mime(path))
    for name, is_dir in [("photos", True), ("index.html", False), ("app.min.js", False),
                         ("styles.css", False), ("logo.PNG", False), ("clip.mp4", False),
                         ("song.flac", False), ("notes.txt", False), ("readme.md", False),
                         ("data.csv", False), ("archive.tar.gz", False), ("manual.pdf", False),
                         ("photo.heic", False), ("blob.bin", False), ("Makefile", False)]:
        c.ck("qsFsIcon(%r)" % name, call("qsFsIcon", [name, is_dir]), G.fs_icon(name, is_dir))

    # -- HTML escape --
    for text in ["<script>alert('x')</script>", "a & <b>", 'say "hi"']:
        c.ck("qsFsHtmlEscape(%r)" % text, call("qsFsHtmlEscape", [text]), G.html_escape(text))

    # -- SPA fallback: the leaf heuristic, with a root index.html in the sandbox
    # (the script asks the filesystem first; the mirror covers the heuristic)
    root = os.path.join(sandbox, "site")
    os.makedirs(root, exist_ok=True)
    with open(os.path.join(root, "index.html"), "w") as fh:
        fh.write("<html>")
    for path in ["/dashboard", "/users/42", "/deep/route/here", "/", "/a.b/c",
                 "/app.js", "/assets/logo.png", "/favicon.ico", "/a/b.min.js", "/style.css"]:
        got = str(call("qsSiteSpaTarget", [root, path]))
        c.ck("qsSiteSpaTarget(%r) is a route" % path, got != "", G.spa_is_route(path))
        if G.spa_is_route(path):
            c.ck("qsSiteSpaTarget(%r) names the index" % path, got, root + "/index.html")
    c.ck("qsSiteSpaTarget with no index.html falls back to nothing",
         call("qsSiteSpaTarget", [os.path.join(sandbox, "empty"), "/dashboard"]), "")

    # -- HTTP framing, on BOTH header-scan paths: the native byteOffset the
    # script probes for (modelled here) and the interpreted loop it keeps for
    # an engine whose scan fails the probe. Same contract, both driven.
    get_full = b"GET /_qs/info HTTP/1.1\r\nHost: x\r\n\r\n"
    post_hdr = b"POST /api HTTP/1.1\r\nContent-Length: 5\r\n\r\n"
    for mode in ("fast", "loop"):
        ip.globals["shdrscanmode"] = "" if mode == "fast" else "loop"
        tag = " [%s]" % mode
        c.ck("header end GET" + tag, call("qsHttpHeaderEnd", [b(get_full)]),
             G.http_header_end(get_full))
        if mode == "fast":
            c.ck("the byteOffset probe chose the fast path", ip.globals["shdrscanmode"], "fast")
        for label, data in [("complete GET", get_full),
                            ("incomplete head", b"GET / HTTP/1.1\r\nHost: x\r\n"),
                            ("post no body yet", post_hdr),
                            ("post partial body", post_hdr + b"hel"),
                            ("post full body", post_hdr + b"hello"),
                            ("post over-long body", post_hdr + b"helloEXTRA"),
                            ("post non-integer CL",
                             b"POST /api HTTP/1.1\r\nContent-Length: abc\r\n\r\n")]:
            c.ck("qsHttpReqComplete " + label + tag,
                 boolish(call("qsHttpReqComplete", [b(data)])), G.http_req_complete(data))
        pair = get_full + post_hdr + b"hello"
        pair2 = post_hdr + b"hello" + get_full
        for label, data in [("GET exact", get_full),
                            ("GET incomplete head", b"GET / HTTP/1.1\r\nHost: x\r\n"),
                            ("POST with body", post_hdr + b"hello"),
                            ("pipelined pair", pair), ("pipelined pair 2", pair2),
                            ("non-integer CL",
                             b"POST /api HTTP/1.1\r\nContent-Length: abc\r\n\r\n")]:
            c.ck("qsHttpReqLength " + label + tag, call("qsHttpReqLength", [b(data)]),
                 G.http_req_length(data))
    ip.globals["shdrscanmode"] = ""

    # -- the head parser: the smuggling lever, the pseudo-field namespace, the
    # request line. The WHOLE map is compared, not the four keys the golden
    # reads, so a key one side does not know about is a failure here - which
    # is how the mirror's invented `__resource` and missing `__version` were
    # found. The one rule applied is the engine's own: an UNSET key reads as
    # empty, so both maps are compared over the union of their keys with
    # absent-as-empty (the script never sets `__query` without a `?`).
    def head_of(raw):
        return raw[:G.http_header_end(raw) - 1]

    def as_read(m):
        m = norm(m)
        return dict((k, v) for k, v in m.items() if v != "")

    def ck_head(label, raw):
        c.ck("qsHttpParseHead " + label, as_read(call("qsHttpParseHead", [b(raw)])),
             as_read(G.parse_head(raw)))
    for label, raw in [
            ("duplicate Content-Length",
             b"POST /x HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 10\r\n\r\n"),
            ("identical repeat",
             b"POST /x HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n"),
            ("pseudo-field injection",
             b"GET /safe HTTP/1.1\r\n__path: /../../etc/passwd\r\n"
             b"__method: DELETE\r\n__params: forged\r\nHost: h\r\n\r\n"),
            ("request line", b"GET /a/b?x=1&y=2 HTTP/1.1\r\nHost: h\r\n\r\n")]:
        ck_head(label, head_of(raw))
    ck_head("no query", b"GET /a HTTP/1.1\r\nHost: h")
    ck_head("no version", b"GET /a\r\nHost: h")

    # -- JSON escaping --
    for s in ["hello", 'a"b', "c:\\path", "a\r\nb", "x\ty", '\\"']:
        c.ck("qsJsonEscape(%r)" % s, call("qsJsonEscape", [s]), G.json_escape(s))

    # -- the editor's write-path confinement, THE linchpin --
    R = "/srv"
    for rel in ["index.html", "css/app.css", "/css/app.css", "a//b.txt", "./a.txt",
                "a/./b.txt", ".env", "../etc/passwd", "a/../b", "..", "...",
                "my..file.txt", "C:/Windows/win.ini", "http://evil/x", "", "/",
                "\\..\\..\\x", "a\x00b.txt", "a\tb.txt"]:
        c.ck("qsEditSafePath(%r)" % rel, call("qsEditSafePath", [R, rel]),
             G.edit_safe_path(R, rel))
    for rel in ["c.png", "a/c.png", "a/b/c.png", "assets/uploads/pic.jpg", "a//b/c.png",
                "a/./b/c.png", "a\\b\\c.png", "a/b/", "a/b/.", "a/b/./", ".", "/", ""]:
        c.ck("qsEditParentDirs(%r)" % rel, call("qsEditParentDirs", [rel]),
             "\n".join(G.edit_parent_dirs(rel)))

    # -- the Content-Disposition filename sanitiser --
    for name in ["report.pdf", "my file.txt", 'a"b.txt', "back\\slash", "nau\x00gh\tty",
                 "caf\u00e9.png", "", "\x01\x02"]:
        c.ck("qsSafeFilename(%r)" % name, call("qsSafeFilename", [name]), G.safe_filename(name))

    # -- transfer-row formatting --
    for bps in [0, -5, 512, 1024, 1536, 1048576, 1300000, 1073741824, 2000]:
        c.ck("qsRateShort(%d)" % bps, call("qsRateShort", [bps]), G.rate_short(bps))
    for secs in [-1, 0, 45, 59, 60, 125, 3599, 3600, 3725, 86399, 86400, 200000, 44.9]:
        c.ck("qsEtaShort(%r)" % secs, call("qsEtaShort", [secs]), G.eta_short(secs))

    # -- the editor's LAN-first gate --
    for conn in ["cw:192.168.1.5:52000", "cw:10.0.0.9:1234", "cw:127.0.0.1:5000",
                 "cw:172.16.4.4:80", "cw:172.31.9.9:80", "cw:172.32.0.1:80",
                 "cw:100.64.0.1:80", "cw:169.254.1.1:80", "cw:::1:5000", "cw:8.8.8.8:443",
                 "cw:203.0.113.7:12345", "cw:192.168.0.1:80|2", "cw:1.2.3.4:80|3",
                 "ox:streamhandle42", "ox:anything"]:
        c.ck("qsEditIsLocal(%r)" % conn, boolish(call("qsEditIsLocal", [conn])),
             G.edit_is_local(conn))

    # -- query-string values --
    for query, name in [("path=css/app.css", "path"), ("path=a%2Fb.txt", "path"),
                        ("path=a%20b.txt", "path"), ("path=a+b.txt", "path"),
                        ("path=a%2Bb.txt", "path"), ("x=1&path=main.js", "path"),
                        ("path=main.js&x=1", "path"), ("path=x=y", "path"), ("path=", "path"),
                        ("q=hello", "path"), ("", "path"), ("foo=bar&foo=baz", "foo")]:
        c.ck("qsQueryParam(%r,%r)" % (query, name), call("qsQueryParam", [query, name]),
             G.query_param(query, name))

    # -- HTTP-date: the pure formatter against the mirror (which the golden
    # holds against the stdlib), across the leap and century edges --
    for epoch in [0, 1, 59, 60, 3599, 3600, 86399, 86400, 951782400, 951868800,
                  1078012800, 1709164800, 1709251200, 1751812800, 1767225599,
                  1735689600, 2147483647, 4102444800, 4107456000, 4133980800]:
        c.ck("qsHttpDate(%d)" % epoch, call("qsHttpDate", [epoch]), G.http_date(epoch))
    c.ck("qsHttpDate(-1)", call("qsHttpDate", [-1]), G.http_date(-1))
    c.ck("qsHttpDate('x')", call("qsHttpDate", ["x"]), G.http_date("x"))

    # -- Allow, over the built-in table and the per-root user table --
    def routes(keys, cors=False):
        return dict((k, {"cors": "true"} if cors else {"handler": "x"}) for k in keys)
    ip.globals["shttproutes"] = routes(["GET /_qs/info", "GET /_edit", "POST /_edit/login",
                                        "GET /_edit/api/list", "GET /_edit/api/read",
                                        "PUT /_edit/api/write"])
    ip.globals["suserroutes"] = {}
    for path in ["/_edit/login", "/_edit/api/write", "/_qs/info", "/nope"]:
        c.ck("qsHttpAllow(%r)" % path, call("qsHttpAllow", [path, ""]),
             G.http_allow(list(ip.globals["shttproutes"]), path))
    ip.globals["shttproutes"] = routes(["POST /x", "PUT /x", "DELETE /x", "GET /x"])
    c.ck("qsHttpAllow multi", call("qsHttpAllow", ["/x", ""]),
         G.http_allow(list(ip.globals["shttproutes"]), "/x"))
    ip.globals["shttproutes"] = {}
    uroutes = ["POST /api/submit", "GET /api/hello", "PUT /api/submit"]
    ip.globals["suserroutes"] = {"/r": routes(uroutes)}
    for path in ["/api/submit", "/api/hello", "/nope"]:
        c.ck("qsHttpAllow user(%r)" % path, call("qsHttpAllow", [path, "/r"]),
             G.http_allow([], path, uroutes))
    ip.globals["shttproutes"] = routes(["POST /dup"])
    ip.globals["suserroutes"] = {"/r": routes(["POST /dup"])}
    c.ck("qsHttpAllow dedup across the tables", call("qsHttpAllow", ["/dup", "/r"]),
         G.http_allow(["POST /dup"], "/dup", ["POST /dup"]))
    ip.globals["shttproutes"] = {}
    for path, ukeys in [
            ("/api/files/readme.txt",
             ["DELETE /api/files/:name", "GET /api/files/:name", "PUT /api/other/:x"]),
            ("/api/files/x", ["POST /api/files/x", "POST /api/files/:n"]),
            ("/api/files/a/b", ["DELETE /api/files/:n"]),
            ("/_qs/info", ["DELETE /:x/info"])]:
        ip.globals["suserroutes"] = {"/r": routes(ukeys)}
        c.ck("qsHttpAllow param(%r)" % path, call("qsHttpAllow", [path, "/r"]),
             G.http_allow([], path, ukeys))

    # -- CORS preflight: only where a cors route matches the path --
    cors_keys = ["POST /api/submit", "GET /api/open"]
    ip.globals["suserroutes"] = {"/r": routes(cors_keys, cors=True)}
    for path, allow in [("/api/submit", "GET, HEAD, OPTIONS, POST"),
                        ("/api/other", "GET, HEAD, OPTIONS")]:
        c.ck("qsCorsPreflight(%r)" % path, call("qsCorsPreflight", ["/r", path, allow]),
             G.cors_preflight(cors_keys, path, allow))
    ip.globals["suserroutes"] = {"/r": {}}
    c.ck("qsCorsPreflight with no routes",
         call("qsCorsPreflight", ["/r", "/api/submit", "GET, HEAD, OPTIONS"]),
         G.cors_preflight([], "/api/submit", "GET, HEAD, OPTIONS"))
    c.ck("qsCorsPreflight with no root",
         call("qsCorsPreflight", ["", "/api/submit", "GET, HEAD, OPTIONS"]), "")
    for keys, path, allow in [(["POST /api/thing/:id"], "/api/thing/42", "GET, HEAD, OPTIONS, POST"),
                              (["POST /api/thing/:id"], "/api/other/42", "GET, HEAD, OPTIONS"),
                              (["GET /:x/info"], "/_qs/info", "GET, HEAD, OPTIONS")]:
        ip.globals["suserroutes"] = {"/r": routes(keys, cors=True)}
        c.ck("qsCorsPreflight param %r" % path, call("qsCorsPreflight", ["/r", path, allow]),
             G.cors_preflight(keys, path, allow))
    ip.globals["suserroutes"] = {}

    # -- conditional GET --
    c.ck("qsHttpWeakETag", call("qsHttpWeakETag", [1000, 42, 0]), G.http_weak_etag(1000, 42, 0))
    et = G.http_weak_etag(1000, 42, 3)
    for tag in ['W/"1000-42-3"', '"1000-42-3"', ' W/"abc" ', 'W/""']:
        c.ck("qsETagCore(%r)" % tag, call("qsETagCore", [tag]), G.etag_core(tag))
    for header in ["", "*", 'W/"1000-42-3"', '"1000-42-3"', 'W/"1000-42-2"',
                   'W/"9-9-9", W/"1000-42-3"', 'W/"9-9-9"']:
        c.ck("qsIfNoneMatch(%r)" % header, boolish(call("qsIfNoneMatch", [header, et])),
             G.if_none_match(header, et))

    # -- the always-sent header block, on a fixed clock --
    fh_epoch = 1751812800
    LCS.SECONDS[0] = fh_epoch
    fh_extra = G.http_extra_headers(fh_epoch)
    c.ck("qsHttpExtraHeaders", call("qsHttpExtraHeaders", []), fh_extra)

    # -- the disposition leaf and line --
    for path in ["movie.mp4", "a/b/c.txt", "a\\b\\x.png", "/abs/dir/f.pdf", "dir/"]:
        c.ck("qsFsLeaf(%r)" % path, call("qsFsLeaf", [path]), G.fs_leaf(path))
    for formime, headers in [("a/movie.mp4", {"__query": ""}), ("movie.mp4", {"__query": "dl=1"}),
                             ('a"b.txt', {"__query": ""})]:
        c.ck("qsHttpDisposition(%r)" % formime, call("qsHttpDisposition", [formime, headers]),
             G.http_disposition(formime, headers))

    # -- the ONE file-head plan both transport twins call --
    fh_get = {"__method": "GET", "__query": "", "range": "", "if-none-match": ""}
    fh_inm = dict(fh_get, **{"if-none-match": 'W/"1000-42-0"'})
    for label, size, formime, headers, override, extra, seed, gen in [
            ("200 full GET", 1000, "movie.mp4", fh_get, "", "", 42, 0),
            ("206 range", 1000, "movie.mp4", dict(fh_get, range="bytes=500-"), "", "", 42, 0),
            ("304 match", 1000, "movie.mp4", fh_inm, "", "", 42, 0),
            ("range beats 304", 1000, "movie.mp4", dict(fh_inm, range="bytes=0-9"), "", "", 42, 0),
            ("stale gen re-serves", 1000, "movie.mp4", fh_inm, "", "", 42, 1),
            ("416 unsatisfiable", 1000, "movie.mp4", dict(fh_get, range="bytes=5000-"), "", "", 42, 0),
            ("override + extra", 10, "data.bin", dict(fh_get, __query="dl=1"),
             "application/json; charset=utf-8", "X-Extra: 1\r\n", 7, 2),
            ("param file route", 10, "big.bin", dict(fh_get, range="bytes=0-3"),
             "application/octet-stream", "X-Route: dl\r\n", 42, 0)]:
        ip.globals["shttpetagseed"] = seed
        ip.globals["seditgen"] = gen
        c.ck("qsHttpFileHead " + label,
             call("qsHttpFileHead", [size, formime, headers, override, extra]),
             G.http_file_head(size, formime, headers, override, extra, seed, gen, fh_epoch))

    # -- the one-shot text reply, both twins, with the writes intercepted --
    tx = "hello, HEAD"
    ctype = "text/plain; charset=utf-8"

    def fs_send(status, body, extra, method):
        ip.globals["sfsmethod"] = {"s1": method}
        ip.sent = []
        call("qsFsSendText", ["s1", status, ctype, body, extra])
        writes = [a for h, a in ip.sent if h.lower() == "oxwrite"]
        closes = [h for h, a in ip.sent if h.lower() == "oxclosestream"]
        assert len(writes) == 1 and len(closes) == 1, ip.sent
        return writes[0][1]

    def cw_send(status, body, extra, method, keep):
        ip.globals["scwmethod"] = {"k1": method}
        ip.globals["scwkeep"] = {"k1": "true" if keep else "false"}
        ip.globals["scwreqcount"] = {"k1": 0}
        ip.sent = []
        call("qsCwSendText", ["k1", status, ctype, body, extra])
        assert len(ip.sent) == 1, ip.sent
        h, a = ip.sent[0]
        assert h.lower() == ("qscwwritecontinue" if keep else "qscwwriteclose"), ip.sent
        return a[1]

    c.ck("qsFsSendText GET", fs_send("200 OK", tx, "", "GET"),
         G.http_text_response("200 OK", ctype, tx, "", fh_epoch, "GET"))
    c.ck("qsFsSendText HEAD sends the GET head and no body", fs_send("200 OK", tx, "", "HEAD"),
         G.http_text_response("200 OK", ctype, tx, "", fh_epoch, "HEAD"))
    c.ck("qsFsSendText extra header (the 405's Allow)",
         fs_send("405 Method Not Allowed", "Method not allowed.", "Allow: GET, HEAD, OPTIONS\r\n", "GET"),
         G.http_text_response("405 Method Not Allowed", ctype, "Method not allowed.",
                              "Allow: GET, HEAD, OPTIONS\r\n", fh_epoch, "GET"))
    c.ck("qsCwSendText GET, connection closing", cw_send("200 OK", tx, "", "GET", False),
         G.http_text_response("200 OK", ctype, tx, "", fh_epoch, "GET", False))
    c.ck("qsCwSendText GET keep-alive is the only twin difference",
         cw_send("200 OK", tx, "", "GET", True),
         G.http_text_response("200 OK", ctype, tx, "", fh_epoch, "GET", True))
    c.ck("qsCwSendText HEAD keep-alive sends no body", cw_send("200 OK", tx, "", "HEAD", True),
         G.http_text_response("200 OK", ctype, tx, "", fh_epoch, "HEAD", True))

    # -- editor login backoff --
    for fails, last_ms, now_ms in [(0, None, 1000), (3, 500, 600), (4, 1000, 1000),
                                   (4, 1000, 1500), (4, 1000, 2000), (5, 1000, 1000),
                                   (6, 1000, 1000), (9, 1000, 1000), (100, 1000, 1000),
                                   (5, None, 1000), (4, 5000, 3000)]:
        c.ck("qsEditLoginWait(%r,%r,%r)" % (fails, last_ms, now_ms),
             call("qsEditLoginWait", [fails, "" if last_ms is None else last_ms, now_ms]),
             G.edit_login_wait(fails, last_ms, now_ms))

    # -- user-route path validation and the reserved-namespace predicate --
    for path in ["/api/hello", "/hello", "/go/docs", "/normal-path_123", "/_qsx", "",
                 "api/x", "/../etc", "/a/../b", "/_qs", "/_qs/info", "/_edit",
                 "/_edit/login", "/a\nb"]:
        c.ck("qsUserPathValid(%r)" % path, boolish(call("qsUserPathValid", [path])),
             G.user_path_valid(path))
    for path in ["/_qs", "/_qs/info", "/_qs/", "/_edit", "/_edit/api/write", "/_qsx",
                 "/_editor", "/a/_qs", "/_q", "/", ""]:
        c.ck("qsHttpReservedPath(%r)" % path, boolish(call("qsHttpReservedPath", [path])),
             G.reserved_path(path))

    # -- HEAD route lookup --
    lk_builtin = ["GET /_qs/info", "GET /_qs/transparency", "POST /_edit/login"]
    lk_user = ["GET /api/hello", "HEAD /probe", "GET /probe", "POST /api/submit"]
    for method, path, keys in [("HEAD", "/_qs/info", lk_builtin), ("HEAD", "/api/hello", lk_user),
                               ("HEAD", "/probe", lk_user), ("GET", "/api/hello", lk_user),
                               ("GET", "/nope", lk_user), ("POST", "/api/submit", lk_user),
                               ("POST", "/probe", lk_user), ("HEAD", "/nope", lk_user),
                               ("head", "/api/hello", lk_user), ("HEAD", "/api/hello", []),
                               ("GET", "/api/hello", [])]:
        table = routes(keys) if keys else ""
        c.ck("qsRouteLookupKey(%r,%r)" % (method, path),
             call("qsRouteLookupKey", [method, path, table]),
             G.route_lookup_key(method, path, keys))

    # -- :param patterns --
    for key in ["GET /api/x", "DELETE /api/files/:name", "GET /a b", "NOSPACE"]:
        c.ck("qsRouteKeyPath(%r)" % key, call("qsRouteKeyPath", [key]), G.route_key_path(key))
    for path in ["/api/hello", "/api/:name", "/api/files/:name", "/api/x:y", "/"]:
        c.ck("qsRouteHasParams(%r)" % path, boolish(call("qsRouteHasParams", [path])),
             G.route_has_params(path))
    for path in ["/api/hello", "/api/:a", "/api/:a/:b", "/api/:a/sub/:b"]:
        c.ck("qsRouteParamCount(%r)" % path, call("qsRouteParamCount", [path]),
             G.route_param_count(path))
    for path in ["/api/:name", "/api/files/:name", "/api/:a/:b", "/api/:a/sub/:b", "/dl/:tag/",
                 "/api/hello", "/:x", "/:x/y", "/_qs/:x", "/_edit/:x", "/api/:", "/api/:na-me",
                 "/api/:x/:x", "/files/:a..b", "api/:x"]:
        c.ck("qsUserPatternValid(%r)" % path, boolish(call("qsUserPatternValid", [path])),
             G.user_pattern_valid(path))
    for pattern, path in [("/api/files/:name", "/api/files/readme.txt"), ("/api/:a/:b", "/api/x/y"),
                          ("/api/files/:name", "/api/files/"), ("/api/files/:name", "/api/files/a/b"),
                          ("/api/files/:name", "/api/other/x"), ("/dl/:tag/", "/dl/v1/"),
                          ("/dl/:tag", "/dl/v1/"), ("/dl/:tag/", "/dl/v1"),
                          ("/api/greet/:name", "/api/greet/:name"), ("/:x/info", "/_qs/info"),
                          ("/_qs/:x", "/_qs/info"), ("/files/:x", "/_qs/info"), ("/:x", "/_edit"),
                          ("/:x/login", "/_edit/login")]:
        got = call("qsRouteMatch", [pattern, path])
        # the script answers "no" (a non-array) where the mirror answers None
        c.ck("qsRouteMatch(%r,%r)" % (pattern, path),
             None if not isinstance(got, dict) else got, G.route_match(pattern, path))
    pat_keys = ["GET /api/hello", "GET /api/files/:name", "POST /api/files/:name", "GET /api/:a/:b"]
    for keys, method, path in [(pat_keys, "GET", "/api/files/x"), (pat_keys, "POST", "/api/files/x"),
                               (pat_keys, "DELETE", "/api/files/x"), (pat_keys, "GET", "/api/x/y"),
                               (pat_keys, "GET", "/api/hello"), (pat_keys, "GET", "/_qs/info"),
                               (["GET /api/files/:b", "GET /api/:a/x"], "GET", "/api/files/x"),
                               (["GET /:x/info"], "GET", "/_qs/info"),
                               (["GET /api/greet/:name"], "GET", "/api/greet/:name")]:
        ip.globals["suserroutes"] = {"/r": routes(keys)}
        c.ck("qsUserRouteFind(%r,%r) over %d keys" % (method, path, len(keys)),
             call("qsUserRouteFind", ["/r", method, path]), G.user_route_find(keys, method, path))
    ip.globals["suserroutes"] = {}

    # -- header sanitising --
    for val in ["value", "a\r\nb", "a\tb", "x\x00y", "keep me"]:
        c.ck("qsSanitizeHeaderValue(%r)" % val, call("qsSanitizeHeaderValue", [val]),
             G.sanitize_header_value(val))
    for name in ["X-Custom", "Content-Type", "bad name", "X:Injection", "a\r\nb", "under_score"]:
        c.ck("qsSanitizeHeaderName(%r)" % name, call("qsSanitizeHeaderName", [name]),
             G.sanitize_header_name(name))

    # -- the redirect mount re-prefix --
    for loc, mount in [("/gallery", "/abc123"), ("/", "/abc123"), ("/go/x/y", "/abc123"),
                       ("/gallery", ""), ("http://example.org/x", "/abc123"),
                       ("https://example.org/x", "/abc123"), ("//example.org/x", "/abc123"),
                       ("gallery/pics", "/abc123"), ("mailto:a@b.example", "/abc123")]:
        c.ck("qsMountLocation(%r,%r)" % (loc, mount), call("qsMountLocation", [loc, mount]),
             G.mount_location(loc, mount))

    # -- template rendering: every token, every content type, the cap --
    treq = {"__method": "GET", "__path": "/api/echo",
            "__query": "name=world&raw=%22%3Cb%3E%22&evil=%3Cscript%3Ealert(1)%3C%2Fscript%3E"}
    json_ct = "application/json; charset=utf-8"
    html_ct = "text/html; charset=utf-8"
    text_ct = "text/plain; charset=utf-8"
    svg_ct = "image/svg+xml"
    js_ct = "application/javascript"
    for text, ct in [("no tokens here", json_ct), ("{{method}}", json_ct),
                     ("path={{path}}", text_ct), ("{{ method }}", json_ct),
                     ("{{query.name}}", text_ct), ("{{unknown}}", json_ct),
                     ("a {{method}} b {{path}} c", text_ct), ("{{oops", json_ct),
                     ("x {{oops y", text_ct), ('{"q":"{{query.raw}}"}', json_ct),
                     ("<p>{{query.raw}}</p>", html_ct), ("v={{query.raw}}", text_ct),
                     ("<svg>{{query.evil}}</svg>", svg_ct), ("cb({{query.raw}})", js_ct),
                     ("{{param.name}}", text_ct)]:
        c.ck("qsRenderTemplate(%r,%s)" % (text, ct.split(";")[0]),
             call("qsRenderTemplate", [text, treq, ct]), G.render_template(text, treq, ct))
    # the clock token: the mirror empties it by its own comment; the script
    # answers the modelled clock, which is the one thing worth asserting
    c.ck("qsRenderTemplate {{now}} is the clock", call("qsRenderTemplate", ["{{now}}", treq, json_ct]),
         str(fh_epoch))
    preq = {"__method": "GET", "__path": "/api/greet/x", "__query": "",
            "__params": {"name": "world", "q": '"<b>"', "evil": "<script>alert(1)</script>"}}
    for text, ct in [("hello {{param.name}}", text_ct), ("{{ param.name }}", json_ct),
                     ("{{param.missing}}", json_ct), ('{"who":"{{param.q}}"}', json_ct),
                     ("<p>{{param.evil}}</p>", html_ct), ("<svg>{{param.evil}}</svg>", svg_ct),
                     ("v={{param.q}}", text_ct)]:
        c.ck("qsRenderTemplate param(%r,%s)" % (text, ct.split(";")[0]),
             call("qsRenderTemplate", [text, preq, ct]), G.render_template(text, preq, ct))
    cap_req = {"__query": "big=" + ("x" * 200000)}
    capped = call("qsRenderTemplate", ["{{query.big}}" * 60, cap_req, "text/plain"])
    c.ck("qsRenderTemplate cap length", len(str(capped)), G._RENDER_MAX)
    c.ck("qsRenderTemplate cap equals kRenderMax", ip.constants.get("kRenderMax"), G._RENDER_MAX)


def build_source(path):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    return re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', src, count=1)


def main(argv):
    # `--check` is what build-all.sh passes every member's copy of this gate;
    # here the check IS the default run. `--source PATH` drives a different
    # file (a mutated copy) - tools/test-script-vectors.py's whole mechanism.
    path = DEMO
    args = [a for a in argv[1:] if a != "--check"]
    if len(args) == 2 and args[0] == "--source":
        path = args[1]
    elif args:
        print("usage: check-script-vectors.py [--check] [--source PATH]")
        return 2
    install_engine_functions()
    c = Checker()
    sandbox = tempfile.mkdtemp(prefix="nocloud-vectors-")
    try:
        world = DB.World(sandbox)
        ip = NcInterp(build_source(path), world)
        drive(c, ip, world, sandbox)
    finally:
        import shutil
        shutil.rmtree(sandbox, ignore_errors=True)
    if c.failed:
        print("check-script-vectors: FAIL (%d of %d)\n%s" % (len(c.failed), c.n, "\n".join(c.failed)))
        return 1
    if c.n < FLOOR:
        print("check-script-vectors: FAIL - only %d checks ran (floor %d): a section "
              "stopped executing" % (c.n, FLOOR))
        return 1
    print("check-script-vectors: OK (%d checks: the shipped script agrees with the "
          "golden's mirrors on every input the golden pins)" % c.n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
