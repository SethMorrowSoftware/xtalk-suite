#!/usr/bin/env python3
"""check-platformer-levels.py - BUILD AND PLAY every platformer level, headlessly.

WHY THIS EXISTS. On 2026-10-08 the platformer (examples/box2dxt-platformer
.livecodescript) met three reports in one day: the art had to be re-imported
on every open (fixed by the first-run import), each level took a long time to
build (fixed by the quiet build, which also found every flag building the next
level TWICE), and level 4 froze the IDE before it began (an endless `next
repeat` in pfL4Scene; gotcha 32). No gate could have seen any of them: the
static checker cannot tell that a loop never ends or that a menu sync sends a
message, and tools/audit-platformer.py reads geometry. Every one of them shows
when the game RUNS, so this gate runs it: the shipped text, opened, imported,
saved, reopened and played through every level to its flag.

WHAT IT DOES. Three profiles, each a fresh sandbox and a fresh stack:

  art          the first open with the repository's Spritesheets/ folder: the
               first-run import (pfImportMedia), its save offer taken, and
               the saved stack captured as `save` wrote it.
  reopen       that saved stack opened in a new sandbox with NO art folder
               and no dialog planned: it must reach the title with its art
               and read no file at all, at the open or in play.
  placeholder  Cancel at the folder prompt: the built-in placeholder hero.

In each, SPACE at the title, then every level in turn: wait out the reveal;
stand on the flag first (short of the coins it must refuse, and say so); take
every key, open every door, press every switch, take every coin, gem and
star, touch every checkpoint, jump into every ?-box and brick (three tries,
as a player would retry a jump a slime spoiled); hold the coin count to the
level's own total; then the flag must clear the level, or on L7 win the run.
The hero is MOVED to each thing (b2kMoveTo, as the game's own edge clamp
moves him), not steered there: this settles that every level builds, that
each thing in it works and that the level can be finished, not that a player
can reach it (layout needs a human eye; box2dxt CLAUDE.md section 8).

Whatever the tour reached, each profile must also show: each level built
ONCE, in order, and no build begun inside another; no menuPick from the level
picker's sync (engine note 5.14); no create, delete or rename message sent
while a level builds with messages unlocked, which the IDE answers at a cost
(engine note 5.15; the first run of this gate found the no-art build sending
them, fixed in the same change); no error that no `try` caught (the engine's
script-error dialog); no error caught but the three catches the game and the
Kit make by design (DESIGNED_CATCHES, each with its reason), and above all
none swallowed by b2kStep's frame `try`, which is silent on an engine
(gotcha 31); the sound system never tripped (b2kSoundStatus); and
every planned dialog met. Each event runs on a STATEMENT budget about ten
times what the shipped game was measured to need (--verbose prints the
peaks), so a build that never ends fails in seconds and names the handler it
was in, instead of hanging the gate the way it hung the IDE.

HOW. The shipped text is prepared (comments cut, `\\` continuations joined,
the engine's one-line `if` forms re-emitted as blocks; nothing else is
rewritten) and executed by a closure compiler with the engine's grammar,
over the family interpreter's value layer (nostrxt's lcs-interp.py, loaded by
riptide's boot runner: arrays, chunks, the engine's number reading). The
engine around the script - objects, properties, layers, groups, messages,
`send ... in` timers on a virtual 16 ms frame clock, `the keysDown`, dialogs,
files - is modelled in World and the property tables, each rule read from the
engine's source (livecode/livecode at 4606a10, BUILD_SHORT_VERSION 9.7.0-dp-1,
the version OXT's Linux preflight printed on 2026-09-26; DOCUMENTED) and cited
where it is used. src/box2dxt.lcb is TRANSLATED onto this member's committed
src/code/x86_64-linux/box2dxt.so through ctypes (LcbBridge refuses a handler
shape it does not know), so the physics is the real Box2D v3.1.0, and the
library's ABI is checked before anything runs. A construct the model does not
know is a ModelRefusal naming it, never a guess: the gate grew one refusal at
a time, and the next unmodelled corner of the engine will be as loud.

WHAT IT IS NOT. The engine. It settles the game's LOGIC on a model of one,
and promotes nothing past "verified statically + headless; needs an OXT
pass": not parsing, painting, timing, sound or feel. If this gate and the
engine disagree, the engine is right. Its stand-ins, declared:
  - `and` and `or` SHORT-CIRCUIT here, as engine/src/operator.cpp's MCAnd and
    MCOr evaluate them ("CONDITIONAL EVALUATION") and as the LiveCode
    dictionary's `and` entry documents. The suite's engine note 2.5 records
    the opposite as DOCUMENTED, until its runbook probe P(b) runs; the Kit's
    b2kSheetEnsureIcon guards (`there is an image tName and the uB2kSig of
    image tName is ...`) rely on the short-circuit, and this gate cannot see
    that reliance.
  - Pixels are decoded for real (a small PNG reader) and sliced, flipped and
    scaled to the right sizes, but no check reads a pixel's value; nothing is
    painted. Sounds are made and never heard.
  - The IDE is absent: its cost shows only as the engine messages counted
    where the engine would send them.
  - Dialogs are answered from each profile's plan; one not planned fails it.
  - The random function is seeded, so a run is repeatable.

THE SIBLINGS (the suite's docs/MEMBER-REPO-SPLIT.md): riptide, for its boot
runner (tools/check-demo-boot.py: the interpreter it loads, its compiled
regex helpers and its non-literal-constant refusal), which loads nostrxt's
interpreter at import, so nostrxt too. (The runner's coinxt binary is optional
and this gate never asks for it.) sibling() below resolves them: the
directory beside this member in the suite tree, the repository cloned beside
it in a standalone checkout, or wherever XTALK_SIBLING_<NAME> / XTALK_SIBLINGS
point. An absent runner stops the gate (exit 2, naming the clone to make).

tools/test-platformer-levels.py edits a defect of each class this gate fails
on, one at a time, into a copy of the game (the old level-4 loop and the
double build among them) and requires this gate to fail naming each; a gate
that went blind would otherwise print OK.

Usage (from the member root):
  python3 tools/check-platformer-levels.py                  # every profile
  python3 tools/check-platformer-levels.py --verbose        # a line a level
  python3 tools/check-platformer-levels.py --profiles art,placeholder
  python3 tools/check-platformer-levels.py --file PATH      # drive a copy
Exit 0 when every profile passed, 1 when one failed, 2 on a setup problem.
"""
import base64
import binascii
import copy
import ctypes
import heapq
import importlib.util
import math
import os
import random
import re
import shutil
import struct
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GAME = os.path.join(MEMBER, "examples", "box2dxt-platformer.livecodescript")
LCB = os.path.join(MEMBER, "src", "box2dxt.lcb")
# This member's OWN committed library - MEMBER-relative, never a sibling.
SO = os.path.join(MEMBER, "src", "code", "x86_64-linux", "box2dxt.so")
ART = os.path.join(MEMBER, "Spritesheets")


def sibling(name):
    """Path of a sibling member's checkout (the suite's
    docs/MEMBER-REPO-SPLIT.md), resolved exactly as coinxt's wallet boot
    resolves it: a member's own name answers this checkout, then
    XTALK_SIBLING_<NAME>, then XTALK_SIBLINGS, then the directory beside
    this member. Nothing is searched for."""
    if name == os.path.basename(MEMBER):
        return MEMBER
    one = os.environ.get("XTALK_SIBLING_" + name.upper().replace("-", "_"))
    if one:
        return one
    return os.path.join(os.environ.get("XTALK_SIBLINGS")
                        or os.path.dirname(MEMBER), name)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# riptide's boot runner is the one sibling file this gate needs, and it
# needs it before anything else loads: its absence is a setup problem
# (stderr, exit 2), not a level failure.
RUNNER = os.path.join(sibling("riptide"), "tools", "check-demo-boot.py")
if not os.path.isfile(RUNNER):
    print("check-platformer-levels: %s is not present: it belongs to the "
          "riptide member, which is not beside this checkout. Clone "
          "https://github.com/SethMorrowSoftware/RipTide beside this checkout "
          "as ../riptide (and its own gate siblings, nostrxt and coinxt), or "
          "point XTALK_SIBLING_RIPTIDE / XTALK_SIBLINGS at it." % RUNNER,
          file=sys.stderr)
    sys.exit(2)
DB = _load("check_demo_boot", RUNNER)
LCS = DB.LCS                    # the ONE interpreter the run executes on
Thrown = LCS.Thrown
_rx, _rxi = DB._rx, DB._rxi


class ModelRefusal(Exception):
    """The MODEL met a construct it does not know. Never a Thrown, so no
    script `try` can swallow it: an unmodelled corner of the engine is a
    loud gate failure naming the line, never a silent wrong answer."""


class Budget(Exception):
    """A statement budget ran out: a level build, an import or a frame
    batch that does not finish is the 2026-10-08 level-4 freeze's shape,
    and it is reported as that, not as a Python RecursionError or a
    two-million-iteration guard minutes later. Not a Thrown either."""


# ==========================================================================
# the source, as the interpreter's subset needs it
# ==========================================================================

def _strip_comment(line):
    """Cut a `--` comment outside string literals (the game writes no `#`,
    `//` or block comments; prepare() refuses them if one appears)."""
    instr = False
    for k, ch in enumerate(line):
        if ch == '"':
            instr = not instr
        elif not instr and ch == "-" and line.startswith("--", k):
            return line[:k].rstrip()
    return line.rstrip()


def _find_word(s, word, start=0):
    """Index of `word` as a whole word OUTSIDE string literals, or -1."""
    instr = False
    n, w = len(s), len(word)
    k = start
    while k < n:
        ch = s[k]
        if ch == '"':
            instr = not instr
        elif (not instr and s[k:k + w].lower() == word
              and (k == 0 or not (s[k - 1].isalnum() or s[k - 1] == "_"))
              and (k + w >= n or not (s[k + w].isalnum() or s[k + w] == "_"))):
            return k
        k += 1
    return -1


class _IfNormalizer(object):
    """LiveCode's `if` grammar -> the interpreter's block form.

    The family interpreter models only `if C then` / `else if C then` /
    `else` / `end if` on lines of their own. The game writes every form the
    ENGINE's parser takes (engine/src/keywords.cpp, MCIf::parse; DOCUMENTED,
    read 2026-10-08): `if C then S` on one line; that one-liner followed by
    `else S` or `else if ...` on the NEXT line; `if C then S1 else S2` on
    one line; and a block `then` closed by a one-line `else S`, which ENDS
    the statement with no `end if`. The state machine is the engine's: after
    a one-line `then`, a following line that begins with `else` continues
    the statement and anything else ends it; an `else` with a statement on
    its own line takes that ONE statement and ends it (an `else if` is that
    one statement, a nested if, so chains nest); an `else` alone on a line
    opens a block to `end if`. Every if is re-emitted with its own `end if`,
    which is the same program."""

    def __init__(self, lines):
        self.lines = lines
        self.out = []

    def run(self):
        i = self.block(0, ())
        if i != len(self.lines):
            raise SyntaxError("stray %r at logical line %d"
                              % (self.lines[i], i + 1))
        return self.out

    @staticmethod
    def _starts(line, word):
        low = line.lower()
        return low == word or (low.startswith(word) and not
                               (low[len(word)].isalnum() or low[len(word)] == "_"))

    def block(self, i, stops):
        while i < len(self.lines):
            line = self.lines[i]
            low = line.lower()
            if ("else" in stops and self._starts(line, "else")) or \
                    ("end if" in stops and _rx(r'^end\s+if\b').match(low)):
                return i
            if self._starts(line, "if"):
                i = self.if_stmt(line, i + 1)
                continue
            if self._starts(line, "else") or _rx(r'^end\s+if\b').match(low):
                raise SyntaxError("unmatched %r (logical line %d)" % (line, i + 1))
            self.out.append(line)
            i += 1
        return i

    def inline(self, text, i):
        """One statement written on the line of a `then` or an `else`."""
        if self._starts(text, "if"):
            return self.if_stmt(text, i)
        self.out.append(text)
        return i

    def if_stmt(self, text, i):
        k = _find_word(text, "then", 3)
        if k < 0:
            raise SyntaxError("an `if` with no `then`: %r" % text)
        cond = text[3:k].strip()
        rest = text[k + 4:].strip()
        self.out.append("if %s then" % cond)
        if rest:
            e = _find_word(rest, "else")
            if e >= 0:
                # `if C then S1 else S2` on one line: the ELSE statement is
                # the last, and may itself be an `if` that reads on
                self.inline(rest[:e].strip(), i)
                self.out.append("else")
                i = self.inline(rest[e + 4:].strip(), i)
                self.out.append("end if")
                return i
            i = self.inline(rest, i)
            if i < len(self.lines) and self._starts(self.lines[i], "else"):
                return self.else_part(self.lines[i], i + 1)
            self.out.append("end if")
            return i
        i = self.block(i, ("else", "end if"))
        if i >= len(self.lines):
            raise SyntaxError("an `if` block with no `end if`: %r" % text)
        if _rx(r'^end\s+if\b').match(self.lines[i].lower()):
            self.out.append("end if")
            return i + 1
        return self.else_part(self.lines[i], i + 1)

    def else_part(self, line, i):
        rest = line[4:].strip()
        self.out.append("else")
        if rest:
            i = self.inline(rest, i)
            self.out.append("end if")
            return i
        i = self.block(i, ("end if",))
        if i >= len(self.lines):
            raise SyntaxError("an `else` block with no `end if`")
        self.out.append("end if")
        return i + 1


def prepare(text, fail):
    """The shipped text -> the interpreter's input: comments cut, `\\`
    continuations joined, the `if` forms normalised. Nothing else is
    rewritten: every other spelling is the model's to understand or refuse."""
    if re.search(r'^\s*(#|//)', text, re.M) or "/*" in re.sub(r'"[^"\n]*"', '', text):
        fail("a `#`, `//` or block comment appeared in the game; prepare() "
             "cuts only `--` comments")
    DB._refuse_nonliteral_constants(text, fail)
    logical, buf = [], ""
    for raw in text.split("\n"):
        code = _strip_comment(raw).strip()
        if code.endswith("\\"):
            buf += code[:-1] + " "
            continue
        code = (buf + code).strip()
        buf = ""
        if code:
            logical.append(code)
    try:
        lines = _IfNormalizer(logical).run()
    except SyntaxError as exc:
        fail("the game's `if` structure did not normalise: %s" % exc)
    return "\n".join(lines)


# ==========================================================================
# box2dxt.lcb, bound to the committed library
# ==========================================================================

_BIG_EXACT = 2 ** 53


class LcbBridge(object):
    """Every public handler of src/box2dxt.lcb, callable from the model, on
    the COMMITTED x86_64-linux library through ctypes.

    It is a translation of the .lcb, not a hand-written fake: each public
    handler's body is read and must be one of the five shapes the file is
    written in (a foreign call into tR and `return tR`; the same returning
    `tR is 1`; a foreign command; checkABI then a call; `return b2X(...)`),
    and an argument is a parameter, `bi(pX)`, `pX - 1` / `pX + 1` or a
    literal. Anything else is refused at load, by name, so a new handler
    shape fails this gate instead of being guessed at.

    The boundary is the engine's (engine/src/exec-extension.cpp, DOCUMENTED):
    a script value bound to a Number or Integer parameter passes as a number
    when it is one, and text through the engine's string-to-real; EMPTY, a
    Boolean or non-numeric text is a "cannot convert value" script error a
    `try` can catch (engine note 6.4 is the empty case). A Boolean parameter
    takes a Boolean or the text true/false, caseless. Too many arguments
    and too few are each a script error (EE_INVOKE_TOOMANYARGS and
    TOOFEWARGS in MCEngineHandleLibraryMessage). The handler's answer
    becomes `the result`, whether it was called as a command or a function.
    A Number into a CInt is truncated toward zero, the
    foreign layer's conversion; one past the int range is refused here
    (Imprecise-class, not a Thrown) rather than modelled."""

    _CTYPE = {"CInt": ctypes.c_int, "CDouble": ctypes.c_double}

    def __init__(self, lcb_path, so_path):
        self.lib = ctypes.CDLL(so_path)
        with open(lcb_path, "r", encoding="utf-8") as fh:
            src = fh.read()
        self.foreign = {}
        for m in re.finditer(
                r'^private foreign handler (_\w+)\((.*?)\) returns '
                r'(optional )?(\w+) binds to "c:(\w*)>(\w+)!cdecl"', src, re.M):
            name, params, _opt, ret, libname, sym = m.groups()
            if libname != "box2dxt":
                continue            # the loader assist (dlopen/realpath)
            ptypes = [p.strip().split()[-1] for p in params.split(",")
                      if p.strip()]
            fn = getattr(self.lib, sym)
            fn.argtypes = [self._CTYPE[t] for t in ptypes]
            fn.restype = None if ret == "nothing" else self._CTYPE[ret]
            self.foreign[name] = (fn, ptypes, ret)
        self.public = {}
        lines = src.split("\n")
        i = 0
        while i < len(lines):
            m = re.match(r'(public|private) handler (\w+)\((.*)\)'
                         r'(?: returns (\w+))?\s*$', lines[i])
            if not m:
                i += 1
                continue
            vis, name, params, ret = m.groups()
            body = []
            i += 1
            while not lines[i].startswith("end handler"):
                s = lines[i].strip()
                if s and not s.startswith("--"):
                    body.append(s)
                i += 1
            if vis == "public":
                plist = []
                for p in params.split(","):
                    p = p.strip()
                    if p:
                        pm = re.match(r'in (p\w+) as (\w+)$', p)
                        plist.append((pm.group(1), pm.group(2)))
                self.public[name.lower()] = (name, plist, ret,
                                             self._shape(name, body))
            i += 1
        self.calls = 0

    _LOADER = ("b2LoadNativeLibHere", "b2LoadNativeLib", "b2LoadNativeLibError")

    def _shape(self, name, body):
        b = [s for s in body if not s.startswith("variable ")]
        if name in self._LOADER:
            return ("loader", None)
        if len(b) == 1:
            m = re.match(r'return (b2\w+)\((.*)\)$', b[0])
            if m:
                return ("delegate", (m.group(1), self._args(name, m.group(2))))
        if b[:1] == ["checkABI()"]:
            b = b[1:]
            abi = True
        else:
            abi = False
        if len(b) == 4 and b[0] == "unsafe" and b[2] == "end unsafe":
            m = re.match(r'put (_\w+)\((.*)\) into tR$', b[1])
            if m and b[3] in ("return tR", "return tR is 1"):
                return ("call", (abi, m.group(1), self._args(name, m.group(2)),
                                 b[3] == "return tR is 1"))
        if len(b) == 3 and b[0] == "unsafe" and b[2] == "end unsafe" and not abi:
            m = re.match(r'(_\w+)\((.*)\)$', b[1])
            if m:
                return ("command", (m.group(1), self._args(name, m.group(2))))
        raise ModelRefusal("box2dxt.lcb: public handler %s has a body shape "
                           "the bridge does not translate: %r" % (name, body))

    @staticmethod
    def _args(name, text):
        out = []
        for a in [x.strip() for x in text.split(",") if x.strip()]:
            m = (re.match(r'^(p\w+)$', a) or re.match(r'^bi\((p\w+)\)$', a)
                 or re.match(r'^(p\w+) ([-+]) (\d+)$', a))
            if re.match(r'^-?\d+(\.\d+)?$', a):
                out.append(("lit", float(a) if "." in a else int(a)))
            elif a in ("true", "false"):
                out.append(("lit", a == "true"))
            elif m and a.startswith("bi("):
                out.append(("bi", m.group(1)))
            elif m and m.lastindex == 3:
                out.append(("off", (m.group(1), m.group(2), int(m.group(3)))))
            elif m:
                out.append(("param", m.group(1)))
            else:
                raise ModelRefusal("box2dxt.lcb: %s passes %r, an argument "
                                   "shape the bridge does not translate"
                                   % (name, a))
        return out

    # -- the script boundary ------------------------------------------------
    @staticmethod
    def _to_number(name, pname, v):
        if isinstance(v, bool):
            raise Thrown("%s: cannot convert value (a Boolean into %s, a "
                         "Number)" % (name, pname))
        if isinstance(v, (int, float)):
            return float(v)
        s = str(LCS._disp(v))
        try:
            if s.strip() == "" or s != s.strip():
                raise ValueError(s)
            f = float(s)
        except ValueError:
            raise Thrown("%s: cannot convert value (%r into %s, a Number)"
                         % (name, s, pname))
        if f != f or f in (float("inf"), float("-inf")):
            raise ModelRefusal("%s: %r into %s reads as %r; the engine's "
                               "string-to-real is not modelled that far"
                               % (name, s, pname, f))
        return f

    @staticmethod
    def _to_bool(name, pname, v):
        if isinstance(v, bool):
            return v
        s = str(LCS._disp(v)).lower()
        if s in ("true", "false"):
            return s == "true"
        raise Thrown("%s: cannot convert value (%r into %s, a Boolean)"
                     % (name, s, pname))

    @staticmethod
    def _to_cint(name, x):
        t = int(x)                          # toward zero, as C's cast does
        if not -2147483648 <= t <= 2147483647:
            raise LCS.Imprecise("%s: %r does not fit the CInt the binding "
                                "passes" % (name, x))
        return t

    def call(self, name, args):
        key = name.lower()
        rec = self.public.get(key)
        if rec is None:
            raise NameError(name)
        hname, plist, ret, (kind, data) = rec
        if len(args) != len(plist):
            raise Thrown("%s: too %s arguments (%d for %d)"
                         % (hname, "many" if len(args) > len(plist) else "few",
                            len(args), len(plist)))
        env = {}
        for k, (pname, ptype) in enumerate(plist):
            v = args[k]
            if ptype in ("Number", "Integer"):
                env[pname] = self._to_number(hname, pname, v)
            elif ptype == "Boolean":
                env[pname] = self._to_bool(hname, pname, v)
            else:
                env[pname] = str(LCS._disp(v))
        self.calls += 1
        if kind == "loader":
            raise ModelRefusal("%s: the Linux loader assist is not modelled "
                               "(nothing in the game calls it)" % hname)
        if kind == "delegate":
            target, argspec = data
            return self.call(target, [self._arg(env, a) for a in argspec])
        if kind == "command":
            fname, argspec = data
            self._foreign(hname, fname, [self._arg(env, a) for a in argspec])
            return ""
        abi, fname, argspec, is_one = data
        if abi:
            self.check_abi()
        r = self._foreign(hname, fname, [self._arg(env, a) for a in argspec])
        if is_one:
            return r == 1
        if ret == "Integer":
            return LCS._exact(int(r))
        if ret == "Number":
            if r != r or r in (float("inf"), float("-inf")):
                # a NaN or an infinity out of the solver is a defect in what
                # the script fed it (a zero-size shape, a runaway force), and
                # it is failed here by name rather than printed as "nan"
                raise ModelRefusal("%s answered %r" % (hname, r))
            return int(r) if r == int(r) and abs(r) <= _BIG_EXACT else r
        if ret == "Boolean":
            return bool(r)
        raise ModelRefusal("%s returns %s, which the bridge does not "
                           "translate" % (hname, ret))

    @staticmethod
    def _arg(env, spec):
        kind, v = spec
        if kind == "lit":
            return v
        if kind == "param":
            return env[v]
        if kind == "bi":
            return 1 if env[v] else 0
        pname, op, n = v
        return env[pname] - n if op == "-" else env[pname] + n

    def _foreign(self, hname, fname, values):
        fn, ptypes, _ret = self.foreign[fname]
        conv = []
        for t, v in zip(ptypes, values):
            conv.append(self._to_cint(hname, v) if t == "CInt" else float(v))
        return fn(*conv)

    def check_abi(self):
        v = self.foreign["_abi_version"][0]()
        if v != 4:
            raise Thrown("box2dxt: incompatible native library (binding "
                         "needs ABI 4) - update libbox2dxt / box2dxt.dll")


