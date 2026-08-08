#!/usr/bin/env python3
"""lcs-interp.py - a tiny interpreter for the LiveCodeScript subset that
src/coinxt.livecodescript is written in. TEST TOOLING; it is not shipped inside
the extension and no shipped code imports it.

WHY THIS EXISTS. OXT cannot compile or run a .livecodescript headlessly, so the
phase-3 encoders would otherwise ship having never executed once - a bad place
for Base58Check and bech32 to be, since a transcription slip there produces a
VALID-LOOKING wrong address. This runs the ACTUAL shipped file against the
published vectors (tools/check-script-vectors.py drives it), so that class of
bug is caught here rather than in a scarce engine session.

WHAT IT IS NOT. It is an approximation of the engine, not the engine. It does
NOT replace the OXT pass and nothing here promotes a handler out of "verified
statically". It models the documented semantics of the subset used - 1-based
chunk indexing, comma item delimiter, `is` comparison, arrays - and it REFUSES
anything outside that subset rather than guessing, because a silent mis-parse
would be worse than no tool at all. If it disagrees with the engine, the engine
is right and this file is the bug.

It is deliberately literal and slow (cxBitXor alone is 31 interpreted iterations
per call, and a bech32 checksum calls it hundreds of times). Speed is not the
point; running the real text is.
"""
import re


class Thrown(Exception):
    def __init__(self, msg):
        self.msg = msg
        super().__init__(msg)


class Bytes(str):
    """xTalk does not distinguish a byte string from a text string; both are
    sequences of chars. We model everything as a python str of code points
    0..255, which is what byteToNum/numToByte imply."""


def _n(v):
    """Coerce to number the way xTalk does when arithmetic is applied."""
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, (int, float)):
        return v
    s = str(v).strip()
    if s == "":
        return 0
    f = float(s)
    return int(f) if f == int(f) else f


