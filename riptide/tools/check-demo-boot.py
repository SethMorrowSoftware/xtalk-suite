#!/usr/bin/env python3
"""check-demo-boot.py - BOOT the shipped riptide-social stack, headlessly.

WHY THIS EXISTS, bluntly. On 2026-08-29 a phase-8 card shipped through a
fully green gate set, five commits, and a self-review, and broke the WHOLE
app at `openStack` on a real engine - twice, two different ways (a
non-literal constant that killed compilation of the one-unit script, then a
runtime `Chunk: no target found`). Both were invisible to every gate in
this repository for one reason: no gate here EXECUTES a stack script.
"All static gates passed" never meant "the window opens". The library rail
survived that day precisely because it has an execution gate
(tools/check-script-vectors.py) and the UI half did not. riptide/CLAUDE.md
now carries the operational rule this file exists to satisfy: DO NOT land
UI changes in this app without a way to RUN them.

WHAT IT DOES. It loads the SHIPPED examples/riptide-social.livecodescript -
the whole file, embedded libraries and all, exactly the text a maintainer
pastes - into the family's headless interpreter (nostrxt/tools/lcs-interp.py,
byte-identical with coinxt's copy, drift-gated), extended here with a model
of the ENGINE'S OBJECT WORLD: a stack, cards, fields/buttons/graphics with
properties, `create`/`set`/`go`/`there is`, delayed `send`s, a clipboard,
and a sandboxed filesystem for `url binfile:` and `specialFolderPath`. Then
it drives the app the way the engine does: `openStack`, the queued
self-check tick, card navigation clicks, and a scripted create/lock/close
session - under TWO capability profiles (a minimal SodiumXT-only machine,
and a full install), because the app promises to degrade per-feature and a
promise nobody executes is the exact failure shape this tree keeps paying
for.

WHAT IT IS NOT. A model of the engine, not the engine - the interpreter's
own header carries that contract and this file inherits it: if this gate
and the engine disagree, the engine is right, and nothing here promotes any
label past "verified statically + headless boot; needs an OXT pass". The
model REFUSES loudly (a Python error, a failed check) rather than guessing
at a construct it does not know, because a silent mis-parse would make this
gate the next thing that "looks like it checks something and does not".

NAMED MODELING DECISIONS, so the divergences are read rather than
discovered:
  - A MISSING HANDLER CALL raises a catchable script error (Thrown), which
    is what the engine does and what every capability probe in this app
    depends on. The minimal profile is nothing more than "the bt*/ox*/dc*/
    en*/cx* natives are not installed".
  - An unqualified control reference (`field "x"`) resolves against the
    CURRENT CARD of the defaultStack. SETTLED 2026-08-29, and in the
    model's favour: the maintainer's real five-card boot reported all 63
    off-card controls "missing" from a stack where every one existed -
    now engine notes 5.6, and the reason the carried self-check's
    scMissing walks every card with qualified `there is` since the same
    day. The boot self-check must therefore report ZERO failures here,
    and the gate asserts exactly that. The GATE's own control checks are
    world-level - the control exists on some card - independent of the
    resolution rule.
  - `set the height` keeps the control's vertical center (the engine rule);
    `set the top` moves it. `the formattedHeight` returns a fixed sane
    number (14) - text metrics are the engine's, and every kit use of the
    measurement is guarded for that.
  - `go to card` to a missing card sets `the result` and stays put; a chunk
    write into a missing control THROWS - both the engine's behaviours.
  - Timers do not exist: `send ... in N milliseconds` queues, and queued
    messages are delivered in order after the driving handler returns, each
    advancing the modeled clock. A handler that re-arms itself is delivered
    a bounded number of times.

THREE MEMBERS DRIVE THIS RUNNER NOW, AND THE THIRD FOUND THREE MODEL DEFECTS
(2026-09-11). coinxt's wallet gate was the second stack through it; nocloud's
helper gate and holde-em's harness gate are the third and fourth, and the
spellings they write beyond riptide's were promoted here rather than modelled
per gate: `repeat for each char|word|element`, a bare `repeat`, single-chunk
deletes, `split ... by`, `sort` with its options and `by EXPR`, the
first/last-chunk forms, `the number of X in`, `the round of`, `^`, `is in`,
`there is not a`, a scrollbar in `there is`, text ORDERING under `<` and `>`,
and the engine functions in install_engine_functions (toUpper/toLower,
urlDecode, byteOffset, min/max/abs, round, baseConvert, numToCodepoint, a
SEEDED random). What holde-em's harness - engine-proven at 543/0 - found
wrong in the model itself, each a silent wrong answer rather than a refusal:
  - `break` was honoured only at a case arm's top level; nested inside an
    `if` it fell to the unknown-call path, became a CATCHABLE error, and the
    script's own try swallowed it, so the rest of the arm ran (four redial
    attempts in eight ticks). `break` raises _Break from any depth now, and
    `exit repeat` inside a switch is no longer caught by the switch.
  - The millisecond clock started at 1,000,000 beside a 1.7e9 `the
    seconds`, so a turn stamped in milliseconds and judged in seconds was
    1.7 billion seconds old: every play context timed itself out. The two
    clocks are one clock now (World.ms seeds from LCS.SECONDS; `the seconds`
    is ms div 1000).
  - In the base interpreter, `put X into item N of VAR` silently created a
    variable named after the chunk expression (a tampered wire still
    verified), and `the number of lines of X & Y` folded `& Y` into the
    target (the engine counts X alone - root engine notes 2.6). Both are
    fixed in the base, whose header carries the record.

THE SOURCE REWRITES are shared with tools/check-script-vectors.py (imported
from it, not copied), for the same reason with the same discipline: each is
named, counted, and must fire, so a rewrite that stops applying fails the
gate instead of leaving it testing a file nobody ships.

Usage:
  python3 tools/check-demo-boot.py             # per-check detail
  python3 tools/check-demo-boot.py --check     # terse (the gate set)
  python3 tools/check-demo-boot.py --file F    # boot an alternate file
                                               # (the mutation fixtures)
"""
import importlib.util
import math
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
SUITE = os.path.dirname(MEMBER)
DEMO = os.path.join(MEMBER, "examples", "riptide-social.livecodescript")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# The execution gate for the library layer: reused for its REWRITES list,
# its native installers, and the oracle it already loaded and self-checked.
CSV = _load("check_script_vectors", os.path.join(HERE,
                                                 "check-script-vectors.py"))
# ONE interpreter module instance, shared with the installers above. Loading
# a second copy here would give this file its own HASHES table and leave
# every native the reused installers register invisible to it - which is
# exactly how the first run of this gate reported canCrypto false on a
# machine whose natives were all installed.
LCS = CSV.LCS

Thrown = LCS.Thrown


# ==========================================================================
# the engine world
# ==========================================================================

class Control:
    def __init__(self, ctype, name):
        self.ctype = ctype              # "field" | "button" | "graphic"
        self.name = name
        self.props = {}
        self.content = ""
        self.rect = None                # [l, t, r, b] once set


class Card:
    def __init__(self, name):
        self.name = name
        self.controls = []              # creation order

    def find(self, ctype, name):
        low = str(name).lower()
        for c in self.controls:
            if c.ctype == ctype and c.name.lower() == low:
                return c
        return None


class World:
    def __init__(self, sandbox):
        self.stack_name = "Untitled 2"  # the paste ritual's fresh mainstack
        self.stack_props = {}
        self.cards = [Card("card1")]    # a new mainstack has one unnamed card
        self.cur = 0
        self.default_stack = self.stack_name
        self.last_created = {}          # ctype -> Control
        self.sends = []                 # (message-string, delay-ms)
        self.clipboard = {}
        self.result = ""
        self.target = None              # (ctype, name) while a click drives
        self.locked = 0
        # The modeled clock, advanced on ticks. It starts at `the seconds`
        # times 1000 so the two clocks the engine keeps in step ARE in step
        # here: holde-em's liveness layer stamps a turn in milliseconds and
        # judges it in seconds, and with the old 1,000,000 start beside a
        # 1.7e9 `the seconds` every turn was 1.7 billion seconds old - the
        # play context timed itself out the moment a refused timeout arrived
        # (found by holde-em's execution gate, 2026-09-11).
        self.ms = LCS.SECONDS[0] * 1000
        self.sandbox = sandbox
        self.log = []                   # what the model DID (diagnostics)

    # -- cards -------------------------------------------------------------
    def card_named(self, name):
        s = str(name).strip()
        # numeric card addressing (`of card 1`), the engine-proven form the
        # demo's cross-card feed writes use
        if re.fullmatch(r"\d+", s):
            n = int(s)
            return self.cards[n - 1] if 1 <= n <= len(self.cards) else None
        low = s.lower()
        for c in self.cards:
            if c.name.lower() == low:
                return c
        return None

    def current(self):
        return self.cards[self.cur]

    def go_to(self, spec):
        s = str(spec).strip().strip('"')
        if re.fullmatch(r"\d+", s):
            n = int(s)
            if 1 <= n <= len(self.cards):
                self.cur = n - 1
                self.result = ""
                return
            self.result = "No such card"
            return
        c = self.card_named(s)
        if c is None:
            self.result = "No such card"
            return
        self.cur = self.cards.index(c)
        self.result = ""

    # -- controls ----------------------------------------------------------
    def create(self, ctype):
        c = Control(ctype, "")
        self.current().controls.append(c)
        self.last_created[ctype] = c
        return c

    def resolve(self, ctype, name, cardspec=None):
        """None when absent. Unqualified = the CURRENT card (the modeled
        engine rule; see the header)."""
        if cardspec is None:
            return self.current().find(ctype, name)
        card = self.card_named(str(cardspec).strip().strip('"'))
        if card is None:
            return None
        return card.find(ctype, name)

    def anywhere(self, name):
        low = str(name).lower()
        for card in self.cards:
            for c in card.controls:
                if c.name.lower() == low:
                    return c
        return None

    # -- files (sandboxed) -------------------------------------------------
    def path_ok(self, path):
        return os.path.abspath(path).startswith(self.sandbox)

    def special_folder(self, label):
        p = os.path.join(self.sandbox, re.sub(r"\W+", "_", str(label)))
        os.makedirs(p, exist_ok=True)
        return p