# ==========================================================================
# the engine's text and numbers
# ==========================================================================

_INF = float("inf")
_BASE_DISP = LCS._disp


def _engine_disp(v):
    """The engine's text for a value: a NON-INTEGRAL number is written by
    the default numberFormat ("0.######": MCU_r8tos, sprintf "%0.6f" with
    the trailing zeros and a bare point stripped and a negative zero
    written 0; engine/src/util.cpp, DOCUMENTED, read 2026-10-08). The
    interpreter writes Python's repr there (lcs-interp.py trap 21 names it
    unmodelled), and the game turns computed coordinates into text on every
    frame (`set the loc of X to tX & comma & tY`), so this gate installs the
    engine's rule for the whole run."""
    if type(v) is float:
        if v != v or v in (_INF, -_INF):
            raise ModelRefusal("the text of %r (a NaN or an infinity) is not "
                               "modelled" % v)
        if v == int(v):
            return str(int(v))
        s = ("%0.6f" % v).rstrip("0")
        if s.endswith("."):
            s = s[:-1]
        return "0" if s == "-0" else s
    return _BASE_DISP(v)


LCS._disp = _engine_disp


def _text(v):
    return str(LCS._disp(v))


def _strtol_reals(s):
    """MCU_strtol(..., reals=True) over one item: optional spaces, a sign,
    digits, and a fraction that ROUNDS on its first digit alone (> 4 adds
    one to the magnitude; MW-2013-06-09, bug 10964), then optional spaces.
    Answers the integer or None where the engine's parse fails. Hex (`0x`)
    is refused rather than modelled; the game never writes it."""
    t = s.strip(" \t\r\n")
    m = re.match(r'^([-+]?)(\d*)(?:\.(\d*))?$', t)
    if not m or (m.group(2) == "" and not m.group(3)):
        return None
    val = int(m.group(2) or "0")
    if m.group(3) and m.group(3)[0] > "4":
        val += 1
    return -val if m.group(1) == "-" else val


def _ints(prop, v, n):
    """A legacy point or rectangle ("x,y" / "l,t,r,b"), parsed as the
    engine's MCU_stoi2x2 / MCU_stoi4x4 parse it (engine/src/util.cpp): each
    item through MCU_strtol with reals, so 12.5 is 13 and 12.4 is 12. A
    value that does not parse is the setter's script error
    (EE_PROPERTY_NOTAINTPAIR / NOTAINTQUAD), a Thrown."""
    parts = _text(v).split(",")
    out = [_strtol_reals(p) for p in parts]
    if len(parts) != n or None in out:
        raise Thrown("set %s: %r is not %d integers" % (prop, _text(v), n))
    return out


def _int1(prop, v):
    """A single integer property: ConvertToInteger, the number rounded half
    away from zero (MCNumberFetchAsInteger, libfoundation)."""
    try:
        x = LCS._n(v) if not isinstance(v, bool) else None
    except ValueError:
        x = None
    if x is None or (isinstance(v, str) and v.strip() == ""):
        raise Thrown("set %s: %r is not a number" % (prop, _text(v)))
    if isinstance(x, int):
        return x
    return int(x - 0.5) if x < 0 else int(x + 0.5)


def _bool(prop, v):
    """A Boolean property: true or false, caseless (anything else is
    EE_PROPERTY_NAB, a script error)."""
    if isinstance(v, bool):
        return v
    s = _text(v).lower()
    if s in ("true", "false"):
        return s == "true"
    raise Thrown("set %s: %r is not true or false" % (prop, _text(v)))


def _parse_points(prop, v):
    """`the points` of a graphic: one "x,y" per line, MCU_parsepoints'
    rounding (engine/src/util.cpp). An empty line (a break in the path) is
    refused rather than modelled; the game draws none."""
    pts = []
    for line in _text(v).split("\n"):
        if line.strip() == "":
            continue
        pts.append(tuple(_ints(prop, line, 2)))
    return pts


# ==========================================================================
# pixels: a PNG reader and the image operations the Kit asks for
# ==========================================================================
#
# No check reads a pixel's VALUE: the game reads sizes and byte counts (the
# slicer's stride guard, `the width of`), so what must be right is each
# image's size and each buffer's length. The pixels are still decoded and
# carried for real (a corrupt PNG is refused as the engine refuses it, and a
# slice is the bytes it would be), at the cost of a little time.

_PNG_SIG = b"\x89PNG\r\n\x1a\n"
_PNG_CACHE = {}


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def png_decode(data):
    """PNG bytes -> (width, height, ARGB bytes, alpha bytes), the engine's
    imageData and alphaData layouts. Non-interlaced, bit depth 8 (the
    Kenney sheets are 8-bit palette; RGB, RGBA, grey and grey-alpha are
    read too). Anything else, and any damage (a CRC, a filter byte, a
    length), raises ValueError: the engine shows no image for it."""
    key = zlib.crc32(data), len(data)
    hit = _PNG_CACHE.get(key)
    if hit is not None:
        return hit
    if data[:8] != _PNG_SIG:
        raise ValueError("not a PNG")
    pos, ihdr, plte, trns, idat = 8, None, None, None, []
    while True:
        if pos + 8 > len(data):
            raise ValueError("truncated PNG")
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + ln]
        if len(chunk) != ln or pos + 12 + ln > len(data):
            raise ValueError("truncated PNG chunk")
        crc = struct.unpack(">I", data[pos + 8 + ln:pos + 12 + ln])[0]
        if zlib.crc32(typ + chunk) & 0xFFFFFFFF != crc:
            raise ValueError("PNG chunk CRC mismatch")
        pos += 12 + ln
        if typ == b"IHDR":
            ihdr = chunk
        elif typ == b"PLTE":
            plte = chunk
        elif typ == b"tRNS":
            trns = chunk
        elif typ == b"IDAT":
            idat.append(chunk)
        elif typ == b"IEND":
            break
    if ihdr is None or not idat:
        raise ValueError("PNG without IHDR or IDAT")
    w, h, depth, ctype, _comp, _filt, inter = struct.unpack(">IIBBBBB", ihdr)
    chans = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if depth != 8 or chans is None or inter != 0 or not (0 < w <= 32767) \
            or not (0 < h <= 32767):
        raise ValueError("PNG form not modelled (depth %d, type %d, "
                         "interlace %d)" % (depth, ctype, inter))
    raw = zlib.decompress(b"".join(idat))
    stride = w * chans
    if len(raw) != h * (stride + 1):
        raise ValueError("PNG image data has the wrong length")
    bpp = chans
    prev = bytearray(stride)
    rows = []
    for y in range(h):
        f = raw[y * (stride + 1)]
        cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if f == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif f == 2:
            cur = bytearray((a + b) & 255 for a, b in zip(cur, prev))
        elif f == 3:
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                upleft = prev[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + _paeth(left, prev[i], upleft)) & 255
        elif f != 0:
            raise ValueError("PNG filter type %d" % f)
        rows.append(bytes(cur))
        prev = cur
    flat = b"".join(rows)
    n = w * h
    if ctype == 3:
        if plte is None or len(plte) % 3:
            raise ValueError("palette PNG without a palette")
        pal = [plte[k:k + 3] for k in range(0, len(plte), 3)]
        pal += [b"\0\0\0"] * (256 - len(pal))
        alphas = bytes(trns or b"") + b"\xff" * (256 - len(trns or b""))
        r = bytes(range(256)).maketrans(bytes(range(256)),
                                        bytes(p[0] for p in pal))
        g = bytes(range(256)).maketrans(bytes(range(256)),
                                        bytes(p[1] for p in pal))
        b = bytes(range(256)).maketrans(bytes(range(256)),
                                        bytes(p[2] for p in pal))
        a = bytes(range(256)).maketrans(bytes(range(256)), alphas[:256])
        cr, cg, cb, ca = (flat.translate(r), flat.translate(g),
                          flat.translate(b), flat.translate(a))
    elif ctype in (2, 6):
        cr, cg, cb = flat[0::chans], flat[1::chans], flat[2::chans]
        ca = flat[3::4] if ctype == 6 else b"\xff" * n
    else:
        cr = cg = cb = flat[0::chans]
        ca = flat[1::2] if ctype == 4 else b"\xff" * n
    out = bytearray(4 * n)
    # imageData is four bytes a pixel, A R G B; the alpha lives in alphaData
    # and the first byte is left 0 here (nothing reads a pixel's value)
    out[1::4], out[2::4], out[3::4] = cr, cg, cb
    res = (w, h, bytes(out).decode("latin-1"), bytes(ca).decode("latin-1"))
    _PNG_CACHE[key] = res
    return res


