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

ONE NAMED DIVERGENCE FROM THE ENGINE, because a general disclaimer is not much
use when the specific gap is known. `is` is modelled here as CASE-SENSITIVE for
strings (see _eq), while a real xTalk engine compares case-INSENSITIVELY unless
`the caseSensitive` is true. This interpreter is therefore STRICTER than the
engine on that one operator: a case bug it reports is real, but a case bug it
misses could still be there, and code that relies on `is` being case-insensitive
would pass here and behave differently on OXT. The shipped file does not rely on
either behaviour - it routes every case-significant comparison through
cxCharIndex, cxCaseKind or cxCompareBytes, which compare byte values and are
exact under both - and that is precisely why it does not.

It is deliberately literal and slow (cxBitXor alone is 31 interpreted iterations
per call, and a bech32 checksum calls it hundreds of times). Speed is not the
point; running the real text is.

ENGINE-CONFIRMED 2026-08-24 (Windows x86_64, OXT 9.6.3): the suite paste ran
2373/0 with every harness section that PINS these modeled divergences green -
the 1e3 integer fold, the trailing-delimiter eat, case-folding `is`, the
array-compares-as-array rule, script-local scope. Confirmation for the PINNED
cases, not a proof of the whole model: an unpinned behavior is still a model.

EXTENDED 2026-08-23 FOR THE NOSTRXT PORT (nostrxt/docs/08-open-questions.md
question 9; the copy in nostrxt/tools/ is byte-identical and drift-gated).
The additions are exactly what nostrxt/src/nostrxt.livecodescript uses beyond
coinxt's subset, measured rather than guessed: command/on handler definitions
and statement-position handler calls; `exit <handler>`; chained array
subscripts (read and write, any depth); `the keys of` and
`is [not] among the keys of`; `repeat for each item`; the lineDelimiter as
modelled state beside the itemDelimiter, with `line` chunks and
`sort lines of`; the operators `contains` / `begins with` / `ends with` /
`is [not] an integer` / `is [not] a number`; textEncode/textDecode with a real
UTF-8 encoding; and base64Encode/base64Decode. Everything outside the union is
still refused loudly.

