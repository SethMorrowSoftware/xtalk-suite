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

WHERE RIPTIDE IS is the sibling rule (docs/MEMBER-REPO-SPLIT.md), resolved by
sibling() below: the directory beside this member in the suite tree, the
repository cloned beside it as ../riptide in a standalone checkout, or
wherever XTALK_SIBLING_RIPTIDE / XTALK_SIBLINGS point. An absent runner stops
this gate before anything loads, with the clone to run.

WHAT IT IS NOT. An approximation of the engine, not the engine. Nothing here
promotes a handler out of "verified statically; needs an OXT pass" - what it
settles is LOGIC, not parser behaviour. The interpreter's header carries the
modelled subset and its named divergences; the one that matters most here is
that `is`, `contains`, `begins with` and `ends with` are modelled CASE-SENSITIVE
where the engine folds case. Every helper driven here is either
case-indifferent by construction or compares through toLower first - bar the
route layer, which since 2026-09-25 must be case-EXACT where the engine's `is`
folds. That layer is driven TWICE (drive_routes): once under the interpreter's
own `is`, which reads plain decimals as numbers and, since 2026-09-25, REFUSES a
pair the engine reads otherwise (so qsSameText's "01" / "1" rows catch a bare `is`,
and its "1e2" / "100" call fails as a refusal, on a row named_calls adds for it), and
once under engine_is_folds, where `is` folds case as the engine's does by default (so a bare `is` in qsHttpAllow, qsCorsPreflight or
qsSameText's exact stage answers as it would on the engine, and fails). Both
passes read the tables through the model's folded array keys, and fill them
through the script's own writers. The second pass was added the same day, when
all three of those reverts were found to pass the first alone.

