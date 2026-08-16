#!/usr/bin/env python3
"""check-table-layout.py - re-derive every control rect the builders set.

WHY THIS EXISTS. The 720p re-layout (v0.23.0) moved the whole table -- felt
48..524, board centre 300 -> 286, the pot line under the board, the
slider/action/status rows pulled inside the fold -- and the claim made for it
was "51 control rects in budget, the disjointness set pairwise disjoint".
That claim was TRUE and it was also UNREPEATABLE: it came out of a scratchpad
script that ran once and was never committed, which is the same shape of
attestation this family already learned not to trust ("shipped is not run",
suite CLAUDE.md). The suite's tools/check-stack-size.py does not close the
gap: it reads exactly ONE number per stack (the stack's own rect) and never
looks at a control, so a tweak to kHeSeatSpots, kHeBoardY, or one more
bottom-row button could push a control below y=640 with every gate green --
the exact regression the removed SKIP entry used to stand for. So the
arithmetic is a gate now, re-run on every push.

WHAT IT PROVES.
  1. BOUNDS -- every derived rect lies inside kHeStackRect (0,0,1024,640).
     This is the check that would have caught the old 690-height overage.
  2. DISJOINTNESS -- controls that must not overlap do not overlap, with
     every DESIGNED overlap named in EXEMPTIONS below with its reason. That
     table is the interesting half of this gate: it is the written record of
     which overlaps are the design and which would be bugs.
  3. ACCOUNTING -- every `set the rect of` site in the stack is either
     derived here, the stack's own rect, or listed in SKIPS by name with a
     reason. A new rect site in a handler this gate does not walk FAILS the
     build rather than quietly falling outside it.

WHAT IT DOES NOT PROVE. This is GEOMETRY, not appearance. Nothing here says
a label fits its plate, that text is not clipped, that the felt still reads,
or that the z-order paints the way the exemptions assume -- that remains the
OXT pass's job, per the house honesty convention. It also says nothing about
the STACK size itself; tools/check-stack-size.py at the suite root owns that
one number, and this gate owns the controls inside it.

HOW THE RECTS ARE DERIVED. src/holdem.livecodescript is the only input, and
it is PARSED, never executed. Three shapes of rect turn up at its 51 sites:

  a. a literal quad          set the rect of field "heStatus" to "40,596,984,636"
  b. a named constant        set the rect of graphic "heFelt" to kHeFeltRect
  c. a computed expression   set the rect of graphic ("hePanel" & tSeatNum) to \\
                                (tSpotX - 76) & comma & (tSpotY - 4) & comma & ...

(a) and (b) are read straight off the line. (c) needs the builders' own
arithmetic, so rather than copy the offsets into Python (a mirror that would
drift the first time somebody nudged a seat plate), this walks the BUILDERS:
a small interpreter for the handful of statement forms heBuildTable,
heBuildLobby, heBuildSettings, heBuildHistory, heReportShow and the makers
(heMakeLabel / heMakeCardSlot / heMakeActionButton / heMakeAvatar /
heMakeSettingRow) are written in -- `repeat with`, `put ... into`, item
chunks of a constant, `set the itemDelimiter`, maker calls with positional
arguments, and `set the rect of`. Offsets, seat spots, and card sizes are
therefore read from the source every run; edit heBuildTable and this gate
re-derives what you wrote, not what somebody once wrote down. Anything the
interpreter does not understand inside a walked handler is a hard FAILURE,
never a silent skip -- a builder that grew a `switch` must be taught here,
because deriving 50 of 51 rects and saying nothing about the 51st is how the
last "verified by arithmetic" claim got to be unfalsifiable.

Those 51 sites are not 51 rects, which is worth stating plainly because the
original claim conflated them: the loops and makers behind them build 153
concrete controls (six seat clusters, five board slots, eleven action
buttons, four overlays), and the dealer button adds six more placements, so
159 rects are checked. `--list` prints every one of them with the source
line it came from -- the arithmetic, re-runnable, which is the whole point.

Python 3 stdlib only; no engine, no deps.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STACK = os.path.join(ROOT, "src", "holdem.livecodescript")

# The builders this gate walks. The first name is the GROUP root: every rect
# set while it is on the stack belongs to that group, and disjointness is
# checked WITHIN a group only (see EXEMPT_CROSS_GROUP).
GROUP_ROOTS = {
    "heBuildTable": "table",
    "heBuildLobby": "lobby",
    "heBuildSettings": "settings",
    "heBuildHistory": "history",
    "heReportShow": "report",
}
# Entry points. heBuildLobby/Settings/History are reached from heBuildTable's
# tail; heReportShow is built on demand by heRunSelftest, so it needs its own
# entry (it is still a real overlay whose rects must fit the window).
ENTRIES = ["heBuildTable", "heReportShow"]
# Handlers the interpreter follows INTO. Everything else called from a walked
# builder is ignored -- and if it sets a rect, ACCOUNTING below catches that.
FOLLOW = set(GROUP_ROOTS) | {
    "heMakeLabel", "heMakeCardSlot", "heMakeActionButton",
    "heMakeAvatar", "heMakeSettingRow",
}

# ---------------------------------------------------------------------------
# SKIPS: rect sites this gate deliberately does not derive, each by name with
# the reason it cannot be. Never silently dropped: a site that is neither
# derived nor listed here FAILS, and a listed site that no longer exists (or
# has become derivable) FAILS too, so the list cannot rot into an excuse for
# code that moved. Keyed by (handler, control) as the source spells them.
# ---------------------------------------------------------------------------
SKIPS = [
    ("heSeatAvatarRender", "heSeatAvImg<N>",
     "runtime aspect re-fit of a HOST-PICKED image file: heFitRect takes the "
     "loaded picture's formatWidth/formatHeight, which exist only once the "
     "engine has read a file this gate cannot see. Bounded by construction -- "
     "heFitRect returns the largest aspect-preserving rect inside the "
     "kHeAvatarSize box centred on the seat disc, so it can only ever shrink "
     "within the built heSeatAv<N> rect, which IS derived below."),
    ("heTableLogoRender", "heTableLogo",
     "same runtime re-fit for the host's table logo: inside the kHeLogoBox "
     "square centred on (512,286), i.e. inside the built heTableLogo rect "
     "derived below. The logo is a blendLevel watermark and is an exempt "
     "underlay in any case."),
]

# ---------------------------------------------------------------------------
# EXEMPTIONS: the overlaps that are DESIGN. Each entry is
# (pattern_a, pattern_b, reason). "<N>" in a pattern matches a seat/slot
# index; when BOTH patterns carry it the indexes must be EQUAL (a seat's own
# cluster), which is what keeps seat 2's plate honest about seat 3's. "*"
# matches anything.
#
# A rule that matches no actual overlap is STALE and fails the gate -- the
# check-suite-coverage lesson: a gate that carries dead excuses answers the
# question nobody asks twice.
# ---------------------------------------------------------------------------
EXEMPTIONS = [
    # -- the ground plane -----------------------------------------------
    ("heFeltRim", "*",
     "the wooden rim is the ground plane: the felt sits on it and the whole "
     "table sits on the felt. Created first, so it paints underneath."),
    ("heFelt", "*",
     "the felt is the table surface every seat, card slot and chip is placed "
     "ON. Created before all of them."),
    ("heTableLogo", "*",
     "the host's centre watermark: created BEFORE the pot and the board on "
     "purpose (heBuildTable says so in as many words) so it paints under "
     "them, and dimmed to kHeLogoDim. It is MEANT to be covered."),
    ("heLobbyBg", "*",
     "the lobby panel is the ground for its own overlay's controls."),
    ("heSetBg", "*",
     "the settings panel is the ground for its own overlay's controls."),
    ("heHistBg", "*",
     "the history panel is the ground for its own overlay's controls."),
    ("heReportBg", "*",
     "the harness-report panel is the ground for its own two controls."),
    # -- one seat's own cluster, which is a deliberate STACK -------------
    # Everything below is same-seat only (both patterns carry <N>), so seat
    # 2's plate is still held honest about seat 3's.
    ("hePanel<N>", "heSeatAv<N>",
     "seat plate and its portrait disc: the disc sits ON the plate."),
    ("hePanel<N>", "heSeatAvTx<N>",
     "the initial-letter fallback is drawn on the portrait disc, on the plate."),
    ("hePanel<N>", "heSeatAvImg<N>",
     "the picked portrait image occupies the same disc rect, on the plate."),
    ("hePanel<N>", "heSeatName<N>",
     "the name label is a child of its seat plate."),
    ("hePanel<N>", "heSeatStack<N>",
     "the chip-count label is a child of its seat plate."),
    ("heSeatAv<N>", "heSeatAvTx<N>",
     "portrait disc, initial fallback and image share ONE rect by design "
     "(heMakeAvatar stacks all three at the same tRect; heSeatAvatarRender "
     "shows exactly one of the top two)."),
    ("heSeatAv<N>", "heSeatAvImg<N>",
     "same three-control portrait stack (disc under the picked image)."),
    ("heSeatAvTx<N>", "heSeatAvImg<N>",
     "same three-control portrait stack (initial under the picked image; "
     "never both visible)."),
    ("hePanel<N>", "heHole<N>a",
     "hole cards are dealt OVER their own seat plate -- the plate's top edge "
     "is deliberately tucked under the card bottoms."),
    ("hePanel<N>", "heHole<N>b",
     "same: the second hole card over its own plate."),
    ("heSeatName<N>", "heHole<N>a",
     "the card bottoms overlap the top few pixels of the name label on the "
     "plate below them -- the same plate-under-cards layering. WHETHER THE "
     "NAME STILL READS at that overlap is an eye question, not a geometry "
     "one: it belongs to the OXT pass."),
    ("heSeatName<N>", "heHole<N>b",
     "same, for the seat's second card."),
    ("heSeatBadge<N>", "heHole<N>b",
     "the blind/all-in badge sits in the plate's top-right corner, under the "
     "right-hand card of its own seat (the left card clears it)."),
    ("heSeatState<N>", "heHole<N>a",
     "the action word (FOLD/CHECK/RAISE) prints across the top of the seat's "
     "own card pair -- it is a caption ON the cards, not beside them."),
    ("heSeatState<N>", "heHole<N>b",
     "same caption over the second card."),
    # -- a seat's bet cluster, pushed toward the pot ---------------------
    # heBuildTable puts the chip 42% of the way from the seat spot to the
    # table centre, so for the seats whose spot is already near the centre
    # column the cluster lands back on top of that seat's own chrome. It is
    # the seat's OWN bet and it paints last; the cross-seat pairs are still
    # checked, which is what stops a bet chip drifting onto a neighbour.
    ("heSeatChip<N>", "heSeatState<N>",
     "the near seat's bet chip lands on its own action caption."),
    ("heSeatBet<N>", "heSeatState<N>",
     "the near seat's bet amount lands on its own action caption."),
    ("heSeatChip<N>", "heHole<N>a",
     "the near seat's bet chip lands over its own left card."),
    ("heSeatChip<N>", "heHole<N>b",
     "the near seat's bet chip lands over its own right card."),
    ("heSeatBet<N>", "heHole<N>a",
     "the near seat's bet amount lands over its own left card."),
    ("heSeatBet<N>", "heHole<N>b",
     "the near seat's bet amount lands over its own right card."),
]
# Cross-group pairs are exempt wholesale, with the reason recorded once here
# rather than as N*M table entries.
EXEMPT_CROSS_GROUP = (
    "the lobby, settings, history and report panels are MODAL overlays: each "
    "covers the table, only one is ever visible (heLobbyShow/heSettingsShow/"
    "heHistShow each hide the other two; heReportShow builds above everything "
    "on demand), and hiding is by name over the whole group. Overlap with the "
    "table beneath them -- and with each other -- is the point. Within one "
    "overlay, disjointness IS checked."
)


# ---------------------------------------------------------------------------
# source loading: block comments, line comments, "\" continuations
# ---------------------------------------------------------------------------

def strip_comments(text):
    """Drop /* */ blocks and -- line comments, QUOTE-AWARE.

    Both matter here: the file opens with a ~900-line /* changelog */ whose
    prose would otherwise parse as code, and several lobby labels carry a
    literal "--" INSIDE a display string ("holde-em online -- serverless
    table over the DHT"), which a naive comment stripper would eat along with
    the rest of the rect line.
    """
    out = []
    in_block = False
    for line in text.split("\n"):
        res = []
        i = 0
        in_str = False
        while i < len(line):
            ch = line[i]
            if in_block:
                if line.startswith("*/", i):
                    in_block = False
                    i += 2
                    continue
                i += 1
                continue
            if in_str:
                res.append(ch)
                if ch == '"':
                    in_str = False
                i += 1
                continue
            if ch == '"':
                in_str = True
                res.append(ch)
                i += 1
                continue
            if line.startswith("--", i):
                break
            if line.startswith("/*", i):
                in_block = True
                i += 2
                continue
            res.append(ch)
            i += 1
        out.append("".join(res))
    return out


def logical_lines(lines):
    """Join "\"-continued lines. Returns [(first_line_number, text)]."""
    joined = []
    buf = ""
    start = 0
    for n, raw in enumerate(lines, 1):
        text = raw.rstrip()
        if not buf:
            start = n
        if text.endswith("\\"):
            buf += text[:-1].rstrip() + " "
            continue
        buf += text
        joined.append((start, buf))
        buf = ""
    if buf:
        joined.append((start, buf))
    return joined


class LayoutError(Exception):
    """A construct this gate cannot derive. Always fatal, never a silent skip."""


# ---------------------------------------------------------------------------
# the expression evaluator
#
# Values are TEXT, as they are in xTalk -- "512" and 512 are the same thing,
# which is what makes `(tSpotX - 76) & comma & (tSpotY - 4)` and
# `"232," & pTopY & ",540,"` both fall out of one evaluator. Arithmetic
# converts on demand and formats an integral result back without a ".0",
# because that is what the engine puts in a rect.
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(r"""
    (?P<str>"[^"]*")
  | (?P<num>\d+\.\d+|\d+)
  | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[&+\-*/(),\[\]])
  | (?P<ws>\s+)
""", re.VERBOSE)


def tokenize(text):
    toks = []
    i = 0
    while i < len(text):
        m = TOKEN_RE.match(text, i)
        if not m:
            raise LayoutError("cannot tokenize %r at %r" % (text, text[i:i + 20]))
        i = m.end()
        if m.lastgroup == "ws":
            continue
        toks.append((m.lastgroup, m.group()))
    return toks


def num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        raise LayoutError("not a number: %r" % (value,))


def fmt(value):
    """Format a computed number the way the engine would put it in a rect."""
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return repr(value)


class Evaluator(object):
    def __init__(self, env, consts, item_delim):
        self.env = env
        self.consts = consts
        self.item_delim = item_delim

    def value_of(self, name):
        if name in self.env:
            return self.env[name]
        if name in self.consts:
            return self.consts[name]
        if name == "comma":
            return ","
        if name == "empty":
            return ""
        raise LayoutError(
            "unknown name %r - this gate only derives geometry from constants "
            "and locals it has watched being assigned" % name)

    # --- recursive descent -------------------------------------------------
    def parse(self, text):
        self.toks = tokenize(text)
        self.pos = 0
        val = self.concat()
        if self.pos != len(self.toks):
            raise LayoutError("trailing tokens in %r" % text)
        return val

    def peek(self):
        return self.toks[self.pos] if self.pos < len(self.toks) else (None, None)

    def take(self):
        tok = self.peek()
        self.pos += 1
        return tok

    def expect_op(self, op):
        kind, text = self.take()
        if text != op:
            raise LayoutError("expected %r, got %r" % (op, text))

    def concat(self):
        # "&" (and "&&", a space join) bind looser than arithmetic in xTalk
        out = self.arith_text()
        while True:
            kind, text = self.peek()
            if text == "&":
                self.take()
                if self.peek()[1] == "&":
                    self.take()
                    out = out + " " + self.arith_text()
                else:
                    out = out + self.arith_text()
            else:
                return out

    def arith_text(self):
        """One concatenation operand, as TEXT.

        Numeric conversion happens only where an arithmetic operator actually
        demands it, so a text-valued name passes straight through: that is
        what lets `set the rect of graphic "heFelt" to kHeFeltRect` (a whole
        "L,T,R,B" quad in one constant) and `(tSpotX - 76) & comma & ...`
        share one evaluator.
        """
        val = self.term_text()
        while True:
            kind, text = self.peek()
            if text in ("+", "-"):
                self.take()
                rhs = num(self.term_text())
                lhs = num(val)
                val = fmt(lhs + rhs if text == "+" else lhs - rhs)
            else:
                return val

    def term_text(self):
        val = self.unary_text()
        while True:
            kind, text = self.peek()
            if text in ("*", "/") or (kind == "id" and text in ("div", "mod")):
                self.take()
                rhs = num(self.unary_text())
                lhs = num(val)
                if text == "*":
                    val = fmt(lhs * rhs)
                elif text == "/":
                    val = fmt(lhs / rhs)
                elif text == "div":
                    val = fmt(float(int(lhs / rhs)))   # truncates toward zero
                else:
                    val = fmt(lhs - rhs * float(int(lhs / rhs)))
            else:
                return val

    def unary_text(self):
        kind, text = self.peek()
        if text == "-":
            self.take()
            return fmt(-num(self.unary_text()))
        return self.primary()

    def primary(self):
        kind, text = self.take()
        if kind == "num":
            return text
        if kind == "str":
            return text[1:-1]
        if text == "(":
            val = self.concat()
            self.expect_op(")")
            return val
        if kind == "id":
            if text in ("item", "line", "char"):
                return self.chunk(text)
            if text in ("trunc", "round", "abs"):
                self.expect_op("(")
                arg = self.concat()
                self.expect_op(")")
                val = num(arg)
                if text == "trunc":
                    return fmt(float(int(val)))
                if text == "round":
                    # xTalk rounds half away from zero
                    return fmt(float(int(val + (0.5 if val >= 0 else -0.5))))
                return fmt(abs(val))
            if self.peek()[1] == "(":
                raise LayoutError("unsupported function call %r" % text)
            return self.value_of(text)
        raise LayoutError("unexpected token %r" % text)

    def chunk(self, kind):
        idx = int(num(self.arith_text()))
        kw = self.take()
        if kw[1] != "of":
            raise LayoutError("expected 'of' in %s chunk, got %r" % (kind, kw[1]))
        src = self.arith_text()
        if kind == "item":
            parts = src.split(self.item_delim)
        elif kind == "line":
            parts = src.split("\n")
        else:
            parts = list(src)
        if idx < 1 or idx > len(parts):
            return ""
        return parts[idx - 1]


# ---------------------------------------------------------------------------
# the statement interpreter
# ---------------------------------------------------------------------------

RECT_RE = re.compile(
    r'^set\s+the\s+rect\s+of\s+'
    r'(?:(this\s+stack)|(field|button|graphic|image|scrollbar)\s+(.+?))'
    r'\s+to\s+(.+)$')
PUT_RE = re.compile(r'^put\s+(.+?)\s+into\s+([A-Za-z_][A-Za-z0-9_]*)$')
DELIM_RE = re.compile(r'^set\s+the\s+itemDelimiter\s+to\s+(.+)$')
REPEAT_RE = re.compile(
    r'^repeat\s+with\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s+to\s+(.+)$')
HANDLER_RE = re.compile(
    r'^(command|function|on)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$')
# A `put` whose target is an ARRAY ELEMENT holds no geometry this gate needs
# (heMakeCardSlot records the slot centre in gSlotCenter for the kit's sprite
# pooling). Every other `put` form must be understood, because a mis-read
# assignment would feed a plausible WRONG number into a rect.
PUT_ARRAY_RE = re.compile(r'^put\s+.+\s+into\s+[A-Za-z_][A-Za-z0-9_]*\[')
# Statement heads that carry no geometry, walked past without comment. Two of
# them are decisions rather than omissions:
#   "if"/"else"/"end" -- conditionals are FLATTENED: both branches are walked,
#     because a build-once guard (heReportShow's `if there is not a field ...`)
#     must be walked, and the only other conditional over a rect-setting body
#     is heBuildTable's rehydrate early-exit, which sets none. If a builder
#     ever grows an if/else that sets the SAME control two different ways,
#     Walker.record refuses it rather than picking a branch.
#   "exit" -- `exit <handler>` follows from that flattening. `exit repeat`
#     does NOT: it would end a seat loop early, so it is refused below.
IGNORE_HEADS = (
    "create", "set", "if", "else", "end", "exit", "lock", "unlock", "show",
    "hide", "delete", "get", "return", "send", "wait",
    "repeat", "try", "catch", "local", "constant", "global",
    "function", "command", "on", "answer", "ask",
)
# Heads that MUST be taught to this gate if they ever turn up inside a walked
# builder: silently walking past one would drop or mis-derive a rect.
REFUSE_HEADS = ("switch", "case", "default", "break", "next", "pass", "throw")
REFUSE_EXACT = ("exit repeat",)


class Builders(object):
    """The walked half of the stack: handler bodies plus the constants."""

    def __init__(self, path):
        raw = open(path, encoding="utf-8").read()
        self.lines = logical_lines(strip_comments(raw))
        self.consts = {}
        self.handlers = {}
        self._scan()

    def _scan(self):
        current = None
        for lineno, text in self.lines:
            stripped = text.strip()
            m = re.match(r'^constant\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$',
                         stripped)
            if m:
                value = m.group(2).strip()
                if value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]
                self.consts[m.group(1)] = value
                continue
            m = HANDLER_RE.match(stripped)
            if m:
                params = [p.strip() for p in m.group(3).split(",") if p.strip()]
                current = (m.group(2), params, [])
                self.handlers[m.group(2)] = current
                continue
            if stripped.startswith("end ") and current is not None:
                if stripped.split()[1] == current[0]:
                    current = None
                    continue
            if current is not None:
                current[2].append((lineno, stripped))