THE NAMED DIVERGENCES GREW WITH IT, same contract as the `is` note above
(stricter-than-engine is acceptable and documented; looser is a bug):
  - `contains` / `begins with` / `ends with` are modelled CASE-SENSITIVELY,
    like `is`. The engine folds case on all three unless `the caseSensitive`
    is set. Stricter, same reasoning as _eq.
  - `is an integer` / `is a number` model the ENGINE's coercion faithfully
    ("1e3" IS an integer to the engine - docs/OXT-ENGINE-NOTES and nostrxt's
    own gotcha 4), because the shipped script GUARDS against that fold with
    digit-run checks and a stricter model here would test the guard against a
    world where the hazard does not exist.
  - `the keys of` returns keys in INSERTION order, one per line. The engine
    documents no order at all, so any script that needs one must sort - the
    shipped files do (`sort lines of`) - and a script that silently relied on
    an order would pass here and misbehave on an engine. Stricter would be
    randomising; insertion order plus the sort discipline is enough for the
    corpus this runs.
  - `sort lines of` sorts case-insensitively (the engine default), ASCII only.
  - base64Encode wraps its output with a line break every 72 characters. The
    real engine wraps too, at a width nobody has measured on OXT
    (nostrxt/docs/08 question 1); the shipped callers strip ALL whitespace, so
    any positive wrap width exercises them and the width itself cannot matter
    to a caller that survives this model.
  - textDecode with "utf-8" replaces invalid sequences (U+FFFD) rather than
    throwing, so an encode-decode round trip DIFFERS on invalid input - which
    is exactly the validity probe the shipped NIP-44 unpad performs.
  - AN ARRAY OPERAND OF `is` IS COMPARED AS AN ARRAY, not folded to a
    string: a populated array `is empty` answers FALSE, an array with no
    keys answers TRUE against empty, and two arrays compare by content.
    This is modelled from the TREE'S OWN ENGINE EVIDENCE, not from engine
    folklore: riptide's engine-proven identity path (`put rsIdentityKeys(...)
    into tKeys` / `if tKeys is empty then return empty`) uses exactly this
    refusal discriminator and passed on two machines, which is only possible
    if a populated array is NOT empty to `is`. (A first draft of this
    extension modelled the classic array-folds-to-empty rule instead, and
    driving the unmodified nostrxt script immediately "found" a dead
    validation block - reproduce-before-fix then checked the model against
    the engine-proven corpus and the MODEL was the bug. Suspect the probe
    first.) _disp still refuses to stringify an array in every string
    context (concatenation, chunks, contains) - the coinxt lesson stands.
"""
import base64
import re


class Thrown(Exception):
    def __init__(self, msg):
        self.msg = msg
        super().__init__(msg)


class Bytes(str):
    """xTalk does not distinguish a byte string from a text string; both are
    sequences of chars. We model everything as a python str of code points
    0..255, which is what byteToNum/numToByte imply."""


def split_outside_strings(line, words):
    """Split `line` at the first of `words` that appears OUTSIDE a string
    literal, as a whole word. Returns (before, word, after) or None.

    A non-greedy regex cannot do this, and getting it wrong is silent. The
    statement

        put "OXT script variables are not locked memory. A seed typed into
             this" & return after tOut

    splits at the `into` INSIDE its own message, leaving an unterminated
    string as the value expression - which surfaces far from the cause, as a
    ValueError out of the string scanner. Found 2026-08-31 by coinxt's boot
    gate on a paint handler no other gate had ever executed. The engine has
    a real tokenizer and never had this problem; this is the model catching
    up with it."""
    low = line.lower()
    i, instr = 0, False
    while i < len(line):
        c = line[i]
        if c == '"':
            instr = not instr
            i += 1
            continue
        if not instr:
            for w in words:
                n = len(w)
                if low[i:i + n] == w:
                    before_ok = i == 0 or not (line[i - 1].isalnum()
                                               or line[i - 1] == "_")
                    j = i + n
                    after_ok = j >= len(line) or not (line[j].isalnum()
                                                      or line[j] == "_")
                    if before_ok and after_ok:
                        return line[:i].rstrip(), w, line[j:].lstrip()
        i += 1
    return None


def _copy(v):
    """xTalk ARRAYS ARE VALUES, not references: `put tA into tB` copies, and a
    later write through tB leaves tA alone. Python dicts are references, so
    every place a value crosses a binding - assignment, argument, return -
    copies. Without this, cxHdNeuter (`put pNode into tNode`, then blank the
    private key) would silently blank the CALLER's node and the interpreter
    would model a bug the engine does not have."""
    return {k: _copy(x) for k, x in v.items()} if isinstance(v, dict) else v


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
        # SCRIPT-LEVEL `local` declarations: file-scope state shared by every
        # handler (an error slot, a capability cache). Modelled as visible
        # file-wide; the engine actually resolves script-level names by
        # LEXICAL POSITION (the suite's 106-declaration fold lesson), which
        # is not modelled here because the corpus declares its script-locals
        # at the top of the file, where the two rules agree - the family
        # checker and the fold machinery are what hold that discipline.
        self.globals = {}
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
            m = re.match(r'local\s+(.+)$', ln)
            if m:
                for v in m.group(1).split(","):
                    self.globals.setdefault(v.strip().lower(), "")
                i += 1
                continue
            m = re.match(r'(?:private\s+)?(?:function|command|on)\s+(\w+)\s*(.*)$', ln)
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
            env[p.lower()] = _copy(args[idx]) if idx < len(args) else ""
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

        # --- try / catch. Only the two-part form the script layer uses; there
        # is no `finally` here because nothing in the file has one, and
        # inventing semantics for a construct we do not ship would be exactly
        # the silent-mis-parse this interpreter refuses to do.
        if low == "try":
            inner, after = self._block(body, i, None, None)
            tryb, catchb, var, depth, seen = [], [], None, 0, False
            for ln in inner:
                s = ln.strip().lower()
                if re.match(r'^(if\b.*\bthen$|repeat\b|try\b)', s):
                    depth += 1
                elif re.match(r'^end\s+(if|repeat|try)\b', s):
                    depth -= 1
                mm = re.match(r'^catch\s+(\w+)$', ln.strip(), re.I)
                if depth == 0 and mm and not seen:
                    seen, var = True, mm.group(1).lower()
                    continue
                (catchb if seen else tryb).append(ln)
            if not seen:
                raise SyntaxError("try without catch")
            try:
                self._exec(tryb, env)
            except Thrown as t:
                env[var] = t.msg
                self._exec(catchb, env)
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
        # `repeat forever` - always paired with an `exit repeat` in the corpus;
        # the same runaway guard as `repeat while`, because an interpreter
        # that can hang is an interpreter whose failures nobody reads.
        if low == "repeat forever":
            inner, after = self._block(body, i, None, None)
            guard = 0
            while True:
                guard += 1
                if guard > 2_000_000:
                    raise RuntimeError("repeat forever did not terminate")
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
            return after
        # `repeat for each item VAR in EXPR` - the one for-each form the corpus
        # uses. The engine iterates a SNAPSHOT of the container, so the list is
        # materialised before the first pass and a mutation inside the loop
        # cannot change the iteration.
        m = re.match(r'repeat\s+for\s+each\s+item\s+(\w+)\s+in\s+(.+)$', line, re.I)
        if m:
            var, src_expr = m.group(1).lower(), m.group(2)
            inner, after = self._block(body, i, None, None)
            items = _split_chunks(str(_disp(self.eval_expr(src_expr, env))),
                                  ITEM_DELIMITER[0])
            for it in items:
                env[var] = it
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
            raise _Return(_copy(self.eval_expr(m.group(1), env))
                          if m.group(1).strip() else "")
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
        m = re.match(r'set\s+the\s+itemDelimiter\s+to\s+(.+)$', line, re.I)
        if m:
            ITEM_DELIMITER[0] = str(_disp(self.eval_expr(m.group(1), env)))
            return i + 1
        m = re.match(r'set\s+the\s+lineDelimiter\s+to\s+(.+)$', line, re.I)
        if m:
            LINE_DELIMITER[0] = str(_disp(self.eval_expr(m.group(1), env)))
            return i + 1
        # `sort lines of VAR` - ascending, case-insensitive (the engine
        # default), which is all the corpus asks of it (canonicalising a key
        # list before iteration). International collation is NOT modelled;
        # every sorted list in the corpus is ASCII.
        m = re.match(r'sort\s+lines\s+of\s+(\w+)$', line, re.I)
        if m:
            tgt = m.group(1)
            s = str(_disp(self.eval_expr(tgt, env)))
            parts = _split_chunks(s, LINE_DELIMITER[0])
            parts.sort(key=lambda x: x.lower())
            self.assign(tgt, LINE_DELIMITER[0].join(parts), env)
            return i + 1
        m = re.match(r'get\s+(.+)$', line, re.I)
        if m:
            # `get EXPR` evaluates EXPR and puts the value in `it`. The script
            # layer uses it to call a validator for its THROW, discarding the
            # return - so the evaluation is the whole point and `it` is not read.
            env["it"] = self.eval_expr(m.group(1), env)
            return i + 1
        m = re.match(r'replace\s+(.+?)\s+with\s+(.+?)\s+in\s+(\w+)$', line, re.I)
        if m:
            tgt = m.group(3).strip()
            old = str(_disp(self.eval_expr(m.group(1), env)))
            new = str(_disp(self.eval_expr(m.group(2), env)))
            self.assign(tgt, str(_disp(self.eval_expr(tgt, env))).replace(old, new), env)
            return i + 1
        m = re.match(r'delete\s+char\s+(.+?)\s+to\s+(.+?)\s+of\s+(.+)$', line, re.I)
        if m:
            a, b, tgt = int(_n(self.eval_expr(m.group(1), env))), int(_n(self.eval_expr(m.group(2), env))), m.group(3).strip()
            s = str(self.eval_expr(tgt, env))
            self.assign(tgt, s[:a - 1] + s[b:], env)
            return i + 1
        # STRING-AWARE, not a non-greedy regex: see split_outside_strings.
        parts = (split_outside_strings(line[4:], ("into", "after", "before"))
                 if re.match(r'put\s', line, re.I) else None)
        if parts:
            val, prep, tgt = parts[0], parts[1], parts[2].strip()
            v = self.eval_expr(val, env)
            if prep == "into":
                self.assign(tgt, v, env)
            else:
                cur = self.eval_expr(tgt, env)
                cur = "" if cur == "" else str(cur)
                self.assign(tgt, (cur + str(v)) if prep == "after" else (str(v) + cur), env)
            return i + 1
        # `exit <handlerName>` - return-with-no-value from anywhere in the
        # handler (the corpus uses it in command-shaped handlers). `exit
        # repeat` was consumed above, so any exit reaching here names a
        # handler; the name is not checked against the enclosing one because
        # the checker already enforces that pairing statically.
        m = re.match(r'exit\s+(\w+)$', line, re.I)
        if m and m.group(1).lower() != "repeat":
            raise _Return("")
        # A statement-position HANDLER CALL (`nxSetError "..."`, or bare with
        # no arguments - the zero-arg form must be bare, which the family
        # checker enforces; the parenthesised spelling is the engine trap this
        # interpreter must not quietly accept either, and does not: it would
        # arrive here as a call whose one argument is `()` and fail to parse).
        m = re.match(r'([A-Za-z_]\w*)\s*(.*)$', line)
        if m and m.group(1).lower() in self.handlers:
            args = []
            rest = m.group(2).strip()
            if rest:
                p = _Expr(self, env)
                p.s, p.i = rest, 0
                while True:
                    args.append(p.p_or())
                    p.ws()
                    if p.i < len(p.s) and p.s[p.i] == ",":
                        p.i += 1
                        continue
                    break
                if p.i < len(p.s):
                    raise SyntaxError(f"trailing input in call {line!r}")
            self.call(m.group(1), args)
            return i + 1
        raise SyntaxError(f"unsupported statement: {line!r}")

    def assign(self, target, value, env):
        m = re.match(r'^(\w+)\s*\[', target)
        if m:
            # A bracket CHAIN (`tTags[tI][tJ]`, any depth), each key itself a
            # full expression, scanned with depth counting so a subscripted
            # key (`tA[tB[1]]`) cannot split the chain in the wrong place.
            name = m.group(1).lower()
            keys, i = [], len(m.group(1))
            while i < len(target) and target[i] in " \t":
                i += 1
            while i < len(target) and target[i] == "[":
                depth, j = 1, i + 1
                while j < len(target) and depth:
                    if target[j] == "[":
                        depth += 1
                    elif target[j] == "]":
                        depth -= 1
                    j += 1
                if depth:
                    raise SyntaxError(f"unbalanced subscript in {target!r}")
                keys.append(str(_disp(self.eval_expr(target[i + 1:j - 1], env))))
                i = j
                while i < len(target) and target[i] in " \t":
                    i += 1
            if i != len(target):
                raise SyntaxError(f"cannot assign to {target!r}")
            store = (self.globals if (name not in env and name in self.globals)
                     else env)
            if not isinstance(store.get(name), dict):
                store[name] = {}
            node = store[name]
            for k in keys[:-1]:
                if not isinstance(node.get(k), dict):
                    node[k] = {}
                node = node[k]
            node[keys[-1]] = _copy(value)
            return
        low = target.lower()
        if low not in env and low in self.globals:
            self.globals[low] = _copy(value)
            return
        env[low] = _copy(value)

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
            if self.kw("contains"):
                r = self.p_concat()
                v = str(_disp(r)) in str(_disp(v))
                continue
            if self.kw("begins"):
                assert self.kw("with"), f"expected `with` in {self.s!r}"
                r = self.p_concat()
                v = str(_disp(v)).startswith(str(_disp(r)))
                continue
            if self.kw("ends"):
                assert self.kw("with"), f"expected `with` in {self.s!r}"
                r = self.p_concat()
                v = str(_disp(v)).endswith(str(_disp(r)))
                continue
            if self.kw("is"):
                neg = bool(self.kw("not"))
                if self.kw("among"):
                    assert self.kw("the") and self.kw("keys") and self.kw("of"), \
                        f"expected `the keys of` in {self.s!r}"
                    target = self.p_concat()
                    hit = isinstance(target, dict) and str(_disp(v)) in target
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
                        hit = _is_numeric(v, word == "integer")
                        v = (not hit) if neg else hit
                        continue
                    self.i = save2
                r = self.p_concat()
                v = (not _eq(v, r)) if neg else _eq(v, r)
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
            if self.kw("itemdelimiter"):
                return ITEM_DELIMITER[0]
            if self.kw("linedelimiter"):
                return LINE_DELIMITER[0]
            if self.kw("seconds"):
                # deterministic tooling: a fixed epoch a driver may set, never
                # the wall clock (a gate that reads real time is a gate whose
                # failures cannot be reproduced).
                return SECONDS[0]
            if self.kw("keys"):
                # `the keys of EXPR`: one key per line, INSERTION order (the
                # engine documents no order; see the named divergences above).
                assert self.kw("of"), f"expected `of` in {self.s!r}"
                target = self.p_concat()
                if not isinstance(target, dict):
                    return ""
                return "\n".join(target.keys())
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
                    return len(_split_chunks(s, ITEM_DELIMITER[0]))
                return len(_split_chunks(s, LINE_DELIMITER[0]))
            raise SyntaxError(f"unsupported `the` expression in {self.s!r}")
        # chunk expressions: byte/char/item/line N [to M] of EXPR
        unit = self.kw("byte", "bytes", "char", "chars", "character", "item",
                       "items", "line", "lines")
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
        # The named literals for characters that cannot be written inside a
        # quoted string without ambiguity.
        if low in ("comma", "space", "tab", "quote", "return", "cr", "lf",
                   "linefeed", "crlf"):
            # `return`/`cr`/`lf`/`linefeed` are all LINEFEED in LiveCodeScript
            # (the engine's cr has been 0x0A since classic MacOS days ended);
            # crlf is the two-byte network form.
            return {"comma": ",", "space": " ", "tab": "\t", "quote": '"',
                    "return": "\n", "cr": "\n", "lf": "\n",
                    "linefeed": "\n", "crlf": "\r\n"}[low]
        self.ws()
        if self.i < len(self.s) and self.s[self.i] == "[":
            # a bracket CHAIN: each step reads one key; a missing key or a
            # non-array node answers empty, the engine's behaviour.
            v = self.env.get(low, self.ip.globals.get(low, {}))
            while self.i < len(self.s) and self.s[self.i] == "[":
                self.i += 1
                key = str(_disp(self.p_or()))
                self.ws()
                assert self.s[self.i] == "]"
                self.i += 1
                v = v.get(key, "") if isinstance(v, dict) else ""
                self.ws()
            return v
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
        if low in self.ip.globals:
            return self.ip.globals[low]
        if low in self.ip.handlers:
            return _builtin_or_handler(self.ip, name, [])
        return ""