class Interp:
    def __init__(self, src):
        self.constants = {}
        self.handlers = {}
        self._parse(src)

    # ---------------------------------------------------------------- parsing
    def _parse(self, src):
        lines = []
        for raw in src.split("\n"):
            # strip comments (-- to end of line), outside strings
            out, i, instr = "", 0, False
            while i < len(raw):
                c = raw[i]
                if c == '"':
                    instr = not instr
                    out += c
                elif not instr and c == "-" and i + 1 < len(raw) and raw[i + 1] == "-":
                    break
                else:
                    out += c
                i += 1
            lines.append(out.rstrip())
        # join continuation lines ending in backslash
        joined, buf = [], ""
        for ln in lines:
            if ln.endswith("\\"):
                buf += ln[:-1]
            else:
                joined.append(buf + ln)
                buf = ""
        i = 0
        while i < len(joined):
            ln = joined[i].strip()
            m = re.match(r'constant\s+(\w+)\s*=\s*(.+)$', ln)
            if m:
                self.constants[m.group(1)] = self.eval_expr(m.group(2), {})
                i += 1
                continue
            m = re.match(r'(?:private\s+)?function\s+(\w+)\s*(.*)$', ln)
            if m:
                name, params = m.group(1), m.group(2)
                plist = [p.strip() for p in params.split(",") if p.strip()]
                body, i = self._collect(joined, i + 1, name)
                self.handlers[name.lower()] = (plist, body)
                continue
            i += 1

    def _collect(self, lines, i, name):
        body = []
        depth = 0
        while i < len(lines):
            s = lines[i].strip()
            low = s.lower()
            if re.match(r'^end\s+' + re.escape(name.lower()) + r'\b', low) and depth == 0:
                return body, i + 1
            if re.match(r'^(if\b.*\bthen$|repeat\b|try\b)', low):
                depth += 1
            elif re.match(r'^end\s+(if|repeat|try)\b', low):
                depth -= 1
            body.append(lines[i])
            i += 1
        raise SyntaxError(f"unterminated handler {name}")

    # -------------------------------------------------------------- execution
    def call(self, name, args):
        key = name.lower()
        if key not in self.handlers:
            raise NameError(f"no handler {name}")
        params, body = self.handlers[key]
        env = {}
        for idx, p in enumerate(params):
            env[p.lower()] = args[idx] if idx < len(args) else ""
        try:
            self._exec(body, env)
        except _Return as r:
            return r.value
        return ""

    def _exec(self, body, env):
        i = 0
        while i < len(body):
            i = self._exec_stmt(body, i, env)

    def _block(self, body, i, opener_re, closer_re):
        """Return (inner, index_after_end) for a block starting at body[i]."""
        depth, j, inner = 0, i + 1, []
        while j < len(body):
            s = body[j].strip().lower()
            if re.match(r'^(if\b.*\bthen$|repeat\b|try\b)', s):
                depth += 1
            elif re.match(r'^end\s+(if|repeat|try)\b', s):
                if depth == 0:
                    return inner, j + 1
                depth -= 1
            inner.append(body[j])
            j += 1
        raise SyntaxError("unterminated block")

    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        if not line:
            return i + 1
        low = line.lower()

        # --- if / else if / else
        m = re.match(r'if\s+(.*)\s+then$', line, re.I)
        if m:
            inner, after = self._block(body, i, None, None)
            # split inner on top-level else
            branches, cur, depth = [], [], 0
            cond = m.group(1)
            conds = [cond]
            for ln in inner:
                s = ln.strip().lower()
                if re.match(r'^(if\b.*\bthen$|repeat\b|try\b)', s):
                    depth += 1
                elif re.match(r'^end\s+(if|repeat|try)\b', s):
                    depth -= 1
                if depth == 0 and re.match(r'^else\s+if\s+.*\s+then$', s):
                    branches.append(cur); cur = []
                    conds.append(re.match(r'else\s+if\s+(.*)\s+then$', ln.strip(), re.I).group(1))
                    continue
                if depth == 0 and s == "else":
                    branches.append(cur); cur = []
                    conds.append(None)
                    continue
                cur.append(ln)
            branches.append(cur)
            for c, b in zip(conds, branches):
                if c is None or self.truth(self.eval_expr(c, env)):
                    self._exec(b, env)
                    break
            return after

        # --- repeat forms
        m = re.match(r'repeat\s+with\s+(\w+)\s*=\s*(.+?)\s+down\s+to\s+(.+)$', line, re.I)
        if m:
            var, a, b = m.group(1).lower(), m.group(2), m.group(3)
            inner, after = self._block(body, i, None, None)
            k, end = _n(self.eval_expr(a, env)), _n(self.eval_expr(b, env))
            while k >= end:
                env[var] = k
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
                k -= 1
            return after
        m = re.match(r'repeat\s+with\s+(\w+)\s*=\s*(.+?)\s+to\s+(.+?)(?:\s+step\s+(.+))?$', line, re.I)
        if m:
            var, a, b, st = m.group(1).lower(), m.group(2), m.group(3), m.group(4)
            inner, after = self._block(body, i, None, None)
            start, end = _n(self.eval_expr(a, env)), _n(self.eval_expr(b, env))
            step = _n(self.eval_expr(st, env)) if st else 1
            k = start
            while (step > 0 and k <= end) or (step < 0 and k >= end):
                env[var] = k
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
                k += step
            return after
        m = re.match(r'repeat\s+while\s+(.+)$', line, re.I)
        if m:
            cond = m.group(1)
            inner, after = self._block(body, i, None, None)
            guard = 0
            while self.truth(self.eval_expr(cond, env)):
                guard += 1
                if guard > 2_000_000:
                    raise RuntimeError("repeat while did not terminate")
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
            return after

        # --- simple statements
        if low.startswith("local "):
            for v in line[6:].split(","):
                env.setdefault(v.strip().lower(), "")
            return i + 1
        if low in ("exit repeat",):
            raise _Exit()
        if low in ("next repeat",):
            raise _Next()
        m = re.match(r'return\b\s*(.*)$', line, re.I)
        if m:
            raise _Return(self.eval_expr(m.group(1), env) if m.group(1).strip() else "")
        m = re.match(r'throw\s+(.+)$', line, re.I)
        if m:
            raise Thrown(str(self.eval_expr(m.group(1), env)))
        m = re.match(r'add\s+(.+?)\s+to\s+(.+)$', line, re.I)
        if m:
            tgt = m.group(2).strip()
            self.assign(tgt, _n(self.eval_expr(tgt, env)) + _n(self.eval_expr(m.group(1), env)), env)
            return i + 1
        m = re.match(r'subtract\s+(.+?)\s+from\s+(.+)$', line, re.I)
        if m:
            tgt = m.group(2).strip()
            self.assign(tgt, _n(self.eval_expr(tgt, env)) - _n(self.eval_expr(m.group(1), env)), env)
            return i + 1
        m = re.match(r'multiply\s+(.+?)\s+by\s+(.+)$', line, re.I)
        if m:
            tgt = m.group(1).strip()
            self.assign(tgt, _n(self.eval_expr(tgt, env)) * _n(self.eval_expr(m.group(2), env)), env)
            return i + 1
        m = re.match(r'delete\s+char\s+(.+?)\s+to\s+(.+?)\s+of\s+(.+)$', line, re.I)
        if m:
            a, b, tgt = int(_n(self.eval_expr(m.group(1), env))), int(_n(self.eval_expr(m.group(2), env))), m.group(3).strip()
            s = str(self.eval_expr(tgt, env))
            self.assign(tgt, s[:a - 1] + s[b:], env)
            return i + 1
        m = re.match(r'put\s+(.+?)\s+(into|after|before)\s+(.+)$', line, re.I)
        if m:
            val, prep, tgt = m.group(1), m.group(2).lower(), m.group(3).strip()
            v = self.eval_expr(val, env)
            if prep == "into":
                self.assign(tgt, v, env)
            else:
                cur = self.eval_expr(tgt, env)
                cur = "" if cur == "" else str(cur)
                self.assign(tgt, (cur + str(v)) if prep == "after" else (str(v) + cur), env)
            return i + 1
        raise SyntaxError(f"unsupported statement: {line!r}")

    def assign(self, target, value, env):
        m = re.match(r'^(\w+)\s*\[\s*(.+?)\s*\]$', target)
        if m:
            name, key = m.group(1).lower(), str(self.eval_expr(m.group(2), env))
            if not isinstance(env.get(name), dict):
                env[name] = {}
            env[name][key] = value
            return
        env[target.lower()] = value

    def truth(self, v):
        if isinstance(v, bool):
            return v
        return str(v).lower() == "true"

    # ------------------------------------------------------------- expressions
    def eval_expr(self, expr, env):
        return _Expr(self, env).parse(expr)