class Walker(object):
    """Executes the geometry-bearing subset of the builders."""

    def __init__(self, builders):
        self.b = builders
        self.rects = []          # (name, group, rect, lineno)
        self.derived_lines = set()
        self.item_delim = ","

    # --- helpers -----------------------------------------------------------
    def eval(self, text, env):
        return Evaluator(env, self.b.consts, self.item_delim).parse(text)

    def split_args(self, text):
        """Split a command's argument list on TOP-LEVEL commas only."""
        args, depth, in_str, buf = [], 0, False, ""
        for ch in text:
            if in_str:
                buf += ch
                if ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
                buf += ch
            elif ch == "(":
                depth += 1
                buf += ch
            elif ch == ")":
                depth -= 1
                buf += ch
            elif ch == "," and depth == 0:
                args.append(buf.strip())
                buf = ""
            else:
                buf += ch
        if buf.strip():
            args.append(buf.strip())
        return args

    # --- execution ---------------------------------------------------------
    def run(self, name, args, group, depth=0):
        if depth > 8:
            raise LayoutError("builder recursion too deep at %s" % name)
        _hname, params, body = self.b.handlers[name]
        env = {}
        for i, p in enumerate(params):
            env[p] = args[i] if i < len(args) else ""
        group = GROUP_ROOTS.get(name, group)
        self.block(body, 0, len(body), env, group, depth)

    def block(self, body, start, stop, env, group, depth):
        i = start
        while i < stop:
            lineno, text = body[i]
            if not text:
                i += 1
                continue
            head = text.split()[0]
            if head == "repeat":
                end = self.match_repeat(body, i, stop)
                self.do_repeat(body, i, end, env, group, depth)
                i = end + 1
                continue
            if head in REFUSE_HEADS or text in REFUSE_EXACT:
                raise LayoutError(
                    "line %d: %r is inside a walked builder and this gate does "
                    "not interpret it - teach it here rather than deriving the "
                    "other rects and staying quiet about this one"
                    % (lineno, text[:60]))
            self.statement(lineno, text, env, group, depth)
            i += 1

    def match_repeat(self, body, i, stop):
        level = 0
        for j in range(i, stop):
            head = body[j][1].split()[0] if body[j][1] else ""
            if head == "repeat":
                level += 1
            elif body[j][1].startswith("end repeat"):
                level -= 1
                if level == 0:
                    return j
        raise LayoutError("unbalanced repeat at line %d" % body[i][0])

    def do_repeat(self, body, i, end, env, group, depth):
        lineno, text = body[i]
        m = REPEAT_RE.match(text)
        if not m:
            raise LayoutError(
                "line %d: only `repeat with <v> = <a> to <b>` is interpreted, "
                "got %r" % (lineno, text[:60]))
        var = m.group(1)
        lo = int(num(self.eval(m.group(2), env)))
        hi = int(num(self.eval(m.group(3), env)))
        for value in range(lo, hi + 1):
            env[var] = str(value)
            self.block(body, i + 1, end, env, group, depth)

    def statement(self, lineno, text, env, group, depth):
        m = DELIM_RE.match(text)
        if m:
            self.item_delim = self.eval(m.group(1), env)
            return
        m = RECT_RE.match(text)
        if m:
            if m.group(1):          # the stack's own rect: check-stack-size's
                self.derived_lines.add(lineno)
                return
            name = self.eval(m.group(3), env)
            rect = self.eval(m.group(4), env)
            self.record(name, group, rect, lineno)
            return
        m = PUT_RE.match(text)
        if m:
            env[m.group(2)] = self.eval(m.group(1), env)
            return
        if PUT_ARRAY_RE.match(text):
            return
        head = text.split()[0]
        if head in self.b.handlers and head in FOLLOW:
            rest = text[len(head):].strip()
            args = [self.eval(a, env) for a in self.split_args(rest)]
            self.run(head, args, group, depth + 1)
            return
        if head in IGNORE_HEADS or head in self.b.handlers:
            return
        # an unknown statement head in a walked builder is a defect in THIS
        # gate, not in the stack - say so loudly
        raise LayoutError("line %d: unhandled statement %r" % (lineno, text[:60]))

    def record(self, name, group, rect, lineno):
        parts = [p.strip() for p in rect.split(",")]
        if len(parts) != 4:
            raise LayoutError(
                "line %d: %s rect %r is not an L,T,R,B quad" % (lineno, name, rect))
        try:
            quad = tuple(int(p) for p in parts)
        except ValueError:
            raise LayoutError(
                "line %d: %s rect %r has a non-integer component"
                % (lineno, name, rect))
        # One control, one rect. A second, DIFFERENT rect for the same name
        # means the build is order-dependent -- and it would also put the
        # control in the disjointness set twice, where it would "overlap
        # itself" and read as a defect in the layout instead of in the
        # builder. An identical repeat is harmless and collapses.
        for other, _g, orect, oline in self.rects:
            if other != name:
                continue
            if orect == quad:
                self.derived_lines.add(lineno)
                return
            raise LayoutError(
                "%s gets two different rects (line %d %s, line %d %s) - this "
                "gate cannot say which one the engine ends up with"
                % (name, oline, "%d,%d,%d,%d" % orect, lineno,
                   "%d,%d,%d,%d" % quad))
        self.rects.append((name, group, quad, lineno))
        self.derived_lines.add(lineno)