def resample(pix, alpha, w, h, w2, h2):
    """Nearest-neighbour scale of an ARGB buffer and its alpha to w2 x h2:
    the stand-in for the engine's resampled render of a resized image (what
    `the imageData` of a scaled image answers). Only the sizes are checked."""
    xs = [min(w - 1, (x * w) // w2) for x in range(w2)]
    out, oa = [], []
    for y in range(h2):
        sy = min(h - 1, (y * h) // h2)
        row = pix[sy * w * 4:(sy + 1) * w * 4]
        arow = alpha[sy * w:(sy + 1) * w] if alpha else ""
        out.append("".join(row[x * 4:x * 4 + 4] for x in xs))
        if alpha:
            oa.append("".join(arow[x] for x in xs))
    return "".join(out), "".join(oa)


def flip_pixels(pix, alpha, w, h, horizontal):
    if horizontal:
        rows = [pix[y * w * 4:(y + 1) * w * 4] for y in range(h)]
        p = "".join("".join(r[x * 4:x * 4 + 4] for x in range(w - 1, -1, -1))
                    for r in rows)
        a = "".join(alpha[y * w:(y + 1) * w][::-1] for y in range(h))
        return p, a
    p = "".join(pix[y * w * 4:(y + 1) * w * 4] for y in range(h - 1, -1, -1))
    a = "".join(alpha[y * w:(y + 1) * w] for y in range(h - 1, -1, -1))
    return p, a


# ==========================================================================
# the engine's objects
# ==========================================================================
#
# One stack, one card, and the controls a run makes: every one with the
# engine's id, name, owner, layer, rect and properties. The rules below are
# the engine's as its source writes them (livecode/livecode, the tree OXT
# grew from; DOCUMENTED, read 2026-10-08), each cited where it is used. A
# property, reference form or command this file does not know is a
# ModelRefusal naming it, never a guess: the gate's first runs grew the
# model one refusal at a time, and the next unmodelled corner will be as
# loud.

KIND = {"button": "button", "btn": "button", "field": "field", "fld": "field",
        "graphic": "graphic", "grc": "graphic", "image": "image",
        "img": "image", "group": "group", "grp": "group",
        "scrollbar": "scrollbar", "player": "player", "control": "control",
        "card": "card", "cd": "card", "stack": "stack",
        "audioclip": "audioclip"}
PLURAL = {"buttons": "button", "btns": "button", "fields": "field",
          "flds": "field", "graphics": "graphic", "grcs": "graphic",
          "images": "image", "imgs": "image", "groups": "group",
          "grps": "group", "controls": "control", "cards": "card",
          "cds": "card", "audioclips": "audioclip"}
CONTROLS = ("button", "field", "graphic", "image", "group", "scrollbar",
            "player")
POINT_STYLES = ("polygon", "line", "curve")

# What a property reads before a script sets it: the engine's template
# defaults, for the properties the game is seen to read that way. A read of
# a default is COUNTED (World.default_reads, printed by --verbose) so a
# wrong default cannot hide; a property in neither table is refused.
_ANY = {"visible": True, "blendlevel": 0, "layermode": "static",
        "lockloc": False, "angle": 0, "traversalon": False,
        "showborder": True, "opaque": False, "textsize": "", "textstyle": "",
        "textcolor": "", "textalign": "", "foregroundcolor": "",
        "backgroundcolor": "", "linesize": 1, "filled": False,
        "margins": 4, "hscroll": 0, "vscroll": 0, "hscrollbar": False,
        "vscrollbar": False, "unboundedhscroll": False,
        "unboundedvscroll": False, "showname": True, "autohilite": True,
        "label": "", "icon": 0, "menumode": "", "menuhistory": 1,
        "locktext": False, "repeatcount": 0, "currentframe": 1}
_STYLE = {"button": "standard", "field": "rectangle", "graphic": "rectangle",
          "image": "", "group": "", "scrollbar": "scrollbar", "player": ""}


class Obj(object):
    __slots__ = ("kind", "id", "name", "owner", "kids", "props", "custom",
                 "rect", "points", "pw", "ph", "pix", "alpha", "data",
                 "gone", "text")

    def __init__(self, kind, oid, owner):
        self.kind, self.id, self.owner = kind, oid, owner
        self.name = ""
        self.kids = [] if kind in ("card", "group") else None
        self.props = {}
        self.custom = {}
        self.rect = [0, 0, 1, 1]          # left, top, right, bottom
        self.points = None                # a points graphic's points
        self.pw = self.ph = 0             # an image's pixel size ...
        self.pix = self.alpha = ""        # ... and its pixels
        self.data = ""                    # an image's or a clip's content
        self.text = ""                    # a field's or a button's text
        self.gone = False

    def __repr__(self):
        return "<%s id %d %r>" % (self.kind, self.id, self.name)


class World(object):
    """The engine around the stack script: objects, the clock, the message
    queue, the dialogs and the files, all inside a sandbox directory."""

    CARD_ID = 1002
    STACK_NAME = "Untitled 1"

    def __init__(self, sandbox, dialogs):
        self.sandbox = sandbox
        self.dialogs = dialogs            # the profile's answers, in order
        self.dialog_log = []
        self.stack = Obj("stack", 1001, None)
        self.stack.name = self.STACK_NAME
        self.stack.rect = [0, 0, 1024, 640]
        self.filename = ""                # set by `save this stack as`
        self.card = Obj("card", self.CARD_ID, self.stack)
        self.next_id = self.CARD_ID + 1
        self.by_id = {}
        self.clips = []                   # audioclips, in order
        self.ver = 0                      # bumped on any change of layers
        self._flat_ver = -1
        self._flat = []
        self.ms = 10 ** 7                 # the virtual clock
        self.timers = []                  # [due, seq, target, message]
        self.seq = 0
        self.result = ""
        self.lock_msgs = False
        self.lock_screen = 0
        self.keys_down = []               # key codes held
        self.shift = False
        self.mouse = (512, 320)
        self.played = []
        self.loudness = 100
        self.lib_mapping = {}
        self.default_reads = {}
        self.engine_msgs = {}             # name -> count sent unlocked
        self.build_msgs = []              # ... of them, sent mid-build
        self.saved = None                 # the snapshot `save` wrote
        self.reads = []                   # every URL read, in order
        self.problems = []                # findings the driver reports
        self.menu_picks = []              # (button, new line, locked)
        self.temp_dir = os.path.join(sandbox, "tmp")
        os.makedirs(self.temp_dir, exist_ok=True)

    # -- ids, layers, lookup ------------------------------------------------
    def card_size(self):
        r = self.stack.rect
        return r[2] - r[0], r[3] - r[1]

    def new_id(self):
        oid = self.next_id
        self.next_id += 1
        return oid

    def flat(self):
        """Every control of the card in LAYER order: a group, then its
        controls (the engine's flattened numbering, which `control N`, `the
        layer` and `the number of controls` all read)."""
        if self._flat_ver != self.ver:
            out = []

            def walk(o):
                for k in o.kids:
                    out.append(k)
                    if k.kind == "group":
                        walk(k)
            walk(self.card)
            self._flat = out
            self._flat_ver = self.ver
        return self._flat

    def descendants(self, o):
        out = []
        for k in o.kids:
            out.append(k)
            if k.kind == "group":
                out.extend(self.descendants(k))
        return out

    def find(self, kind, by, key, within=None):
        """The control (or audioclip) `kind by key`, searched the way the
        engine searches a card: in layer order, first match, grouped
        controls included; within a group when one is named. by is "id",
        "name" or "index"; kind "control" matches any control type."""
        if kind == "audioclip":
            pool = self.clips
        else:
            pool = self.descendants(within) if within is not None else self.flat()
            if kind != "control":
                pool = [o for o in pool if o.kind == kind]
        if by == "id":
            o = self.by_id.get(key)
            if o is None or o.gone:
                return None
            if kind == "audioclip":
                return o if o.kind == "audioclip" else None
            if kind != "control" and o.kind != kind:
                return None
            if kind == "control" and o.kind not in CONTROLS:
                return None
            if within is not None and o not in pool:
                return None
            return o
        if by == "index":
            return pool[key - 1] if 1 <= key <= len(pool) else None
        low = key.lower()
        for o in pool:
            if o.name.lower() == low:
                return o
        return None

    # -- names --------------------------------------------------------------
    def stack_ref(self):
        return 'stack "%s"' % (self.filename or self.stack.name)

    def long_id(self, o):
        if o.kind == "stack":
            return self.stack_ref()
        if o.kind == "card":
            return "card id %d of %s" % (o.id, self.stack_ref())
        if o.kind == "audioclip":
            return "audioClip id %d of %s" % (o.id, self.stack_ref())
        return "%s id %d of %s" % (o.kind, o.id, self.long_id(o.owner))

    def long_name(self, o):
        if o.kind == "stack":
            return self.stack_ref()
        own = self.long_name(o.owner) if o.owner is not None else ""
        if not o.name:
            return "%s id %d of %s" % (o.kind, o.id, own)
        return '%s "%s" of %s' % (o.kind if o.kind != "audioclip"
                                  else "audioClip", o.name, own)

    def name_of(self, o, adjective):
        kw = "audioClip" if o.kind == "audioclip" else o.kind
        if adjective == "long":
            return self.long_name(o)
        if o.kind == "stack" and adjective != "short":
            return 'stack "%s"' % o.name
        if not o.name:
            return "%s id %d" % (kw, o.id)
        if adjective == "short":
            return o.name
        return '%s "%s"' % (kw, o.name)

    # -- create, delete, layers --------------------------------------------
    def create(self, kind, name, parent):
        """`create <kind> [name] [in group G]`: a new control at the TOP of
        its container, centred on the card (the template's 128 x 32; the
        game sizes every control it makes), with `it` set by the caller."""
        o = Obj(kind, self.new_id(), parent)
        o.name = name
        w, h = self.card_size()
        o.rect = [(w - 128) // 2, (h - 32) // 2, (w - 128) // 2 + 128,
                  (h - 32) // 2 + 32]
        parent.kids.append(o)
        self.by_id[o.id] = o
        self.ver += 1
        return o

    def clone(self, src):
        """`clone`: a copy of the control in the same container, offset
        by MCcloneoffset (32) and attached on TOP of that container, as a
        new control is (MCImage::clone -> MCControl::attach, which appends;
        DOCUMENTED)."""
        if src.kind == "group":
            raise ModelRefusal("cloning a group is not modelled")
        o = Obj(src.kind, self.new_id(), src.owner)
        o.name = src.name
        o.props = dict(src.props)
        o.custom = dict(src.custom)
        o.rect = [src.rect[0] + 32, src.rect[1] + 32, src.rect[2] + 32,
                  src.rect[3] + 32]
        if src.points is not None:
            o.points = [(x + 32, y + 32) for x, y in src.points]
        o.pw, o.ph, o.pix, o.alpha, o.data = (src.pw, src.ph, src.pix,
                                              src.alpha, src.data)
        o.text = src.text
        src.owner.kids.append(o)
        self.by_id[o.id] = o
        self.ver += 1
        return o

    def delete(self, o):
        if o.kind == "audioclip":
            self.clips.remove(o)
        else:
            o.owner.kids.remove(o)
        for d in [o] + (self.descendants(o) if o.kind == "group" else []):
            d.gone = True
            self.by_id.pop(d.id, None)
        self.ver += 1

    def ungroup(self, g):
        """`ungroup`: the group's controls take its place in the card's
        layers, in their order, and the group itself is gone."""
        if g.kind != "group":
            raise Thrown("ungroup: object is not a group")
        if g.owner is not self.card:
            raise ModelRefusal("ungrouping a nested group is not modelled")
        sib = self.card.kids
        k = sib.index(g)
        for c in g.kids:
            c.owner = self.card
        sib[k:k + 1] = g.kids
        g.kids = []
        g.gone = True
        self.by_id.pop(g.id, None)
        self.ver += 1

    def relayer_into_group(self, o, g):
        """`relayer X to front of group G`: X moves into G, on top."""
        if g.kind != "group":
            raise Thrown("relayer: target is not a group")
        o.owner.kids.remove(o)
        o.owner = g
        g.kids.append(o)
        self.ver += 1

    def set_layer(self, o, n):
        """`set the layer of X to N` (MCObject::SetLayer and MCCard::relayer,
        DOCUMENTED): a grouped control refuses (EE_OBJECT_BADRELAYER, as
        `the relayerGroupedControls` is false), and a card control moves so
        that its layer is N in the flattened numbering, never inside a
        group: landing on a grouped control places it before or after the
        whole top-level group."""
        if o.owner is not self.card:
            raise Thrown("set layer: a grouped control cannot be relayered "
                         "(relayerGroupedControls is false)")
        top = self.card.kids
        top.remove(o)
        self.ver += 1
        if n <= 1:
            top.insert(0, o)
            self.ver += 1
            return
        flat = self.flat()
        if n - 2 >= len(flat):
            top.append(o)
            self.ver += 1
            return
        found = flat[n - 2]
        while found.owner is not self.card:
            found = found.owner
        k = top.index(found)
        if flat[n - 2] is found:
            top.insert(k + 1, o)
        else:
            # landed inside a group: before it, unless the layer asked for
            # is past the group's last control
            nxt = top[k + 1] if k + 1 < len(top) else None
            if nxt is None or n < flat.index(nxt) + 1:
                top.insert(k, o)
            else:
                top.insert(k + 1, o)
        self.ver += 1

    def layer(self, o):
        if o.kind == "card":
            return 1
        return self.flat().index(o) + 1

    # -- geometry -------------------------------------------------------------
    def set_rect(self, o, l, t, r, b):
        """A control's new rect (MCObject::SetRectProp): nothing when it is
        unchanged; a points graphic moves its points (a RESIZE scales them
        on the engine, which is refused, engine note 5.1); a group applies
        it the engine's way (applyrect); the owner group then refits."""
        r, b = l + max(1, r - l), t + max(1, b - t)
        if [l, t, r, b] == o.rect:
            return
        if o.kind == "graphic" and o.points is not None:
            ow, oh = o.rect[2] - o.rect[0], o.rect[3] - o.rect[1]
            if (r - l, b - t) != (ow, oh):
                raise ModelRefusal("resizing a %s graphic (its points scale "
                                   "on the engine) is not modelled; engine "
                                   "note 5.1" % o.props.get("style"))
            self.move(o, l - o.rect[0], t - o.rect[1])
        elif o.kind == "group":
            self.group_apply_rect(o, [l, t, r, b])
        else:
            o.rect = [l, t, r, b]
        self.child_changed(o)

    def move(self, o, dx, dy):
        if not dx and not dy:
            return
        o.rect = [o.rect[0] + dx, o.rect[1] + dy, o.rect[2] + dx,
                  o.rect[3] + dy]
        if o.points is not None:
            o.points = [(x + dx, y + dy) for x, y in o.points]
        if o.kind == "group":
            for k in o.kids:
                self.move(k, dx, dy)

    def points_rect(self, o):
        """A points graphic's rect (MCGraphic::compute_minrect and
        expand_minrect, DOCUMENTED): the points' extents grown by the pen,
        (lineSize >> 1) + 1 a side when there is a pen (the template's
        round caps and default join add nothing more), and a polygon at
        least 8 px each way. Engine note 5.1 saw the padding grow a polygon
        2 px a rebuild."""
        xs = [p[0] for p in o.points]
        ys = [p[1] for p in o.points]
        l, t, r, b = min(xs), min(ys), max(xs), max(ys)
        ls = o.props.get("linesize", 1)
        ls = int(ls) if ls != "" else 1
        if ls:
            pad = (ls >> 1) + 1
            l, t, r, b = l - pad, t - pad, r + pad, b + pad
        if o.props.get("style") == "polygon":
            if r - l < 8:
                d = 8 - (r - l)
                l -= d >> 1
                r = l + 8
            if b - t < 8:
                d = 8 - (b - t)
                t -= d >> 1
                b = t + 8
        o.rect = [l, t, r, b]

    # -- groups ---------------------------------------------------------------
    def child_changed(self, o):
        """A grouped control moved, resized, showed, hid or arrived: its
        group refits unless it is lockLoc (MCObject::resizeparent)."""
        g = o.owner
        if g is not None and g.kind == "group" and \
                not g.props.get("lockloc", False):
            self.group_changed(g)

    def group_changed(self, g):
        """MCGroup::computeminrect (DOCUMENTED): a lockLoc group keeps its
        rect; any other becomes its VISIBLE controls' bounds (a zero-size
        rect at its own top-left when none shows) grown by its margins and,
        with showBorder, its 2 px border; its scroll resets to 0."""
        if g.props.get("lockloc", False):
            return
        if g.props.get("showname", False):
            raise ModelRefusal("a group showing its name refits by its "
                               "font's height, which is not modelled")
        m = g.props.get("margins", 4)
        vis = [k.rect for k in g.kids if k.props.get("visible", True)]
        if vis:
            l = min(r[0] for r in vis)
            t = min(r[1] for r in vis)
            r_ = max(r[2] for r in vis)
            b = max(r[3] for r in vis)
        else:
            l, t = g.rect[0] + m, g.rect[1] + m
            r_, b = l, t
        l, t, r_, b = l - m, t - m, r_ + m, b + m
        if g.props.get("showborder", False):
            l, t, r_, b = l - 2, t - 2, r_ + 2, b + 2
        g.rect = [l, t, r_, b]
        g.props["hscroll"] = g.props["vscroll"] = 0
        self.child_changed(g)

    def group_apply_rect(self, g, nrect):
        """MCGroup::applyrect (DOCUMENTED): with controls, a new top-left
        MOVES them by its change unless the bottom-right corner is
        unchanged; without, only the rect changes."""
        old = g.rect
        if g.kids and not (old[2] == nrect[2] and old[3] == nrect[3]):
            dx, dy = nrect[0] - old[0], nrect[1] - old[1]
            for k in g.kids:
                self.move(k, dx, dy)
        g.rect = list(nrect)

    def scroll_group(self, g, axis, value):
        """A group's hScroll / vScroll: its controls MOVE by the change (the
        engine scrolls a group by moving its children; the Kit's camera
        reads it that way, sCamLocVisual). Only an UNBOUNDED axis is
        modelled: a bounded one clamps to the content, which is refused."""
        prop = "hscroll" if axis == "h" else "vscroll"
        if not g.props.get("unbounded" + prop, False):
            raise ModelRefusal("scrolling a BOUNDED group axis (%s of %r) is "
                               "not modelled" % (prop, g.name))
        old = g.props.get(prop, 0)
        g.props[prop] = value
        d = value - old
        if not d or not g.kids:
            return
        for k in g.kids:
            if axis == "h":
                self.move(k, -d, 0)
            else:
                self.move(k, 0, -d)

    # -- images -------------------------------------------------------------
    def image_set_text(self, o, data):
        """`set the text of image`: PNG bytes decode to the picture; with
        lockLoc false the control takes the picture's natural size about
        its centre. Bytes that are no picture leave the control exactly as
        it was, without an error (engine note 5.7, OBSERVED)."""
        if data == "":
            o.data, o.pw, o.ph, o.pix, o.alpha = "", 0, 0, "", ""
            return
        try:
            w, h, pix, alpha = png_decode(data.encode("latin-1"))
        except (ValueError, zlib.error):
            return
        o.data, o.pw, o.ph, o.pix, o.alpha = data, w, h, pix, alpha
        if not o.props.get("lockloc", False):
            cx = o.rect[0] + ((o.rect[2] - o.rect[0]) >> 1)
            cy = o.rect[1] + ((o.rect[3] - o.rect[1]) >> 1)
            o.rect = [cx - (w >> 1), cy - (h >> 1), cx - (w >> 1) + w,
                      cy - (h >> 1) + h]

    def image_render(self, o):
        """The pixels as displayed: the picture scaled to the control."""
        w, h = o.rect[2] - o.rect[0], o.rect[3] - o.rect[1]
        if not o.pw:
            return w, h, "\0" * (4 * w * h), "\xff" * (w * h)
        if (w, h) == (o.pw, o.ph):
            return w, h, o.pix, o.alpha
        pix, alpha = resample(o.pix, o.alpha, o.pw, o.ph, w, h)
        return w, h, pix, alpha

    def image_set_data(self, o, data):
        """`set the imageData`: the bytes become the picture at the
        control's size (MCImage::SetImageData; rows past the bytes given
        are black); the alpha already there is kept."""
        w, h = o.rect[2] - o.rect[0], o.rect[3] - o.rect[1]
        need = 4 * w * h
        if len(data) < need:
            data = data + "\0" * (need - len(data))
        alpha = o.alpha if (o.pw, o.ph) == (w, h) and o.alpha else "\xff" * (w * h)
        o.pw, o.ph, o.pix, o.alpha = w, h, data[:need], alpha
        o.data = None                     # no longer the file's bytes

    def image_set_alpha(self, o, data):
        w, h = o.rect[2] - o.rect[0], o.rect[3] - o.rect[1]
        if (o.pw, o.ph) != (w, h):
            o.pw, o.ph, o.pix = w, h, self.image_render(o)[2]
        need = w * h
        o.alpha = (data + "\xff" * max(0, need - len(data)))[:need]
        o.data = None

    def image_flip(self, o, horizontal):
        w, h, pix, alpha = self.image_render(o)
        o.pw, o.ph = w, h
        o.pix, o.alpha = flip_pixels(pix, alpha, w, h, horizontal)
        o.data = None

    # -- engine messages ------------------------------------------------------
    def note_engine_message(self, name, building, frames):
        """One engine message sent unlocked; those sent while a level
        builds are kept apart (the quiet build sends none), each with the
        handlers that caused it, innermost last."""
        self.engine_msgs[name] = self.engine_msgs.get(name, 0) + 1
        if building:
            self.build_msgs.append((name, tuple(frames[-3:])))

    # -- files and the saved stack ----------------------------------------------
    def real_path(self, path):
        """A path the script names -> itself when it lies inside the
        sandbox, else None: the run reads and writes nothing else."""
        if not path or not os.path.isabs(path):
            return None
        real = os.path.normpath(path)
        root = os.path.normpath(self.sandbox)
        if real != root and not real.startswith(root + os.sep):
            return None
        return real

    def snapshot(self):
        """What `save this stack` writes: the stack, its card, every
        control and audioclip with every property, and the next id. Script
        locals, timers, locks and the clock are not part of a stack file."""
        return copy.deepcopy((self.stack, self.card, self.clips, self.next_id,
                              self.filename))

    @classmethod
    def reopen(cls, snap, sandbox, dialogs):
        """A World opened from a saved stack's file."""
        w = cls(sandbox, dialogs)
        stack, card, clips, next_id, filename = copy.deepcopy(snap)
        w.stack, w.card, w.clips, w.next_id = stack, card, clips, next_id
        w.filename = filename
        w.by_id = {}
        for o in w.descendants(w.card) + list(w.clips):
            w.by_id[o.id] = o
        w.ver += 1
        return w


# ==========================================================================
# values: the engine's conversions, comparisons and arithmetic
# ==========================================================================
#
# The closure compiler below evaluates the shipped script by the ENGINE's
# rules, read from its source (livecode/livecode, the tree OXT grew from;
# DOCUMENTED, read 2026-10-08) and cited where each is used. The family
# interpreter REFUSES a comparison the engine answers differently from IEEE
# or from Python (engine notes 2.10, 2.11), because its question is "does
# this library compute the same thing on every engine". This model's
# question is "what does this stack do on one", so it answers those the
# engine's way, with the family's own port of the engine's number reading
# (LCS._read_text, MCU_strtor8). What that port calls UNSURE is refused.

_RN, _RU = LCS._READ_NUMBER, LCS._READ_UNSURE
_READ = LCS._read_text
_NEAR = LCS._engine_equal
_BIG = 2 ** 53
_U32 = 0xFFFFFFFF


def _s(v):
    """A value's text (ForceToString). An array has none in this model."""
    if type(v) is str:
        return v
    if isinstance(v, dict):
        raise ModelRefusal("an array used as text (the engine gives the "
                           "empty string; nothing in the game should)")
    return _text(v)


def _num(v, what):
    """ConvertToNumber (engine/src/exec.cpp): a number as itself, empty as
    0, text through MCU_strtor8; anything else is the operator's script
    error ("error in left operand"), a Thrown."""
    t = type(v)
    if t is int or t is float:
        return v
    if t is str:
        if not v:
            return 0
        kind, x, why = _READ(v)
        if kind == _RN:
            return x
        if kind == _RU:
            raise ModelRefusal("%s: how the engine reads %s as a number is "
                               "not established (%s; engine note 2.11)"
                               % (what, LCS._shown(v), why))
        raise Thrown("%s: %s is not a number" % (what, LCS._shown(v)))
    if t is bool:
        raise Thrown("%s: %s is a Boolean, not a number" % (what, _s(v)))
    if isinstance(v, dict):
        raise ModelRefusal("%s: arithmetic on an array is not modelled" % what)
    raise ModelRefusal("%s: a %s value" % (what, t.__name__))


def _fix(x, what):
    """An arithmetic result as the engine holds it: a double. A Python int
    is exact, so past 2^53 it becomes the double the engine's sum would be
    (IEEE operations are correctly rounded, so float(a op b) is the
    engine's answer when a and b are exact); a NaN or an infinity is the
    checked operator's range error (MCMathEvalChecked*Function)."""
    if type(x) is int:
        if -_BIG <= x <= _BIG:
            return x
        return float(x)
    if x != x or x == _INF or x == -_INF:
        raise Thrown("%s: the result is not a finite number" % what)
    return x


def _int_of(v, what):
    """A whole number for a chunk index, a count or an id: the number, which
    must be integral (the engine would round; the game never asks it to)."""
    x = _num(v, what)
    if type(x) is float:
        if x != x or x in (_INF, -_INF) or x != int(x):
            raise ModelRefusal("%s: %r is not a whole number (the engine "
                               "rounds; not modelled)" % (what, x))
        x = int(x)
    return x


def _round_half_away(x):
    """MCMathEvalRoundToPrecision at precision 0 (engine/src/exec-math.cpp):
    floor(x + 0.5) above zero, ceil(x - 0.5) below, in doubles."""
    if type(x) is int:
        return x
    r = math.ceil(x - 0.5) if x < 0 else math.floor(x + 0.5)
    return r


def _u32(v, what):
    """A bitwise operand: uinteger_t (MCMathEvalBitwise*). A value that is
    not a whole number in 0 .. 2^32-1 is refused rather than modelled."""
    x = _num(v, what)
    if type(x) is float:
        if x != int(x):
            raise ModelRefusal("%s: %r is not a whole number" % (what, x))
        x = int(x)
    if not 0 <= x <= _U32:
        raise ModelRefusal("%s: %r is outside 0 .. 2^32-1" % (what, x))
    return x


def _truth(v):
    """EvalExprAsNonStrictBool: true only for the Boolean true or the text
    "true" in any case (an `if`, `not`, `and`, `or`)."""
    if v is True:
        return True
    return type(v) is str and len(v) == 4 and v.lower() == "true"


def _fold(s):
    """The caseless form of a text, for `is`, `contains`, `offset`, ...
    (kMCStringOptionCompareCaseless unless the caseSensitive is true). ASCII
    folds exactly; beyond ASCII Python's lower() stands in for the engine's
    native folding, and the comparisons below refuse where it could decide."""
    return s if LCS.CASE_SENSITIVE[0] else s.lower()


def _real_or_none(v, empty_zero):
    """TryToConvertToReal: (the number) or None where the operand stays text.
    An empty operand is no number to `is` (MCLogicIsEqualTo skips it) and 0
    to the orderings (MCLogicCompareTo converts it)."""
    t = type(v)
    if t is int or t is float:
        return v
    if t is str:
        if not v:
            return 0 if empty_zero else None
        kind, x, why = _READ(v)
        if kind == _RN:
            return x
        if kind == _RU:
            raise ModelRefusal("a comparison operand %s: how the engine "
                               "reads it is not established (%s; engine "
                               "note 2.11)" % (LCS._shown(v), why))
    return None


def _text_equal(sa, sb):
    if LCS.CASE_SENSITIVE[0]:
        return sa == sb
    la, lb = sa.lower(), sb.lower()
    if la == lb and sa != sb and not (sa.isascii() and sb.isascii()):
        raise ModelRefusal("a caseless `is` between %s and %s, which differ "
                           "only beyond ASCII: the engine's folding there is "
                           "not modelled" % (LCS._shown(sa), LCS._shown(sb)))
    return la == lb


def pf_eq(a, b):
    """MCLogicIsEqualTo (engine/src/exec-logic.cpp): two non-empty arrays
    compare as arrays and an array never equals a non-array (an EMPTY array
    is empty); two operands that both convert to numbers compare as numbers
    within MC_EPSILON (engine note 2.10); an empty operand never converts,
    and equals only another empty one; anything else compares as text,
    caseless unless the caseSensitive is true."""
    if a is b:
        return True
    da, db = isinstance(a, dict), isinstance(b, dict)
    if da or db:
        aa, ab = da and len(a) > 0, db and len(b) > 0
        if aa != ab:
            return False
        if aa:
            if len(a) != len(b):
                return False
            for k, v in dict.items(a):
                if not LCS._arr_has(b, k) or not pf_eq(v, LCS._arr_get(b, k)):
                    return False
            return True
        a = "" if da else a
        b = "" if db else b
    x = _real_or_none(a, False)
    if x is not None:
        y = _real_or_none(b, False)
        if y is not None:
            return x == y or _NEAR(x, y)
    sa, sb = _s(a), _s(b)
    if (sa == "") != (sb == ""):
        return False
    return _text_equal(sa, sb)


def pf_order(a, b):
    """MCLogicCompareTo: -1, 0 or 1. Numbers (empty is 0) within MC_EPSILON,
    else the two texts, caseless unless the caseSensitive is true."""
    if isinstance(a, dict) or isinstance(b, dict):
        raise ModelRefusal("ordering an array is not modelled")
    x = _real_or_none(a, True)
    if x is not None:
        y = _real_or_none(b, True)
        if y is not None:
            if x == y or _NEAR(x, y):
                return 0
            return -1 if x < y else 1
    sa, sb = _s(a), _s(b)
    if not (sa.isascii() and sb.isascii()):
        raise ModelRefusal("ordering text beyond ASCII (%s, %s) is not "
                           "modelled" % (LCS._shown(sa), LCS._shown(sb)))
    sa, sb = _fold(sa), _fold(sb)
    return (sa > sb) - (sa < sb)


def _is_number(v):
    """`is a number` (MCMathEvalIsANumber): ConvertToNumber succeeds, and
    an empty value is not a number."""
    t = type(v)
    if t is int or t is float:
        return True
    if t is not str or not v:
        return False
    kind, _x, why = _READ(v)
    if kind == _RU:
        raise ModelRefusal("`%s is a number`: %s (engine note 2.11)"
                           % (LCS._shown(v), why))
    return kind == _RN


def _is_integer(v):
    """`is an integer` (MCMathEvalIsAnInteger): a number equal to its
    floor, exactly (engine note 2.12)."""
    if not _is_number(v):
        return False
    x = v if type(v) in (int, float) else _READ(v)[1]
    if type(x) is int:
        return True
    return x == x and x not in (_INF, -_INF) and x == math.floor(x)


def _chunks(text, unit):
    """The pieces `item`, `line`, `word` and `char` / `byte` count, with the
    engine's one-ignored-trailing-delimiter rule (engine note 2.2)."""
    if unit == "item":
        return LCS._split_chunks(text, LCS.ITEM_DELIMITER[0])
    if unit == "line":
        return LCS._split_chunks(text, LCS.LINE_DELIMITER[0])
    if unit == "word":
        return _word_list(text)
    return text


# ICU's White_Space, which MCUnicodeIsWhitespace asks (not Python's isspace,
# which also takes \x1c-\x1f)
_WS = frozenset("\t\n\x0b\x0c\r \x85\xa0\u1680\u2028\u2029\u202f\u205f"
                "\u3000" + "".join(chr(c) for c in range(0x2000, 0x200b)))


def _skip_word(text, k, skip_spaces):
    """MCChunkSkipWord: a word that opens with a quote runs to the next
    quote (taking it) or past the next line delimiter, whichever comes
    first; any other word runs to whitespace."""
    n = len(text)
    if k < n and text[k] == '"':
        d = LCS.LINE_DELIMITER[0]
        q = text.find('"', k + 1)
        e = text.find(d, k + 1)
        q = n if q < 0 else q
        e = n if e < 0 else e
        if q < e:
            k = q + 1
        elif e < q:
            k = e + len(d)
        else:
            k = n
    else:
        while k < n and text[k] not in _WS:
            k += 1
    if skip_spaces:
        while k < n and text[k] in _WS:
            k += 1
    return k


def _word_list(text):
    """The words `the number of words` counts and `repeat for each word`
    walks (MCTextChunkIterator_Word, which trims nothing)."""
    out, n, k = [], len(text), 0
    while k < n:
        while k < n and text[k] in _WS:
            k += 1
        if k >= n:
            break
        s = k
        k = _skip_word(text, k, False)
        out.append(text[s:k])
    return out


def _word_get(text, a, b):
    """`word a [to b] of text` (MCChunkGetExtentsBy*InRange, then
    MCStringsMarkTextChunkInRange's CT_WORD arm): a negative index counts
    from the end; the words come back with the whitespace between them and
    none at either end."""
    count = len(_word_list(text)) if a < 0 or (b is not None and b < 0) \
        else 0
    first = a + count if a < 0 else a - 1
    if b is None:
        many = 1
        if first < 0:
            many, first = 0, 0
    else:
        many = (b + count + 1 if b < 0 else b) - first
        if first < 0:
            many += first
            first = 0
        many = max(many, 0)
    n = len(text)
    k = 0
    while k < n and text[k] in _WS:
        k += 1
    while first > 0 and k < n:
        k = _skip_word(text, k, True)
        first -= 1
    start = min(k, n)
    while many > 0 and k < n:
        many -= 1
        k = _skip_word(text, k, many != 0)
    end = min(k, n)
    while end > start and text[end - 1] in _WS:
        end -= 1
    return text[start:end]


def chunk_get(unit, a, b, text):
    """`<unit> a [to b] of text`, a and b whole numbers (b None for one)."""
    if unit == "word":
        return _word_get(text, a, b)
    return LCS._chunk(unit, a, b, text)


def chunk_count(unit, text):
    return len(_chunks(text, unit))


def chunk_put(unit, n, text, value, prep):
    """`put value into|after|before <unit> n of text` (n one index)."""
    if unit in ("char", "byte"):
        nn = LCS._negative_index(n, len(text))
        if prep == "into":
            return LCS._chunk_store("char", n, text, value)
        if not 1 <= nn <= len(text):
            raise ModelRefusal("put %s char %d of a %d-char text" % (
                prep, n, len(text)))
        k = nn - 1 if prep == "before" else nn
        return text[:k] + value + text[k:]
    if unit not in ("item", "line"):
        raise ModelRefusal("put into a %s chunk is not modelled" % unit)
    if prep != "into":
        cur = LCS._chunk(unit, n, None, text)
        value = cur + value if prep == "after" else value + cur
    try:
        return LCS._chunk_store(unit, n, text, value)
    except SyntaxError as exc:
        raise ModelRefusal("put %s %s %d: %s" % (prep, unit, n, exc))


def chunk_delete(unit, a, b, text):
    """`delete <unit> a [to b] of text`: the pieces and, for items and
    lines, one delimiter with them (the one after, or before the last)."""
    if unit in ("char", "byte"):
        n = len(text)
        a = LCS._negative_index(a, n)
        b = a if b is None else LCS._negative_index(b, n)
        if not (1 <= a <= n) or b < a:
            return text
        return text[:a - 1] + text[min(b, n):]
    if unit not in ("item", "line"):
        raise ModelRefusal("delete a %s chunk is not modelled" % unit)
    d = LCS.ITEM_DELIMITER[0] if unit == "item" else LCS.LINE_DELIMITER[0]
    parts = LCS._split_chunks(text, d)
    trailing = text.endswith(d) and text != ""
    a = LCS._negative_index(a, len(parts))
    b = a if b is None else LCS._negative_index(b, len(parts))
    if not (1 <= a <= len(parts)) or b < a:
        return text
    del parts[a - 1:b]
    out = d.join(parts)
    if trailing and parts:
        out += d
    return out
# ==========================================================================
# expressions: a closure compiler with the engine's grammar
# ==========================================================================
#
# Each expression is tokenized and parsed ONCE into a tree of Python
# closures (env -> value); a handler's statements are compiled the same way
# the first time it runs. The grammar is the engine's (engine/src/
# express.cpp's MCExpression::getexps and the operator classes of
# operator.cpp; DOCUMENTED, read 2026-10-08):
#
#   - precedence, loosest first: or; and; bitOr; bitXor; bitAnd; the
#     equality family (is, =, <>, is not, is a / an, is among); the
#     comparisons (<, <=, >, >=, contains, begins with, ends with, is in);
#     concatenation (&, &&, and a comma where items are allowed); + and -;
#     *, /, div, mod, wrap; ^ (right to left); then the unary operators
#     (-, not, bitNot, there is), which bind TIGHTEST: `not a is b` is
#     `(not a) is b`. Equal precedence groups left to right.
#   - `and` and `or` SHORT-CIRCUIT: MCAnd::eval_ctxt evaluates the right
#     operand only when the left is true, MCOr only when it is false. The
#     suite's engine note 2.5 records the opposite as DOCUMENTED; the
#     source says this, and the game depends on it (`there is an image
#     tName and the uB2kSig of image tName is ...` reads a property of an
#     image that may not exist). See this file's header.
#   - an object's name or id, a chunk's container and the operand of `url`
#     are each ONE factor (engine note 2.6), so `item 1 of tA & tB` is
#     `(item 1 of tA) & tB`.
#   - a name resolves as the engine's parser resolves it: the engine's
#     constants (empty, comma, quote, ...), then the script's constants,
#     then a handler's variables, then the script's locals; a name that is
#     none of these is its own spelling, an unquoted literal (engine note
#     2.1). A name followed by `(` is a function call.

_TOK_RX = re.compile(r'[ \t]*(?:("[^"\n]*")|((?:\d+\.?\d*|\.\d+)'
                     r'(?:[eE][-+]?\d+)?)|([A-Za-z_][A-Za-z0-9_]*)|'
                     r'(<>|<=|>=|&&|[-+*/^&=<>(),\[\]]))')
_TOK_CACHE = {}
_END = ("e", "", "")


def tokens(text):
    """A text -> its tokens: ("s", text) a string literal, ("n", text) a
    number literal, ("w", spelling, lowercase) a word, ("o", op). A number
    the engine would lex together with a letter after it ("12ab", its hex
    and exponent letters) is a syntax error, as there."""
    hit = _TOK_CACHE.get(text)
    if hit is not None:
        return hit
    out, i, n = [], 0, len(text)
    while i < n:
        m = _TOK_RX.match(text, i)
        if not m:
            if text[i:].strip():
                raise SyntaxError("cannot read %r at %r" % (text, text[i:]))
            break
        if m.group(1) is not None:
            out.append(("s", m.group(1)[1:-1], ""))
        elif m.group(2) is not None:
            if m.end() < n and text[m.end()].isalnum():
                raise SyntaxError("a malformed number in %r" % text)
            out.append(("n", m.group(2), ""))
        elif m.group(3) is not None:
            out.append(("w", m.group(3), m.group(3).lower()))
        else:
            out.append(("o", m.group(4), m.group(4)))
        i = m.end()
    out.append(_END)
    out = tuple(out)
    if len(_TOK_CACHE) < 200000:
        _TOK_CACHE[text] = out
    return out


# the engine's constant table (engine/src/lextable.cpp, constant_table): the
# entries a script could meet here; a name in it is never a variable
_CONSTS = {"empty": "", "true": True, "false": False, "comma": ",",
           "space": " ", "tab": "\t", "quote": '"', "return": "\n",
           "cr": "\n", "lf": "\n", "linefeed": "\n", "crlf": "\r\n",
           "colon": ":", "slash": "/", "backslash": "\\", "null": "\0",
           "formfeed": "\f", "up": "up", "down": "down", "pi": math.pi}

_CHUNK = {"item": "item", "items": "item", "line": "line", "lines": "line",
          "char": "char", "chars": "char", "character": "char",
          "characters": "char", "word": "word", "words": "word",
          "byte": "byte", "bytes": "byte"}
_CHUNK_ONE = ("item", "line", "char", "character", "word", "byte")
_ADJ = ("short", "long", "abbreviated", "abbrev", "abbr", "effective")
_UNITS = {"milliseconds": 1, "millisecond": 1, "millisecs": 1,
          "millisec": 1, "ms": 1, "seconds": 1000, "second": 1000,
          "secs": 1000, "sec": 1000, "ticks": 1000.0 / 60, "tick": 1000.0 / 60}


class _NoSuchObject(Thrown):
    """The engine's "no such object" script error: a Thrown a `try` may
    catch, and what `there is` turns into false."""

    def __init__(self, what):
        Thrown.__init__(self, "Chunk: no such object (%s)" % what)


class _Scope(object):
    """What one handler's names are, decided when it is compiled: its
    parameters, its declared locals and the names it creates by assigning
    them (the engine makes an undeclared name a local where it is first
    assigned; the game never reads one before that, which the lexical
    precondition below checks), and `it`."""

    def __init__(self, name, env_names):
        self.name = name
        self.env_names = env_names


class _Cx(object):
    """A recursive-descent parser over one text's tokens, answering
    closures. `ip` supplies the world (objects, properties, handlers)."""

    def __init__(self, ip, scope, text):
        self.ip = ip
        self.scope = scope
        self.text = text
        self.t = tokens(text)
        self.i = 0

    # -- token helpers ------------------------------------------------------
    def fail(self, msg):
        raise SyntaxError("%s at %r in %r" % (
            msg, " ".join(t[1] for t in self.t[self.i:self.i + 4]), self.text))

    def lw(self, k=0):
        tok = self.t[self.i + k] if self.i + k < len(self.t) else _END
        return tok[2] if tok[0] == "w" else None

    def op(self, k=0):
        tok = self.t[self.i + k] if self.i + k < len(self.t) else _END
        return tok[1] if tok[0] == "o" else None

    def take(self, *words):
        tok = self.t[self.i]
        if tok[0] == "w" and tok[2] in words:
            self.i += 1
            return tok[2]
        return None

    def need(self, *words):
        w = self.take(*words)
        if w is None:
            self.fail("expected %s" % " or ".join(words))
        return w

    def take_op(self, op):
        tok = self.t[self.i]
        if tok[0] == "o" and tok[1] == op:
            self.i += 1
            return True
        return False

    def need_op(self, op):
        if not self.take_op(op):
            self.fail("expected %r" % op)

    def at_end(self):
        return self.t[self.i][0] == "e"

    def done(self):
        if not self.at_end():
            self.fail("unexpected input")

    # -- the precedence ladder ---------------------------------------------
    def expr(self, litems=True):
        return self.p_or(litems)

    def p_or(self, li):
        left = self.p_and(li)
        while self.take("or"):
            right = self.p_and(li)
            left = self._or(left, right)
        return left

    @staticmethod
    def _or(l, r):
        def f(env):
            return True if _truth(l(env)) else _truth(r(env))
        return f

    @staticmethod
    def _and(l, r):
        def f(env):
            return _truth(r(env)) if _truth(l(env)) else False
        return f

    def p_and(self, li):
        left = self.p_bitor(li)
        while self.take("and"):
            right = self.p_bitor(li)
            left = self._and(left, right)
        return left

    def _bitop(self, sub, word, fn, li):
        left = sub(li)
        while self.take(word):
            right = sub(li)
            left = self._mkbit(left, right, fn, word)
        return left

    @staticmethod
    def _mkbit(l, r, fn, word):
        def f(env):
            return fn(_u32(l(env), word), _u32(r(env), word))
        return f

    def p_bitor(self, li):
        return self._bitop(self.p_bitxor, "bitor", lambda a, b: a | b, li)

    def p_bitxor(self, li):
        return self._bitop(self.p_bitand, "bitxor", lambda a, b: a ^ b, li)

    def p_bitand(self, li):
        return self._bitop(self.p_eq, "bitand", lambda a, b: a & b, li)

    def p_eq(self, li):
        left = self.p_cmp(li)
        while True:
            if self.take_op("="):
                left = self._mkeq(left, self.p_cmp(li), False)
                continue
            if self.take_op("<>"):
                left = self._mkeq(left, self.p_cmp(li), True)
                continue
            if self.lw() != "is":
                return left
            save = self.i
            self.i += 1
            neg = bool(self.take("not"))
            if self.lw() in ("in", "within"):
                self.i = save            # `is in`: a comparison, below
                return left
            if self.take("a", "an"):
                kind = self.need("number", "integer", "boolean", "array")
                left = self._mktype(left, kind, neg)
                continue
            if self.take("among"):
                self.need("the")
                unit = self.need("items", "lines", "keys", "words")
                self.need("of")
                left = self._mkamong(left, self.p_cmp(li), unit, neg)
                continue
            left = self._mkeq(left, self.p_cmp(li), neg)

    @staticmethod
    def _mkeq(l, r, neg):
        if neg:
            def f(env):
                return not pf_eq(l(env), r(env))
        else:
            def f(env):
                return pf_eq(l(env), r(env))
        return f

    @staticmethod
    def _mktype(l, kind, neg):
        def f(env):
            v = l(env)
            if kind == "number":
                hit = _is_number(v)
            elif kind == "integer":
                hit = _is_integer(v)
            elif kind == "boolean":
                hit = type(v) is bool or (type(v) is str and v.lower() in
                                          ("true", "false"))
            else:
                raise ModelRefusal("`is an array` is not modelled")
            return hit != neg
        return f

    @staticmethod
    def _mkamong(l, r, unit, neg):
        def f(env):
            v, c = l(env), r(env)
            if unit == "keys":
                hit = isinstance(c, dict) and LCS._arr_has(c, _s(v))
            else:
                sv = _fold(_s(v))
                hit = any(_fold(x) == sv for x in _chunks(_s(c), unit[:-1]))
            return hit != neg
        return f

    def p_cmp(self, li):
        left = self.p_concat(li)
        while True:
            o = self.op()
            if o in ("<", "<=", ">", ">="):
                self.i += 1
                left = self._mkord(left, self.p_concat(li), o)
                continue
            w = self.lw()
            if w == "contains":
                self.i += 1
                left = self._mkstr(left, self.p_concat(li), "contains")
                continue
            if w in ("begins", "ends"):
                self.i += 1
                self.need("with")
                left = self._mkstr(left, self.p_concat(li), w)
                continue
            if w == "is" and self.lw(1) == "in" or (
                    w == "is" and self.lw(1) == "not" and self.lw(2) == "in"):
                self.i += 1
                neg = bool(self.take("not"))
                self.need("in")
                left = self._mkstr(left, self.p_concat(li),
                                   "notin" if neg else "in")
                continue
            return left

    @staticmethod
    def _mkord(l, r, o):
        if o == "<":
            def f(env):
                return pf_order(l(env), r(env)) < 0
        elif o == "<=":
            def f(env):
                return pf_order(l(env), r(env)) <= 0
        elif o == ">":
            def f(env):
                return pf_order(l(env), r(env)) > 0
        else:
            def f(env):
                return pf_order(l(env), r(env)) >= 0
        return f

    @staticmethod
    def _mkstr(l, r, how):
        def f(env):
            a, b = _fold(_s(l(env))), _fold(_s(r(env)))
            if how == "contains":
                return b in a
            if how == "begins":
                return a.startswith(b)
            if how == "ends":
                return a.endswith(b)
            if how == "in":
                return a in b
            return a not in b
        return f

    def p_concat(self, li):
        left = self.p_add(li)
        while True:
            o = self.op()
            if o == "&":
                self.i += 1
                left = self._mkcat(left, self.p_add(li), "")
            elif o == "&&":
                self.i += 1
                left = self._mkcat(left, self.p_add(li), " ")
            elif o == "," and li:
                self.i += 1
                left = self._mkcat(left, self.p_add(li), ",")
            else:
                return left

    @staticmethod
    def _mkcat(l, r, sep):
        if sep:
            def f(env):
                return _s(l(env)) + sep + _s(r(env))
        else:
            def f(env):
                return _s(l(env)) + _s(r(env))
        return f

    def p_add(self, li):
        left = self.p_mul(li)
        while True:
            o = self.op()
            if o == "+":
                self.i += 1
                left = self._mkarith(left, self.p_mul(li), "+")
            elif o == "-":
                self.i += 1
                left = self._mkarith(left, self.p_mul(li), "-")
            else:
                return left

    def p_mul(self, li):
        left = self.p_pow(li)
        while True:
            o = self.op()
            if o in ("*", "/"):
                self.i += 1
                left = self._mkarith(left, self.p_pow(li), o)
                continue
            w = self.lw()
            if w in ("div", "mod", "wrap"):
                self.i += 1
                left = self._mkarith(left, self.p_pow(li), w)
                continue
            return left

    def p_pow(self, li):
        base = self.p_unary(li)
        if self.take_op("^"):
            return self._mkarith(base, self.p_pow(li), "^")
        return base

    @staticmethod
    def _mkarith(l, r, o):
        if o == "+":
            def f(env):
                a, b = l(env), r(env)
                if type(a) is not int and type(a) is not float:
                    a = _num(a, "+")
                if type(b) is not int and type(b) is not float:
                    b = _num(b, "+")
                return _fix(a + b, "+")
        elif o == "-":
            def f(env):
                a, b = l(env), r(env)
                if type(a) is not int and type(a) is not float:
                    a = _num(a, "-")
                if type(b) is not int and type(b) is not float:
                    b = _num(b, "-")
                return _fix(a - b, "-")
        elif o == "*":
            def f(env):
                a, b = _num(l(env), "*"), _num(r(env), "*")
                return _fix(a * b, "*")
        elif o == "/":
            def f(env):
                a, b = _num(l(env), "/"), _num(r(env), "/")
                if b == 0:
                    raise Thrown("/: divide by zero")
                return _fix(a / b, "/")
        elif o == "div":
            def f(env):
                a, b = _num(l(env), "div"), _num(r(env), "div")
                if b == 0:
                    raise Thrown("div: divide by zero")
                q = a / b
                return _fix(math.ceil(q) if q < 0 else math.floor(q), "div")
        elif o == "mod":
            def f(env):
                a, b = _num(l(env), "mod"), _num(r(env), "mod")
                if b == 0:
                    raise Thrown("mod: divide by zero")
                return _fix(math.fmod(a, b) if (type(a) is float or
                                                type(b) is float)
                            else int(math.fmod(a, b)), "mod")
        elif o == "wrap":
            raise ModelRefusal("`wrap` is not modelled")
        else:
            def f(env):
                a, b = _num(l(env), "^"), _num(r(env), "^")
                if a == 0 and b < 0:
                    raise Thrown("^: divide by zero")
                try:
                    x = math.pow(a, b)
                except (OverflowError, ValueError):
                    raise Thrown("^: the result is not a finite number")
                return _fix(x, "^")
        return f

    def p_unary(self, li):
        if self.take_op("-"):
            sub = self.p_unary(li)

            def f(env):
                v = sub(env)
                if type(v) is not int and type(v) is not float:
                    v = _num(v, "-")
                return _fix(-v, "-")
            return f
        w = self.lw()
        if w == "not":
            self.i += 1
            sub = self.p_unary(li)
            return lambda env: not _truth(sub(env))
        if w == "bitnot":
            self.i += 1
            sub = self.p_unary(li)
            return lambda env: (~_u32(sub(env), "bitNot")) & _U32
        if w == "there" and self.lw(1) == "is":
            return self.p_there()
        return self.p_factor()

    # -- factors ------------------------------------------------------------
    def p_factor(self):
        tok = self.t[self.i]
        kind = tok[0]
        if kind == "s":
            self.i += 1
            v = tok[1]
            return lambda env: v
        if kind == "n":
            self.i += 1
            return self._numlit(tok[1])
        if kind == "o":
            if tok[1] == "(":
                self.i += 1
                inner = self.expr(True)
                self.need_op(")")
                return inner
            self.fail("unexpected %r" % tok[1])
        if kind != "w":
            self.fail("an expression ended early")
        low = tok[2]
        if low == "the":
            self.i += 1
            return self.p_the()
        if low in _CHUNK_ONE:
            return self.p_chunk()
        if low == "url":
            self.i += 1
            spec = self.p_factor()
            ip = self.ip
            return lambda env: ip.url_read(_s(spec(env)))
        if low in KIND and low not in ("card", "cd", "stack"):
            if low in ("field", "fld", "button", "btn"):
                ref = self.p_objref()
                ip = self.ip
                return lambda env: ip.obj_text(ref(env))
            self.fail("an object as a value")
        if low == "me":
            self.fail("`me` as a value")
        if self.op(1) == "(":
            self.i += 2
            args = []
            if not self.take_op(")"):
                while True:
                    args.append(self.expr(False))
                    if self.take_op(","):
                        continue
                    self.need_op(")")
                    break
            return self.ip.compile_call(tok[1], args)
        self.i += 1
        if low in _CONSTS:
            v = _CONSTS[low]
            return lambda env: v
        ip, scope = self.ip, self.scope
        if low in ip.consts:
            v = ip.consts[low]
            return lambda env: v
        if self.op() == "[":
            keys = self.p_subscripts()
            return self._element(low, keys)
        if scope is not None and low in scope.env_names:
            return lambda env: env[low]
        if low in ip.globals:
            g = ip.globals
            return lambda env: g[low]
        # the engine's unquoted literal (engine note 2.1)
        ip.literals[tok[1]] = ip.literals.get(tok[1], 0) + 1
        v = tok[1]
        return lambda env: v

    @staticmethod
    def _numlit(text):
        """A number literal: the engine keeps its text AND its number
        (MCLiteralNumber), so `put 1.50 into x` shows "1.50" and adds 1.5.
        Held as the number where the number's text is the literal's own,
        else as the literal's text (which reads back as the same number)."""
        if "e" in text.lower():
            raise ModelRefusal("an exponent literal (%s) is not modelled" % text)
        v = float(text) if ("." in text) else int(text)
        if _text(v) != text:
            v = text
        return lambda env: v

    def p_subscripts(self):
        keys = []
        while self.take_op("["):
            keys.append(self.expr(True))
            self.need_op("]")
        return keys

    def _element(self, low, keys):
        scope, ip = self.scope, self.ip
        if scope is not None and low in scope.env_names:
            src = None
        elif low in ip.globals:
            src = ip.globals
        else:
            self.fail("a subscript of %r, which is not a variable" % low)

        def f(env):
            node = env[low] if src is None else src[low]
            for k in keys:
                if not isinstance(node, dict):
                    return ""
                node = LCS._arr_get(node, _s(k(env)))
            return node
        return f

    def p_chunk(self):
        unit = _CHUNK[self.lw()]
        self.i += 1
        a = self.expr(False)
        b = None
        if self.take("to"):
            b = self.expr(False)
        self.need("of", "in")
        cont = self.p_factor()
        return self._mkchunk(unit, a, b, cont)

    @staticmethod
    def _mkchunk(unit, a, b, cont):
        if b is None:
            def f(env):
                return chunk_get(unit, _int_of(a(env), unit), None,
                                 _s(cont(env)))
        else:
            def f(env):
                return chunk_get(unit, _int_of(a(env), unit),
                                 _int_of(b(env), unit), _s(cont(env)))
        return f

    def p_there(self):
        self.i += 2                       # there is
        neg = False
        if self.take("no"):
            neg = True
        elif self.take("not"):
            neg = True
            self.need("a", "an")
        else:
            self.need("a", "an")
        w = self.lw()
        ip = self.ip
        if w in ("file", "folder", "directory"):
            self.i += 1
            path = self.p_factor()
            what = "file" if w == "file" else "folder"
            return lambda env: ip.path_exists(_s(path(env)), what) != neg
        ref = self.p_objref(typed_only=True)

        def f(env):
            try:
                ref(env)
                hit = True
            except _NoSuchObject:
                hit = False
            return hit != neg
        return f

    # -- `the` --------------------------------------------------------------
    def p_the(self):
        w = self.lw()
        if w is None:
            self.fail("expected a property after `the`")
        ip = self.ip
        if w == "number" and self.lw(1) == "of":
            self.i += 2
            u = self.lw()
            if u in ("items", "lines", "chars", "characters", "words",
                     "bytes"):
                self.i += 1
                self.need("of", "in")
                cont = self.p_factor()
                unit = _CHUNK[u]
                return lambda env: chunk_count(unit, _s(cont(env)))
            if u in PLURAL:
                self.i += 1
                kind = PLURAL[u]
                within = None
                if self.take("of", "in"):
                    within = self.p_container()
                return lambda env: ip.count_of(kind, within(env) if within
                                               else None)
            ref = self.p_objref()
            return lambda env: ip.prop_get(ref(env), "number", "", None)
        if w == "keys" and self.lw(1) == "of":
            self.i += 2
            arr = self.p_factor()

            def keys(env):
                v = arr(env)
                return "\n".join(dict.keys(v)) if isinstance(v, dict) else ""
            return keys
        if w in ("last", "first") and self.lw(1) in _CHUNK_ONE:
            self.i += 1
            unit = _CHUNK[self.lw()]
            self.i += 1
            self.need("of", "in")
            cont = self.p_factor()
            n = -1 if w == "last" else 1
            return lambda env: chunk_get(unit, n, None, _s(cont(env)))
        adj = ""
        if w in _ADJ and self.lw(1) is not None and self.lw(1) != "of":
            adj = {"abbrev": "abbreviated", "abbr": "abbreviated"}.get(w, w)
            self.i += 1
            w = self.lw()
        prop = w
        self.i += 1
        key = None
        if self.op() == "[":
            self.i += 1
            key = self.expr(True)
            self.need_op("]")
        if self.take("of"):
            if prop in _FN1 and not adj and key is None:
                arg = self.p_factor()
                fn = _FN1[prop]
                return lambda env: fn(ip, [arg(env)])
            ref = self.p_objref()
            return ip.compile_prop_get(ref, prop, adj, key)
        if adj and not (adj == "long" and prop in ("seconds", "time")):
            self.fail("`the %s %s` with no object" % (adj, prop))
        return ip.compile_global_get(prop, key)

    # -- object references -------------------------------------------------
    def p_objref(self, typed_only=False):
        """An object reference -> a closure answering the Obj (or raising
        _NoSuchObject, the engine's script error)."""
        ip = self.ip
        w = self.lw()
        if w == "me":
            self.i += 1
            return lambda env: ip.w.stack
        if w == "this" and self.lw(1) in ("card", "cd", "stack"):
            self.i += 2
            if self.t[self.i - 1][2] == "stack":
                return lambda env: ip.w.stack
            return lambda env: ip.w.card
        if w == "the":
            n1 = self.lw(1)
            if n1 == "target":
                self.i += 2
                return lambda env: ip.target_obj()
            if n1 == "owner" and self.lw(2) == "of":
                self.i += 3
                sub = self.p_objref()

                def owner(env):
                    o = sub(env)
                    if o.owner is None:
                        raise _NoSuchObject("the owner of the stack")
                    return o.owner
                return owner
            if n1 in ("last", "first") and self.lw(2) in KIND:
                self.i += 2
                kind = KIND[self.lw()]
                self.i += 1
                within = None
                if self.take("of"):
                    within = self.p_container()
                last = n1 == "last"
                return lambda env: ip.ordinal(kind, last, within(env) if within
                                              else None)
        if w in KIND:
            self.i += 1
            kind = KIND[w]
            if kind == "stack" and self.lw() not in ("id",) and (
                    self.at_end() or self.lw() in ("of", "to", "with", "in")):
                return lambda env: ip.w.stack
            by_id = bool(self.take("id"))
            key = self.p_factor()
            within = None
            if self.take("of"):
                within = self.p_container()
            return lambda env: ip.resolve(kind, by_id, key(env),
                                          within(env) if within else None)
        if typed_only:
            self.fail("expected an object type")
        val = self.p_factor()
        return lambda env: ip.ref_from_text(_s(val(env)))

    def p_container(self):
        """After `of` in an object reference: a card, a stack or a group."""
        ip = self.ip
        w = self.lw()
        if w == "me":
            self.i += 1
            return lambda env: ip.w.stack
        if w == "this" and self.lw(1) in ("card", "cd", "stack"):
            self.i += 2
            if self.t[self.i - 1][2] == "stack":
                return lambda env: ip.w.stack
            return lambda env: ip.w.card
        if w in ("group", "grp", "card", "cd", "stack"):
            return self.p_objref(typed_only=True)
        val = self.p_factor()
        return lambda env: ip.ref_from_text(_s(val(env)))
# ==========================================================================
# the simple statements
# ==========================================================================
#
# Each statement form the game writes, compiled once to a closure. The
# forms are the ones a census of the prepared game finds (put, set, get,
# add, subtract, delete, create, clone, ungroup, relayer, flip, import,
# play, answer, ask, save, lock, unlock, send, dispatch, replace, return,
# exit, pass, next, break, throw, local, and a call of a handler or of a
# box2dxt.lcb handler); a form outside them is refused when the handler
# holding it is first compiled.

_UNIT_WORDS = frozenset(_UNITS)


class _Statements(object):
    """PfInterp's simple statements (the block forms live in PfInterp)."""

    def _stmt(self, line, scope):
        first = self._first(line)
        fn = _STMT.get(first)
        if fn is not None:
            return fn(self, line, scope)
        return self._s_call(line, scope)

    # -- variables and containers -------------------------------------------
    def _var(self, low, scope):
        """(get, set) closures for a plain variable: a handler's own name,
        else a script local. An array crossing a binding is COPIED (arrays
        are values; LCS._copy)."""
        if low in scope.env_names:
            def get(env):
                return env[low]

            def put(env, v):
                env[low] = LCS._copy(v) if isinstance(v, dict) else v
            return get, put
        if low in self.globals:
            g = self.globals

            def gget(env):
                return g[low]

            def gput(env, v):
                g[low] = LCS._copy(v) if isinstance(v, dict) else v
            return gget, gput
        raise ModelRefusal("%s: %s is not a variable here" % (scope.name, low))

    def _elem(self, low, keys, scope):
        """(get, set) for `name[k1][k2]...`. A missing element reads empty;
        a write makes each level an array (the engine discards a scalar it
        must index, MCVariable::setvalueref with a path)."""
        vget, vput = self._var(low, scope)
        last = len(keys) - 1

        def get(env):
            node = vget(env)
            for k in keys:
                if not isinstance(node, dict):
                    return ""
                node = LCS._arr_get(node, _s(k(env)))
            return node

        def put(env, v):
            ks = [_s(k(env)) for k in keys]
            root = vget(env)
            if not isinstance(root, dict):
                root = LCS.LcsArray()
                vput(env, root)
                root = vget(env)
            node = root
            for n, k in enumerate(ks):
                if n == last:
                    LCS._arr_set(node, k, LCS._copy(v) if isinstance(v, dict)
                                 else v)
                    return
                nxt = LCS._arr_get(node, k)
                if not isinstance(nxt, dict):
                    nxt = LCS.LcsArray()
                    LCS._arr_set(node, k, nxt)
                    nxt = LCS._arr_get(node, k)
                node = nxt
        return get, put

    def _cont(self, cx, scope):
        """A container -> (get, put): a variable, an element, a chunk of a
        container, a field's text or a URL."""
        w = cx.lw()
        if w is None:
            cx.fail("expected a container")
        if w == "the" and cx.lw(1) in ("last", "first") and \
                cx.lw(2) in _CHUNK_ONE:
            cx.i += 1
            n = -1 if cx.lw() == "last" else 1
            cx.i += 1
            unit = _CHUNK[cx.lw()]
            cx.i += 1
            cx.need("of", "in")
            g, p = self._cont(cx, scope)
            a = (lambda env: n)
            return self._chunk_cont(unit, a, None, g, p)
        if w in _CHUNK_ONE:
            unit = _CHUNK[w]
            cx.i += 1
            a = cx.expr(False)
            b = None
            if cx.take("to"):
                b = cx.expr(False)
            cx.need("of", "in")
            g, p = self._cont(cx, scope)
            return self._chunk_cont(unit, a, b, g, p)
        if w in ("field", "fld"):
            ref = cx.p_objref()
            ip = self

            def fget(env):
                return ip.obj_text(ref(env))

            def fput(env, v):
                ip.set_text(ref(env), _s(v))
            return fget, fput
        if w == "url":
            cx.i += 1
            spec = cx.p_factor()
            ip = self

            def uget(env):
                return ip.url_read(_s(spec(env)))

            def uput(env, v):
                ip.url_write(_s(spec(env)), v)
            return uget, uput
        tok = cx.t[cx.i]
        if tok[0] != "w":
            cx.fail("expected a container")
        low = tok[2]
        if low in _CONSTS or low in self.consts or low in KIND:
            cx.fail("%s is not a container" % low)
        cx.i += 1
        if cx.op() == "[":
            return self._elem(low, cx.p_subscripts(), scope)
        return self._var(low, scope)

    @staticmethod
    def _chunk_cont(unit, a, b, g, p):
        def get(env):
            return chunk_get(unit, _int_of(a(env), unit),
                             None if b is None else _int_of(b(env), unit),
                             _s(g(env)))

        def put(env, v, prep="into"):
            if b is not None:
                raise ModelRefusal("a put into a chunk RANGE is not modelled")
            p(env, chunk_put(unit, _int_of(a(env), unit), _s(g(env)), _s(v),
                             prep))

        def delete(env):
            p(env, chunk_delete(unit, _int_of(a(env), unit),
                                None if b is None else _int_of(b(env), unit),
                                _s(g(env))))
        put.chunk = True
        put.delete = delete
        return get, put

    # -- put, get, add, subtract, replace -------------------------------------
    def _s_put(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        val = cx.expr(True)
        prep = cx.take("into", "after", "before")
        if prep is None:
            raise ModelRefusal("%s: a `put` with no container writes the "
                               "message box, which is not modelled: %r"
                               % (scope.name, line))
        get, put = self._cont(cx, scope)
        cx.done()
        if getattr(put, "chunk", False):
            if prep == "into":
                return lambda env: put(env, val(env))
            return lambda env: put(env, val(env), prep)
        if prep == "into":
            return lambda env: put(env, val(env))
        if prep == "after":
            return lambda env: put(env, _s(get(env)) + _s(val(env)))
        return lambda env: put(env, _s(val(env)) + _s(get(env)))

    def _s_get(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        val = cx.expr(True)
        cx.done()

        def f(env):
            env["it"] = LCS._copy(val(env))
        return f

    def _s_add(self, line, scope):
        sub = self._first(line) == "subtract"
        cx = _Cx(self, scope, line)
        cx.i = 1
        val = cx.expr(True)
        cx.need("from" if sub else "to")
        get, put = self._cont(cx, scope)
        cx.done()
        what = "subtract" if sub else "add"

        def f(env):
            # MCAdd / MCSubtract: the source, then the destination's value
            # as a number (empty is 0; text that is no number is the
            # command's script error); an array destination is refused
            b = _num(val(env), what)
            a = get(env)
            if isinstance(a, dict):
                raise ModelRefusal("%s on an array is not modelled" % what)
            a = _num(a, what + " (destination)")
            put(env, _fix(a - b if sub else a + b, what))
        return f

    def _s_replace(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        old = cx.expr(False)
        cx.need("with")
        new = cx.expr(False)
        cx.need("in")
        get, put = self._cont(cx, scope)
        cx.done()

        def f(env):
            o, n, t = _s(old(env)), _s(new(env)), _s(get(env))
            if not o:
                return
            if LCS.CASE_SENSITIVE[0] or not any(c.isalpha() for c in o):
                put(env, t.replace(o, n))
            else:
                raise ModelRefusal("a caseless `replace` of letters is not "
                                   "modelled")
        return f

    # -- set --------------------------------------------------------------------
    def _s_set(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        cx.need("the")
        if cx.lw() in ("long", "short") and cx.lw(1) not in ("of", "to"):
            raise ModelRefusal("%s: setting a %s property: %r"
                               % (scope.name, cx.lw(), line))
        prop = cx.lw()
        if prop is None:
            cx.fail("expected a property")
        cx.i += 1
        key = None
        if cx.take_op("["):
            key = cx.expr(True)
            cx.need_op("]")
        ref = None
        if cx.take("of"):
            ref = cx.p_objref()
        cx.need("to")
        val = cx.expr(True)
        cx.done()
        if ref is None:
            return self.compile_global_set(prop, key, val, scope)
        if key is not None:
            raise ModelRefusal("%s: a keyed object property: %r"
                               % (scope.name, line))
        return self.compile_prop_set(ref, prop, val)

    # -- delete -------------------------------------------------------------
    def _s_delete(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        w = cx.lw()
        ip = self
        if w == "variable":
            cx.i += 1
            tok = cx.t[cx.i]
            if tok[0] != "w":
                cx.fail("expected a variable")
            low = tok[2]
            cx.i += 1
            keys = cx.p_subscripts()
            cx.done()
            if not keys:
                raise ModelRefusal("%s: deleting a whole variable is not "
                                   "modelled" % scope.name)
            parent = (self._elem(low, keys[:-1], scope)[0] if len(keys) > 1
                      else self._var(low, scope)[0])
            last = keys[-1]

            def dv(env):
                node = parent(env)
                if isinstance(node, dict):
                    LCS._arr_del(node, _s(last(env)))
            return dv
        if w == "file":
            cx.i += 1
            path = cx.expr(False)
            cx.done()
            return lambda env: ip.delete_file(_s(path(env)))
        if w in KIND or w == "the" and cx.lw(1) in ("last", "first") and \
                cx.lw(2) in KIND:
            ref = cx.p_objref()
            cx.done()
            return lambda env: ip.delete_object(ref(env))
        get, put = self._cont(cx, scope)
        cx.done()
        if getattr(put, "chunk", False):
            return put.delete
        # `delete <variable>`: MCDelete reads the container as an OBJECT
        # reference and deletes that object (the game keeps long ids in
        # variables and deletes through them)
        return lambda env: ip.delete_object(ip.ref_from_text(_s(get(env))))

    # -- objects ------------------------------------------------------------
    def _s_create(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        w = cx.lw()
        if w not in ("graphic", "grc", "field", "fld", "button", "btn",
                     "image", "img", "group", "grp"):
            raise ModelRefusal("%s: create %s is not modelled" % (scope.name, w))
        kind = KIND[w]
        cx.i += 1
        name = None
        if not cx.at_end() and cx.lw() != "in":
            name = cx.expr(False)
        within = None
        if cx.take("in"):
            within = cx.p_container()
        cx.done()
        ip = self

        def f(env):
            nm = _s(name(env)) if name is not None else ""
            parent = within(env) if within is not None else ip.w.card
            env["it"] = ip.create_object(kind, nm, parent)
        return f

    def _s_clone(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        ref = cx.p_objref()
        cx.done()
        ip = self

        def f(env):
            env["it"] = ip.clone_object(ref(env))
        return f

    def _s_ungroup(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        ref = cx.p_objref()
        cx.done()
        ip = self
        return lambda env: ip.ungroup_object(ref(env))

    def _s_relayer(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        ref = cx.p_objref()
        cx.need("to")
        cx.need("front")
        cx.need("of")
        grp = cx.p_container()
        cx.done()
        ip = self
        return lambda env: ip.relayer_object(ref(env), grp(env))

    def _s_flip(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        if cx.lw() not in ("image", "img"):
            raise ModelRefusal("%s: flip of a non-image" % scope.name)
        ref = cx.p_objref()
        how = cx.need("horizontal", "vertical")
        cx.done()
        ip = self
        return lambda env: ip.flip_image(ref(env), how == "horizontal")

    # -- media and files ----------------------------------------------------
    def _s_import(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        if cx.lw() != "audioclip":
            raise ModelRefusal("%s: import of a %s" % (scope.name, cx.lw()))
        cx.i += 1
        cx.need("from")
        cx.need("file")
        path = cx.expr(False)
        cx.done()
        ip = self
        return lambda env: ip.import_clip(_s(path(env)))

    def _s_play(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        ip = self
        if cx.take("stop"):
            cx.done()
            return lambda env: ip.play_stop()
        if cx.lw() != "audioclip":
            raise ModelRefusal("%s: play of a %s" % (scope.name, cx.lw()))
        cx.i += 1
        name = cx.p_factor()
        looping = bool(cx.take("looping"))
        cx.done()
        return lambda env: ip.play_clip(_s(name(env)), looping)

    def _s_save(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        cx.need("this")
        cx.need("stack")
        cx.need("as")
        path = cx.expr(False)
        cx.done()
        ip = self
        return lambda env: ip.save_stack(_s(path(env)))

    # -- dialogs --------------------------------------------------------------
    def _s_answer(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        ip = self
        if cx.take("folder"):
            prompt = cx.expr(False)
            cx.done()

            def af(env):
                env["it"] = ip.dialog("answer folder", _s(prompt(env)), ())
            return af
        prompt = cx.expr(False)
        buttons = []
        if cx.take("with"):
            # MCAnswer::parse: the buttons are FACTORS separated by `or`
            # (the `or` there is grammar, not the operator)
            buttons.append(cx.p_factor())
            while cx.take("or"):
                buttons.append(cx.p_factor())
        cx.done()

        def an(env):
            env["it"] = ip.dialog("answer", _s(prompt(env)),
                                  tuple(_s(b(env)) for b in buttons))
        return an

    def _s_ask(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        if not cx.take("file"):
            raise ModelRefusal("%s: an `ask` other than `ask file`" % scope.name)
        prompt = cx.expr(False)
        default = None
        if cx.take("with"):
            default = cx.expr(False)
        cx.done()
        ip = self

        def f(env):
            env["it"] = ip.dialog("ask file", _s(prompt(env)),
                                  (_s(default(env)),) if default else ())
        return f

    # -- locks, messages ------------------------------------------------------
    def _s_lock(self, line, scope):
        low = line.lower().split()
        w = self.w
        if low == ["lock", "screen"]:
            def ls(env):
                w.lock_screen += 1
            return ls
        if low == ["unlock", "screen"]:
            def us(env):
                if w.lock_screen > 0:
                    w.lock_screen -= 1
            return us
        if low == ["lock", "messages"]:
            def lm(env):
                w.lock_msgs = True
            return lm
        if low == ["unlock", "messages"]:
            def um(env):
                w.lock_msgs = False
            return um
        raise ModelRefusal("%s: %r is not modelled" % (scope.name, line))

    def _s_send(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        msg = cx.expr(False)
        cx.need("to")
        target = cx.p_objref()
        delay, unit = None, None
        if cx.take("in"):
            delay = cx.expr(False)
            unit = cx.need(*_UNIT_WORDS)
        cx.done()
        ip = self

        def f(env):
            text = _s(msg(env))
            name, args = ip.split_message(text, scope, env)
            tgt = target(env)
            if delay is None:
                ip.send_now(tgt, name, args)
            else:
                ms = _num(delay(env), "send ... in") * _UNITS[unit]
                ip.send_later(tgt, name, args, ms)
        return f

    def _s_dispatch(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        msg = cx.expr(False)
        target = None
        if cx.take("to"):
            target = cx.p_objref()
        args = []
        if cx.take("with"):
            while True:
                args.append(cx.expr(False))
                if not cx.take_op(","):
                    break
        cx.done()
        ip = self

        def f(env):
            name = _s(msg(env))
            tgt = target(env) if target is not None else ip.w.stack
            vals = [a(env) for a in args]
            env["it"] = ip.dispatch(tgt, name, vals)
        return f

    # -- leaving --------------------------------------------------------------
    def _s_return(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        if cx.at_end():
            def r0(env):
                raise _Return("")
            return r0
        val = cx.expr(True)
        cx.done()

        def r(env):
            raise _Return(LCS._copy(val(env)))
        return r

    def _s_exit(self, line, scope):
        low = line.lower().split()
        if len(low) != 2:
            raise ModelRefusal("%s: %r" % (scope.name, line))
        if low[1] == "repeat":
            def er(env):
                raise _ExitRepeat()
            return er
        if low[1] != scope.name.lower():
            if low[1] in ("to", "switch"):
                raise ModelRefusal("%s: %r is not modelled" % (scope.name, line))
            raise ModelRefusal("%s: `exit %s` names another handler (the "
                               "engine's parse error)" % (scope.name, low[1]))

        def eh(env):
            raise _ExitHandler()
        return eh

    def _s_pass(self, line, scope):
        low = line.lower().split()
        if len(low) != 2 or low[1] != scope.name.lower():
            raise ModelRefusal("%s: %r" % (scope.name, line))

        def ps(env):
            raise _ExitHandler(passed=True)
        return ps

    def _s_next(self, line, scope):
        if line.lower().split() != ["next", "repeat"]:
            raise ModelRefusal("%s: %r" % (scope.name, line))

        def nr(env):
            raise _NextRepeat()
        return nr

    def _s_break(self, line, scope):
        if line.lower() != "break":
            raise ModelRefusal("%s: %r" % (scope.name, line))

        def br(env):
            raise _Break()
        return br

    def _s_throw(self, line, scope):
        cx = _Cx(self, scope, line)
        cx.i = 1
        val = cx.expr(True)
        cx.done()

        def th(env):
            raise Thrown(_s(val(env)))
        return th

    def _s_local(self, line, scope):
        return None                       # declared names start empty

    # -- calls ----------------------------------------------------------------
    def _s_call(self, line, scope):
        """`name args`: a command handler of the script (private ones too:
        a direct call is not a message), else box2dxt.lcb's, whose answer
        becomes `the result` (MCEngineHandleLibraryMessage)."""
        cx = _Cx(self, scope, line)
        tok = cx.t[0]
        if tok[0] != "w":
            raise ModelRefusal("%s: %r" % (scope.name, line))
        word, low = tok[1], tok[2]
        cx.i = 1
        args = []
        if not cx.at_end():
            while True:
                args.append(cx.expr(False))
                if not cx.take_op(","):
                    break
        cx.done()
        h = self.handlers.get(low)
        ip = self
        if h is not None:
            if h[1] == "function":
                raise ModelRefusal("%s: %s is a function, called as a "
                                   "command (spike S11: the engine throws)"
                                   % (scope.name, word))

            def call(env):
                ip.call_command(low, [a(env) for a in args])
            return call
        if low in self.bridge.public:
            bridge = self.bridge

            def lcb(env):
                ip.w.result = bridge.call(word, [a(env) for a in args])
            return lcb
        raise ModelRefusal("%s: an unknown command %s" % (scope.name, word))


_STMT = {"put": _Statements._s_put, "get": _Statements._s_get,
         "add": _Statements._s_add, "subtract": _Statements._s_add,
         "replace": _Statements._s_replace, "set": _Statements._s_set,
         "delete": _Statements._s_delete, "create": _Statements._s_create,
         "clone": _Statements._s_clone, "ungroup": _Statements._s_ungroup,
         "relayer": _Statements._s_relayer, "flip": _Statements._s_flip,
         "import": _Statements._s_import, "play": _Statements._s_play,
         "save": _Statements._s_save, "answer": _Statements._s_answer,
         "ask": _Statements._s_ask, "lock": _Statements._s_lock,
         "unlock": _Statements._s_lock, "send": _Statements._s_send,
         "dispatch": _Statements._s_dispatch,
         "return": _Statements._s_return, "exit": _Statements._s_exit,
         "pass": _Statements._s_pass, "next": _Statements._s_next,
         "break": _Statements._s_break, "throw": _Statements._s_throw,
         "local": _Statements._s_local}
# ==========================================================================
# objects, properties, files, dialogs and messages
# ==========================================================================

_LONG_ID_RX = re.compile(
    r'^(button|field|graphic|image|group|scrollbar|player) id (\d+)'
    r'((?: of group id \d+)*) of card id (\d+) of stack "([^"]*)"$')
_GROUP_IDS_RX = re.compile(r'group id (\d+)')
_SCREEN = (1920, 1080)

# What a property reads before a script sets it, by kind: the template
# defaults of the engine's constructors (MCObject: visible, showBorder,
# opaque; MCGroup: traversalOn, no border, not opaque; MCGraphic: not
# opaque/filled, no border, no traversal, lineSize 1; MCButton: menuHistory
# 1; DOCUMENTED, read 2026-10-08). A read of one is COUNTED
# (World.default_reads; --verbose prints them), so a wrong default shows.
_KIND_DEFAULTS = {
    "graphic": {"showborder": False, "opaque": False, "filled": False,
                "traversalon": False, "style": "rectangle"},
    "group": {"showborder": False, "opaque": False, "traversalon": True,
              "margins": 4},
    "button": {"style": "standard", "menuhistory": 1, "showname": True},
    "field": {"style": "rectangle", "locktext": False},
    "image": {"lockloc": False},
}


class _Objects(object):
    """PfInterp's world side: references, properties, files, dialogs,
    media and messages."""

    # -- references -----------------------------------------------------------
    def resolve(self, kind, by_id, key, within):
        """`kind [id] key [of within]` -> the Obj, or the engine's "no such
        object" (a Thrown). A key that is an integer is an INDEX (the
        engine reads a numeric name as a number), else a name."""
        w = self.w
        if kind == "stack":
            s = _s(key)
            if by_id or not (s == w.stack.name or (w.filename and
                                                     s == w.filename)):
                raise _NoSuchObject("stack %s" % LCS._shown(s))
            return w.stack
        if kind == "card":
            if by_id:
                ok = _int_of(key, "card id") == w.CARD_ID
            else:
                ok = _is_integer(key) and _int_of(key, "card") == 1
            if not ok:
                raise _NoSuchObject("card %s" % LCS._shown(_s(key)))
            return w.card
        if within is not None and within.kind in ("stack", "card"):
            within = None
        if by_id:
            o = w.find(kind, "id", _int_of(key, "id"), within)
        elif _is_integer(key):
            o = w.find(kind, "index", _int_of(key, kind), within)
        else:
            o = w.find(kind, "name", _s(key), within)
        if o is None:
            raise _NoSuchObject("%s %s%s" % (kind, "id " if by_id else "",
                                             LCS._shown(_s(key))))
        return o

    def ref_from_text(self, text):
        """An object reference held as TEXT (a long id, a name, `graphic
        "x"`), resolved as the engine resolves a variable used as an object
        (MCChunk::getobj with the variable's text). Long ids take a fast
        path, cached while the layer structure is unchanged."""
        w = self.w
        hit = self._ref_cache.get(text)
        if hit is not None and hit[1] == w.ver and not hit[0].gone:
            return hit[0]
        m = _LONG_ID_RX.match(text)
        if m:
            kind, oid, groups, cid, sname = m.groups()
            if int(cid) != w.CARD_ID or not (sname == w.stack.name or (
                    w.filename and sname == w.filename)):
                raise _NoSuchObject(text)
            o = w.by_id.get(int(oid))
            if o is None or o.gone or o.kind != kind:
                raise _NoSuchObject(text)
            # the group chain must be the object's own (the engine searches
            # the named group for the id)
            chain = [int(g) for g in _GROUP_IDS_RX.findall(groups)]
            own, p = [], o.owner
            while p is not None and p.kind == "group":
                own.append(p.id)
                p = p.owner
            if chain and chain[0] not in own:
                raise _NoSuchObject(text)
            self._ref_cache[text] = (o, w.ver)
            return o
        try:
            cx = _Cx(self, None, text)
            ref = cx.p_objref(typed_only=True)
            cx.done()
        except SyntaxError:
            raise _NoSuchObject(text)
        o = ref({})
        self._ref_cache[text] = (o, w.ver)
        return o

    def ordinal(self, kind, last, within):
        w = self.w
        if kind == "audioclip":
            pool = w.clips
        else:
            if within is not None and within.kind in ("stack", "card"):
                within = None
            pool = w.descendants(within) if within is not None else w.flat()
            if kind != "control":
                pool = [o for o in pool if o.kind == kind]
        if not pool:
            raise _NoSuchObject("the %s %s" % ("last" if last else "first",
                                               kind))
        return pool[-1] if last else pool[0]

    def count_of(self, kind, within):
        w = self.w
        if kind == "audioclip":
            return len(w.clips)
        if kind == "card":
            return 1
        if within is not None and within.kind in ("stack", "card"):
            within = None
        pool = w.descendants(within) if within is not None else w.flat()
        if kind == "control":
            return len(pool)
        return sum(1 for o in pool if o.kind == kind)

    def obj_text(self, o):
        if o.kind in ("field", "button"):
            return o.text
        raise ModelRefusal("the text of a %s used as a value" % o.kind)

    def set_text(self, o, s):
        if o.kind in ("field", "button"):
            o.text = s
            return
        raise ModelRefusal("put into a %s" % o.kind)

    # -- properties -------------------------------------------------------------
    def compile_prop_get(self, ref, prop, adj, key):
        if key is not None:
            raise ModelRefusal("a keyed object property (%s[...])" % prop)
        ip = self
        if prop.startswith("u") and prop not in _PROP_GET:
            def custom(env):
                return ref(env).custom.get(prop, "")
            return custom
        if prop == "id" and adj == "long":
            return lambda env: ip.w.long_id(ref(env))
        if prop == "name":
            return lambda env: ip.w.name_of(ref(env), adj)
        if adj and not (adj == "effective" and prop == "filename"):
            raise ModelRefusal("the %s %s is not modelled" % (adj, prop))
        g = _PROP_GET.get(prop)
        if g is None:
            raise ModelRefusal("reading the %s of an object is not modelled"
                               % prop)
        return lambda env: g(ip, ref(env))

    def prop_get(self, o, prop, adj, key):
        return self.compile_prop_get(lambda env: o, prop, adj, key)({})

    def compile_prop_set(self, ref, prop, val):
        ip = self
        if prop.startswith("u") and prop not in _PROP_SET:
            def custom(env):
                o = ref(env)
                v = val(env)
                if isinstance(v, dict):
                    raise ModelRefusal("an array into a custom property")
                o.custom[prop] = _s(v)
            return custom
        s = _PROP_SET.get(prop)
        if s is None:
            raise ModelRefusal("setting the %s of an object is not modelled"
                               % prop)

        def f(env):
            v = val(env)
            s(ip, ref(env), v)
        return f

    def _default(self, o, prop):
        """A property never set: the kind's template default, counted."""
        w = self.w
        d = _KIND_DEFAULTS.get(o.kind, {})
        if prop in d:
            v = d[prop]
        elif prop in _ANY:
            v = _ANY[prop]
        else:
            raise ModelRefusal("the %s of a %s is read before any set, and "
                               "its default is not modelled" % (prop, o.kind))
        k = (o.kind, prop)
        w.default_reads[k] = w.default_reads.get(k, 0) + 1
        return v

    def p(self, o, prop):
        v = o.props.get(prop, _MISSING)
        return self._default(o, prop) if v is _MISSING else v

    # -- global properties ----------------------------------------------------
    def compile_global_get(self, prop, key):
        ip, w = self, self.w
        if key is not None:
            if prop != "revlibrarymapping":
                raise ModelRefusal("the %s[...] is not modelled" % prop)
            return lambda env: w.lib_mapping.get(_s(key(env)), "")
        g = _GLOBAL_GET.get(prop)
        if g is None:
            raise ModelRefusal("the global property %s is not modelled" % prop)
        return lambda env: g(ip)

    def compile_global_set(self, prop, key, val, scope):
        ip, w = self, self.w
        if key is not None:
            if prop != "revlibrarymapping":
                raise ModelRefusal("set the %s[...] is not modelled" % prop)

            def lm(env):
                w.lib_mapping[_s(key(env))] = _s(val(env))
            return lm
        if prop == "itemdelimiter":
            def idl(env):
                v = _s(val(env))
                if len(v) != 1:
                    raise ModelRefusal("an itemDelimiter of %r" % v)
                LCS.ITEM_DELIMITER[0] = v
            return idl
        if prop == "wholematches":
            def wm(env):
                ip.whole_matches[0] = _bool("wholeMatches", val(env))
            return wm
        if prop == "defaultstack":
            def ds(env):
                v = _s(val(env))
                if v not in (w.stack.name, w.filename):
                    raise ModelRefusal("the defaultStack set to %r, another "
                                       "stack" % v)
            return ds
        if prop == "playloudness":
            def pl(env):
                w.loudness = max(0, min(100, _int1("playLoudness", val(env))))
            return pl
        raise ModelRefusal("set the %s (a global property) is not modelled"
                           % prop)

    # -- objects: create, clone, delete, layers ----------------------------------
    def create_object(self, kind, name, parent):
        w = self.w
        if parent.kind not in ("card", "group"):
            raise ModelRefusal("create in a %s" % parent.kind)
        o = w.create(kind, name, parent)
        if parent.kind == "group":
            w.child_changed(o)
        self.engine_message(o, "new" + kind.capitalize(), [])
        return w.long_id(o)

    def clone_object(self, src):
        w = self.w
        if src.kind not in CONTROLS or src.kind == "group":
            raise ModelRefusal("clone of a %s" % src.kind)
        o = w.clone(src)
        w.child_changed(o)
        self.engine_message(o, "new" + o.kind.capitalize(), [])
        return w.long_id(o)

    def delete_object(self, o):
        w = self.w
        if o.kind in ("stack", "card"):
            raise ModelRefusal("delete of a %s" % o.kind)
        if o.gone:
            raise _NoSuchObject("a deleted object")
        if o.kind != "audioclip":
            self.engine_message(o, "delete" + o.kind.capitalize(), [])
        owner = o.owner
        w.delete(o)
        if owner is not None and owner.kind == "group":
            w.group_changed(owner)

    def ungroup_object(self, g):
        self.w.ungroup(g)

    def relayer_object(self, o, g):
        w = self.w
        old = o.owner
        w.relayer_into_group(o, g)
        if old.kind == "group":
            w.group_changed(old)
        w.child_changed(o)

    def flip_image(self, o, horizontal):
        if o.kind != "image":
            raise Thrown("flip: object is not an image")
        self.w.image_flip(o, horizontal)

    # -- media ---------------------------------------------------------------
    def import_clip(self, path):
        w = self.w
        real = w.real_path(path)
        if real is None or not os.path.isfile(real):
            w.result = "can't open file"
            return
        with open(real, "rb") as fh:
            data = fh.read().decode("latin-1")
        o = Obj("audioclip", w.new_id(), w.stack)
        o.name = os.path.basename(path)
        o.data = data
        w.clips.append(o)
        w.by_id[o.id] = o
        w.ver += 1
        w.result = ""

    def play_clip(self, name, looping):
        w = self.w
        o = w.find("audioclip", "name", name)
        if o is None:
            raise Thrown("play: no such audioClip %s" % LCS._shown(name))
        w.played.append(o.name)
        w.result = ""

    def play_stop(self):
        self.w.result = ""

    # -- files -------------------------------------------------------------------
    def path_exists(self, path, what):
        real = self.w.real_path(path)
        if real is None:
            return False
        return os.path.isfile(real) if what == "file" else os.path.isdir(real)

    def url_read(self, spec):
        w = self.w
        low = spec.lower()
        if low.startswith("binfile:"):
            path, binary = spec[8:], True
        elif low.startswith("file:"):
            path, binary = spec[5:], False
        else:
            raise ModelRefusal("URL %s is not modelled" % LCS._shown(spec))
        real = w.real_path(path)
        w.reads.append(path)
        if real is None or not os.path.isfile(real):
            w.result = "can't open file"
            return ""
        with open(real, "rb") as fh:
            data = fh.read().decode("latin-1")
        w.result = ""
        if binary:
            return data
        # a `file:` read converts the platform's line endings to return
        return data.replace("\r\n", "\n").replace("\r", "\n")

    def url_write(self, spec, value):
        w = self.w
        if not spec.lower().startswith("binfile:"):
            raise ModelRefusal("a URL write to %s" % LCS._shown(spec))
        real = w.real_path(spec[8:])
        if real is None:
            raise ModelRefusal("a write outside the sandbox: %s" % spec)
        with open(real, "wb") as fh:
            fh.write(_s(value).encode("latin-1"))
        w.result = ""

    def delete_file(self, path):
        w = self.w
        real = w.real_path(path)
        if real is None or not os.path.isfile(real):
            w.result = "can't delete that file"
            return
        os.remove(real)
        w.result = ""

    def save_stack(self, path):
        w = self.w
        real = w.real_path(path)
        if real is None:
            raise ModelRefusal("a save outside the sandbox: %s" % path)
        w.filename = path
        w.saved = w.snapshot()
        w.ver += 1
        with open(real, "wb") as fh:
            fh.write(b"modelled stack snapshot\n")
        w.result = ""

    # -- dialogs ---------------------------------------------------------------
    def dialog(self, kind, prompt, buttons):
        """A modal dialog: the profile's next planned answer. Unplanned,
        out-of-order or under `lock messages` (engine note 5.15: the IDE's
        dialog needs its messages) is a failure the driver reports."""
        w = self.w
        w.dialog_log.append((kind, prompt.split("\n")[0][:70],
                             w.lock_msgs))
        if w.lock_msgs:
            w.problems.append("a %s dialog opened while messages were "
                              "locked: %r" % (kind, prompt[:70]))
        if not w.dialogs:
            raise DialogError("an unplanned %s dialog: %r" % (kind, prompt[:90]))
        want_kind, rx, answer = w.dialogs.pop(0)
        if want_kind != kind or not re.search(rx, prompt):
            raise DialogError("expected a %s dialog matching %r, got a %s "
                              "dialog: %r" % (want_kind, rx, kind, prompt[:90]))
        if kind == "answer" and buttons and answer not in buttons and \
                answer is not None:
            raise DialogError("the plan answers %r, which is not one of the "
                              "dialog's buttons %r" % (answer, buttons))
        if answer is None:
            w.result = "Cancel"
            return ""
        w.result = ""
        if kind == "answer" and not buttons:
            return "OK"
        return answer

    # -- messages ------------------------------------------------------------------
    def split_message(self, text, scope, env):
        """A message text -> (name, args): the first word names the
        message; the rest is comma-separated parameters, each EVALUATED as
        an expression where the send runs (MCEngineSendOrCall's parse), and
        one that does not parse is passed as its raw text."""
        m = re.match(r'\s*([A-Za-z_]\w*)\s*(.*)$', text, re.S)
        if not m:
            raise ModelRefusal("a message text %r" % text)
        name, rest = m.group(1), m.group(2).strip()
        args = []
        if rest:
            for part in rest.split(","):
                part = part.strip()
                try:
                    cx = _Cx(self, scope, part)
                    f = cx.expr(False)
                    cx.done()
                    args.append(f(env))
                except SyntaxError:
                    args.append(part)
        return name, args

    def send_now(self, target, name, args):
        w = self.w
        was = w.lock_msgs
        w.lock_msgs = False             # MCEngineExecSend unlocks messages
        try:
            self.deliver(target, name, args)
        finally:
            w.lock_msgs = was

    def send_later(self, target, name, args, ms):
        w = self.w
        w.seq += 1
        due = w.ms + max(0, int(ms))
        heapq.heappush(w.timers, (due, w.seq, target, name, args))

    def dispatch(self, target, name, args):
        w = self.w
        was = w.lock_msgs
        w.lock_msgs = False             # MCEngineExecDispatch: Bug 10478
        try:
            return self.deliver(target, name, args)
        finally:
            w.lock_msgs = was


_MISSING = object()


class DialogError(Exception):
    """A dialog the profile did not plan for: a failure, never a Thrown."""


# -- property getters and setters ------------------------------------------
#
# Each takes (ip, obj) or (ip, obj, value). Geometry is World's; the rest
# are stored values with the engine's checks where the game could trip one.

def _rect_text(r):
    return "%d,%d,%d,%d" % tuple(r)


def _g_rect(ip, o):
    if o.kind == "card":
        w, h = ip.w.card_size()
        return "0,0,%d,%d" % (w, h)
    return _rect_text(o.rect)


def _g_loc(ip, o):
    if o.kind == "card":
        w, h = ip.w.card_size()
        return "%d,%d" % (w >> 1, h >> 1)
    r = o.rect
    return "%d,%d" % (r[0] + ((r[2] - r[0]) >> 1), r[1] + ((r[3] - r[1]) >> 1))


def _g_width(ip, o):
    if o.kind == "card":
        return ip.w.card_size()[0]
    return o.rect[2] - o.rect[0]


def _g_height(ip, o):
    if o.kind == "card":
        return ip.w.card_size()[1]
    return o.rect[3] - o.rect[1]


def _need_control(o, what):
    if o.kind not in CONTROLS:
        raise ModelRefusal("set the %s of a %s" % (what, o.kind))


def _s_rect(ip, o, v):
    if o.kind == "stack":
        l, t, r, b = _ints("rect", v, 4)
        o.rect = [l, t, r, b]
        return
    _need_control(o, "rect")
    l, t, r, b = _ints("rect", v, 4)
    ip.w.set_rect(o, l, t, r, b)


def _s_loc(ip, o, v):
    x, y = _ints("loc", v, 2)
    r = o.rect
    w, h = r[2] - r[0], r[3] - r[1]
    l, t = x - (w >> 1), y - (h >> 1)
    if o.kind == "stack":
        o.rect = [l, t, l + w, t + h]
        return
    _need_control(o, "loc")
    ip.w.set_rect(o, l, t, l + w, t + h)


def _s_width(ip, o, v):
    n = _int1("width", v)
    r = list(o.rect)
    w = r[2] - r[0]
    if o.kind == "stack":
        o.rect = [r[0], r[1], r[0] + max(1, n), r[3]]
        return
    _need_control(o, "width")
    if not ip.p(o, "lockloc"):
        r[0] += (w - n) >> 1
    ip.w.set_rect(o, r[0], r[1], r[0] + max(n, 1), r[3])


def _s_height(ip, o, v):
    n = _int1("height", v)
    r = list(o.rect)
    h = r[3] - r[1]
    if o.kind == "stack":
        o.rect = [r[0], r[1], r[2], r[1] + max(1, n)]
        return
    _need_control(o, "height")
    if not ip.p(o, "lockloc"):
        r[1] += (h - n) >> 1
    ip.w.set_rect(o, r[0], r[1], r[2], r[1] + max(n, 1))


def _g_points(ip, o):
    if o.points is None:
        return ""
    return "\n".join("%d,%d" % p for p in o.points)


def _s_points(ip, o, v):
    if o.kind != "graphic":
        raise ModelRefusal("the points of a %s" % o.kind)
    o.points = _parse_points("points", v)
    if ip.p(o, "style") in POINT_STYLES and o.points:
        ip.w.points_rect(o)
        ip.w.child_changed(o)


def _s_style(ip, o, v):
    s = _s(v).lower()
    if o.kind == "graphic" and s not in ("rectangle", "oval", "polygon",
                                         "line", "curve", "roundrect",
                                         "regular"):
        raise ModelRefusal("a graphic style %r" % s)
    o.props["style"] = s
    if o.kind == "graphic" and s in POINT_STYLES and o.points:
        ip.w.points_rect(o)


def _g_visible(ip, o):
    return ip.p(o, "visible")


def _s_visible(ip, o, v):
    b = _bool("visible", v)
    if o.props.get("visible", True) != b:
        o.props["visible"] = b
        ip.w.child_changed(o)


def _s_blend(ip, o, v):
    o.props["blendlevel"] = max(0, min(100, _int1("blendLevel", v)))


def _bool_prop(name):
    def g(ip, o):
        return ip.p(o, name)

    def s(ip, o, v):
        o.props[name] = _bool(name, v)
    return g, s


def _plain_prop(name):
    def g(ip, o):
        return ip.p(o, name)

    def s(ip, o, v):
        if isinstance(v, dict):
            raise ModelRefusal("an array into the %s" % name)
        o.props[name] = v if type(v) in (int, float) else _s(v)
    return g, s


def _g_text(ip, o):
    if o.kind in ("field", "button"):
        return o.text
    if o.kind == "image":
        if o.data is None:
            raise ModelRefusal("the text of an image whose pixels were "
                               "replaced (the engine recompresses them)")
        return o.data
    raise ModelRefusal("the text of a %s" % o.kind)


def _s_text(ip, o, v):
    if o.kind in ("field", "button"):
        o.text = _s(v)
        return
    if o.kind == "image":
        ip.w.image_set_text(o, _s(v))
        ip.w.child_changed(o)
        return
    raise ModelRefusal("set the text of a %s" % o.kind)


def _g_imagedata(ip, o):
    if o.kind != "image":
        raise ModelRefusal("the imageData of a %s" % o.kind)
    return ip.w.image_render(o)[2]


def _s_imagedata(ip, o, v):
    if o.kind != "image":
        raise ModelRefusal("the imageData of a %s" % o.kind)
    ip.w.image_set_data(o, _s(v))


def _g_alphadata(ip, o):
    if o.kind != "image":
        raise ModelRefusal("the alphaData of a %s" % o.kind)
    return ip.w.image_render(o)[3]


def _s_alphadata(ip, o, v):
    if o.kind != "image":
        raise ModelRefusal("the alphaData of a %s" % o.kind)
    ip.w.image_set_alpha(o, _s(v))


def _s_name(ip, o, v):
    w = ip.w
    if o.kind == "stack":
        raise ModelRefusal("renaming the stack")
    o.name = _s(v)
    w.ver += 1
    if o.kind != "audioclip":
        ip.engine_message(o, "nameChanged", [])


def _g_id(ip, o):
    return o.id


def _g_number(ip, o):
    w = ip.w
    if o.kind == "audioclip":
        return w.clips.index(o) + 1
    if o.kind == "card":
        return 1
    pool = [c for c in w.flat() if c.kind == o.kind]
    return pool.index(o) + 1


def _g_layer(ip, o):
    return ip.w.layer(o)


def _s_layer(ip, o, v):
    _need_control(o, "layer")
    ip.w.set_layer(o, _int1("layer", v))


def _g_owner(ip, o):
    if o.owner is None:
        return ""
    return ip.w.name_of(o.owner, "")


def _g_icon(ip, o):
    return ip.p(o, "icon")


def _s_icon(ip, o, v):
    if o.kind != "button":
        raise ModelRefusal("the icon of a %s" % o.kind)
    s = _s(v)
    if s == "":
        o.props["icon"] = 0
        return
    if not _is_integer(s):
        raise ModelRefusal("an icon by name (%r)" % s)
    o.props["icon"] = _int_of(s, "icon")


def _s_menuhistory(ip, o, v):
    """MCButton::setmenuhistory (DOCUMENTED): nothing without menu text;
    an option menu clamps to its lines and, when the line CHANGED, sends
    menuPick with the new and the old item (engine note 5.14), which lock
    messages stops."""
    if o.kind != "button":
        raise ModelRefusal("the menuHistory of a %s" % o.kind)
    n = _int1("menuHistory", v)
    if o.text == "":
        return
    if ip.p(o, "menumode") != "option":
        raise ModelRefusal("the menuHistory of a %r menu" % ip.p(o, "menumode"))
    items = o.text.split("\n")
    old = ip.p(o, "menuhistory")
    new = max(min(n, len(items)), 1)
    o.props["menuhistory"] = new
    if new != old:
        ip.w.menu_picks.append((o.name, new, ip.w.lock_msgs))
        ip.engine_message(o, "menuPick", [items[new - 1], items[old - 1]])


def _s_hscroll(ip, o, v):
    if o.kind != "group":
        raise ModelRefusal("the hScroll of a %s" % o.kind)
    ip.w.scroll_group(o, "h", _int1("hScroll", v))


def _s_vscroll(ip, o, v):
    if o.kind != "group":
        raise ModelRefusal("the vScroll of a %s" % o.kind)
    ip.w.scroll_group(o, "v", _int1("vScroll", v))


def _s_margins(ip, o, v):
    n = _int1("margins", v)
    o.props["margins"] = n
    if o.kind == "group":
        ip.w.group_changed(o)


def _s_showborder(ip, o, v):
    o.props["showborder"] = _bool("showBorder", v)
    if o.kind == "group":
        ip.w.group_changed(o)


def _s_lockloc(ip, o, v):
    o.props["lockloc"] = _bool("lockLoc", v)


def _s_angle(ip, o, v):
    n = _int1("angle", v)
    if o.kind == "image" and n % 360:
        raise ModelRefusal("rotating an image (its rect follows the rotated "
                           "picture on the engine) is not modelled")
    o.props["angle"] = n


def _s_filled(ip, o, v):
    o.props["filled"] = o.props["opaque"] = _bool("filled", v)


def _g_title(ip, o):
    return ip.p(o, "title")


def _g_scriptonly(ip, o):
    if o.kind != "stack":
        raise ModelRefusal("the scriptOnly of a %s" % o.kind)
    return False


def _g_filename(ip, o):
    if o.kind != "stack":
        raise ModelRefusal("the filename of a %s" % o.kind)
    return ip.w.filename


_PROP_GET = {"rect": _g_rect, "loc": _g_loc, "location": _g_loc,
             "width": _g_width, "height": _g_height, "points": _g_points,
             "visible": _g_visible, "text": _g_text,
             "imagedata": _g_imagedata, "alphadata": _g_alphadata,
             "id": _g_id, "number": _g_number, "layer": _g_layer,
             "owner": _g_owner, "icon": _g_icon, "title": _g_title,
             "scriptonly": _g_scriptonly, "filename": _g_filename}
_PROP_SET = {"rect": _s_rect, "rectangle": _s_rect, "loc": _s_loc,
             "location": _s_loc, "width": _s_width, "height": _s_height,
             "points": _s_points, "style": _s_style, "visible": _s_visible,
             "blendlevel": _s_blend, "text": _s_text,
             "imagedata": _s_imagedata, "alphadata": _s_alphadata,
             "name": _s_name, "layer": _s_layer, "icon": _s_icon,
             "menuhistory": _s_menuhistory, "hscroll": _s_hscroll,
             "vscroll": _s_vscroll, "margins": _s_margins,
             "showborder": _s_showborder, "lockloc": _s_lockloc,
             "angle": _s_angle, "filled": _s_filled}
for _n in ("opaque", "traversalon", "locktext", "showname", "autohilite",
           "hscrollbar", "vscrollbar", "unboundedhscroll",
           "unboundedvscroll"):
    _PROP_GET[_n], _PROP_SET[_n] = _bool_prop(_n)
for _n in ("backgroundcolor", "foregroundcolor", "textcolor", "textsize",
           "textstyle", "textalign", "linesize", "label", "menumode",
           "layermode", "repeatcount", "currentframe", "title"):
    _g, _st = _plain_prop(_n)
    _PROP_GET.setdefault(_n, _g)
    _PROP_SET[_n] = _st
for _n in ("style", "blendlevel", "filled", "lockloc", "showborder",
           "menuhistory", "hscroll", "vscroll", "margins", "angle"):
    _PROP_GET[_n] = (lambda name: (lambda ip, o: ip.p(o, name)))(_n)
del _n, _g, _st


def _gg_keysdown(ip):
    return ",".join(str(k) for k in ip.w.keys_down)


_GLOBAL_GET = {
    "result": lambda ip: ip.w.result,
    "itemdelimiter": lambda ip: LCS.ITEM_DELIMITER[0],
    "linedelimiter": lambda ip: LCS.LINE_DELIMITER[0],
    "milliseconds": lambda ip: ip.w.ms,
    "millisecs": lambda ip: ip.w.ms,
    "mouseh": lambda ip: ip.w.mouse[0],
    "mousev": lambda ip: ip.w.mouse[1],
    "screenloc": lambda ip: "%d,%d" % (_SCREEN[0] >> 1, _SCREEN[1] >> 1),
    "defaultstack": lambda ip: ip.w.stack.name,
    "shiftkey": lambda ip: "down" if ip.w.shift else "up",
    "platform": lambda ip: "Linux",
    "keysdown": _gg_keysdown,
    "wholematches": lambda ip: ip.whole_matches[0],
    "playloudness": lambda ip: ip.w.loudness,
    "casesensitive": lambda ip: LCS.CASE_SENSITIVE[0],
}


# -- built-in functions ------------------------------------------------------

def _args1(name, args):
    if len(args) != 1:
        raise ModelRefusal("%s() with %d arguments" % (name, len(args)))
    return args[0]


def _f_round(ip, args):
    if len(args) == 2:
        x = _num(args[0], "round")
        p = _int_of(args[1], "round")
        k = 10.0 ** p
        y = x * k
        r = math.ceil(y - 0.5) if y < 0 else math.floor(y + 0.5)
        return _fix(r / k, "round")
    x = _num(_args1("round", args), "round")
    return _round_half_away(x)


def _f_abs(ip, args):
    x = _num(_args1("abs", args), "abs")
    return abs(x)


def _f_trunc(ip, args):
    x = _num(_args1("trunc", args), "trunc")
    return int(x) if type(x) is float else x


def _f_sqrt(ip, args):
    x = _num(_args1("sqrt", args), "sqrt")
    if x < 0:
        raise Thrown("sqrt: domain error")
    return _fix(math.sqrt(x), "sqrt")


def _f_sin(ip, args):
    return _fix(math.sin(_num(_args1("sin", args), "sin")), "sin")


def _f_cos(ip, args):
    return _fix(math.cos(_num(_args1("cos", args), "cos")), "cos")


def _minmax(name, args, pick):
    vals = []
    if len(args) == 1 and "," in _s(args[0]):
        args = _s(args[0]).split(",")
    for a in args:
        vals.append(_num(a, name))
    if not vals:
        return ""
    return pick(vals)


def _f_max(ip, args):
    return _minmax("max", args, max)


def _f_min(ip, args):
    return _minmax("min", args, min)


def _f_random(ip, args):
    n = _num(_args1("random", args), "random")
    n = math.floor(n + 0.5)
    if n < 1:
        raise Thrown("random: the range is less than 1")
    return int(math.floor(n * ip.rng.random())) + 1


def _f_numtobyte(ip, args):
    return chr(_int_of(_round_half_away(_num(_args1("numToByte", args),
                                             "numToByte")), "numToByte") & 255)


def _f_numtochar(ip, args):
    n = _int_of(_args1("numToChar", args), "numToChar")
    if not 0 <= n < 256:
        raise ModelRefusal("numToChar(%d) beyond one byte" % n)
    return chr(n)


def _f_chartonum(ip, args):
    s = _s(_args1("charToNum", args))
    if not s:
        return ""
    return ord(s[0])


def _f_toupper(ip, args):
    s = _s(_args1("toUpper", args))
    if not s.isascii():
        raise ModelRefusal("toUpper beyond ASCII")
    return s.upper()


def _f_tolower(ip, args):
    s = _s(_args1("toLower", args))
    if not s.isascii():
        raise ModelRefusal("toLower beyond ASCII")
    return s.lower()


_FMT_RX = re.compile(r'%([-0 +#]*)(\d*)(?:\.(\d+))?([dsfx%])')


def _f_format(ip, args):
    if not args:
        raise ModelRefusal("format() with no arguments")
    fmt = _s(args[0])
    rest = list(args[1:])
    out, pos = [], 0
    for m in _FMT_RX.finditer(fmt):
        out.append(fmt[pos:m.start()])
        pos = m.end()
        flags, width, prec, conv = m.groups()
        if conv == "%":
            out.append("%")
            continue
        if not rest:
            raise ModelRefusal("format(%r) with too few arguments" % fmt)
        v = rest.pop(0)
        spec = "%" + flags + width + ("." + prec if prec else "") + conv
        if conv in ("d", "x"):
            out.append(spec % int(_num(v, "format")))
        elif conv == "f":
            out.append(spec % float(_num(v, "format")))
        else:
            out.append(spec % _s(v))
    out.append(fmt[pos:])
    if "\\" in fmt:
        raise ModelRefusal("format() escapes are not modelled")
    return "".join(out)


def _f_offset(ip, args):
    if len(args) not in (2, 3):
        raise ModelRefusal("offset() with %d arguments" % len(args))
    needle, hay = _fold(_s(args[0])), _fold(_s(args[1]))
    skip = _int_of(args[2], "offset") if len(args) == 3 else 0
    if skip < 0:
        raise ModelRefusal("offset() with a negative skip")
    k = hay.find(needle, skip) if needle else -1
    return 0 if k < 0 else k - skip + 1


def _f_lineoffset(ip, args):
    if len(args) != 2:
        raise ModelRefusal("lineOffset() with %d arguments" % len(args))
    needle, hay = _fold(_s(args[0])), _fold(_s(args[1]))
    if "\n" in needle or not needle:
        raise ModelRefusal("lineOffset() of a multi-line or empty needle")
    for n, ln in enumerate(LCS._split_chunks(hay, "\n"), 1):
        if (ln == needle) if ip.whole_matches[0] else (needle in ln):
            return n
    return 0


def _f_base64decode(ip, args):
    """base64Decode: a character outside the alphabet (a line break) is
    skipped, and the padding is the decoder's to supply."""
    s = re.sub(r'[^A-Za-z0-9+/]', '', _s(_args1("base64Decode", args)))
    try:
        return base64.b64decode(s + "=" * (-len(s) % 4)).decode("latin-1")
    except (ValueError, binascii.Error):
        raise ModelRefusal("base64Decode of a malformed text")


def _f_specialfolderpath(ip, args):
    s = _s(_args1("specialFolderPath", args)).lower()
    if s != "temporary":
        raise ModelRefusal("specialFolderPath(%r)" % s)
    return ip.w.temp_dir


_BUILTINS = {"round": _f_round, "abs": _f_abs, "trunc": _f_trunc,
             "sqrt": _f_sqrt, "sin": _f_sin, "cos": _f_cos, "max": _f_max,
             "min": _f_min, "random": _f_random, "numtobyte": _f_numtobyte,
             "numtochar": _f_numtochar, "chartonum": _f_chartonum,
             "toupper": _f_toupper, "tolower": _f_tolower,
             "format": _f_format, "offset": _f_offset,
             "lineoffset": _f_lineoffset, "base64decode": _f_base64decode,
             "specialfolderpath": _f_specialfolderpath}
# the `the <function> of <factor>` forms
_FN1 = {k: _BUILTINS[k] for k in ("round", "abs", "trunc", "sqrt", "sin",
                                  "cos")}
# ==========================================================================
# statements and handlers
# ==========================================================================

class _ExitHandler(Exception):
    """`exit <handler>` and `pass <message>`: leave the handler, `the
    result` as it stands. Not a Thrown."""

    def __init__(self, passed=False):
        Exception.__init__(self)
        self.passed = passed


class _Break(Exception):
    """`break`: leave the switch (ES_EXIT_SWITCH)."""


_Return, _ExitRepeat, _NextRepeat = LCS._Return, LCS._Exit, LCS._Next

_HEADER_RX = re.compile(r'(?i)^(private\s+)?(on|command|function)\s+(\w+)\s*(.*)$')
_LOCAL_RX = re.compile(r'(?i)^local\s+(.+)$')
_CONST_RX = re.compile(r'(?i)^constant\s+(\w+)\s*=\s*(.+)$')
# the names a handler's statements create by assigning them (an undeclared
# name becomes a handler local where it is first assigned)
_IMPLICIT_RX = (
    re.compile(r'(?i)^put\s.*?\b(?:into|after|before)\s+(?:(?:item|line|char|'
               r'character|byte|word)s?\s+\S+(?:\s+to\s+\S+)?\s+of\s+)?'
               r'([A-Za-z_]\w*)\s*(?:\[.*)?$'),
    re.compile(r'(?i)^add\s.+\sto\s+([A-Za-z_]\w*)\s*(?:\[.*)?$'),
    re.compile(r'(?i)^subtract\s.+\sfrom\s+([A-Za-z_]\w*)\s*(?:\[.*)?$'),
    re.compile(r'(?i)^(?:multiply|divide)\s+([A-Za-z_]\w*)\s*(?:\[.*?\])*\s+by\s'),
    re.compile(r'(?i)^repeat\s+with\s+([A-Za-z_]\w*)\s*='),
    re.compile(r'(?i)^repeat\s+for\s+each\s+\w+\s+([A-Za-z_]\w*)\s+in\s'),
    re.compile(r'(?i)^catch\s+([A-Za-z_]\w*)\s*$'),
)


class PfInterp(_Statements, _Objects):
    """The stack script on the modelled engine: its handlers compiled to
    closures on first call, its script locals in `globals`, the message
    path, the world's objects and properties, files, dialogs and timers."""

    def __init__(self, text, world, bridge):
        self.w = world
        self.bridge = bridge
        self.consts = {}
        self.globals = {}
        self.handlers = {}
        self.compiled = {}
        self.literals = {}
        self.calls = {}
        self.catches = []
        self.frames = []
        self.target = None
        self.stmts = 0
        self.limit = 1 << 62
        self.whole_matches = [False]
        self.event = ""
        self.hooks = {}
        self._ref_cache = {}
        self.rng = random.Random(20261008)
        self._parse(text)

    # -- the script ------------------------------------------------------------
    def _parse(self, text):
        """Script-level declarations and handlers. A script local declared
        with a value, a duplicate handler or a handler that names a script
        local or constant declared BELOW it (which the engine resolves by
        lexical position, engine note 1.2, where this model resolves file-
        wide) is refused: the model and the engine agree only without them."""
        lines = text.split("\n")
        declared_at = {}
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            m = _HEADER_RX.match(line)
            if m:
                private, how, name, params = m.groups()
                low = name.lower()
                if low in self.handlers:
                    raise ModelRefusal("handler %s is defined twice" % name)
                j = i + 1
                end_rx = re.compile(r'(?i)^end\s+%s\s*$' % re.escape(name))
                while j < len(lines) and not end_rx.match(lines[j].strip()):
                    j += 1
                if j >= len(lines):
                    raise ModelRefusal("handler %s has no `end %s`"
                                       % (name, name))
                plist = [p.strip().lower() for p in params.split(",")
                         if p.strip()]
                for p in plist:
                    if not re.match(r'^[a-z_]\w*$', p):
                        raise ModelRefusal("handler %s: parameter %r"
                                           % (name, p))
                self.handlers[low] = (name, how.lower(), bool(private), plist,
                                      [s.strip() for s in lines[i + 1:j]], i)
                i = j + 1
                continue
            m = _LOCAL_RX.match(line)
            if m:
                for v in m.group(1).split(","):
                    v = v.strip()
                    if not re.match(r'^[A-Za-z_]\w*$', v):
                        raise ModelRefusal("a script local with a value or an "
                                           "odd name: %r" % line)
                    self.globals.setdefault(v.lower(), "")
                    declared_at.setdefault(v.lower(), i)
                i += 1
                continue
            m = _CONST_RX.match(line)
            if m:
                name, lit = m.group(1).lower(), m.group(2).strip()
                cx = _Cx(self, None, lit)
                val = cx.p_factor()({})
                cx.done()
                self.consts[name] = val
                declared_at.setdefault(name, i)
                i += 1
                continue
            if line:
                raise ModelRefusal("an unmodelled script-level line: %r" % line)
            i += 1
        # the lexical precondition (engine note 1.2)
        for low, (name, _how, _priv, plist, body, at) in self.handlers.items():
            own = set(plist)
            for s in body:
                m = _LOCAL_RX.match(s)
                if m:
                    own.update(v.strip().lower() for v in m.group(1).split(","))
            for s in body:
                try:
                    toks = tokens(s)
                except SyntaxError:
                    continue
                for tok in toks:
                    if tok[0] == "w" and tok[2] in declared_at and \
                            declared_at[tok[2]] > at and tok[2] not in own:
                        raise ModelRefusal(
                            "handler %s names %s, which is declared below it: "
                            "the engine resolves a script local or constant "
                            "by lexical position (engine note 1.2), this model "
                            "file-wide" % (name, tok[1]))

    def _scope(self, low):
        name, how, _priv, plist, body, _at = self.handlers[low]
        names = set(plist)
        names.add("it")
        for s in body:
            m = _LOCAL_RX.match(s)
            if m:
                for v in m.group(1).split(","):
                    v = v.strip()
                    if not re.match(r'^[A-Za-z_]\w*$', v):
                        raise ModelRefusal("%s: a local with a value: %r"
                                           % (name, s))
                    names.add(v.lower())
                continue
            for rx in _IMPLICIT_RX:
                m = rx.match(s)
                if m:
                    v = m.group(1).lower()
                    if v not in self.globals and v not in _CONSTS \
                            and v not in self.consts and v not in KIND \
                            and v not in ("url", "field", "the"):
                        names.add(v)
                    break
        return _Scope(name, frozenset(names))

    def compiled_handler(self, low):
        hit = self.compiled.get(low)
        if hit is None:
            name, how, _priv, plist, body, _at = self.handlers[low]
            scope = self._scope(low)
            block, i = self._block(body, 0, scope, ())
            if i != len(body):
                raise ModelRefusal("%s: stray %r" % (name, body[i]))
            hit = self.compiled[low] = (scope, plist, block)
        return hit

    # -- calls -----------------------------------------------------------------
    def run_block(self, block, env):
        self.stmts += len(block) + 1
        if self.stmts > self.limit:
            raise Budget("the statement budget ran out in %s"
                         % " > ".join(self.frames[-6:]))
        for f in block:
            f(env)

    def call(self, low, args):
        """Run handler `low` with args; answers what it returned. `the
        result` is cleared as a handler starts (MCHandler::exec) and set by
        its `return`; a function's value is what it returns. The
        itemDelimiter and the caseSensitive are LOCAL to a handler (engine
        note 2.3, OBSERVED for the itemDelimiter on Windows and Linux): each
        call starts at the defaults and its own sets end with it."""
        scope, plist, block = self.compiled_handler(low)
        self.calls[low] = self.calls.get(low, 0) + 1
        env = dict.fromkeys(scope.env_names, "")
        for k, p in enumerate(plist):
            if k < len(args):
                env[p] = LCS._copy(args[k])
        w = self.w
        w.result = ""
        was = (LCS.ITEM_DELIMITER[0], self.whole_matches[0],
               LCS.CASE_SENSITIVE[0])
        LCS.ITEM_DELIMITER[0] = ","
        self.whole_matches[0] = False
        LCS.CASE_SENSITIVE[0] = False
        self.frames.append(scope.name)
        if len(self.frames) > 400:
            raise Budget("the handler stack is %d deep: %s" % (
                len(self.frames), " > ".join(self.frames[-8:])))
        hook = self.hooks.get(low)
        if hook is not None:
            hook(args)
        try:
            self.run_block(block, env)
            # no `return`: a function's value is the result as the handler
            # left it (MCFuncref::eval_ctxt reads MCresult)
            value = w.result
        except _Return as r:
            value = r.value
            w.result = value
        except (_ExitHandler, _ExitRepeat, _NextRepeat, _Break):
            raise
        except Exception as e:
            # where it happened, for the report: the stack unwinds below
            if getattr(e, "pf_frames", None) is None:
                e.pf_frames = list(self.frames)
            raise
        finally:
            self.frames.pop()
            (LCS.ITEM_DELIMITER[0], self.whole_matches[0],
             LCS.CASE_SENSITIVE[0]) = was
        return value

    def call_command(self, low, args):
        try:
            self.call(low, args)
        except _ExitHandler:
            pass

    def compile_call(self, word, args):
        """`word(args)`: a built-in function, else a function handler of the
        script, else box2dxt.lcb's (a library in the message path)."""
        low = word.lower()
        f = _BUILTINS.get(low)
        ip = self
        if f is not None:
            if len(args) == 1:
                a0 = args[0]
                return lambda env: f(ip, [a0(env)])
            return lambda env: f(ip, [a(env) for a in args])
        h = self.handlers.get(low)
        if h is not None:
            if h[1] != "function":
                raise ModelRefusal("%s() is called as a function but is a %s"
                                   % (word, h[1]))

            def fn(env):
                vals = [a(env) for a in args]
                try:
                    return ip.call(low, vals)
                except _ExitHandler:
                    return ip.w.result
            return fn
        if low in self.bridge.public:
            bridge = self.bridge

            def lcb(env):
                v = bridge.call(word, [a(env) for a in args])
                ip.w.result = v
                return v
            return lcb
        raise ModelRefusal("an unknown function %s()" % word)

    # -- messages --------------------------------------------------------------
    def deliver(self, target, message, args):
        """A message to an object: every control's and the card's script is
        empty, so it travels to the stack script, which handles it with an
        `on` or `command` handler (never a private one). Answers handled,
        unhandled or passed, as `dispatch` sets `it`."""
        low = message.lower()
        h = self.handlers.get(low)
        if h is None or h[1] == "function" or h[2]:
            return "unhandled"
        was = self.target
        self.target = target
        try:
            self.call(low, args)
        except _ExitHandler as e:
            return "passed" if e.passed else "handled"
        finally:
            self.target = was
        return "handled"

    def engine_message(self, target, message, args):
        """A message the ENGINE sends because of something a script did:
        an option menu's menuPick (engine note 5.14), and the IDE-facing
        create / rename / delete messages (engine note 5.15). None is sent
        while messages are locked (MCObject::message)."""
        w = self.w
        if w.lock_msgs:
            return
        w.note_engine_message(message,
                              _s(self.globals.get("gbuilding", "")) == "true",
                              self.frames)
        self.deliver(target, message, args)

    def target_obj(self):
        if self.target is None:
            raise Thrown("Chunk: there is no target")
        if self.target.gone:
            raise _NoSuchObject("the target (deleted)")
        return self.target

    # -- blocks ------------------------------------------------------------------
    @staticmethod
    def _first(line):
        k = 0
        n = len(line)
        while k < n and (line[k].isalnum() or line[k] == "_"):
            k += 1
        return line[:k].lower()

    def _block(self, lines, i, scope, enders):
        out = []
        n = len(lines)
        while i < n:
            line = lines[i]
            low = line.lower()
            first = self._first(line)
            if first in ("else", "end", "case", "default", "catch",
                         "finally"):
                key = low if first != "catch" else "catch"
                if first == "end":
                    key = "end " + low.split()[1] if len(low.split()) > 1 \
                        else low
                if key in enders or (first in ("case", "default") and
                                     "case" in enders):
                    return tuple(out), i
                raise SyntaxError("%s: unexpected %r" % (scope.name, line))
            try:
                if first == "if":
                    f, i = self._c_if(lines, i, scope)
                elif first == "repeat":
                    f, i = self._c_repeat(lines, i, scope)
                elif first == "switch":
                    f, i = self._c_switch(lines, i, scope)
                elif low == "try":
                    f, i = self._c_try(lines, i, scope)
                else:
                    f = self._stmt(line, scope)
                    i += 1
            except SyntaxError as exc:
                raise ModelRefusal("%s: %s" % (scope.name, exc))
            if f is not None:
                out.append(f)
        if enders:
            raise ModelRefusal("%s: a block with no %s" % (scope.name,
                                                           enders[0]))
        return tuple(out), i

    def _cond(self, text, scope):
        cx = _Cx(self, scope, text)
        f = cx.expr(True)
        cx.done()
        return f

    def _c_if(self, lines, i, scope):
        m = re.match(r'(?i)^if\s+(.*)\s+then$', lines[i])
        if not m:
            raise SyntaxError("an if with no then: %r" % lines[i])
        cond = self._cond(m.group(1), scope)
        then, i = self._block(lines, i + 1, scope, ("else", "end if"))
        other = ()
        if lines[i].lower() == "else":
            other, i = self._block(lines, i + 1, scope, ("end if",))
        run = self.run_block

        def f(env):
            if _truth(cond(env)):
                if then:
                    run(then, env)
            elif other:
                run(other, env)
        return f, i + 1

    def _c_try(self, lines, i, scope):
        """try / catch <var> / end try, or a bare try / end try, which
        swallows the error (MCKeywordsExecTry: no catch statements to run;
        the parse allows it). Every caught error is recorded with where it
        was caught: the driver tells the designed ones from the rest."""
        body, i = self._block(lines, i + 1, scope, ("catch", "end try",
                                                    "finally"))
        handler, store = (), None
        if lines[i].lower().startswith("catch"):
            m = re.match(r'(?i)^catch\s+([A-Za-z_]\w*)$', lines[i])
            if not m:
                raise SyntaxError("a catch without a variable: %r" % lines[i])
            store = self._store_plain(m.group(1).lower(), scope)
            handler, i = self._block(lines, i + 1, scope,
                                     ("end try", "finally"))
        if lines[i].lower() != "end try":
            raise ModelRefusal("%s: try ... finally is not modelled"
                               % scope.name)
        run, ip, where = self.run_block, self, scope.name

        def f(env):
            try:
                run(body, env)
            except Thrown as t:
                # where it was THROWN (call() stamps the frames as it leaves
                # the innermost handler), not where it was caught
                origin = getattr(t, "pf_frames", None) or ip.frames
                ip.catches.append((ip.event, where, list(origin[-5:]), t.msg))
                if store is not None:
                    store(env, t.msg)
                if handler:
                    run(handler, env)
        return f, i + 1

    def _c_switch(self, lines, i, scope):
        m = re.match(r'(?i)^switch\b\s*(.*)$', lines[i])
        subject = self._cond(m.group(1), scope) if m.group(1).strip() else None
        i += 1
        arms = []                         # (case closures or None, block)
        while True:
            line = lines[i]
            low = line.lower()
            if re.match(r'^end\s+switch$', low):
                break
            if low.startswith("case "):
                conds = [self._cond(line[5:].strip(), scope)]
                i += 1
                # several `case` lines share the block that follows them
                while lines[i].lower().startswith("case "):
                    conds.append(self._cond(lines[i][5:].strip(), scope))
                    i += 1
                block, i = self._block(lines, i, scope, ("case", "default",
                                                         "end switch"))
                arms.append((conds, block))
                continue
            if low == "default":
                block, i = self._block(lines, i + 1, scope, ("case",
                                                             "end switch"))
                arms.append((None, block))
                continue
            raise SyntaxError("a switch line %r" % line)
        run = self.run_block

        def f(env):
            # MCKeywordsExecSwitch: the subject and each case as TEXT,
            # compared caseless (no subject: each case against "true");
            # the first match, else the default, runs to a break
            s = _fold(_s(subject(env))) if subject is not None else "true"
            start = None
            for k, (conds, _b) in enumerate(arms):
                if conds is None:
                    continue
                for c in conds:
                    if _fold(_s(c(env))) == s:
                        start = k
                        break
                if start is not None:
                    break
            if start is None:
                for k, (conds, _b) in enumerate(arms):
                    if conds is None:
                        start = k
                        break
            if start is None:
                return
            try:
                for _c, block in arms[start:]:
                    if block:
                        run(block, env)
            except _Break:
                pass
        return f, i + 1

    def _c_repeat(self, lines, i, scope):
        line = lines[i]
        body, j = self._block(lines, i + 1, scope, ("end repeat",))
        run = self.run_block
        m = re.match(r'(?i)^repeat\s+with\s+(\w+)\s*=\s*(.+?)'
                     r'\s+(down\s+to|to)\s+(.+)$', line)
        if m:
            var = m.group(1).lower()
            start = self._cond(m.group(2), scope)
            step = -1 if m.group(3).lower() != "to" else 1
            end = self._cond(m.group(4), scope)
            store = self._store_plain(var, scope)
            read = self._read_plain(var, scope)

            def f(env):
                # MCKeywordsExecRepeatWith: the variable is set one step
                # BEFORE the start, the end is read once after that, and
                # each pass reads the variable back (a body may move it);
                # "down to" is a step of -1 and stops at or below the end
                cur = _num(start(env), "repeat") - step
                store(env, _fix(cur, "repeat"))
                stop = _num(end(env), "repeat")
                while True:
                    cur = _num(read(env), "repeat")
                    if (cur <= stop) if step < 0 else (cur >= stop):
                        break
                    store(env, _fix(cur + step, "repeat"))
                    try:
                        run(body, env)
                    except _NextRepeat:
                        pass
                    except _ExitRepeat:
                        break
            return f, j + 1
        m = re.match(r'(?i)^repeat\s+while\s+(.+)$', line)
        if m:
            cond = self._cond(m.group(1), scope)

            def f(env):
                while _truth(cond(env)):
                    try:
                        run(body, env)
                    except _NextRepeat:
                        pass
                    except _ExitRepeat:
                        break
            return f, j + 1
        m = re.match(r'(?i)^repeat\s+for\s+each\s+(item|line|key|word|char|'
                     r'character|byte)\s+(\w+)\s+in\s+(.+)$', line)
        if m:
            unit = m.group(1).lower()
            unit = "char" if unit == "character" else unit
            store = self._store_plain(m.group(2).lower(), scope)
            src = self._cond(m.group(3), scope)

            def f(env):
                v = src(env)
                if unit == "key":
                    seq = list(dict.keys(v)) if isinstance(v, dict) else []
                else:
                    seq = list(_chunks(_s(v), unit))
                for x in seq:
                    store(env, x)
                    try:
                        run(body, env)
                    except _NextRepeat:
                        pass
                    except _ExitRepeat:
                        break
            return f, j + 1
        raise ModelRefusal("%s: an unmodelled repeat form %r"
                           % (scope.name, line))

    # -- plain variables ---------------------------------------------------------
    def _store_plain(self, low, scope):
        if low in scope.env_names:
            def st(env, v):
                env[low] = v
            return st
        if low in self.globals:
            g = self.globals

            def st(env, v):
                g[low] = v
            return st
        raise ModelRefusal("%s: %s is not a variable here" % (scope.name, low))

    def _read_plain(self, low, scope):
        if low in scope.env_names:
            return lambda env: env[low]
        if low in self.globals:
            g = self.globals
            return lambda env: g[low]
        raise ModelRefusal("%s: %s is not a variable here" % (scope.name, low))
# ==========================================================================
# the run: events, the clock, and a tour of every level
# ==========================================================================

FRAME_MS = 16
K_SPACE = 32
# Statement budgets, each about ten times the most the shipped game was
# measured to need on 2026-10-08 (the import 1,065,126; a level build
# 83,630; a frame 7,490), so a build or an import that never ends fails in
# seconds, and names where it was, instead of hanging the gate the way the
# level-4 loop hung the IDE.
BUDGET_EVENT = 600000          # one frame, one key, one timer
BUDGET_BUILD = 1000000         # one level's build (pfStartGame)
BUDGET_IMPORT = 10000000       # openCard: the first-run import
LEVELS = 7


class Failure(Exception):
    """The game did not do what a player would see it do: reported with
    the level and what the hero was doing, never a Thrown."""


def _xy(text):
    """"x,y" -> two floats (b2kPosition's answer)."""
    parts = _s(text).split(",")
    if len(parts) != 2:
        raise Failure("a position %r" % text)
    return float(parts[0]), float(parts[1])


def _true(v):
    return _s(v).lower() == "true"


class Run(object):
    """One profile's session: the world, the interpreter on it, and the
    engine's event loop around them (top-level events, timers, idle)."""

    def __init__(self, name, ip, verbose):
        self.name = name
        self.ip = ip
        self.w = ip.w
        self.verbose = verbose
        self.builds = []               # (gLevel, gBuilding) per pfStartGame
        self.event_stmts = {}          # message -> most statements it ran
        ip.hooks["pfstartgame"] = self._on_build

    def say(self, msg):
        if self.verbose:
            print("    %s" % msg)

    def _on_build(self, args):
        ip = self.ip
        self.builds.append((_s(ip.globals.get("glevel", "")),
                            _s(ip.globals.get("gbuilding", ""))))
        ip.limit = ip.stmts + BUDGET_BUILD

    # -- the engine's event loop ------------------------------------------------
    def event(self, target, message, args, budget=BUDGET_EVENT):
        """A top-level engine event, then idle: the engine resets the
        screen lock and lockMessages between events."""
        ip, w = self.ip, self.w
        ip.stmts = 0
        ip.limit = budget
        ip.event = message
        try:
            ip.deliver(target, message, args)
        except Budget as exc:
            if _true(ip.globals.get("gbuilding", "")):
                raise Failure("the L%s build never finished: %s"
                              % (self.level(), exc))
            raise Failure("%s never finished: %s" % (message, exc))
        finally:
            n = ip.stmts
            if n > self.event_stmts.get(message, 0):
                self.event_stmts[message] = n
            w.lock_screen = 0
            w.lock_msgs = False
        return n

    def poke(self, handler, args):
        """The driver's own call into the stack script between two events
        (a teleport, a position read), as the message box would make it."""
        ip, w = self.ip, self.w
        ip.stmts = 0
        ip.limit = BUDGET_EVENT
        ip.event = "(driver) " + handler
        try:
            return ip.call(handler.lower(), args)
        except _ExitHandler:
            return w.result
        finally:
            w.lock_screen = 0
            w.lock_msgs = False

    def pump_to(self, until_ms):
        """Advance the clock to until_ms, delivering each timer as it falls
        due (a handler's own sends land in the same queue)."""
        w = self.w
        while w.timers and w.timers[0][0] <= until_ms:
            due, _seq, target, name, args = heapq.heappop(w.timers)
            if due > w.ms:
                w.ms = due
            self.event(target, name, args)
        if until_ms > w.ms:
            w.ms = until_ms

    def frames(self, n):
        self.pump_to(self.w.ms + n * FRAME_MS)

    def key(self, code):
        """A key press as the engine delivers it (rawKeyDown to the card);
        play reads the held set instead (the Kit polls the keysDown)."""
        self.event(self.w.card, "rawKeyDown", [code])

    def until(self, pred, limit, what):
        """Frames until pred() holds; a Failure naming `what` when it never
        does within `limit` frames."""
        for k in range(limit):
            self.frames(1)
            if pred():
                return k + 1
        raise Failure("L%s: %s did not happen within %d frames (%s)"
                      % (self.level(), what, limit, self.hero_note()))

    # -- the game, as the driver reads it ---------------------------------------
    def g(self, name):
        return self.ip.globals.get(name.lower(), "")

    def gi(self, name, i):
        """Element i of the global array `name` ("" when absent)."""
        v = self.g(name)
        if not isinstance(v, dict):
            return ""
        return LCS._arr_get(v, str(i)) if LCS._arr_has(v, str(i)) else ""

    def gn(self, name):
        v = self.g(name)
        return int(_num(v, name)) if _s(v) else 0

    def level(self):
        return _s(self.g("gLevel"))

    def hero_note(self):
        """Where the hero is and what it is doing, for a failure."""
        hero = self.g("gHero")
        if not hero:
            return "no hero"
        out = ["the hero at %s" % _s(self.poke("b2kPosition", [hero]))]
        if _s(self.g("gHeroState")):
            out.append(_s(self.g("gHeroState")))
        if _true(self.g("gHurtLock")):
            out.append("respawning")
        out.append("velocity %s" % _s(self.poke("b2kVelocity", [hero])))
        return ", ".join(out)

    def flagged(self, prop):
        """Every live control whose custom property `prop` is true, oldest
        first."""
        return sorted((o for o in self.w.flat()
                       if not o.gone and _true(o.custom.get(prop, ""))),
                      key=lambda o: o.id)

    def pos(self, o):
        return _xy(self.poke("b2kPosition", [self.w.long_id(o)]))

    def visible(self, kind, name):
        o = self.w.find(kind, "name", name)
        return o is not None and not o.gone and \
            _s(o.props.get("visible", True)).lower() != "false"

    # -- moving the hero ----------------------------------------------------------
    def teleport(self, x, y):
        """The hero to world px (x, y) at rest, through the Kit's own
        b2kMoveTo (b2kFrame's edge clamp moves him the same way)."""
        hero = self.g("gHero")
        self.poke("b2kMoveTo", [hero, x, y])
        self.poke("b2kSetVelocity", [hero, 0, 0])

    def settle(self):
        """Out of any respawn, knockback and mercy window before the next
        move: a respawn would undo a teleport, and a knocked-back hero
        ignores the jump key (b2kPlayerTick steers nothing while hurt)."""
        self.until(lambda: not _true(self.g("gHurtLock")) and
                   not _true(self.poke("b2kPlayerHurtIs", [])), 400,
                   "the hero recovering from a hit")

    def take(self, o, what, done):
        """Stand the hero on pickup `o` until `done()` says it is taken."""
        x, y = self.pos(o)
        self.teleport(x, y)
        self.until(done, 60, "the %s at %d,%d taken" % (what, x, y))
        self.settle()

    # -- the run ------------------------------------------------------------------
    def boot(self, budget):
        """openCard, as opening the stack sends it, then the title."""
        self.event(self.w.card, "openCard", [], budget)
        self.frames(30)
        if not _true(self.g("gAtTitle")):
            raise Failure("opening the stack did not reach the title")

    def play(self):
        """SPACE at the title, then every level in turn. Answers each
        level's tour counts."""
        self.key(K_SPACE)
        tours = []
        for n in range(1, LEVELS + 1):
            if self.level() != str(n) or len(self.builds) != n:
                raise Failure("after %d level(s) the game is on L%s and has "
                              "built %d time(s): L%d, after one build per "
                              "level, was expected"
                              % (n - 1, self.level(), len(self.builds), n))
            t0, f0 = time.time(), self.w.ms
            title = _s(self.g("gLevelName")) or "?"
            tour = self.play_level()
            tour["frames"] = (self.w.ms - f0) // FRAME_MS
            tour["seconds"] = time.time() - t0
            tours.append(tour)
            self.say("L%d %s: %s" % (n, title,
                                     ", ".join("%s %s" % (v, k) for k, v in
                                               tour.items() if k != "seconds"
                                               and v)))
        return tours

    def play_level(self):
        """Tour the level just built: the flag first (it must refuse), then
        every key, door, switch, coin, gem, star, checkpoint and box, then
        the flag again, which must clear the level, or on the last level win
        the run."""
        lvl = self.level()
        tour = {}
        self.until(lambda: self.gn("gIntroPan") == 0
                   and not self.visible("graphic", "pfCardShade"),
                   400, "the reveal and the intro beat")
        total = self.gn("gCoinsTotal")
        if total < 1:
            raise Failure("L%s: built with no coins" % lvl)
        tour["coins"] = total
        goal = self.flagged("upfgoalflag")
        if len(goal) != 1:
            raise Failure("L%s: %d goal flags" % (lvl, len(goal)))
        gx, gy = self.pos(goal[0])
        self.teleport(gx, gy)
        self.frames(20)
        if _true(self.g("gWinLock")):
            raise Failure("L%s: the flag cleared the level with %d of %d coins"
                          % (lvl, self.gn("gCoins"), total))
        if not _true(self.g("gFlagHint")):
            raise Failure("L%s: the flag, short of the coins, never said so"
                          % lvl)
        self.settle()
        # keys before their doors
        for o in self.flagged("upfkeyflag"):
            word = _s(o.custom.get("upfkeyword", "")) or "yellow"
            self.take(o, word + " key",
                      lambda: word in _s(self.g("gKeysHeld")).split(","))
            tour["keys"] = tour.get("keys", 0) + 1
        for i in range(1, self.gn("gDoorN") + 1):
            if _true(self.gi("gDoorOpen", i)):
                continue
            dx = _num(self.gi("gDoorX", i), "door")
            self.teleport(dx - 60, 500)
            self.until(lambda: _true(self.gi("gDoorOpen", i)), 60,
                       "the %s door at x %s opening"
                       % (_s(self.gi("gDoorWord", i)), dx))
            self.settle()
            tour["doors"] = tour.get("doors", 0) + 1
        for i in range(1, self.gn("gSwN") + 1):
            if _true(self.gi("gSwOpen", i)):
                continue
            sx = _num(self.gi("gSwX", i), "switch")
            self.teleport(sx, 436)
            self.until(lambda: _true(self.gi("gSwOpen", i)), 60,
                       "the switch at x %s pressed" % sx)
            self.settle()
            tour["switches"] = tour.get("switches", 0) + 1
        for prop, what in (("upfcoinflag", "coin"), ("upfgemflag", "gem"),
                           ("upfstarflag", "star")):
            for o in self.flagged(prop):
                if o.gone:
                    continue        # taken on the way to an earlier one
                self.take(o, what, lambda: o.gone)
                tour[what + "s taken"] = tour.get(what + "s taken", 0) + 1
        for o in self.flagged("upfcheckflag"):
            self.take(o, "checkpoint",
                      lambda: _true(o.custom.get("upfcheckdone", "")))
            tour["checkpoints"] = tour.get("checkpoints", 0) + 1
        # the ?-boxes and the bricks: stand under each and jump into it
        for i in range(1, self.gn("gBonkN") + 1):
            if _true(self.gi("gBonkUsed", i)) or not _s(self.gi("gBonkHost", i)):
                continue
            bx = _num(self.gi("gBonkX", i), "bonk")
            kind = _s(self.gi("gBonkKind", i))
            for _attempt in range(3):
                # a player's retry: a slime or a saw can spoil one jump
                self.teleport(bx, 520)
                self.until(lambda: _true(self.poke("b2kPlayerOnGround", [])),
                           90, "landing under the %s at x %s" % (kind, bx))
                self.settle()
                self.w.keys_down.append(K_SPACE)
                try:
                    for _f in range(40):
                        self.frames(1)
                        if _true(self.gi("gBonkUsed", i)):
                            break
                finally:
                    self.w.keys_down.remove(K_SPACE)
                self.frames(2)
                if _true(self.gi("gBonkUsed", i)):
                    break
            else:
                raise Failure("L%s: three jumps under the %s at x %s never "
                              "bonked it (%s)" % (lvl, kind, bx,
                                                  self.hero_note()))
            self.settle()
            tour[kind + "es" if kind == "box" else kind + "s"] = \
                tour.get(kind + "es" if kind == "box" else kind + "s", 0) + 1
        coins = self.gn("gCoins")
        if coins != total:
            raise Failure("L%s: %d of its %d coins after every pickup and box"
                          % (lvl, coins, total))
        # the flag again, gold now
        gx, gy = self.pos(goal[0])
        self.teleport(gx, gy)
        if lvl == str(LEVELS):
            self.until(lambda: _true(self.g("gWon")), 60,
                       "the L%s flag winning the run" % lvl)
            self.frames(60)
            if not self.visible("field", "pfWinText"):
                raise Failure("L%s: the win screen never showed" % lvl)
            return tour
        n = len(self.builds)
        self.until(lambda: _true(self.g("gWinLock")), 60,
                   "the L%s flag clearing the level" % lvl)
        self.until(lambda: len(self.builds) > n, 200,
                   "the level after L%s building" % lvl)
        self.frames(30)         # a second build would have begun by now
        return tour

# ==========================================================================
# the profiles, what each must show, and the command line
# ==========================================================================

# The game's own `try` blocks that catch BY DESIGN, each with why. Any other
# caught error fails the gate, above all one that b2kStep's frame `try`
# swallowed: on an engine that error is silent (box2dxt's CLAUDE.md, gotcha
# 31), and here it is the commonest way a broken level would still "play".
DESIGNED_CATCHES = (
    ("b2ksensorenter", r"^Chunk: no such object",
     "the `delete` after b2kSpriteRemove: a Kit sprite is gone already, "
     "and only a no-art fallback shape is left for it to delete"),
    ("b2kspritesweeporphans", r"^ungroup: object is not a group$",
     "the camera's anchor GRAPHIC shares the b2kcam_ prefix: `ungroup` "
     "refuses it and the catch deletes it instead"),
    ("b2kcamoff", r'^Chunk: no such object \(group "b2kcam_view"\)$',
     "b2kTeardown's orphan sweep has dissolved the viewport already"),
)

PROFILES = ("art", "reopen", "placeholder")


def _sandbox(with_art):
    root = tempfile.mkdtemp(prefix="pf-levels-")
    if with_art:
        shutil.copytree(ART, os.path.join(root, "Spritesheets"))
    os.makedirs(os.path.join(root, "saved"))
    return root


def verdict(run):
    """What every profile must show once its run is over (or has failed):
    each level built once, in order; no menuPick and no engine message
    while a level built; no caught error but the designed ones; the sound
    system never tripped; every planned dialog met."""
    w, ip = run.w, run.ip
    out = []
    levels = [lv for lv, _busy in run.builds]
    if levels != [str(n) for n in range(1, len(levels) + 1)]:
        out.append("the levels were built in the order %s: each once, from "
                   "1 up, was expected" % ", ".join(levels))
    for lv, busy in run.builds:
        if _true(busy):
            out.append("an L%s build began while a build was running" % lv)
    for btn, line, locked in w.menu_picks:
        if not locked:
            out.append("setting %s's menuHistory to %s sent it menuPick "
                       "(engine note 5.14): a second build" % (btn, line))
    seen = {}
    for name, frames in w.build_msgs:
        seen[(frames, name)] = seen.get((frames, name), 0) + 1
    for (frames, name), n in sorted(seen.items()):
        out.append("a level build sent %s %d time(s) with messages unlocked, "
                   "from %s: the quiet build is not quiet (engine note 5.15)"
                   % (name, n, " > ".join(frames)))
    odd = {}
    for event, where, frames, msg in ip.catches:
        if not any(where.lower() == h and re.search(rx, msg)
                   for h, rx, _why in DESIGNED_CATCHES):
            key = (where, msg)
            if key not in odd:
                odd[key] = [0, event, frames]
            odd[key][0] += 1
    for (where, msg), (n, event, frames) in sorted(odd.items()):
        out.append("%s caught an error %d time(s), first thrown in %s during "
                   "%s: %s" % (where, n, " > ".join(frames), event, msg))
    try:
        status = _s(run.poke("b2kSoundStatus", []))
    except Exception as exc:          # noqa: BLE001 - reported, never hidden
        status = "b2kSoundStatus itself failed: %s" % exc
    if status:
        out.append("the sound system tripped: %s" % status)
    out.extend(w.problems)
    if w.dialogs:
        out.append("planned dialog(s) never opened: %s"
                   % ", ".join("%s %r" % (k, rx) for k, rx, _a in w.dialogs))
    return out


def run_profile(name, src, bridge, verbose, saved=None):
    """One profile, start to finish. Answers (problems, the saved stack,
    a one-line summary)."""
    t0 = time.time()
    if name == "reopen":
        # another machine: no art folder anywhere the run may read, and the
        # stack exactly as `save` wrote it (script locals start empty, as
        # on any open)
        root = _sandbox(False)
        w = World.reopen(saved, root, [])
    elif name == "art":
        root = _sandbox(True)
        save = os.path.join(root, "saved", "box2dxt-platformer.livecode")
        w = World(root, [
            ("answer folder", r"Spritesheets", os.path.join(root, "Spritesheets")),
            ("answer", r"^Every sprite", "Save"),
            ("ask file", r"^Save the platformer", save),
            ("answer", r"^Saved:", "OK")])
    else:
        root = _sandbox(False)
        w = World(root, [("answer folder", r"Spritesheets", None)])
    run = Run(name, PfInterp(src, w, bridge), verbose)
    problems, tours = [], []
    try:
        try:
            run.boot(BUDGET_IMPORT)
            art = _true(run.g("gAssetsOK"))
            if name == "art" and w.saved is None:
                raise Failure("the first run never saved the stack")
            if name in ("art", "reopen") and not art:
                raise Failure("the title came up without the art (%s)"
                              % (_s(run.g("gLoadNote")) or "no load note"))
            if name == "placeholder" and art:
                raise Failure("a Cancel at the folder prompt still loaded art")
            if name == "reopen" and w.reads:
                raise Failure("the saved stack read %d file(s) at open, "
                              "first %s" % (len(w.reads), w.reads[0]))
            tours = run.play()
            if name == "reopen" and w.reads:
                raise Failure("the saved stack read %d file(s) in play, "
                              "first %s" % (len(w.reads), w.reads[0]))
        except Failure as exc:
            problems.append(str(exc))
        except Thrown as exc:
            # what the engine shows as its script-error dialog: an error no
            # `try` caught, which ends the handler chain it was thrown in
            problems.append("a script error no `try` caught, during %s, in "
                            "%s: %s" % (run.ip.event, " > ".join(
                                getattr(exc, "pf_frames", None) or []) or "-",
                                exc.msg))
        except (ModelRefusal, DialogError, Budget) as exc:
            problems.append("%s: %s (in %s)" % (
                type(exc).__name__, exc,
                " > ".join(getattr(exc, "pf_frames", None) or []) or "-"))
        problems.extend(verdict(run))
        if verbose:
            # the measurements the budgets at the top of the run section are
            # set from, and every property read before a script set it (a
            # template default this file supplies: a wrong one shows here)
            peaks = run.event_stmts
            run.say("most statements one event ran: %s" % ", ".join(
                "%s %d" % (k, peaks[k]) for k in sorted(peaks, key=peaks.get,
                                                        reverse=True)[:6]))
            run.say("defaults read: %s" % (", ".join(
                "the %s of a %s x%d" % (prop, kind, n)
                for (kind, prop), n in sorted(w.default_reads.items()))
                or "none"))
    finally:
        shutil.rmtree(root, ignore_errors=True)
    frames = sum(t.get("frames", 0) for t in tours)
    coins = sum(t.get("coins", 0) for t in tours)
    summary = ("%d level(s) built once each and cleared, %d coins, %d "
               "frames, %.0f s" % (len(tours), coins, frames, time.time() - t0))
    return problems, w.saved, summary


def main(argv):
    sys.setrecursionlimit(20000)
    verbose = "--verbose" in argv
    path = GAME
    if "--file" in argv:
        path = argv[argv.index("--file") + 1]
    names = list(PROFILES)
    if "--profiles" in argv:
        names = argv[argv.index("--profiles") + 1].split(",")
        for n in names:
            if n not in PROFILES:
                print("check-platformer-levels: no profile %r (%s)"
                      % (n, ", ".join(PROFILES)), file=sys.stderr)
                return 2
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    setup = []
    src = prepare(text, setup.append)
    if setup:
        print("check-platformer-levels: FAIL - %s" % setup[0])
        return 1
    try:
        bridge = LcbBridge(LCB, SO)
        bridge.check_abi()
    except OSError as exc:
        # a host that cannot load the committed x86_64-linux library (the one
        # every execution gate in the suite runs on): a setup problem
        print("check-platformer-levels: %s does not load on this host: %s"
              % (SO, exc), file=sys.stderr)
        return 2
    except (ModelRefusal, Thrown) as exc:
        # a binding shape the bridge does not translate, or a committed
        # library at another ABI: nothing below could run
        print("check-platformer-levels: FAIL - %s" % exc)
        return 1
    failed = 0
    saved = None
    todo = names[:]
    if "reopen" in todo and "art" not in todo:
        todo.insert(0, "art")         # the reopen profile opens art's save
    for name in todo:
        if name == "reopen" and saved is None:
            print("FAIL reopen: the art profile saved no stack to reopen")
            failed += 1
            continue
        if verbose:
            print("  profile %s" % name)
        problems, snap, summary = run_profile(name, src, bridge, verbose,
                                              saved)
        if name == "art":
            saved = snap
        if name not in names:
            continue
        if problems:
            failed += 1
            print("FAIL %s:" % name)
            for p in problems:
                print("    - %s" % p)
        else:
            print("ok   %s: %s" % (name, summary))
    if failed:
        print("check-platformer-levels: %d of %d profile(s) FAILED"
              % (failed, len(names)))
        return 1
    print("check-platformer-levels: OK (%s: every level of %s built once and "
          "played to its flag)" % (", ".join(names), os.path.basename(path)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