class _Return(Exception):
    def __init__(self, value): self.value = value


class _Exit(Exception): pass
class _Next(Exception): pass


class _Expr:
    """Recursive-descent evaluator for the expression subset used."""

    def __init__(self, interp, env):
        self.ip, self.env = interp, env

    def parse(self, s):
        self.s, self.i = s.strip(), 0
        v = self.p_or()
        self.ws()
        if self.i < len(self.s):
            raise SyntaxError(f"trailing input in {s!r} at {self.s[self.i:]!r}")
        return v

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t":
            self.i += 1

    def kw(self, *words):
        self.ws()
        for w in words:
            if self.s[self.i:self.i + len(w)].lower() == w and (
                    self.i + len(w) == len(self.s) or not self.s[self.i + len(w)].isalnum()):
                self.i += len(w)
                return w
        return None

    def p_or(self):
        v = self.p_and()
        while True:
            save = self.i
            if self.kw("or"):
                r = self.p_and()
                v = self.ip.truth(v) or self.ip.truth(r)
            else:
                self.i = save
                return v

    def p_and(self):
        v = self.p_not()
        while True:
            save = self.i
            if self.kw("and"):
                r = self.p_not()
                v = self.ip.truth(v) and self.ip.truth(r)
            else:
                self.i = save
                return v

    def p_not(self):
        if self.kw("not"):
            return not self.ip.truth(self.p_not())
        return self.p_cmp()

    def p_cmp(self):
        v = self.p_concat()
        while True:
            save = self.i
            if self.kw("is"):
                if self.kw("not"):
                    r = self.p_concat()
                    v = not _eq(v, r)
                else:
                    r = self.p_concat()
                    v = _eq(v, r)
                continue
            self.ws()
            for op in (">=", "<=", "<>", ">", "<"):
                if self.s[self.i:self.i + len(op)] == op:
                    self.i += len(op)
                    r = self.p_concat()
                    a, b = _n(v), _n(r)
                    v = {">=": a >= b, "<=": a <= b, ">": a > b, "<": a < b,
                         "<>": a != b}[op]
                    break
            else:
                self.i = save
                return v

    def p_concat(self):
        v = self.p_add()
        while True:
            self.ws()
            if self.s[self.i:self.i + 2] == "&&":
                self.i += 2
                v = str(_disp(v)) + " " + str(_disp(self.p_add()))
            elif self.s[self.i:self.i + 1] == "&":
                self.i += 1
                v = str(_disp(v)) + str(_disp(self.p_add()))
            else:
                return v

    def p_add(self):
        v = self.p_mul()
        while True:
            self.ws()
            if self.i < len(self.s) and self.s[self.i] in "+-":
                op = self.s[self.i]; self.i += 1
                r = self.p_mul()
                v = _n(v) + _n(r) if op == "+" else _n(v) - _n(r)
            else:
                return v

    def p_mul(self):
        v = self.p_unary()
        while True:
            self.ws()
            if self.i < len(self.s) and self.s[self.i] in "*/":
                op = self.s[self.i]; self.i += 1
                r = self.p_unary()
                v = _n(v) * _n(r) if op == "*" else _n(v) / _n(r)
            else:
                return v

    def p_unary(self):
        self.ws()
        if self.i < len(self.s) and self.s[self.i] == "-":
            self.i += 1
            return -_n(self.p_unary())
        return self.p_atom()

    def p_atom(self):
        self.ws()
        if self.i >= len(self.s):
            return ""
        c = self.s[self.i]
        if c == "(":
            self.i += 1
            v = self.p_or()
            self.ws()
            assert self.s[self.i] == ")", f"expected ) in {self.s!r}"
            self.i += 1
            return v
        if c == '"':
            j = self.s.index('"', self.i + 1)
            v = self.s[self.i + 1:j]
            self.i = j + 1
            return v
        if c.isdigit():
            j = self.i
            while j < len(self.s) and (self.s[j].isdigit() or self.s[j] == "."):
                j += 1
            txt = self.s[self.i:j]; self.i = j
            return float(txt) if "." in txt else int(txt)
        # `the number of X of Y`
        if self.kw("the"):
            if self.kw("number"):
                assert self.kw("of")
                unit = self.kw("bytes", "chars", "characters", "items", "lines")
                assert self.kw("of")
                # bind the target tightly: `the number of items of X < 1` must
                # parse as `(count of X) < 1`, not as a count of `X < 1`
                target = self.p_concat()
                s = str(_disp(target))
                if unit in ("bytes", "chars", "characters"):
                    return len(s)
                if unit == "items":
                    return 0 if s == "" else len(s.split(","))
                return 0 if s == "" else len(s.split("\n"))
            raise SyntaxError(f"unsupported `the` expression in {self.s!r}")
        # chunk expressions: byte/char/item N [to M] of EXPR
        unit = self.kw("byte", "bytes", "char", "chars", "character", "item", "items")
        if unit:
            a = self.p_add()
            b = None
            if self.kw("to"):
                b = self.p_add()
            assert self.kw("of"), f"expected `of` in {self.s!r}"
            target = self.p_atom()
            return _chunk(unit, int(_n(a)), None if b is None else int(_n(b)), target)
        # identifier: constant, variable, array ref, or function call
        m = re.match(r'[A-Za-z_]\w*', self.s[self.i:])
        if not m:
            raise SyntaxError(f"cannot parse {self.s[self.i:]!r}")
        name = m.group(0)
        self.i += len(name)
        low = name.lower()
        if low in ("true", "false"):
            return low == "true"
        if low == "empty":
            return ""
        self.ws()
        if self.i < len(self.s) and self.s[self.i] == "[":
            self.i += 1
            key = str(_disp(self.p_or()))
            self.ws()
            assert self.s[self.i] == "]"
            self.i += 1
            v = self.env.get(low, {})
            return v.get(key, "") if isinstance(v, dict) else ""
        if self.i < len(self.s) and self.s[self.i] == "(":
            self.i += 1
            args = []
            self.ws()
            if self.s[self.i] != ")":
                while True:
                    args.append(self.p_or())
                    self.ws()
                    if self.s[self.i] == ",":
                        self.i += 1
                        continue
                    break
            assert self.s[self.i] == ")", f"expected ) in {self.s!r}"
            self.i += 1
            return _builtin_or_handler(self.ip, name, args)
        if name in self.ip.constants:
            return self.ip.constants[name]
        if low in self.env:
            return self.env[low]
        if low in self.ip.handlers:
            return _builtin_or_handler(self.ip, name, [])
        return ""