# ---------------------------------------------------------------------------
# the one control the GAME moves after the build
#
# heHudRefresh slides the dealer button onto the seat holding it, off the same
# kHeSeatSpots the seat clusters come from -- so a seat-ring tweak moves the
# disc too, and its six landing places are exactly the kind of arithmetic
# nobody re-runs. The offset is READ from that line rather than copied here,
# for the same reason as everything else in this gate: a mirror drifts, a
# parse cannot. The built rect (parked at the origin, hidden) supplies the
# size, so the disc is derived at 7 positions, all of them checked.
# ---------------------------------------------------------------------------

DISC_LOC_RE = re.compile(
    r'^set\s+the\s+loc\s+of\s+field\s+"heDealerDisc"\s+to\s+(.+)$')


def disc_placements(builders, rects):
    built = [r for n, _g, r, _l in rects if n == "heDealerDisc"]
    if not built:
        raise LayoutError(
            "heDealerDisc has no built rect - this gate sizes the moved disc "
            "from it")
    half_w = (built[0][2] - built[0][0]) // 2
    half_h = (built[0][3] - built[0][1]) // 2
    sites = [(lineno, m.group(1))
             for lineno, text in builders.lines
             for m in [DISC_LOC_RE.match(text.strip())] if m]
    if len(sites) != 1:
        raise LayoutError(
            "expected exactly one `set the loc of field \"heDealerDisc\"` "
            "site, found %d - the disc's placement arithmetic moved and this "
            "gate would silently stop checking it" % len(sites))
    lineno, expr = sites[0]
    spots = builders.consts["kHeSeatSpots"].split(";")
    out = []
    for seat, spot in enumerate(spots, 1):
        x, y = [p.strip() for p in spot.split(",")]
        env = {"tSpotX": x, "tSpotY": y}
        loc = Evaluator(env, builders.consts, ",").parse(expr)
        cx, cy = (int(p.strip()) for p in loc.split(","))
        out.append(("heDealerDisc@seat%d" % seat, "table",
                    (cx - half_w, cy - half_h, cx + half_w, cy + half_h),
                    lineno))
    return out