def _disp(v):
    if isinstance(v, dict):
        # An array has no string value in xTalk. Rendering one as Python's
        # `{'a': 1}` would let a chunk expression or a concatenation quietly
        # produce nonsense, so this refuses instead - the same reason the rest
        # of the interpreter raises on anything outside the modelled subset.
        raise TypeError("an array has no string value; index it or use its keys")
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return v


def _eq(a, b):
    if isinstance(a, dict) or isinstance(b, dict):
        if isinstance(a, dict) and isinstance(b, dict):
            return a == b
        arr, other = (a, b) if isinstance(a, dict) else (b, a)
        return len(arr) == 0 and str(_disp(other)) == ""
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


def _split_chunks(s, d):
    # The engine ignores ONE trailing delimiter when it chunks a string:
    # "m," is ONE item, "a,," is two, "," is one (empty) item. Modelling this
    # with a bare Python split() over-counts by one whenever the string ends
    # with the delimiter, and that mismatch is exactly how cxHdDerivePath's
    # "m/" fail-open stayed invisible to this gate while failing on the real
    # engine (pass of 2026-08-10): the gate's own negative vector exercised
    # the check against a model in which the check fires, and the engine
    # never ran it. Items were engine-observed; lines follow the same
    # documented chunk rule.
    if s == "":
        return []
    if s.endswith(d):
        s = s[:-len(d)]
    return s.split(d)