def _disp(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return v


def _eq(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return str(_disp(a)).lower() == str(_disp(b)).lower()
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return _n(a) == _n(b)
    sa, sb = str(_disp(a)), str(_disp(b))
    try:
        return _n(sa) == _n(sb) if sa.strip() and sb.strip() and \
            re.fullmatch(r'-?\d+(\.\d+)?', sa.strip()) and \
            re.fullmatch(r'-?\d+(\.\d+)?', sb.strip()) else sa == sb
    except Exception:
        return sa == sb


def _chunk(unit, a, b, target):
    s = str(_disp(target))
    if unit.startswith("item"):
        parts = s.split(",") if s != "" else []
        if b is None:
            return parts[a - 1] if 1 <= a <= len(parts) else ""
        return ",".join(parts[a - 1:b])
    if b is None:
        return s[a - 1] if 1 <= a <= len(s) else ""
    if a < 1:
        a = 1
    return s[a - 1:b]


HASHES = {}


def _builtin_or_handler(ip, name, args):
    low = name.lower()
    if low == "bytetonum":
        s = str(_disp(args[0]))
        return ord(s[0]) if s else 0
    if low == "numtobyte":
        return chr(int(_n(args[0])) % 256)
    if low == "numtochar":
        return chr(int(_n(args[0])))
    if low == "chartonum":
        s = str(_disp(args[0]))
        return ord(s[0]) if s else 0
    if low == "trunc":
        return int(_n(args[0]))
    if low == "textencode":
        return str(_disp(args[0]))          # ASCII only in our vectors
    if low == "offset":
        hay, nee = str(_disp(args[1])), str(_disp(args[0]))
        return hay.find(nee) + 1
    if low in HASHES:
        return HASHES[low](args)
    if low in ip.handlers:
        return ip.call(name, args)
    raise NameError(f"unknown function {name}")