# ---------------------------------------------------------------------------
# the checks
# ---------------------------------------------------------------------------

def overlaps(a, b):
    """True when two L,T,R,B rects share at least one pixel. Edge-adjacent
    rects (a's right == b's left) do NOT overlap: the engine's rect is
    half-open on the right/bottom, and the layout leans on that (the action
    row's buttons are 80 apart and 76 wide, but several panels do touch)."""
    return (a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3])


def pattern_match(pattern, name):
    """Match a control name against an exemption pattern.

    Returns (True, index) where index is the "<N>" capture (or None). "*"
    matches anything, "<N>" matches a run of digits.
    """
    if pattern == "*":
        return True, None
    if "<N>" not in pattern:
        return pattern == name, None
    rx = re.escape(pattern).replace(re.escape("<N>"), r"(\d+)")
    m = re.match("^" + rx + "$", name)
    if not m:
        return False, None
    return True, m.group(1)


def exemption_for(name_a, name_b):
    """The EXEMPTIONS index that covers this pair, or None."""
    for i, (pa, pb, _reason) in enumerate(EXEMPTIONS):
        for x, y in ((name_a, name_b), (name_b, name_a)):
            ok_a, idx_a = pattern_match(pa, x)
            if not ok_a:
                continue
            ok_b, idx_b = pattern_match(pb, y)
            if not ok_b:
                continue
            # both patterns carrying <N> means "the same seat's own cluster"
            if idx_a is not None and idx_b is not None and idx_a != idx_b:
                continue
            return i
    return None