THE SPELLINGS, AND WHERE THEY LIVE. nocloud writes nine forms the shared
interpreter had never modelled: `repeat for each char`, a bare `repeat` (the
engine's `repeat forever`), `delete char N of X` / `delete the last char of X`,
`the last item|char|line|word of X`, `the round of X`, `the number of bytes IN
X` (the base accepts only `of`), `^`, text ORDERING under `<` and `>` (the base
refuses a non-numeric operand), and the engine functions toUpper / toLower /
urlDecode / byteOffset. The first version of this gate modelled them in a
subclass here, by the precedent coinxt's wallet gate set for `the number of
controls`, with the note that a second writer would promote them. holde-em
turned out to be that second writer the same day, so they live in riptide's
runner now (DemoExpr / DemoInterp / install_engine_functions), beside `div`,
`mod` and the word chunk, and this file keeps only the write interception
below. Each model states its engine rule beside it there; `the round of`
rounds half AWAY from zero, the engine's rule and the golden's _round1, NOT
python's round().

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
re-proven on every push rather than remembered, beside twelve for the
case-exact route table and the declared-method token (2026-09-25; that file
lists them). One check here is STRUCTURAL, and says so in its label:
qsLoadUserRoutes reads a file and parses JSON, which the model cannot run, so
check_load_refuses_methods holds where its method refusal sits.

Run from the member directory or anywhere:  python3 tools/check-script-vectors.py
"""
import contextlib
import importlib.util
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)


def sibling(name):
    """Path of a sibling member's checkout (docs/MEMBER-REPO-SPLIT.md).

    In the suite tree the siblings are the directories beside this member;
    in a standalone checkout they are the sibling repositories cloned
    beside it under their member names. Two overrides, checked in this
    order: XTALK_SIBLING_<NAME> (one member, any path) and XTALK_SIBLINGS
    (a directory holding them all). No sibling is ever searched for: an
    absent one is reported by the gate that needs it, naming the
    repository to clone."""
    # A member is never its own sibling: its own name answers this checkout
    # before any override is read, so XTALK_SIBLINGS cannot redirect a gate
    # away from the tree running it (coinxt's wallet boot reuses riptide's
    # runner, and that runner resolves coinxt by name).
    if name == os.path.basename(MEMBER):
        return MEMBER
    one = os.environ.get("XTALK_SIBLING_" + name.upper().replace("-", "_"))
    if one:
        return one
    return os.path.join(os.environ.get("XTALK_SIBLINGS")
                        or os.path.dirname(MEMBER), name)


DEMO = os.path.join(MEMBER, "src", "nocloudquickshare.livecodescript")
GOLDEN = os.path.join(MEMBER, "tests", "fileserver_golden.py")
RUNNER = os.path.join(sibling("riptide"), "tools", "check-demo-boot.py")
# The runner is needed before anything else loads, so its absence is settled
# here as one paragraph (stderr, exit 2: a setup problem, not a vector
# failure) rather than as the traceback importlib would print.
if not os.path.isfile(RUNNER):
    print("check-script-vectors: %s is not present: it belongs to the riptide "
          "member, which is not beside this checkout. Clone "
          "https://github.com/SethMorrowSoftware/RipTide beside this checkout "
          "as ../riptide, or point XTALK_SIBLING_RIPTIDE / XTALK_SIBLINGS at "
          "it." % RUNNER, file=sys.stderr)
    sys.exit(2)

# The floor is a ratchet, not a target: a run that finds FEWER checks than this
# is a run where a section silently stopped executing (a helper renamed, an
# import failing inside a try) and must fail rather than print OK. Raised from
# 380 on 2026-09-25, when the route-table rows added about a hundred checks: the
# old floor would have let every one of them stop unseen; raised again the same
# day, to below the count with the route layer's second pass (drive_routes under
# engine_is_folds, about 220 checks), so a run without that pass fails.
FLOOR = 700


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
# the one thing this gate models that the shared runner does not: the writes

class NcInterp(DB.DemoInterp):
    """The transport writes, intercepted at statement level: OnionXT's stream
    write and close, and the clearweb twin's two socket writers. Everything a
    send command computed is in the bytes it hands over, which is what the
    golden's http_text_response pins. Every other spelling this app writes
    beyond the base subset lives in the runner itself since 2026-09-11 (see
    the header)."""

    def __init__(self, src, world):
        self.sent = []          # (handler, [args]) for every intercepted write
        super().__init__(src, world)

    def _args(self, rest, env):
        args = []
        rest = rest.strip()
        if rest:
            p = DB.DemoExpr(self, env)
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
        m = re.match(r'(oxWrite|oxCloseStream|qsCwWriteContinue|qsCwWriteClose|'
                     r'qsFsCleanup)\b\s*(.*)$', line, re.I)
        if m:
            self.sent.append((m.group(1), self._args(m.group(2), env)))
            return i + 1
        return super()._exec_stmt(body, i, env)


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
# the engine's `is`, for the route layer's second pass (2026-09-25)

ENGINE_IS = " [engine is]"


@contextlib.contextmanager
def engine_is_folds():
    """Run the block with `is` / `is not` comparing TEXT case-insensitively, as the engine
    does while `the caseSensitive` is false (its default; engine note 2.7, and the
    interpreter header's named divergence, whose pinned half the 2026-08-24 suite paste
    confirmed on an engine). The interpreter models `is` case-EXACT on purpose: stricter
    for code that must never rely on a fold. The route layer is the opposite case: since
    2026-09-25 it must be case-exact WHERE `is` FOLDS, so under the interpreter's `is` a
    bare `is` in qsHttpAllow, qsCorsPreflight or qsSameText's exact stage answered exactly
    what the fix answers, and all three reverts passed this gate (the number rows could not
    catch them either: a path begins with "/", so it is never number-like). Under this
    model they answer as the engine would, and fail. The fold is Python's str.lower(), as
    the key fold's is: exact for ASCII, the alphabet every row that needs it is written
    in; beyond ASCII the engine's folding may merge more (not modelled here). Everything
    else the interpreter does stays as it is: its number reading (a plain decimal only,
    and a refusal wherever the engine's strtod reading would answer otherwise; note
    2.11), the case-exact `contains` / `begins
    with` / `ends with` / `is among the items|lines of` (the named divergences this pass
    does not touch), `set the caseSensitive to true` (honoured: an exact compare), and the
    key fold. The patch is the module attribute every comparison reads (the runner's
    comparator calls LCS._eq), restored on the way out whatever happens."""
    exact = LCS._eq

    def folded(a, b):
        if exact(a, b):
            return True
        if LCS.CASE_SENSITIVE[0] or isinstance(a, dict) or isinstance(b, dict):
            return False
        return str(LCS._disp(a)).lower() == str(LCS._disp(b)).lower()

    LCS._eq = folded
    try:
        yield
    finally:
        LCS._eq = exact


REFUSED = "REFUSED by the family interpreter (LCS.Indistinct)"


def _args_shown(args):
    """A call's arguments as a failure label spells them: each repr cut to 40 characters,
    so an HTTP buffer does not bury the name."""
    out = []
    for a in args:
        text = repr(a)
        out.append(text if len(text) <= 40 else text[:37] + "...")
    return ", ".join(out)


def named_calls(c, ip):
    """ip.call, bar one thing: a comparison the family interpreter REFUSES
    (LCS.Indistinct: the engine answers it differently from the model, engine notes 2.10
    and 2.11) FAILS A ROW OF ITS OWN, named by the call and its arguments, and the call
    answers REFUSED so the rows after it still run. Until 2026-09-26 it ended the gate in
    a traceback that named no row: the mutation drive's bare-`is` qsSameText is refused
    at "1e2" / "100" (the engine reads both as one number, the text says two), and
    test-script-vectors needs the name. The failure is recorded HERE, not left to the
    caller's row, because a row reads its value through a filter a refusal can pass: the
    first version returned the REFUSED text and let each row fail on it, and
    boolish(REFUSED) is false, which is what qsSameText('1e2','100') expects, so that row
    passed, and qsRouteMatch's `None if not isinstance(got, dict)` read it as "no match"
    (a planted refusal went through the whole gate green; test-script-vectors now
    carries it). A refusal is never a pass: the shipped script meets none (every route
    comparison is letter-prefixed), and one fails here, named. `c` is the pass's own
    checker, so the row carries the pass's tag."""
    def call(name, args):
        try:
            return ip.call(name, args)
        except LCS.Indistinct as exc:
            c.ck("%s(%s): REFUSED by the family interpreter" % (name, _args_shown(args)),
                 "%s: %s" % (REFUSED, str(exc)[:200]), "an answer")
            return REFUSED
    return call


class Tagged:
    """A Checker whose every label carries a suffix: the second pass's rows name their
    model, so a failure says which `is` it failed under."""

    def __init__(self, c, tag):
        self.c, self.tag = c, tag

    def ck(self, label, got, want):
        self.c.ck(label + self.tag, got, want)


# --------------------------------------------------------------------------
# the route layer (2026-09-25): driven twice, once per model of `is`

def drive_routes(c, ip):
    """Every route-layer row: the tables, Allow, the CORS preflight, share roots, the
    reserved namespaces, the declared-method token, the case-exact keys, the lookups and
    the :param patterns. drive() runs it under the interpreter's `is` and again under
    engine_is_folds(), with each label tagged; see engine_is_folds for why both."""
    call = named_calls(c, ip)

    # -- the route tables are filled through the SCRIPT's own writers (qsHttpRoute for the
    # built-in table, qsUserRouteStore for a folder's), never typed here: the key shape is
    # the script's business, and a hand-built table would pin a shape the script never
    # writes (root CLAUDE.md, "component verified, system claimed"). Each reset empties both.
    def builtin(keys):
        ip.globals["shttproutes"] = ""
        for k in keys:
            m, pth = k.split(" ", 1)
            call("qsHttpRoute", [m, pth, "x"])
        return ip.globals["shttproutes"]

    def user(keys, cors=False, root="/r"):
        ip.globals["suserroutes"] = ""
        store(keys, cors, root)
        return user_table(root)

    def store(keys, cors=False, root="/r"):
        for k in keys:
            m, pth = k.split(" ", 1)
            call("qsUserRouteStore", [root, m, pth,
                                      {"kind": "body", "cors": "true"} if cors else {"kind": "body"}])

    def user_table(root="/r"):
        # read with the ENGINE's folded subscript, as the script would (LCS._arr_get),
        # so a table filed under a folded root key cannot hide behind python's exact `in`
        tbl = ip.globals.get("suserroutes")
        return LCS._arr_get(tbl, G.root_key(root)) if isinstance(tbl, dict) else ""

    # -- Allow, over the built-in table and the per-root user table --
    _routes = ["GET /_qs/info", "GET /_edit", "POST /_edit/login",
               "GET /_edit/api/list", "GET /_edit/api/read", "PUT /_edit/api/write"]
    builtin(_routes)
    ip.globals["suserroutes"] = ""
    for path in ["/_edit/login", "/_edit/api/write", "/_qs/info", "/nope"]:
        c.ck("qsHttpAllow(%r)" % path, call("qsHttpAllow", [path, ""]),
             G.http_allow(_routes, path))
    builtin(["POST /x", "PUT /x", "DELETE /x", "GET /x"])
    c.ck("qsHttpAllow multi", call("qsHttpAllow", ["/x", ""]),
         G.http_allow(["POST /x", "PUT /x", "DELETE /x", "GET /x"], "/x"))
    builtin([])
    uroutes = ["POST /api/submit", "GET /api/hello", "PUT /api/submit"]
    user(uroutes)
    for path in ["/api/submit", "/api/hello", "/nope"]:
        c.ck("qsHttpAllow user(%r)" % path, call("qsHttpAllow", [path, "/r"]),
             G.http_allow([], path, uroutes))
    builtin(["POST /dup"])
    user(["POST /dup"])
    c.ck("qsHttpAllow dedup across the tables", call("qsHttpAllow", ["/dup", "/r"]),
         G.http_allow(["POST /dup"], "/dup", ["POST /dup"]))
    builtin([])
    for path, ukeys in [
            ("/api/files/readme.txt",
             ["DELETE /api/files/:name", "GET /api/files/:name", "PUT /api/other/:x"]),
            ("/api/files/x", ["POST /api/files/x", "POST /api/files/:n"]),
            ("/api/files/a/b", ["DELETE /api/files/:n"]),
            ("/_qs/info", ["DELETE /:x/info"])]:
        user(ukeys)
        c.ck("qsHttpAllow param(%r)" % path, call("qsHttpAllow", [path, "/r"]),
             G.http_allow([], path, ukeys))
    # the path claim is EXACT, as the table is (2026-09-25): the engine's bare `is` folds
    # case, so Allow would advertise a method no route answers. A whole path begins with
    # "/" and is never number-like, so the "/v/01" rows pin only that number-shaped
    # segments stay exact here; a bare `is` answers them right under EITHER model. The
    # case rows are the ones a bare `is` fails, and only in the [engine is] pass, where
    # `is` folds as the engine's does (engine_is_folds says why the first pass cannot).
    for path, routes, ukeys in [
            ("/API/submit", [], uroutes),
            ("/_EDIT/api/write", _routes, []),
            ("/v/01", ["POST /v/1"], ["PUT /v/1"]),
            ("/v/1.0", ["POST /v/1"], ["PUT /v/1"]),
            ("/v/1e2", [], ["PUT /v/100"]),
            ("/v/1", ["POST /v/1"], ["PUT /v/1"])]:
        builtin(routes)
        user(ukeys)
        c.ck("qsHttpAllow exact(%r)" % path, call("qsHttpAllow", [path, "/r"]),
             G.http_allow(routes, path, ukeys))
    builtin([])

    # -- CORS preflight: only where a cors route matches the path --
    cors_keys = ["POST /api/submit", "GET /api/open"]
    user(cors_keys, cors=True)
    for path, allow in [("/api/submit", "GET, HEAD, OPTIONS, POST"),
                        ("/api/other", "GET, HEAD, OPTIONS"),
                        ("/API/SUBMIT", "GET, HEAD, OPTIONS"),
                        ("/api/Submit", "GET, HEAD, OPTIONS")]:
        c.ck("qsCorsPreflight(%r)" % path, call("qsCorsPreflight", ["/r", path, allow]),
             G.cors_preflight(cors_keys, path, allow))
    user([])
    c.ck("qsCorsPreflight with no routes",
         call("qsCorsPreflight", ["/r", "/api/submit", "GET, HEAD, OPTIONS"]),
         G.cors_preflight([], "/api/submit", "GET, HEAD, OPTIONS"))
    c.ck("qsCorsPreflight with no root",
         call("qsCorsPreflight", ["", "/api/submit", "GET, HEAD, OPTIONS"]), "")
    for keys, path, allow in [(["POST /api/thing/:id"], "/api/thing/42", "GET, HEAD, OPTIONS, POST"),
                              (["POST /api/thing/:id"], "/api/other/42", "GET, HEAD, OPTIONS"),
                              (["POST /api/thing/:id"], "/API/thing/42", "GET, HEAD, OPTIONS"),
                              (["POST /v/1/:id"], "/v/01/42", "GET, HEAD, OPTIONS"),
                              (["GET /:x/info"], "/_qs/info", "GET, HEAD, OPTIONS")]:
        user(keys, cors=True)
        c.ck("qsCorsPreflight param %r" % path, call("qsCorsPreflight", ["/r", path, allow]),
             G.cors_preflight(keys, path, allow))

    # -- share ROOTS are case-exact too (qsRootKey): on a case-sensitive filesystem
    # /srv/Site and /srv/site are two folders, two route tables, two teardowns --
    ip.globals["suserroutes"] = ""
    store(["POST /api/x", "GET /api/p/:id"], cors=True, root="/srv/Site")
    for root, ukeys in [("/srv/Site", ["POST /api/x", "GET /api/p/:id"]), ("/srv/site", []),
                        ("/SRV/SITE", [])]:
        c.ck("qsHttpAllow under root %r" % root, call("qsHttpAllow", ["/api/x", root]),
             G.http_allow([], "/api/x", ukeys))
        c.ck("qsCorsPreflight under root %r" % root,
             call("qsCorsPreflight", [root, "/api/x", "GET, HEAD, OPTIONS"]),
             G.cors_preflight(ukeys, "/api/x", "GET, HEAD, OPTIONS"))
        c.ck("qsUserRouteFind under root %r" % root,
             call("qsUserRouteFind", [root, "GET", "/api/p/7"]),
             G.user_route_find(ukeys, "GET", "/api/p/7"))
    c.ck("qsRootKey is the mirror's root_key", call("qsRootKey", ["/srv/Site"]),
         G.root_key("/srv/Site"))
    ip.globals["suserroutes"] = ""


    # -- user-route path validation and the reserved-namespace predicate --
    for path in ["/api/hello", "/hello", "/go/docs", "/normal-path_123", "/_qsx", "",
                 "api/x", "/../etc", "/a/../b", "/_qs", "/_qs/info", "/_edit",
                 "/_edit/login", "/a\nb", "/_QS/info", "/_Edit/api/write", "/_QSX"]:
        c.ck("qsUserPathValid(%r)" % path, boolish(call("qsUserPathValid", [path])),
             G.user_path_valid(path))
    for path in ["/_qs", "/_qs/info", "/_qs/", "/_edit", "/_edit/api/write", "/_qsx",
                 "/_editor", "/a/_qs", "/_q", "/", "", "/_QS", "/_QS/info", "/_Qs/",
                 "/_EDIT", "/_Edit/api/write", "/_QSX", "/_EDITOR"]:
        c.ck("qsHttpReservedPath(%r)" % path, boolish(call("qsHttpReservedPath", [path])),
             G.reserved_path(path))

    # -- the case-exact keys (2026-09-25) --
    for text in ["", "GET /api/x", "/caf\u00e9", "A", "a", "\x00\x7f", "PUT /_EDIT/API"]:
        c.ck("qsHexKey(%r)" % text, call("qsHexKey", [text]), G.hex_key(text))
    for method, path in [("GET", "/api/x"), ("get", "/api/x"), ("GET", "/API/x"),
                         ("POST", "/caf\u00e9"), ("HEAD", "/")]:
        c.ck("qsRouteKey(%r,%r)" % (method, path), call("qsRouteKey", [method, path]),
             G.route_key(method, path))
    for one, two in [("/api/x", "/api/x"), ("", ""), ("/api/x", "/API/x"), ("01", "1"),
                     ("1.0", "1"), ("1e2", "100"), ("caf\u00e9", "CAF\u00c9"), ("a", "a ")]:
        c.ck("qsSameText(%r,%r)" % (one, two), boolish(call("qsSameText", [one, two])),
             G.same_text(one, two))

    # -- HEAD route lookup, and the FOLD rows: the script READS the table (since
    # 2026-09-25), so the subscript the engine folds is the interpreter's folded one here.
    # Each row runs against BOTH tables, filled by the script's own writers: one lookup
    # serves both. The golden holds each fold row's witness (it collided pre-fix). --
    lk_builtin = ["GET /_qs/info", "GET /_qs/transparency", "POST /_edit/login"]
    lk_user = ["GET /api/hello", "HEAD /probe", "GET /probe", "POST /api/submit"]
    lk_odd = ["GET /caf\u00e9", "GET /v/1"]
    rows = [("HEAD", "/_qs/info", lk_builtin), ("HEAD", "/api/hello", lk_user),
            ("HEAD", "/probe", lk_user), ("GET", "/probe", lk_user),
            ("GET", "/api/hello", lk_user), ("GET", "/nope", lk_user),
            ("POST", "/api/submit", lk_user), ("POST", "/probe", lk_user),
            ("HEAD", "/nope", lk_user), ("head", "/api/hello", lk_user),
            ("HEAD", "/api/hello", []), ("GET", "/api/hello", []),
            # the fold rows: GET /API/x is not the /api/x route, nor through HEAD
            ("GET", "/API/hello", lk_user), ("GET", "/Api/Hello", lk_user),
            ("HEAD", "/API/HELLO", lk_user), ("HEAD", "/PROBE", lk_user),
            ("POST", "/API/submit", lk_user), ("GET", "/_QS/info", lk_builtin),
            ("POST", "/_Edit/Login", lk_builtin),
            ("GET", "/caf\u00e9", lk_odd), ("GET", "/CAF\u00c9", lk_odd),
            ("GET", "/v/1", lk_odd), ("GET", "/v/01", lk_odd), ("GET", "/v/1.0", lk_odd)]
    for method, path, keys in rows:
        want = G.route_lookup_key(method, path, G.table(keys))
        tbl = builtin(keys) if keys else ""
        c.ck("qsRouteLookupKey(%r,%r) over the built-in table" % (method, path),
             call("qsRouteLookupKey", [method, path, tbl]), want)
        tbl = user(keys) if keys else ""
        c.ck("qsRouteLookupKey(%r,%r) over a folder's table" % (method, path),
             call("qsRouteLookupKey", [method, path, tbl]), want)
    builtin([])
    ip.globals["suserroutes"] = ""

    # -- :param patterns --
    for path in ["/api/hello", "/api/:name", "/api/files/:name", "/api/x:y", "/"]:
        c.ck("qsRouteHasParams(%r)" % path, boolish(call("qsRouteHasParams", [path])),
             G.route_has_params(path))
    for path in ["/api/hello", "/api/:a", "/api/:a/:b", "/api/:a/sub/:b"]:
        c.ck("qsRouteParamCount(%r)" % path, call("qsRouteParamCount", [path]),
             G.route_param_count(path))
    for path in ["/api/:name", "/api/files/:name", "/api/:a/:b", "/api/:a/sub/:b", "/dl/:tag/",
                 "/api/hello", "/:x", "/:x/y", "/_qs/:x", "/_edit/:x", "/api/:", "/api/:na-me",
                 "/api/:x/:x", "/files/:a..b", "api/:x", "/api/:id/:ID", "/api/:id/:idx",
                 "/_QS/:x"]:
        c.ck("qsUserPatternValid(%r)" % path, boolish(call("qsUserPatternValid", [path])),
             G.user_pattern_valid(path))
    for pattern, path in [("/api/files/:name", "/api/files/readme.txt"), ("/api/:a/:b", "/api/x/y"),
                          ("/api/files/:name", "/api/files/"), ("/api/files/:name", "/api/files/a/b"),
                          ("/api/files/:name", "/api/other/x"), ("/dl/:tag/", "/dl/v1/"),
                          ("/dl/:tag", "/dl/v1/"), ("/dl/:tag/", "/dl/v1"),
                          ("/api/greet/:name", "/api/greet/:name"), ("/:x/info", "/_qs/info"),
                          ("/_qs/:x", "/_qs/info"), ("/files/:x", "/_qs/info"), ("/:x", "/_edit"),
                          ("/:x/login", "/_edit/login"), ("/:x/info", "/_QS/info"),
                          ("/api/files/:name", "/API/files/x"), ("/api/files/:name", "/api/FILES/x"),
                          ("/v/1/:x", "/v/01/x"), ("/v/1/:x", "/v/1.0/x"), ("/v/1e2/:x", "/v/100/x"),
                          ("/v/1/:x", "/v/1/x"), ("/api/files/:name", "/api/files/README")]:
        got = call("qsRouteMatch", [pattern, path])
        # the script answers "no" (a non-array) where the mirror answers None
        c.ck("qsRouteMatch(%r,%r)" % (pattern, path),
             None if not isinstance(got, dict) else got, G.route_match(pattern, path))
    pat_keys = ["GET /api/hello", "GET /api/files/:name", "POST /api/files/:name", "GET /api/:a/:b"]
    for keys, method, path in [(pat_keys, "GET", "/api/files/x"), (pat_keys, "POST", "/api/files/x"),
                               (pat_keys, "DELETE", "/api/files/x"), (pat_keys, "GET", "/api/x/y"),
                               (pat_keys, "GET", "/api/hello"), (pat_keys, "GET", "/_qs/info"),
                               (pat_keys, "GET", "/API/files/x"), (pat_keys, "GET", "/_QS/info"),
                               (["GET /api/files/:b", "GET /api/:a/x"], "GET", "/api/files/x"),
                               # the tie-break is BYTE order: /api/:Z/x before /api/:a/x,
                               # where the old readable keys' folded `<` picked :a
                               (["GET /api/:a/x", "GET /api/:Z/x"], "GET", "/api/files/x"),
                               (["GET /api/:Z/x", "GET /api/:a/x"], "GET", "/api/files/x"),
                               (["GET /:x/info"], "GET", "/_qs/info"),
                               (["GET /api/greet/:name"], "GET", "/api/greet/:name")]:
        user(keys)
        c.ck("qsUserRouteFind(%r,%r) over %s" % (method, path, keys),
             call("qsUserRouteFind", ["/r", method, path]), G.user_route_find(keys, method, path))
    ip.globals["suserroutes"] = ""

    # -- a declared route method is a token (qsHttpMethodValid, 2026-09-25): no space, CR
    # or LF can reach the Allow header or alias another route's key --
    for method, _ in G.HTTP_METHOD_ROWS:
        c.ck("qsHttpMethodValid(%r)" % method, boolish(call("qsHttpMethodValid", [method])),
             G.http_method_valid(method))


# --------------------------------------------------------------------------
# the drive, section by section in the golden's order

def drive_own_code(c, ip):
    """qsIsOwnCode (2026-09-26), under engine_is_folds() only: its answer is a case-FOLDED
    compare, as the engine's `is` gives, so the interpreter's case-exact `is` would fail the
    upper-case row for the wrong reason. The number rows are the point: two 40-hex codes
    "0e1..." and "0e2..." are one number to a bare `is`, which the interpreter REFUSES
    (named_calls fails that row by name), so a revert of any of the three letter-prefixed
    compares fails here. The script's three sources are set directly: they are state the
    share flow writes, and qsIsOwnCode only reads them."""
    call = named_calls(c, ip)
    h1, h2, hx = "0e" + "1" * 38, "0e" + "2" * 38, "ab" * 20
    for code, share, by_handle, active in [
            (h2, h1, [], ""), (h2, "", [h1], ""), (h2, "", [], h1), (h1, h1, [], ""),
            (hx.upper(), hx, [], ""), (hx, "", ["x", hx], ""), (hx, "", [], hx),
            (hx, h1, [h2], "zz")]:
        ip.globals["ssharecode"] = share
        ip.globals["ssharecodebyhandle"] = ({"h%d" % i: v for i, v in enumerate(by_handle)}
                                            if by_handle else "")
        ip.globals["sactiveshare"] = {"code": active} if active else ""
        c.ck("qsIsOwnCode(%r...) over %r / %d retained / %r" % (code[:6], share[:6],
                                                                  len(by_handle), active[:6]),
             boolish(call("qsIsOwnCode", [code])),
             G.is_own_code(code, share, by_handle, active))
    ip.globals["ssharecode"] = ""
    ip.globals["ssharecodebyhandle"] = ""
    ip.globals["sactiveshare"] = ""


def drive(c, ip, world, sandbox):
    call = named_calls(c, ip)
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

    # -- the route layer, TWICE: under the interpreter's own `is` (case-exact, and it reads
    # plain decimals as numbers) and under the engine's default (case folds; see
    # engine_is_folds). Each pass must agree with the mirrors on every row. --
    drive_routes(c, ip)
    with engine_is_folds():
        drive_routes(Tagged(c, ENGINE_IS), ip)
        drive_own_code(Tagged(c, ENGINE_IS), ip)
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
    world.ms = fh_epoch * 1000      # the runner derives `the seconds` from its ms clock
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


def check_load_refuses_methods(c, source):
    """qsHttpMethodValid is driven above; its ONE caller is qsLoadUserRoutes, which opens
    and reads a file and calls JSONToArray, spellings the interpreter models nowhere, so
    that handler cannot run here. This holds the call site structurally instead: in its
    body (comments cut), the method is refused through qsHttpMethodValid AFTER it is
    trimmed, upper-cased and defaulted to GET, and BEFORE the route is filed through
    qsUserRouteStore - the order that keeps a CR, LF or space out of every stored method.
    A structural check, labelled as one: it settles where the refusal sits, not that the
    load runs."""
    m = re.search(r'^command qsLoadUserRoutes\b(.*?)^end qsLoadUserRoutes\b', source,
                  re.M | re.S)
    body = m.group(1) if m else ""
    lines = [ln.split("--", 1)[0].strip() for ln in body.split("\n")]

    def first(pattern):
        for i, ln in enumerate(lines):
            if re.fullmatch(pattern, ln):
                return i
        return -1

    upper = first(r'put toUpper\(qsTrim\(tRoute\["method"\]\)\) into tMethod')
    default = first(r'put "GET" into tMethod')
    refuse = first(r'if not qsHttpMethodValid\(tMethod\) then')
    store = first(r'qsUserRouteStore pRoot, tMethod, tPath, tDesc')
    skips = refuse >= 0 and refuse + 1 < len(lines) and lines[refuse + 1] == "next repeat"
    c.ck("qsLoadUserRoutes refuses a method that is not a token before it files the route "
         "(upper-case, default, refuse, store)",
         (m is not None and skips and 0 <= upper < default < refuse < store), True)


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
    c = Checker()
    sandbox = tempfile.mkdtemp(prefix="nocloud-vectors-")
    try:
        world = DB.World(sandbox)
        DB.install_engine_functions(world)
        ip = NcInterp(build_source(path), world)
        drive(c, ip, world, sandbox)
        with open(path, "r", encoding="utf-8") as fh:
            check_load_refuses_methods(c, fh.read())
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
