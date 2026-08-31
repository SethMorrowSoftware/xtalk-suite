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
        self.ms = 1000000               # the modeled clock, advanced on ticks
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
                    a, b = LCS._n(v), LCS._n(r)
                    v = {">=": a >= b, "<=": a <= b, ">": a > b,
                         "<": a < b, "<>": a != b}[op]
                    break
            else:
                self.i = save
                return v

    def p_atom(self):
        world = self.ip.world
        rest = self.s[self.i:]

        # `there is a|an|no <thing> <expr>` - never throws, answers a boolean
        # IMAGE joined the list on 2026-08-31, with the carried self-check
        # block: scMissing asks about it now, because a demo may build a
        # control the KIT does not (coinxt's wallet paints a QR into one).
        # Without it here every adopter's scMissing walk would die on an
        # unmodelled expression rather than answer.
        m = re.match(r'there\s+is\s+(a|an|no)\s+'
                     r'(field|button|graphic|image|card|file|folder)\s+', rest,
                     re.I)
        if m:
            self.i += m.end()
            want_missing = m.group(1).lower() == "no"
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
        m = re.match(r'the\s+(platform|milliseconds|millisecs|result|target)'
                     r'\b', rest, re.I)
        if m:
            word = m.group(1).lower()
            self.i += m.end()
            if word == "platform":
                return "Win32"
            if word in ("milliseconds", "millisecs"):
                return world.ms
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
            return obj.name
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

        # ---- repeat for each key/line (absent from the base)
        m = re.match(r'repeat\s+for\s+each\s+(key|line)\s+(\w+)\s+in\s+(.+)$',
                     line, re.I)
        if m:
            kind, var = m.group(1).lower(), m.group(2).lower()
            inner, after = self._block(body, i, None, None)
            src = self.eval_expr(m.group(3), env)
            if kind == "key":
                items = list(src.keys()) if isinstance(src, dict) else []
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
        m = re.match(r'(sxSignKeypairFromSeed|sxKeyExchangeKeypairFromSeed)'
                     r'\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*$', line, re.I)
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
        try:
            for _conds, stmts in arms[start:]:
                self._exec([s for s in stmts
                            if s.strip().lower() != "break"], env)
                if any(s.strip().lower() == "break" for s in stmts):
                    break
        except LCS._Exit:
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

def install_common(world):
    CSV.install_pure_natives()
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
            print("  FAIL %s%s" % (label, ("\n       " + detail) if detail
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