def rect_sites(builders):
    """Every `set the rect of` site in the stack, as (lineno, control text)."""
    sites = []
    for lineno, text in builders.lines:
        stripped = text.strip()
        m = RECT_RE.match(stripped)
        if m:
            sites.append((lineno, m.group(1) or (m.group(2) + " " + m.group(3))))
    return sites


def handler_of(builders, lineno):
    """Which handler a source line falls inside (for the accounting report)."""
    for name, (_n, _p, body) in builders.handlers.items():
        for bl, _text in body:
            if bl == lineno:
                return name
    return "?"


def main():
    problems = []
    builders = Builders(STACK)

    stack_rect = builders.consts.get("kHeStackRect")
    if not stack_rect:
        print("check-table-layout: FAILED")
        print("  - kHeStackRect is not a literal constant in the stack source")
        return 1
    sl, st, sr, sb = (int(p.strip()) for p in stack_rect.split(","))

    walker = Walker(builders)
    try:
        for entry in ENTRIES:
            walker.run(entry, [], GROUP_ROOTS.get(entry, "table"))
        rects = walker.rects + disc_placements(builders, walker.rects)
    except LayoutError as err:
        print("check-table-layout: FAILED")
        print("  - %s" % err)
        return 1

    if "--list" in sys.argv:
        for name, group, rect, lineno in rects:
            print("%-20s %-8s %-24s src line %d"
                  % (name, group, "%d,%d,%d,%d" % rect, lineno))
        print("-- groups: %s" % EXEMPT_CROSS_GROUP)

    # 1. bounds ------------------------------------------------------------
    for name, group, rect, _lineno in rects:
        left, top, right, bottom = rect
        if left < sl or top < st or right > sr or bottom > sb:
            problems.append(
                "%s (%s) rect %d,%d,%d,%d falls outside the stack rect %s"
                % (name, group, left, top, right, bottom, stack_rect))

    # 2. disjointness ------------------------------------------------------
    used_exemptions = set()
    cross_group = 0
    checked_pairs = 0
    in_set = set()
    for i in range(len(rects)):
        name_a, group_a, rect_a, _la = rects[i]
        for j in range(i + 1, len(rects)):
            name_b, group_b, rect_b, _lb = rects[j]
            if group_a != group_b:
                cross_group += 1
                continue
            idx = exemption_for(name_a, name_b)
            if idx is not None:
                if overlaps(rect_a, rect_b):
                    used_exemptions.add(idx)
                continue
            checked_pairs += 1
            in_set.add(name_a)
            in_set.add(name_b)
            if overlaps(rect_a, rect_b):
                problems.append(
                    "%s %d,%d,%d,%d overlaps %s %d,%d,%d,%d - neither is an "
                    "exempt layer, so one of them is in the wrong place"
                    % ((name_a,) + rect_a + (name_b,) + rect_b))

    for i, (pa, pb, _reason) in enumerate(EXEMPTIONS):
        if i not in used_exemptions:
            problems.append(
                "the overlap exemption %s / %s no longer covers any real "
                "overlap - delete it rather than leave a dead excuse behind"
                % (pa, pb))

    # 3. accounting --------------------------------------------------------
    # Every `set the rect of` site in the whole stack is derived above, is the
    # stack's own rect (check-stack-size's one number), or is named in SKIPS.
    # Nothing falls through the middle: that is the property the original
    # once-run scratchpad script could not offer.
    skipped = []
    stack_sites = 0
    for lineno, control in rect_sites(builders):
        if lineno in walker.derived_lines:
            continue
        if control.startswith("this"):
            stack_sites += 1
            continue
        handler = handler_of(builders, lineno)
        hit = [s for s in SKIPS if s[0] == handler]
        if hit:
            skipped.append((lineno, handler, hit[0][1]))
            continue
        problems.append(
            "%s:%d sets a rect (%s) that this gate never derives and SKIPS "
            "does not name - walk the handler here or add it to SKIPS with a "
            "reason" % (handler, lineno, control))
    for handler, control, _reason in SKIPS:
        if not any(h == handler for _l, h, _c in skipped):
            problems.append(
                "the SKIP for %s / %s matches no rect site any more - the "
                "handler moved or became derivable; re-check it and drop the "
                "entry" % (handler, control))

    if problems:
        print("check-table-layout: FAILED")
        for p in problems:
            print("  - %s" % p)
        return 1

    names = sorted(set(n for n, _g, _r, _l in rects))
    sites = len(rect_sites(builders))
    discs = len([n for n, _g, _r, _l in rects if "@seat" in n])
    skip_names = ", ".join("%s in %s" % (c, h) for _l, h, c in skipped)
    print("check-table-layout: OK (%d rects derived, %d in the disjointness "
          "set, %d skipped: %s)"
          % (len(rects), len(in_set), len(skipped), skip_names))
    print("  %d controls from %d of the stack's %d `set the rect` sites (%d "
          "is the stack's own rect - check-stack-size's number, not this "
          "gate's) plus the dealer disc's %d placements; every one inside %s"
          % (len(names), sites - stack_sites - len(skipped), sites,
             stack_sites, discs, stack_rect))
    print("  %d same-overlay pairs proved disjoint; %d designed overlaps "
          "exempt by name; %d cross-overlay pairs exempt (modal panels)"
          % (checked_pairs, len(EXEMPTIONS), cross_group))
    print("  GEOMETRY only: nothing clipped, the felt still reads, and the "
          "paint order the exemptions assume are the OXT pass's to confirm.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