def _negative_index(i, count):
    """xTalk counts a NEGATIVE chunk index from the end: -1 is the last
    element, -2 the one before it. Fixed 2026-08-28; before that this
    function did not exist and _chunk simply CLAMPED a negative start to 1
    and handed a negative end straight to a Python slice, so
    `char -3 to -1 of "abcdef"` came back "abcde" instead of "def" - wrong
    at both ends, and silently.

    It was latent rather than active: neither coinxt's nor nostrxt's shipped
    source uses a negative range, so no gate was reading a wrong answer. It
    surfaced when riptide's execution gate met `byte 10 to -1 of pFileBytes`,
    the engine-proven idiom rsOpenMasterSeed has used since phase 1 - which
    is the point worth keeping: the tool was not wrong about anything it had
    been asked, and a member with a slightly different dialect habit was all
    it took. Positive indices are untouched, deliberately, so nothing that
    passed before can change."""
    if i is None or i >= 0:
        return i
    return count + 1 + i


def _chunk(unit, a, b, target):
    s = str(_disp(target))
    if unit.startswith("item") or unit.startswith("line"):
        d = ITEM_DELIMITER[0] if unit.startswith("item") else LINE_DELIMITER[0]
        parts = _split_chunks(s, d)
        a = _negative_index(a, len(parts))
        b = _negative_index(b, len(parts))
        if b is None:
            return parts[a - 1] if 1 <= a <= len(parts) else ""
        if a < 1:
            a = 1
        return d.join(parts[a - 1:b])
    a = _negative_index(a, len(s))
    b = _negative_index(b, len(s))
    if b is None:
        return s[a - 1] if 1 <= a <= len(s) else ""
    if a < 1:
        a = 1
    if b < 0:
        return ""
    return s[a - 1:b]