# rect helpers: LiveCode rules - `set the top` moves, `set the height`
# resizes around the vertical center, `the bottom` reads the live geometry.
def _rect_set(ctl, prop, value):
    if prop == "rect":
        parts = [int(float(x)) for x in str(value).split(",")]
        if len(parts) == 4:
            ctl.rect = parts
        return
    if ctl.rect is None:
        ctl.rect = [0, 0, 100, 20]
    l, t, r, b = ctl.rect
    v = int(float(value))
    if prop == "top":
        h = b - t
        ctl.rect = [l, v, r, v + h]
    elif prop == "bottom":
        h = b - t
        ctl.rect = [l, v - h, r, v]
    elif prop == "left":
        w = r - l
        ctl.rect = [v, t, v + w, b]
    elif prop == "height":
        c = (t + b) // 2
        ctl.rect = [l, c - v // 2, r, c - v // 2 + v]
    elif prop == "width":
        c = (l + r) // 2
        ctl.rect = [c - v // 2, t, c - v // 2 + v, b]


def _rect_get(ctl, prop):
    if ctl.rect is None:
        return ""
    l, t, r, b = ctl.rect
    return {"rect": "%d,%d,%d,%d" % (l, t, r, b), "left": l, "top": t,
            "right": r, "bottom": b, "width": r - l,
            "height": b - t}.get(prop, "")


RECT_PROPS = ("rect", "left", "top", "right", "bottom", "width", "height")

_OBJ_RE = (r'(?:(field|button|graphic|card)\s+'
           r'("(?:[^"]*)"|\([^)]*\)|[A-Za-z_]\w*)'
           r'(?:\s+of\s+card\s+("(?:[^"]*)"|\([^)]*\)|[A-Za-z_]\w*|\d+))?'
           r'|(this\s+stack|this\s+card|me|the\s+target|'
           r'the\s+last\s+(?:field|button|graphic)))')


# ==========================================================================
# the interpreter subclass
# ==========================================================================

class DemoExpr(LCS._Expr):
    """Adds the engine-expression surface the demo reads."""

    def p_mul(self):
        # `div` and `mod` are real xTalk operators the kit uses; the base
        # models only * and /. Same precedence tier.
        v = self.p_unary()
        while True:
            self.ws()
            if self.i < len(self.s) and self.s[self.i] in "*/":
                op = self.s[self.i]
                self.i += 1
                r = self.p_unary()
                v = LCS._n(v) * LCS._n(r) if op == "*" else LCS._n(v) / LCS._n(r)
                continue
            m = re.match(r'(div|mod)\b', self.s[self.i:], re.I)
            if m:
                self.i += len(m.group(1))
                r = self.p_unary()
                a, b = LCS._n(v), LCS._n(r)
                v = int(a // b) if m.group(1).lower() == "div" else a - b * int(a // b)
                continue
            return v

    def p_cmp(self):
        # The base's comparator, restated with ONE extension: `is [not]
        # among the ITEMS|LINES of` beside the base's keys-of (the demo's
        # persona guard tests a comma list; the LAN layer, lines). Restated
        # rather than delegated because the operand is consumed before the
        # operator is seen, so a partial override cannot hand the tail back
        # to super() without re-parsing a spent operand.
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
                        parts = LCS._split_chunks(str(LCS._disp(target)),
                                                  delim)
                        hit = str(LCS._disp(v)) in parts
                    v = (not hit) if neg else hit
                    continue
                # `X is [not] in Y` - the engine's string membership, the
                # mirror of `Y contains X` (holde-em's onion whitespace test)
                if self.kw("in"):
                    r = self.p_concat()
                    hit = str(LCS._disp(v)) in str(LCS._disp(r))
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
                    # operands that are not BOTH numbers order as TEXT,
                    # case-insensitively (the engine's default; the base
                    # refuses with a ValueError out of _n, which is stricter
                    # than the engine). holde-em breaks a tie on two route
                    # keys with `<`, nocloud on two 64-hex lines (2026-09-11).
                    if LCS._is_numeric(v, False) and LCS._is_numeric(r, False):
                        a, b = LCS._n(v), LCS._n(r)
                    else:
                        a, b = (str(LCS._disp(v)).lower(),
                                str(LCS._disp(r)).lower())
                    v = {">=": a >= b, "<=": a <= b, ">": a > b,
                         "<": a < b, "<>": a != b}[op]
                    break
            else:
                self.i = save
                return v

    def p_unary(self):
        # `^` - exponentiation, one tier above `*`; the base does not model
        # it because coinxt's layer avoids the operator (some OXT parsers
        # reject it inside a compound expression). nocloud writes it
        # parenthesised, `(2 ^ tExp)`, in its login backoff (2026-09-11).
        v = super().p_unary()
        while True:
            self.ws()
            if self.i < len(self.s) and self.s[self.i] == "^":
                self.i += 1
                r = super().p_unary()
                v = LCS._exact(LCS._n(v) ** LCS._n(r))
                continue
            return v

    def p_atom(self):
        world = self.ip.world
        # SKIP LEADING WHITESPACE FIRST. Every branch below matches against
        # `rest` with an anchored regex, so a single leading space makes all
        # of them miss - and the base's own p_atom calls ws() before it looks,
        # so the miss lands as "unsupported `the` expression" about a form
        # this class models perfectly well. It bit on `word 1 of the name of
        # the target`: the word branch's `self.kw("of")` leaves the cursor on
        # the space, and the recursive p_atom then failed to see `the name
        # of ...`. Found 2026-08-31 by coinxt's boot gate on the wallet's
        # click router, which is the first body in this tree to write that
        # combination.
        self.ws()
        rest = self.s[self.i:]

        # `the last|first item|char|line|word of X` - the engine's end-chunk forms
        # (nocloud's leaf and MIME helpers, holde-em's helpers; promoted from
        # nocloud's gate 2026-09-11 when holde-em became the second writer).
        # The target binds tightly - an atom - so `the last char of X is Y`
        # leaves `is Y` to the comparator. `the last <objtype>` (a control
        # reference) is a different form and does not match this regex.
        m = re.match(r'the\s+(last|first)\s+(item|char|line|word)\s+of\s+',
                     rest, re.I)
        if m:
            self.i += m.end()
            last = m.group(1).lower() == "last"
            unit = m.group(2).lower()
            s = str(LCS._disp(self.p_atom()))
            if unit == "char":
                return s[-1:] if last else s[:1]
            if unit == "word":
                w = s.split()
                return (w[-1] if last else w[0]) if w else ""
            delim = (LCS.ITEM_DELIMITER[0] if unit == "item"
                     else LCS.LINE_DELIMITER[0])
            parts = LCS._split_chunks(s, delim)
            return (parts[-1] if last else parts[0]) if parts else ""
        # `the number of bytes IN X` - the base models only `of`; the engine
        # accepts either preposition and the count is the same. `words` is
        # new in both spellings (holde-em's onion section counts them).
        m = (re.match(r'the\s+number\s+of\s+(bytes|chars|characters|items|'
                      r'lines|words)\s+in\s+', rest, re.I)
             or re.match(r'the\s+number\s+of\s+(words)\s+of\s+', rest, re.I))
        if m:
            self.i += m.end()
            unit = m.group(1).lower()
            # a FACTOR, as the base's `of` form binds it (see the base)
            s = str(LCS._disp(self.p_unary()))
            if unit in ("bytes", "chars", "characters"):
                return len(s)
            if unit == "words":
                return len(s.split())
            if unit == "items":
                return len(LCS._split_chunks(s, LCS.ITEM_DELIMITER[0]))
            return len(LCS._split_chunks(s, LCS.LINE_DELIMITER[0]))
        # `the round of X` - half AWAY from zero, the engine's rule (python's
        # round() is banker's and would answer 2 for 2.5). Binds to the atom.
        m = re.match(r'the\s+round\s+of\s+', rest, re.I)
        if m:
            self.i += m.end()
            x = LCS._n(self.p_atom())
            r = math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)
            return LCS._exact(int(r))

        # `there is a|an|no <thing> <expr>` - never throws, answers a boolean
        # IMAGE joined the list on 2026-08-31, with the carried self-check
        # block: scMissing asks about it now, because a demo may build a
        # control the KIT does not (coinxt's wallet paints a QR into one).
        # Without it here every adopter's scMissing walk would die on an
        # unmodelled expression rather than answer.
        # scrollbar joined 2026-09-11 (holde-em's bet slider): no runner
        # builds one, so the answer is "absent", which is what a headless
        # harness run needs to hear
        m = re.match(r'there\s+is\s+(a|an|no|not\s+a|not\s+an)\s+'
                     r'(field|button|graphic|image|scrollbar|card|file|folder)\s+',
                     rest, re.I)
        if m:
            self.i += m.end()
            # `there is no X` and `there is not a X` are the same question
            want_missing = m.group(1).lower() in ("no", "not a", "not an")
            kind = m.group(2).lower()
            # the object-name expression binds tighter than `and`/`of card`
            name = LCS._disp(self.p_concat())
            cardspec = None
            m2 = re.match(r'\s*of\s+card\s+', self.s[self.i:], re.I)
            if m2 and kind in ("field", "button", "graphic", "image"):
                self.i += m2.end()
                cardspec = LCS._disp(self.p_concat())
            if kind == "card":
                exists = world.card_named(name) is not None
            elif kind == "file":
                exists = world.path_ok(name) and os.path.isfile(name)
            elif kind == "folder":
                exists = world.path_ok(name) and os.path.isdir(name)
            else:
                exists = world.resolve(kind, name, cardspec) is not None
            return (not exists) if want_missing else exists

        # `the <adjective>? <prop> of <object>`
        m = re.match(r'the\s+(?:(short|long|abbreviated)\s+)?(\w+)\s+of\s+'
                     + _OBJ_RE, rest, re.I)
        if m:
            self.i += m.end()
            return self.ip.obj_prop_get(m, self)

        # `the number of cards of this stack` (scMissing's card walk)
        m = re.match(r'the\s+number\s+of\s+cards\s+of\s+this\s+stack\b',
                     rest, re.I)
        if m:
            self.i += m.end()
            return len(world.cards)

        # bare engine `the` constants the demo reads
        m = re.match(r'the\s+(platform|milliseconds|millisecs|seconds|result|'
                     r'target)\b', rest, re.I)
        if m:
            word = m.group(1).lower()
            self.i += m.end()
            if word == "platform":
                return "Win32"
            if word in ("milliseconds", "millisecs"):
                return world.ms
            if word == "seconds":
                # derived from the same clock as the milliseconds (see
                # World.__init__), never the base's fixed constant alone
                return world.ms // 1000
            if word == "result":
                return world.result
            # `the target` bare: the long-ish reference of the clicked control
            if world.target is None:
                raise Thrown("Chunk: no target found")
            return '%s "%s"' % world.target

        # `field <expr> [of card <expr>]` as a VALUE (content read)
        m = re.match(r'(field|button)\s+', rest, re.I)
        if m:
            save = self.i
            self.i += m.end()
            kind = m.group(1).lower()
            try:
                name = LCS._disp(self.p_concat())
            except Exception:
                self.i = save
                return super().p_atom()
            cardspec = None
            m2 = re.match(r'\s*of\s+card\s+', self.s[self.i:], re.I)
            if m2:
                self.i += m2.end()
                cardspec = LCS._disp(self.p_concat())
            ctl = world.resolve(kind, name, cardspec)
            if ctl is None:
                raise Thrown('Chunk: no such object (%s "%s")' % (kind, name))
            return ctl.content if kind == "field" else ctl.props.get("label", "")

        # bare engine globals read as `the <name>`
        m = re.match(r'the\s+defaultStack\b', rest, re.I)
        if m:
            self.i += m.end()
            return world.default_stack

        # the WORD chunk, which the base does not model (its corpus never
        # uses it; this demo splits relay urls and pasted keys with it).
        # Engine rule: words are runs separated by spaces/tabs/returns.
        unit = self.kw("word", "words")
        if unit:
            a = self.p_add()
            b = None
            if self.kw("to"):
                b = self.p_add()
            assert self.kw("of"), "expected `of` in %r" % self.s
            target = self.p_atom()
            words = str(LCS._disp(target)).split()
            n = len(words)
            ai = int(LCS._n(a))
            ai = n + 1 + ai if ai < 0 else ai
            if b is None:
                return words[ai - 1] if 1 <= ai <= n else ""
            bi = int(LCS._n(b))
            bi = n + 1 + bi if bi < 0 else bi
            return " ".join(words[max(ai, 1) - 1:bi])

        # `url ("binfile:" & ...)` as a VALUE
        m = re.match(r'url\s+', rest, re.I)
        if m:
            self.i += m.end()
            spec = str(LCS._disp(self.p_concat()))
            return self.ip.url_read(spec)

        try:
            return super().p_atom()
        except NameError as e:
            # engine-faithful: calling a MISSING handler is a catchable
            # script error, and it is exactly what the capability probes
            # catch on a machine without an extension
            raise Thrown("Handler: can't find handler (%s)" % e)


class _Break(Exception):
    """`break`: leave the enclosing switch. Not a Thrown, so a script's own
    try/catch cannot swallow it (the engine's break is control flow, not an
    error), and not an _Exit, so a repeat around the switch keeps looping."""


class DemoInterp(LCS.Interp):
    def __init__(self, src, world):
        self.world = world
        super().__init__(src)

    def eval_expr(self, expr, env):
        return DemoExpr(self, env).parse(expr)

    # -- object property access -------------------------------------------
    def _objref(self, m, exprobj):
        """Resolve the _OBJ_RE groups of a matched object reference. The
        name group may be a quoted literal, a parenthesised expression, or
        an identifier - evaluate it like the engine does."""
        world = self.world
        def ev(tok):
            return str(LCS._disp(exprobj.ip.eval_expr(tok, exprobj.env)))
        kind, name, cardspec, special = m.group(3), m.group(4), m.group(5), m.group(6)
        if special is not None:
            s = re.sub(r'\s+', ' ', special.lower())
            if s == "this stack":
                return ("stack", None)
            if s == "this card":
                return ("card", world.current())
            if s == "me":
                return ("stack", None)      # a stack script: me IS the stack
            if s == "the target":
                if world.target is None:
                    raise Thrown("Chunk: no target found")
                ctl = world.anywhere(world.target[1])
                return ("control", ctl)
            if s.startswith("the last "):
                ctype = s.rsplit(" ", 1)[1]
                ctl = world.last_created.get(ctype)
                if ctl is None:
                    raise Thrown("Chunk: no such object (last %s)" % ctype)
                return ("control", ctl)
        name_v = ev(name)
        if kind.lower() == "card":
            card = world.card_named(name_v)
            if card is None:
                raise Thrown('Chunk: no such object (card "%s")' % name_v)
            return ("card", card)
        cs = ev(cardspec) if cardspec else None
        ctl = world.resolve(kind.lower(), name_v, cs)
        if ctl is None:
            raise Thrown('Chunk: no such object (%s "%s")'
                         % (kind.lower(), name_v))
        return ("control", ctl)

    def obj_prop_get(self, m, exprobj):
        world = self.world
        adjective, prop = (m.group(1) or "").lower(), m.group(2).lower()
        kind, obj = self._objref(m, exprobj)
        if kind == "stack":
            if prop == "name":
                return ("stack " + world.stack_name if adjective == "long"
                        else world.stack_name)
            if prop == "id":
                return 'stack "%s"' % world.stack_name
            return world.stack_props.get(prop, "")
        if kind == "card":
            if prop == "name":
                return obj.name
            return ""
        # control
        if prop == "name":
            # THE ADJECTIVE DECIDES. `the SHORT name` of a control is its bare
            # name; `the name` (and `the long name`, and `the abbreviated
            # name`) begin with the control's TYPE - `button "nv_wl"` - which
            # is what lets a click router ask `word 1 of the name of the
            # target` whether a button or a field was clicked. Modelled as the
            # short name in every case, that router silently answered "not a
            # button" for every click and passed the message on, so a gate
            # driving clicks would have reported a green routing pass over a
            # stack where nothing routed. coinxt's wallet is the first body in
            # this tree to write the unqualified form.
            if adjective == "short":
                return obj.name
            if adjective == "long":
                return '%s "%s" of card "%s" of stack "%s"' % (
                    obj.ctype, obj.name, world.current().name,
                    world.stack_name)
            return '%s "%s"' % (obj.ctype, obj.name)
        if prop == "id":
            return '%s "%s"' % (obj.ctype, obj.name)
        if prop == "formattedheight":
            return 14
        if prop in RECT_PROPS:
            return _rect_get(obj, prop)
        return obj.props.get(prop, "")

    def obj_prop_set(self, m, value, env):
        world = self.world
        prop = m.group(1).lower()
        fake = DemoExpr(self, env)
        kind, obj = self._objref(_reshift(m), fake)
        if kind == "stack":
            world.stack_props[prop] = value
            return
        if kind == "card":
            if prop == "name":
                obj.name = str(value)
            return
        if prop == "name":
            obj.name = str(value)
            return
        if prop in RECT_PROPS:
            _rect_set(obj, prop, value)
            return
        obj.props[prop] = value

    # -- url + sends --------------------------------------------------------
    def url_read(self, spec):
        m = re.match(r'(?:binfile|file):(.*)$', spec)
        if not m:
            raise Thrown("url: unmodeled scheme " + spec)
        path = m.group(1)
        if not self.world.path_ok(path):
            raise Thrown("url: path outside the sandbox " + path)
        if not os.path.isfile(path):
            return ""
        with open(path, "rb") as fh:
            return fh.read().decode("latin-1")

    def url_write(self, spec, data):
        m = re.match(r'(?:binfile|file):(.*)$', spec)
        if not m:
            raise Thrown("url: unmodeled scheme " + spec)
        path = m.group(1)
        if not self.world.path_ok(path):
            raise Thrown("url: path outside the sandbox " + path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(str(data).encode("latin-1"))

    def deliver_sends(self, rounds=6):
        """Deliver queued `send ... in N ms` messages. Bounded: a message
        that re-arms itself (raPoll) is delivered at most `rounds` times."""
        delivered = []
        for _ in range(rounds):
            if not self.world.sends:
                break
            batch, self.world.sends = self.world.sends, []
            for msg, delay in batch:
                self.world.ms += max(1, int(delay))
                name = msg.split()[0]
                rest = msg[len(name):].strip()
                args = []
                if rest:
                    p = DemoExpr(self, {})
                    p.s, p.i = rest, 0
                    while True:
                        args.append(p.p_or())
                        p.ws()
                        if p.i < len(p.s) and p.s[p.i] == ",":
                            p.i += 1
                            continue
                        break
                delivered.append(name)
                self.call(name, args)
        return delivered

    # -- statements ---------------------------------------------------------
    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        low = line.lower()
        world = self.world

        # ---- switch (absent from the base; mouseUp and raAppLoad use it)
        if low.startswith("switch"):
            return self._exec_switch(body, i, env)
        # `break` leaves the ENCLOSING switch from any depth - inside an `if`
        # in a case arm as much as at the arm's top level. Until 2026-09-11
        # only a top-level `break` was honoured: a nested one fell through
        # to the unknown-call path, became a CATCHABLE script error, and
        # holde-em's onion tick (`if wait > 0 then break end if`) swallowed
        # it in its own try and ran the rest of the arm - four redial
        # attempts in eight ticks instead of one. Found by holde-em's
        # execution gate.
        if low == "break":
            raise _Break()

        # ---- repeat for each key/element/line/char/word (absent from the
        # base, which models `item` alone). The engine iterates a SNAPSHOT
        # of the container, so the list is built before the first pass.
        # char and word joined 2026-09-11 (nocloud's sanitisers, holde-em's
        # evaluator harness), element the same day (holde-em).
        m = re.match(r'repeat\s+for\s+each\s+(key|element|line|char|word)'
                     r'\s+(\w+)\s+in\s+(.+)$', line, re.I)
        if m:
            kind, var = m.group(1).lower(), m.group(2).lower()
            inner, after = self._block(body, i, None, None)
            src = self.eval_expr(m.group(3), env)
            if kind == "key":
                items = list(src.keys()) if isinstance(src, dict) else []
            elif kind == "element":
                items = ([LCS._copy(x) for x in src.values()]
                         if isinstance(src, dict) else [])
            elif kind == "char":
                items = list(str(LCS._disp(src)))
            elif kind == "word":
                items = str(LCS._disp(src)).split()
            else:
                items = LCS._split_chunks(str(LCS._disp(src)),
                                          LCS.LINE_DELIMITER[0])
            for it in items:
                env[var] = it
                try:
                    self._exec(inner, env)
                except LCS._Next:
                    pass
                except LCS._Exit:
                    break
            return after

        # ---- a bare `repeat` is the engine's `repeat forever`; the base's
        # runaway guard applies, because an interpreter that can hang is one
        # whose failures nobody reads (nocloud's template renderer, 2026-09-11)
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

        # ---- single-chunk deletes: `delete [the] last char|item|line|word
        # of X`, `delete char|item|line N of X` (N may be negative, counted
        # from the end). The base models only `delete char A to B of X`.
        # Deleting an item or a line takes ONE adjacent delimiter with it,
        # which is what makes `delete line 1 of sQueue` a queue pop; the
        # engine's one-ignored-trailing-delimiter rule is applied when the
        # index is resolved, as the base's chunk reader applies it.
        m = (re.match(r'delete\s+(?:the\s+)?last\s+(char|item|line|word)'
                      r'\s+of\s+(\w+)$', line, re.I)
             or re.match(r'delete\s+(char|item|line)\s+(.+?)\s+of\s+(\w+)$',
                         line, re.I))
        if m and not re.search(r'\s+to\s+', m.group(2) if m.lastindex == 3
                                else ""):
            if m.lastindex == 2:
                unit, n_expr, tgt = m.group(1).lower(), None, m.group(2)
            else:
                unit, n_expr, tgt = (m.group(1).lower(), m.group(2),
                                     m.group(3))
            s = str(LCS._disp(self.eval_expr(tgt, env)))
            if unit == "char":
                n = -1 if n_expr is None else int(LCS._n(self.eval_expr(n_expr, env)))
                if n < 0:
                    n = len(s) + 1 + n
                if 1 <= n <= len(s):
                    s = s[:n - 1] + s[n:]
            elif unit == "word":
                w = s.split()
                if w:
                    w.pop()
                s = " ".join(w)
            else:
                d = (LCS.ITEM_DELIMITER[0] if unit == "item"
                     else LCS.LINE_DELIMITER[0])
                raw = s.split(d)
                trailing = len(raw) > 1 and raw[-1] == ""
                count = len(raw) - (1 if trailing else 0)
                n = -1 if n_expr is None else int(LCS._n(self.eval_expr(n_expr, env)))
                if n < 0:
                    n = count + 1 + n
                if 1 <= n <= count:
                    del raw[n - 1]
                    s = d.join(raw)
            self.assign(tgt, s, env)
            return i + 1

        # ---- sort lines|items of VAR [ascending|descending] [numeric|text]
        # [by EXPR]: the base models the bare `sort lines of VAR` only.
        # The option words come in any order (holde-em writes both `numeric
        # descending` and `ascending numeric`); `by EXPR` evaluates EXPR once
        # per element with `each` bound to it. Stable, as the engine's is;
        # text keys fold case (the engine default); international collation
        # is not modelled (every sorted list in the corpus is ASCII).
        m = re.match(r'sort\s+(lines|items)\s+of\s+(\w+)((?:\s+(?:ascending|'
                     r'descending|numeric|text|international|datetime))*)'
                     r'(?:\s+by\s+(.+))?$', line, re.I)
        if m:
            unit, tgt = m.group(1).lower(), m.group(2)
            opts = m.group(3).lower().split()
            by = m.group(4)
            d = (LCS.ITEM_DELIMITER[0] if unit == "items"
                 else LCS.LINE_DELIMITER[0])
            s = str(LCS._disp(self.eval_expr(tgt, env)))
            parts = LCS._split_chunks(s, d)
            numeric = "numeric" in opts

            def key_of(part):
                if by is None:
                    k = part
                else:
                    env["each"] = part
                    k = LCS._disp(self.eval_expr(by, env))
                if numeric:
                    return LCS._n(k) if LCS._is_numeric(k, False) else 0
                return str(k).lower()
            parts.sort(key=key_of, reverse="descending" in opts)
            env.pop("each", None)
            self.assign(tgt, d.join(parts), env)
            return i + 1

        # ---- split VAR by A [and B]: the container becomes an array. With
        # one delimiter the keys are 1..n; with two, each A-part is split at
        # its first B into key and value (holde-em's wire bodies, 2026-09-11)
        m = re.match(r'split\s+(\w+)\s+by\s+(.+?)(?:\s+and\s+(.+))?$', line,
                     re.I)
        if m:
            tgt = m.group(1)
            s = str(LCS._disp(self.eval_expr(tgt, env)))
            a = str(LCS._disp(self.eval_expr(m.group(2), env)))
            out = {}
            if s != "":
                parts = s.split(a) if a else [s]
                if m.group(3) is None:
                    for k, part in enumerate(parts):
                        out[str(k + 1)] = part
                else:
                    b = str(LCS._disp(self.eval_expr(m.group(3), env)))
                    for part in parts:
                        k, _sep, val = part.partition(b)
                        out[k] = val
            self.assign(tgt, out, env)
            return i + 1

        # ---- repeat N times (absent from the base; the base32 layer uses it)
        m = re.match(r'repeat\s+(.+?)\s+times$', line, re.I)
        if m:
            inner, after = self._block(body, i, None, None)
            count = int(LCS._n(self.eval_expr(m.group(1), env)))
            for _ in range(max(0, count)):
                try:
                    self._exec(inner, env)
                except LCS._Next:
                    pass
                except LCS._Exit:
                    break
            return after

        # ---- create / go / lock / screen furniture
        if low == "create card":
            world.cards.append(Card("card%d" % (len(world.cards) + 1)))
            world.cur = len(world.cards) - 1
            return i + 1
        m = re.match(r'create\s+(field|button|graphic)\s*$', line, re.I)
        if m:
            world.create(m.group(1).lower())
            return i + 1
        m = re.match(r'create\s+folder\s+(.+)$', line, re.I)
        if m:
            path = str(LCS._disp(self.eval_expr(m.group(1), env)))
            if not world.path_ok(path):
                raise Thrown("create folder: outside the sandbox " + path)
            os.makedirs(path, exist_ok=True)
            return i + 1
        m = re.match(r'go\s+to\s+card\s+(.+)$', line, re.I)
        if m:
            world.go_to(LCS._disp(self.eval_expr(m.group(1), env)))
            return i + 1
        if low in ("lock screen", "unlock screen"):
            world.locked += 1 if low == "lock screen" else -1
            return i + 1
        m = re.match(r'(hide|show)\s+(field|button|graphic)\s+(.+)$', line,
                     re.I)
        if m:
            name = str(LCS._disp(self.eval_expr(m.group(3), env)))
            ctl = world.resolve(m.group(2).lower(), name)
            if ctl is None:
                raise Thrown('Chunk: no such object (%s "%s")'
                             % (m.group(2).lower(), name))
            ctl.props["visible"] = m.group(1).lower() == "show"
            return i + 1

        # ---- engine globals the script sets around strict compares
        m = re.match(r'set\s+the\s+caseSensitive\s+to\s+(.+)$', line, re.I)
        if m:
            # tracked only: the base interpreter's `is` is already
            # case-SENSITIVE (its named divergence), so both settings are
            # modeled by the stricter behaviour
            world.stack_props["casesensitive"] = self.eval_expr(m.group(1),
                                                                env)
            return i + 1

        # ---- set the <prop> of <obj> / defaultStack / clipboard
        m = re.match(r'set\s+the\s+defaultStack\s+to\s+(.+)$', line, re.I)
        if m:
            world.default_stack = str(LCS._disp(self.eval_expr(m.group(1),
                                                               env)))
            return i + 1
        m = re.match(r'set\s+the\s+clipboardData\[(.+?)\]\s+to\s+(.+)$',
                     line, re.I)
        if m:
            key = str(LCS._disp(self.eval_expr(m.group(1), env)))
            world.clipboard[key] = self.eval_expr(m.group(2), env)
            return i + 1
        m = re.match(r'set\s+the\s+(\w+)\s+of\s+' + _OBJ_RE + r'\s+to\s+(.+)$',
                     line, re.I)
        if m and m.group(1).lower() not in ("itemdelimiter", "linedelimiter"):
            # groups: 1 prop, 2-5 the object reference, 6 the value
            value = self.eval_expr(m.group(6), env)
            self.obj_prop_set(m, value, env)
            return i + 1

        # ---- put into engine containers (fields, url, msg)
        # STRING-AWARE (2026-08-31), through the interpreter's own helper:
        # a non-greedy regex splits inside a literal that happens to contain
        # the word `into`, which leaves an unterminated string as the value
        # expression. See LCS.split_outside_strings for the case that found it.
        parts = (LCS.split_outside_strings(line[4:],
                                           ("into", "after", "before"))
                 if re.match(r'put\s', line, re.I) else None)
        if parts and re.match(r'(field\s+.+|url\s*\(.+\)|url\s+.+|msg)$',
                              parts[2].strip(), re.I):
            value = self.eval_expr(parts[0], env)
            prep, tgt = parts[1], parts[2].strip()
            if tgt.lower() == "msg":
                world.log.append("msg: " + str(LCS._disp(value)))
                return i + 1
            if tgt.lower().startswith("url"):
                spec = str(LCS._disp(self.eval_expr(tgt[3:].strip(), env)))
                if prep != "into":
                    raise Thrown("url: only `into` is modeled")
                self.url_write(spec, LCS._disp(value))
                return i + 1
            # field target
            m2 = re.match(r'field\s+(.+?)(?:\s+of\s+card\s+(.+))?$', tgt,
                          re.I)
            name = str(LCS._disp(self.eval_expr(m2.group(1), env)))
            cardspec = None
            if m2.group(2):
                cardspec = str(LCS._disp(self.eval_expr(m2.group(2), env)))
            ctl = world.resolve("field", name, cardspec)
            if ctl is None:
                raise Thrown('Chunk: no such object (field "%s")' % name)
            v = str(LCS._disp(value))
            if prep == "into":
                ctl.content = v
            elif prep == "after":
                ctl.content = ctl.content + v
            else:
                ctl.content = v + ctl.content
            return i + 1

        # ---- send ... to me in N <unit>
        m = re.match(r'send\s+(.+?)\s+to\s+me\s+in\s+(.+?)\s*'
                     r'(milliseconds|millisecs|ms|seconds|ticks)$', line,
                     re.I)
        if m:
            msg = str(LCS._disp(self.eval_expr(m.group(1), env)))
            delay = LCS._n(self.eval_expr(m.group(2), env))
            unit = m.group(3).lower()
            if unit == "seconds":
                delay *= 1000
            elif unit == "ticks":
                delay *= 1000 / 60.0
            world.sends.append((msg, delay))
            return i + 1

        # ---- delete a control (the upgrade path's raBuildResetCard)
        m = re.match(r'delete\s+(field|button|graphic)\s+(.+)$', line, re.I)
        if m:
            name = str(LCS._disp(self.eval_expr(m.group(2), env)))
            ctl = world.resolve(m.group(1).lower(), name)
            if ctl is None:
                raise Thrown('Chunk: no such object (%s "%s")'
                             % (m.group(1).lower(), name))
            world.current().controls.remove(ctl)
            return i + 1

        # ---- delete variable (array-element teardown)
        m = re.match(r'delete\s+variable\s+(\w+)\[(.+)\]$', line, re.I)
        if m:
            name = m.group(1).lower()
            key = str(LCS._disp(self.eval_expr(m.group(2), env)))
            store = env if name in env else self.globals
            if isinstance(store.get(name), dict):
                store[name].pop(key, None)
            return i + 1

        # ---- pass <message> (the model does not re-dispatch)
        m = re.match(r'pass\s+\w+$', line, re.I)
        if m:
            raise LCS._Return("")

        # ---- the two SodiumXT keypair COMMANDS, which return through OUT
        # parameters - a shape no expression-position native can model, and
        # the reason check-script-vectors ships a shim for rsIdentityKeys.
        # Here the engine statement is modeled instead, oracle-backed, and
        # the modeled secret is the 32-byte SEED (the named divergence: every
        # in-model consumer hands it back to natives that expect the seed).
        # The seed is an EXPRESSION (holde-em passes `heHash32(...)` inline;
        # riptide passes a variable), the two out-parameters are names.
        m = re.match(r'(sxSignKeypairFromSeed|sxKeyExchangeKeypairFromSeed)'
                     r'\s+(.+?)\s*,\s*(\w+)\s*,\s*(\w+)\s*$', line, re.I)
        if m:
            seed = str(LCS._disp(self.eval_expr(m.group(2), env))
                       ).encode("latin-1")
            if len(seed) != 32:
                raise Thrown("SodiumXT: the seed must be 32 bytes")
            if m.group(1).lower().startswith("sxsign"):
                pub = CSV.REF["ed25519_publickey"](seed)
            else:
                pub, _sk = CSV.REF["kx_seed_keypair"](seed)
            self.assign(m.group(3), pub.decode("latin-1"), env)
            self.assign(m.group(4), seed.decode("latin-1"), env)
            return i + 1

        # ---- statement-position handler calls, with THIS class's expression
        # parser. The base handles these too, but builds its own _Expr for
        # the arguments - which cannot see the engine expressions this file
        # adds, so `nxrInit the long id of me` would die on the argument.
        m = re.match(r'([A-Za-z_]\w*)\s*(.*)$', line)
        if m and m.group(1).lower() in self.handlers:
            args = []
            rest = m.group(2).strip()
            if rest:
                p = DemoExpr(self, env)
                p.s, p.i = rest, 0
                while True:
                    args.append(p.p_or())
                    p.ws()
                    if p.i < len(p.s) and p.s[p.i] == ",":
                        p.i += 1
                        continue
                    break
                if p.i < len(p.s):
                    raise SyntaxError("trailing input in call %r" % line)
            self.call(m.group(1), args)
            return i + 1

        # ---- wait (never legitimate on the paths this gate drives)
        if low.startswith("wait "):
            raise Thrown("wait: the boot model refuses blocking waits")

        try:
            return super()._exec_stmt(body, i, env)
        except SyntaxError as e:
            # A statement-shaped call to a handler that does not exist is a
            # CATCHABLE script error on the engine, and the capability
            # probes depend on that. Only convert clean call shapes; a
            # genuinely unmodeled construct stays a loud harness failure.
            m = re.match(r'^([A-Za-z]\w*)(\s+.*)?$', line)
            if (m and "unsupported statement" in str(e)
                    and m.group(1).lower() not in self.handlers
                    and not re.match(r'(if|else|end|repeat|switch|case|'
                                     r'default|break|try|catch|return|exit|'
                                     r'next|put|set|get|add|delete|create|'
                                     r'go|send|local|constant|global|throw|'
                                     r'pass|hide|show|lock|unlock|sort|'
                                     r'replace|multiply|subtract|divide|'
                                     r'wait|answer|ask|do)$',
                                     m.group(1), re.I)):
                raise Thrown("Handler: can't find handler: " + m.group(1))
            raise

    def _exec_switch(self, body, i, env):
        header = body[i].strip()
        m = re.match(r'switch\s*(.*)$', header, re.I)
        subject_expr = m.group(1).strip()
        # collect to the matching `end switch`, counting nested switches
        depth, j, inner = 0, i + 1, []
        while j < len(body):
            s = body[j].strip().lower()
            if s.startswith("switch"):
                depth += 1
            elif re.match(r'^end\s+switch\b', s):
                if depth == 0:
                    break
                depth -= 1
            inner.append(body[j])
            j += 1
        else:
            raise SyntaxError("unterminated switch")
        after = j + 1
        subject = (self.eval_expr(subject_expr, env)
                   if subject_expr else None)
        # split the top level into (case-exprs, stmts) arms; nested blocks
        # keep their own case-free structure by depth tracking
        arms, cur_conds, cur_stmts, depth = [], [], [], 0
        for ln in inner:
            s = ln.strip()
            slow = s.lower()
            if re.match(r'^(if\b.*\bthen$|repeat\b|try\b|switch\b)', slow):
                depth += 1
            elif re.match(r'^end\s+(if|repeat|try|switch)\b', slow):
                depth -= 1
            if depth == 0 and slow.startswith("case "):
                if cur_stmts:
                    arms.append((cur_conds, cur_stmts))
                    cur_conds, cur_stmts = [], []
                cur_conds.append(s[5:].strip())
                continue
            if depth == 0 and slow == "default":
                if cur_stmts or cur_conds:
                    arms.append((cur_conds, cur_stmts))
                cur_conds, cur_stmts = [None], []
                continue
            cur_stmts.append(ln)
        if cur_conds or cur_stmts:
            arms.append((cur_conds, cur_stmts))
        # find the matching arm, then run with FALLTHROUGH until break
        start = None
        for idx, (conds, _stmts) in enumerate(arms):
            for c in conds:
                if c is None:
                    start = idx if start is None else start
                    continue
                v = self.eval_expr(c, env)
                if subject is None:
                    if self.truth(v):
                        start = idx
                        break
                elif LCS._eq(subject, v):
                    start = idx
                    break
            if start == idx:
                break
        if start is None:
            # no case matched and no default
            return after
        # Arms fall through until a `break` is RAISED (from any depth); an
        # `exit repeat` inside an arm belongs to the enclosing repeat and is
        # deliberately NOT caught here (it used to be, which turned an exit
        # from a loop into an exit from the switch alone).
        try:
            for _conds, stmts in arms[start:]:
                self._exec(stmts, env)
        except _Break:
            pass
        return after


def _reshift(m):
    """obj_prop_set matched `set the PROP of <OBJ> to ...` where _OBJ_RE's
    groups start at index 2; obj_prop_get / _objref expect them starting at
    index 3 (after adjective+prop). Reindex via a tiny shim object."""
    class Shim:
        def group(self, n):
            return m.group(n - 1)
    return Shim()


# ==========================================================================
# natives and profiles
# ==========================================================================

def install_engine_functions(world):
    """Engine FUNCTIONS the base does not model, for every stack this
    runner drives (promoted from nocloud's gate 2026-09-11, when holde-em
    became the second writer of most of them). `random(n)` is the engine's
    1..n draw over a SEEDED generator on the world, so a run is reproducible
    and a gate that reads it cannot flake; min/max take numbers or one
    comma list, as the engine does."""
    import random as _random
    from urllib.parse import unquote_plus
    world.rng = _random.Random(20260911)

    def _s(a):
        return str(LCS._disp(a[0]))

    def _nums(a):
        if len(a) == 1 and not isinstance(a[0], (int, float)):
            return [LCS._n(x) for x in LCS._split_chunks(_s(a), LCS.ITEM_DELIMITER[0])]
        return [LCS._n(x) for x in a]

    LCS.HASHES.update({
        "toupper": lambda a: _s(a).upper(),
        "tolower": lambda a: _s(a).lower(),
        # the engine's urlDecode turns '+' into a space as well as %xx
        "urldecode": lambda a: unquote_plus(_s(a)),
        "byteoffset": lambda a: str(LCS._disp(a[1])).find(_s(a)) + 1,
        "min": lambda a: LCS._exact(min(_nums(a))),
        "max": lambda a: LCS._exact(max(_nums(a))),
        "abs": lambda a: LCS._exact(abs(LCS._n(a[0]))),
        "numtocodepoint": lambda a: chr(int(LCS._n(a[0]))),
        "codepointtonum": lambda a: ord(_s(a)[0]) if _s(a) else "",
        "random": lambda a: world.rng.randint(1, max(1, int(LCS._n(a[0])))),
        # round(x[, digits]) - half AWAY from zero, like `the round of`
        "round": lambda a: _round_away(LCS._n(a[0]),
                                       int(LCS._n(a[1])) if len(a) > 1 else 0),
        # baseConvert(n, from, to): the engine answers hex digits UPPERCASE
        "baseconvert": lambda a: _base_convert(_s(a), int(LCS._n(a[1])),
                                               int(LCS._n(a[2]))),
    })


def _round_away(x, digits):
    scale = 10 ** digits
    y = x * scale
    r = math.floor(y + 0.5) if y >= 0 else math.ceil(y - 0.5)
    return LCS._exact(int(r)) if digits == 0 else r / scale


def _base_convert(text, base_from, base_to):
    n = int(str(text).strip(), base_from)
    if base_to == 10:
        return LCS._exact(n)
    digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    neg = n < 0
    n = abs(n)
    out = ""
    while n:
        out = digits[n % base_to] + out
        n //= base_to
    return ("-" if neg else "") + (out or "0")


def install_common(world):
    CSV.install_pure_natives()
    install_engine_functions(world)
    import hashlib

    def to_str(b):
        return b.decode("latin-1")

    def to_bytes(s):
        return str(s).encode("latin-1")

    LCS.HASHES.update({
        "specialfolderpath":
            lambda a: world.special_folder(LCS._disp(a[0])),
        "sxsha3_256":
            lambda a: to_str(hashlib.sha3_256(to_bytes(a[0])).digest()),
        "sha1digest":
            lambda a: to_str(hashlib.sha1(to_bytes(a[0])).digest()),
        "sxpwhash":
            lambda a: to_str(hashlib.blake2b(
                to_bytes(a[0]) + to_bytes(a[1]), digest_size=int(LCS._n(a[2]))
            ).digest()),
        "sxpwmeminteractive": lambda a: 33554432,
    })


ABSENT = "the extension is not installed on this modeled machine"


def install_profile(profile):
    """MIN = a SodiumXT-only machine (CoinXT absent, so the Nostr rail and
    the coin-backed SHA3 fallback are both off; sxSha3_256 still serves).
    FULL = every extension present but INERT - version probes answer,
    nothing else is modeled, so any deeper call is a loud failure instead
    of a silent fake success."""
    for name in ("btlasterror", "oxversion", "dclibraryversion",
                 "enlibraryversion", "cxsha3_256len", "btstartsession"):
        LCS.HASHES.pop(name, None)
    if profile == "FULL":
        CSV.install_coin_natives()
        LCS.HASHES.update({
            "btlasterror": lambda a: "",
            "oxversion": lambda a: "OnionXT 1.0",
            "dclibraryversion": lambda a: "0.24.5",
            "enlibraryversion": lambda a: "1.3.18",
            "cxsha3_256len": lambda a: 32,
        })
    else:
        for name in list(LCS.HASHES):
            if name.startswith("cx"):
                del LCS.HASHES[name]


# ==========================================================================
# the checks
# ==========================================================================

class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.n = 0
        self.failed = 0

    def note(self, text):
        if not self.terse:
            print("-- %s" % text)

    def info(self, text):
        print("  info %s" % text)

    def ck(self, label, ok, detail=""):
        self.n += 1
        if ok:
            if not self.terse:
                print("  ok   %s" % label)
        else:
            self.failed += 1
            # str(): a detail is whatever the caller had to hand, and a
            # tuple or a list here used to raise INSIDE the report of a
            # failing check - so the one thing that had gone wrong was
            # replaced by a traceback about printing it. Found by coinxt's
            # Core block, 2026-09-04.
            print("  FAIL %s%s" % (label, ("\n       " + str(detail)) if detail
                                   else ""))


_CONST_LIT = re.compile(r'^(?:"[^"]*"|[-+]?\d+(?:\.\d+)?|true|false|empty)$',
                        re.I)


def _refuse_nonliteral_constants(src, fail):
    """The ENGINE's rule, applied before parsing: a constant takes a
    LITERAL, and one expression value kills the whole one-unit compile.
    The interpreter underneath is LOOSER - it happily evaluates the
    expression - so without this the boot gate would greenlight the exact
    2026-08-29 compile-killer. Mirrors the family checker's rule 22
    (string-aware comma split and all), because a boot gate that models
    compilation must refuse what the compiler refuses."""
    for lineno, line in enumerate(src.split("\n"), 1):
        code = line.split("--", 1)[0]
        m = re.match(r'^\s*constant\s+(.+)$', code)
        if not m:
            continue
        parts, buf, instr = [], "", False
        for ch in m.group(1):
            if ch == '"':
                instr = not instr
                buf += ch
            elif ch == "," and not instr:
                parts.append(buf)
                buf = ""
            else:
                buf += ch
        parts.append(buf)
        for part in parts:
            part = part.strip()
            if "=" not in part:
                continue
            name, _, value = part.partition("=")
            if not _CONST_LIT.match(value.strip()):
                fail("line %d: constant `%s` has a non-literal value %r - "
                     "the engine refuses to COMPILE this, and a "
                     ".livecodescript is one unit, so the whole stack goes "
                     "dark" % (lineno, name.strip(), value.strip()[:60]))


def build_source(path, fail):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    src = re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', src, count=1)
    _refuse_nonliteral_constants(src, fail)
    if re.search(r'^\s*if .+ then .+ else ', src, re.M):
        fail("a one-line `if ... then ... else ...` appeared; the one-line "
             "rewrite would drop its else branch")
    hits = dict((name, 0) for name, _w, _f in CSV.REWRITES)
    out = []
    for line in src.split("\n"):
        for name, _w, fn in CSV.REWRITES:
            new = fn(line)
            if new != line:
                hits[name] += 1
                line = new
        out.append(line)
    for name, why, _f in CSV.REWRITES:
        if hits[name] == 0:
            fail("the shared rewrite %r matched nothing (%s) - it has gone "
                 "stale against this file" % (name, why))
    return "\n".join(out), hits


def _bool(v):
    """The modeled `enabled` value as a Python bool, or None when unset."""
    if isinstance(v, bool):
        return v
    if str(v).lower() in ("true", "false"):
        return str(v).lower() == "true"
    return None


def expected_cards(src):
    """The named cards the source itself builds - self-deriving, so a new
    card enters the expectation the day its builder lands."""
    return sorted(set(re.findall(
        r'set the name of this card to "(\w+)"', src)))


def boot(c, path, profile, drive=True):
    sandbox = tempfile.mkdtemp(prefix="riptide-boot-")
    world = World(sandbox)
    failures_before = c.failed

    def fail(msg):
        print("check-demo-boot: %s" % msg)
        sys.exit(1)

    try:
        src, _hits = build_source(path, fail)
        try:
            ip = DemoInterp(src, world)
        except Exception as exc:                        # noqa: BLE001
            c.ck("[%s] the stack script parses" % profile, False,
                 "%s: %s" % (type(exc).__name__, exc))
            return
        c.ck("[%s] the stack script parses (%d handlers)"
             % (profile, len(ip.handlers)), True)

        install_common(world)
        install_profile(profile)

        # ---- THE BOOT
        try:
            ip.call("openStack", [])
            c.ck("[%s] openStack ran to completion" % profile, True)
        except Exception as exc:                        # noqa: BLE001
            c.ck("[%s] openStack ran to completion" % profile, False,
                 "%s: %s" % (type(exc).__name__, exc))
            return

        cards = expected_cards(src)
        have = sorted(cd.name for cd in world.cards if cd.name in cards)
        c.ck("[%s] every named card was built (%s)"
             % (profile, ",".join(cards)), have == cards,
             "built: %s" % ",".join(have))
        c.ck("[%s] the boot returns to card 1" % profile, world.cur == 0)
        c.ck("[%s] the screen lock is balanced" % profile,
             world.locked == 0, "depth %d" % world.locked)

        # every control the demo's own registry names exists SOMEWHERE
        # (the world-level check; current-card resolution is a separate,
        # unsettled engine question - see the header)
        reg = str(ip.constants.get("kRaScControls", ""))
        missing = [n for n in reg.split(",")
                   if n and world.anywhere(n) is None]
        c.ck("[%s] all %d registered controls exist in the built world"
             % (profile, len(reg.split(","))), not missing,
             "missing: %s" % ",".join(missing[:8]))

        status = world.anywhere("uiStatus")
        c.ck("[%s] the status line says something" % profile,
             status is not None and status.content != "",
             repr(status.content if status else None))

        # ---- the queued self-check tick (and anything else armed at boot)
        try:
            delivered = ip.deliver_sends()
            c.ck("[%s] queued boot messages deliver (%s)"
                 % (profile, ",".join(delivered) or "none"), True)
        except Exception as exc:                        # noqa: BLE001
            c.ck("[%s] queued boot messages deliver" % profile, False,
                 "%s: %s" % (type(exc).__name__, exc))

        # The boot self-check must be GREEN in the model. This was an info
        # line until 2026-08-29, when a real engine run showed the check's
        # own cross-card defect (engine notes 5.6) as the one red line on a
        # working app: scMissing walks every card now, so a modeled failure
        # here is a real regression, not an open question.
        sc_failed = ip.globals.get("sscfailed", "")
        sc_passed = ip.globals.get("sscpassed", "")
        c.ck("[%s] the boot self-check reports zero failures (%s passed)"
             % (profile, sc_passed), str(sc_failed) == "0",
             "%s failed" % sc_failed)

        if not drive:
            return

        # ---- the identity gate starts LOCKED (affordance: a fresh boot's
        # seed-needing buttons are disabled, not click-to-refuse)
        post = world.anywhere("raPost")
        c.ck("[%s] identity-gated buttons start disabled" % profile,
             post is not None and _bool(post.props.get("enabled")) is False,
             repr(post.props.get("enabled") if post else None))

        # ---- the upgrade path: a stack stamped with an OLDER uUiVersion
        # sheds retired furniture and rebuilds clean. Planted: a legacy
        # raGo* hub button, exactly what a pre-v11 stack would carry.
        world.cards[0].controls.append(Control("button", "raGoDm"))
        world.stack_props["uuiversion"] = "ra-ui-720p-10"
        try:
            ip.call("raBuild", [])
            gone = world.anywhere("raGoDm") is None
            still = [n for n in reg.split(",")
                     if n and world.anywhere(n) is None]
            c.ck("[%s] a version-bump rebuild sheds retired controls and "
                 "rebuilds every registered one" % profile,
                 gone and not still and world.locked == 0 and world.cur == 0,
                 "raGoDm gone=%s missing=%s locked=%d cur=%d"
                 % (gone, ",".join(still[:5]), world.locked, world.cur))
        except Exception as exc:                        # noqa: BLE001
            c.ck("[%s] a version-bump rebuild sheds retired controls"
                 % profile, False, "%s: %s" % (type(exc).__name__, exc))

        # ---- drive the navigation clicks (every raNav* tab, on every card)
        for card in list(world.cards):
            for ctl in list(card.controls):
                if ctl.ctype == "button" and ctl.name.startswith("raNav"):
                    world.target = ("button", ctl.name)
                    try:
                        ip.call("mouseUp", [])
                    except Exception as exc:            # noqa: BLE001
                        c.ck("[%s] click %s navigates"
                             % (profile, ctl.name), False,
                             "%s: %s" % (type(exc).__name__, exc))
                        world.target = None
                        break
            else:
                continue
            break
        else:
            c.ck("[%s] every navigation button clicks without error"
                 % profile, True)
        world.target = None
        world.go_to("1")

        # ---- a full identity session: create, lock, close
        keyfield = world.anywhere("raKeyFile")
        passfield = world.anywhere("raPassphrase")
        if keyfield is not None and passfield is not None:
            keyfield.content = os.path.join(sandbox, "id.riptkey")
            passfield.content = "boot-harness-passphrase"
            try:
                ip.call("raCreate", [])
                created = os.path.isfile(keyfield.content)
                c.ck("[%s] raCreate seals a key file and survives its "
                     "degraded paths" % profile, created,
                     world.anywhere("raIdOut").content[-200:])
                c.ck("[%s] creating an identity enables the gated buttons"
                     % profile,
                     _bool(world.anywhere("raPost").props.get("enabled"))
                     is True,
                     repr(world.anywhere("raPost").props.get("enabled")))
            except Exception as exc:                    # noqa: BLE001
                c.ck("[%s] raCreate runs" % profile, False,
                     "%s: %s" % (type(exc).__name__, exc))
            ip.deliver_sends()
            drive_nostr(c, ip, world, profile)
            try:
                ip.call("raLock", [])
                c.ck("[%s] raLock tears down cleanly" % profile, True)
            except Exception as exc:                    # noqa: BLE001
                c.ck("[%s] raLock tears down cleanly" % profile, False,
                     "%s: %s" % (type(exc).__name__, exc))
        try:
            ip.call("closeStack", [])
            c.ck("[%s] closeStack tears down cleanly" % profile, True)
        except Exception as exc:                        # noqa: BLE001
            c.ck("[%s] closeStack tears down cleanly" % profile, False,
                 "%s: %s" % (type(exc).__name__, exc))

        if c.failed == failures_before:
            c.note("[%s] boot green" % profile)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def drive_nostr(c, ip, world, profile):
    """Exercise the phase-8 card the way a person would, offline: identity,
    a follow, a post with no relay open, the bridge, the sealed app-state
    round trip, and the clipboard copy. Skipped quietly on a build that has
    no Nostr card (the pre-phase-8 app), so the gate holds for both."""
    if world.card_named("raNostr") is None:
        return
    npub_field = world.anywhere("raNxNpub")

    if profile == "MIN":
        # CoinXT absent: the rail must disable itself and NOTHING else -
        # the raCreate/raLock/closeStack checks around this are the proof
        # of "nothing else", and this is the proof of "itself".
        try:
            world.target = ("button", "raNxFollowBtn")
            ip.call("mouseUp", [])
            world.target = None
            status = world.anywhere("raNxStatus")
            c.ck("[MIN] without CoinXT the Nostr card refuses with the "
                 "install line", "coinxt" in status.content.lower(),
                 repr(status.content[:120]))
            c.ck("[MIN] and the npub field stays empty",
                 npub_field.content == "")
        except Exception as exc:                        # noqa: BLE001
            c.ck("[MIN] without CoinXT the Nostr card refuses cleanly",
                 False, "%s: %s" % (type(exc).__name__, exc))
        return

    # FULL: real libsecp256k1 under the natives, so this is a genuine
    # derivation driven through the app's own click paths.
    c.ck("[FULL] unlocking derived a real npub into the card",
         npub_field.content.startswith("npub1"),
         repr(npub_field.content[:40]))
    try:
        ip.call("raNxCopyNpub", [])
        c.ck("[FULL] Copy puts the npub on the clipboard",
             world.clipboard.get("text", "") == npub_field.content)
    except Exception as exc:                            # noqa: BLE001
        c.ck("[FULL] Copy puts the npub on the clipboard", False,
             "%s: %s" % (type(exc).__name__, exc))

    # follow a foreign key (the oracle's, so it is valid), by the click path
    other = CSV.REF["nostr_npub"](CSV.REF["nostr_pubkey"](b"\x43" * 32))
    world.anywhere("raNxFollowTo").content = other
    try:
        world.target = ("button", "raNxFollowBtn")
        ip.call("mouseUp", [])
        world.target = None
        follows = world.anywhere("raNxFollows")
        c.ck("[FULL] a pasted npub becomes a follow",
             "..." in follows.content and follows.content != "",
             repr(follows.content[:80]))
    except Exception as exc:                            # noqa: BLE001
        c.ck("[FULL] a pasted npub becomes a follow", False,
             "%s: %s" % (type(exc).__name__, exc))

    # post with no relay open: signed, and honestly NOT sent
    world.anywhere("raNxCompose").content = "boot-harness note"
    try:
        ip.call("raNxPost", [])
        status = world.anywhere("raNxStatus")
        c.ck("[FULL] a post with no relay open says NOT sent",
             "not sent" in status.content.lower(),
             repr(status.content[:120]))
    except Exception as exc:                            # noqa: BLE001
        c.ck("[FULL] a post with no relay open says NOT sent", False,
             "%s: %s" % (type(exc).__name__, exc))

    # the bridge: built and self-verifying even with no session and no relay
    try:
        ip.call("raNxBridge", [])
        bridge = ip.globals.get("snxpendingbridge", "")
        ok = bridge != "" and ip.call("rsVerifyBridge",
                                      [bridge, "", ""]) != ""
        c.ck("[FULL] the bridge the app built verifies under both keys", ok)
    except Exception as exc:                            # noqa: BLE001
        c.ck("[FULL] the bridge the app built verifies under both keys",
             False, "%s: %s" % (type(exc).__name__, exc))

    # the sealed app-state round trip, through the app's own save/load
    try:
        ip.call("raAppSave", [])
        follows_before = dict(ip.globals.get("sappfollows", {}))
        ip.globals["sappfollows"] = {}
        ip.call("raAppLoad", [])
        follows_after = ip.globals.get("sappfollows", {})
        c.ck("[FULL] follows survive the sealed save/load round trip",
             follows_before != {} and follows_after == follows_before,
             "before %d after %d" % (len(follows_before),
                                     len(follows_after)))
    except Exception as exc:                            # noqa: BLE001
        c.ck("[FULL] follows survive the sealed save/load round trip",
             False, "%s: %s" % (type(exc).__name__, exc))

    # The READER WATERMARKS across the same round trip (2026-09-08). This is
    # the check that would have caught the bug it was written for: raAppSave
    # had emitted `headseq` since it was written and raAppLoad's switch had no
    # case for it, so our own head sequence was persisted every save and read
    # back never. A write with no reader is invisible to every other gate in
    # this tree - it is not a parse error, not a name the checker can miss, and
    # not a vector anything pins - so it can only be caught by round-tripping
    # the value and looking. rsIngestHead's rollback gate is only as good as
    # these surviving a restart: at 0 every launch would accept the oldest head
    # a DHT node still holds.
    try:
        handle = "ab" * 32
        ip.globals["sheadseen"] = {handle: 42}
        ip.globals["sseq"] = 7
        ip.call("raAppSave", [])
        ip.globals["sheadseen"] = {}
        ip.globals["sseq"] = ""
        ip.call("raAppLoad", [])
        seen = ip.globals.get("sheadseen", {})
        seq = ip.globals.get("sseq", "")
        c.ck("[FULL] the reader watermarks survive the save/load round trip",
             seen.get(handle) in (42, "42"),
             "got %r" % (seen,))
        c.ck("[FULL] our own head seq survives it too (headseq had no reader)",
             str(seq) == "7", "got %r" % (seq,))
    except Exception as exc:                            # noqa: BLE001
        c.ck("[FULL] the reader watermarks survive the save/load round trip",
             False, "%s: %s" % (type(exc).__name__, exc))

    # Surviving a round trip is not the same as REACHING one. raAppSave only
    # runs when sAppDirty is "true" (the debounced tick and raNxTeardown both
    # gate on it), so a session that accepts a head and changes nothing else
    # would quit with the new watermark still in memory - and the next launch
    # would start from 0 and accept the same stale head again. Reported by
    # review on PR #132; the round-trip check above could not see it, because
    # it calls raAppSave directly.
    try:
        # NOTE the signature: this file's ck() is (label, OK_BOOLEAN, detail),
        # not the (label, got, want) that riptide's check-script-vectors.py
        # uses. Passing got/want here makes every non-empty "got" truthy and
        # the check pass vacuously - which is exactly what the first draft of
        # these two lines did.
        ip.globals["sappdirty"] = ""
        ip.call("raHeadAccepted", ["cd" * 32, 9])
        got_new = str(ip.globals.get("sappdirty", ""))
        c.ck("[FULL] accepting a newer head marks the app state dirty",
             got_new == "true", "sAppDirty = %r" % (got_new,))
        ip.globals["sappdirty"] = ""
        ip.call("raHeadAccepted", ["cd" * 32, 4])
        got_stale = str(ip.globals.get("sappdirty", ""))
        c.ck("[FULL] a STALE head does not mark it dirty (no pointless save)",
             got_stale == "", "sAppDirty = %r" % (got_stale,))
    except Exception as exc:                            # noqa: BLE001
        c.ck("[FULL] accepting a newer head marks the app state dirty",
             False, "%s: %s" % (type(exc).__name__, exc))


def main(argv):
    terse = "--check" in argv
    path = DEMO
    if "--file" in argv:
        path = argv[argv.index("--file") + 1]
    c = Checker(terse)
    for profile in ("MIN", "FULL"):
        c.note("profile %s" % profile)
        boot(c, path, profile)
    if c.failed:
        print("check-demo-boot: %d of %d check(s) FAILED" % (c.failed, c.n))
        return 1
    print("check-demo-boot: OK (%d checks; the shipped stack booted, "
          "navigated, created an identity, locked and closed under both "
          "capability profiles)" % c.n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