def _is_numeric(v, want_int):
    """`is a number` / `is an integer`, modelled the ENGINE's way: the operand
    is parsed as a number first, so "1e3" IS an integer here (see the named
    divergences in the header - the shipped scripts guard against exactly this
    fold with digit-run checks, and a stricter model would test those guards
    against a world without the hazard)."""
    try:
        s = str(_disp(v)).strip()
    except TypeError:
        return False
    if s == "":
        return False
    try:
        f = float(s)
    except ValueError:
        return False
    return f == int(f) if want_int else True


HASHES = {}

# ---------------------------------------------------------------------------
# `the itemDelimiter`, modelled rather than hardcoded.
#
# This used to be a hidden assumption: item chunks split on "," unconditionally,
# so a script's dependence on the engine default was INVISIBLE here. An
# adversarial review flagged exactly that, and it matters because the property is
# GLOBAL MUTABLE STATE in this engine family (templates/CLAUDE.md rule 5) - an
# app may set it and not restore it, and any script that reads `item` afterwards
# then silently parses something else.
#
# Modelling it lets a gate run the published vectors under a HOSTILE delimiter
# and see what the engine would really do. Without this, no fix for that exposure
# could be verified headlessly, only asserted.
# ---------------------------------------------------------------------------
ITEM_DELIMITER = [","]

# The lineDelimiter, the same modelled-global-state story as the item
# delimiter above: the corpus saves, sets, uses and restores it around every
# line-shaped parse, and modelling it is what lets a gate prove that
# discipline rather than assume it.
LINE_DELIMITER = ["\n"]

# `the seconds`, as a settable constant (see the note at its read site).
SECONDS = [1700000000]


def set_item_delimiter(ch):
    """Set the modelled delimiter. Returns the previous value, so a caller can
    restore it the way the family's own rule requires."""
    was = ITEM_DELIMITER[0]
    ITEM_DELIMITER[0] = ch
    return was


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
        # 1-arg / non-UTF-8 stays the identity the coinxt vectors use (ASCII);
        # "utf-8"/"utf8" performs the real encoding, TEXT code points in to a
        # 0..255 byte string out - the model the Bytes docstring above states.
        enc = str(_disp(args[1])).lower() if len(args) > 1 else ""
        if enc in ("utf-8", "utf8"):
            return str(_disp(args[0])).encode("utf-8").decode("latin-1")
        return str(_disp(args[0]))          # ASCII only in our vectors
    if low == "textdecode":
        enc = str(_disp(args[1])).lower() if len(args) > 1 else ""
        if enc in ("utf-8", "utf8"):
            # invalid sequences become U+FFFD rather than raising - the
            # documented divergence that makes the shipped encode-decode
            # round-trip validity probe behave the way it was designed to.
            return str(_disp(args[0])).encode("latin-1").decode("utf-8", errors="replace")
        return str(_disp(args[0]))
    if low == "base64encode":
        raw = str(_disp(args[0])).encode("latin-1")
        enc = base64.b64encode(raw).decode("ascii")
        # the engine wraps; the width is a modelled guess (header note) that
        # any whitespace-stripping caller is indifferent to.
        return "\n".join(enc[k:k + 72] for k in range(0, len(enc), 72))
    if low == "base64decode":
        txt = re.sub(r"\s+", "", str(_disp(args[0])))
        try:
            return base64.b64decode(txt.encode("ascii"), validate=False).decode("latin-1")
        except Exception:
            return ""
    if low == "offset":
        hay, nee = str(_disp(args[1])), str(_disp(args[0]))
        return hay.find(nee) + 1
    if low in HASHES:
        return HASHES[low](args)
    if low in ip.handlers:
        return ip.call(name, args)
    raise NameError(f"unknown function {name}")
