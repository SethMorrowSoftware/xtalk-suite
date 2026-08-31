#!/usr/bin/env python3
"""check-wallet-boot.py - BOOT the shipped wallet stack, headlessly.

WHY THIS EXISTS, AND WHAT IT IS NOT
-----------------------------------
tools/check-wallet-vectors.py proves the CALCULATOR: it drives
examples/wallet-core.livecodescript against an independent oracle with the
real secp256k1 underneath, twice, once under each comparison rule. It never
opens a window, because wallet-core does not have one. Everything ABOVE that
line - the ten screens, the show/hide
sweep, the click router, the paint handlers, the wallet file, the boot
self-check - was, until this gate, verified only by reading it. That is the
suite's own recorded failure shape, and this member's CLAUDE.md names it in
one sentence: shipped is not run.

So this is the same move riptide made, and it is deliberately built by
REUSING riptide's runner rather than copying it. tools/check-demo-boot.py in
that member already models the engine well enough to open a stack: cards and
controls, rect arithmetic, `there is a field`, the `send ... in` queue, a
sandboxed url:/binfile: layer, switch, and the two SodiumXT keypair commands
that return through out-parameters. Copying 1400 lines of that to change
three things would put a fourth copy of an engine model in this tree, and
this tree already knows what happens to copies (tools/check-checker-drift.py
exists because seven of them drifted). What is here instead is the DELTA.

WHAT THE DELTA IS
-----------------
Three engine constructs the wallet uses and riptide's model does not:

  1. `the number of controls of this card` and `control N of this card`.
     waShow sweeps the card by INDEX rather than by a registry, because a
     screen is a name prefix and not a group - the engine has no reparenting
     and the family's other multi-screen stacks do the same.
  2. the IMAGE control. The Receive screen paints a QR into one, which is the
     only way a BMP this layer builds becomes something a phone can read.
     (`there is a|no image` is riptide's own now: the carried self-check block
     gained an image arm on the same day, for the same reason, so its model
     had to learn the type or every adopter's scMissing walk would die on it.)
  3. `the last image` as an object reference, which is how a just-created
     control is named.
  4. `the effective filename of this stack`, which the Settings screen walks
     back to a folder to propose a default wallet-file path. Answered with a
     path inside the sandbox, so the derivation is really exercised and what
     it derives is somewhere this gate may write.

(1) and (3) are expression and statement forms added by the two subclasses
below. (2) is a widening of riptide's shared object regex, done by rebinding
its module global with the old text ASSERTED first, so a change to the shape
of that regex fails here loudly instead of silently switching image support
off. No source rewrite is used: unlike riptide, the wallet was written inside
the modelled subset from the start, and a rewrite list this file does not
need is a rewrite list that could go stale without anyone noticing.

ONE INTERPRETER MODULE, AND WHY THAT NEEDS SAYING
-------------------------------------------------
riptide's runner loads nostrxt's copy of lcs-interp.py; this member's vector
gate loads its own. The two files are byte-identical and
tools/check-checker-drift.py holds them that way - but they are two module
OBJECTS, with two HASHES tables and two Thrown classes, and a native
installed in one is invisible to the other. That is the exact trap riptide's
own header records finding the hard way. This file therefore asserts the two
files are identical and then rebinds the vector gate's module global so every
native lands in the ONE interpreter the boot actually runs on.

WHAT IS REAL AND WHAT IS MODELLED
---------------------------------
  - CoinXT is REAL. Every cx* handler the wallet calls is served by
    src/code/x86_64-linux/coinxt.so, the COMMITTED library, through ctypes.
    No compiler is needed, which is what lets this gate run anywhere the
    repository is checked out. The wiring is the vector gate's own
    wire_hashes/wire_signing, so the two gates cannot disagree about what
    CoinXT does.
  - SodiumXT is MODELLED, and every model is declared in SODIUM_MODELS below
    with what it stands in for. sxRandomBytes is DETERMINISTIC on purpose: a
    boot that mints a fresh seed on every run cannot be compared against
    anything.
  - OnionXT answers its version probe and nothing else. The wallet must come
    up OFFLINE here; a gate that dialled a real onion would be a gate that
    fails when the network does.

WHAT IT CANNOT SEE
------------------
It runs the interpreter's semantics, not OXT's. Everything in
docs/OXT-ENGINE-NOTES.md that the interpreter models differently is invisible
here - most sharply, `is` and `offset()` are modelled CASE-SENSITIVELY and
the engine folds case by default. That whole class is checked by
check-wallet-vectors.py's case-folded tier instead, which re-runs its vectors
under the engine's rule; this gate does not duplicate it. And a green boot
here is not an OXT pass: it says the code RUNS and what it computes, not that
a window appeared.
"""

import ctypes
import hashlib
import hmac
import importlib.util
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
SUITE = os.path.dirname(MEMBER)
DEMO = os.path.join(MEMBER, "examples", "coin-wallet.livecodescript")
COIN_SO = os.path.join(MEMBER, "src", "code", "x86_64-linux", "coinxt.so")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def _die(msg):
    print("check-wallet-boot: %s" % msg)
    sys.exit(1)


# ---- the two reused gates, and the one-interpreter rule --------------------
DB = _load("check_demo_boot",
           os.path.join(SUITE, "riptide", "tools", "check-demo-boot.py"))
WV = _load("check_wallet_vectors",
           os.path.join(HERE, "check-wallet-vectors.py"))

_MINE = open(os.path.join(HERE, "lcs-interp.py"), "rb").read()
_THEIRS = open(DB.CSV.INTERP, "rb").read()
if _MINE != _THEIRS:
    _die("this member's lcs-interp.py and the one riptide's runner loaded (%s) "
         "are not byte-identical, so rebinding one onto the other would change "
         "behaviour. tools/check-checker-drift.py holds them equal; fix that "
         "first." % os.path.relpath(DB.CSV.INTERP, SUITE))

LCS = DB.LCS                    # the ONE interpreter the boot runs on
WV.LCS = LCS
WV.CSV.LCS = LCS
Thrown = LCS.Thrown

# The image control, added to riptide's shared object regex. Asserted first:
# if that regex is ever reshaped, this fails loudly rather than quietly
# leaving every `image` reference unmatched.
for _old, _new in (
        ("(field|button|graphic|card)", "(field|button|graphic|image|card)"),
        (r"the\s+last\s+(?:field|button|graphic)",
         r"the\s+last\s+(?:field|button|graphic|image)")):
    if _old not in DB._OBJ_RE:
        _die("riptide's _OBJ_RE no longer contains %r, so the image widening "
             "cannot be applied" % _old)
    DB._OBJ_RE = DB._OBJ_RE.replace(_old, _new)
_OBJ_RE = DB._OBJ_RE

_CTL_OF_CARD = (r'control\s+(.+?)\s+of\s+(this\s+card|card\s+'
                r'(?:"[^"]*"|\d+|[A-Za-z_]\w*))')


class Checker(DB.Checker):
    """riptide's Checker plus an explicit EQUALITY form, and the reason is a
    defect this file shipped in its first draft. `DB.Checker.ck` is
    `(label, ok, detail)` - a BOOLEAN and a message - while the vector gate's
    Checker beside it is `(label, got, want)`. Nine checks here were written
    in the second shape against the first, so `ok` was a non-empty string and
    every one of them passed for any value at all: the account xpub, the first
    address, the balance, the restored label. That is precisely the class the
    adversarial pass found in check-wallet-vectors.py, reproduced one file
    later by the person who had just fixed it. Two names now, so the shapes
    cannot be confused: ck() takes a boolean, eq() takes two values."""

    def eq(self, label, got, want):
        self.ck(label, got == want,
                "got:  %r\n       want: %r" % (got, want))


# ==========================================================================
# the engine-model delta
# ==========================================================================

def _ctl_prop_get(ctl, prop):
    if prop == "name":
        return ctl.name
    if prop == "id":
        return '%s "%s"' % (ctl.ctype, ctl.name)
    if prop in DB.RECT_PROPS:
        return DB._rect_get(ctl, prop)
    return ctl.props.get(prop, "")


class WalletExpr(DB.DemoExpr):
    """riptide's expression surface plus the by-index control reads."""

    def card_of(self, spec):
        s = re.sub(r'\s+', ' ', str(spec).strip().lower())
        if s == "this card":
            return self.ip.world.current()
        name = str(LCS._disp(self.ip.eval_expr(spec.strip()[4:].strip(),
                                               self.env)))
        card = self.ip.world.card_named(name)
        if card is None:
            raise Thrown('Chunk: no such object (card "%s")' % name)
        return card

    def control_at(self, idx_expr, card_expr):
        card = self.card_of(card_expr)
        n = int(LCS._n(self.ip.eval_expr(idx_expr, self.env)))
        if not 1 <= n <= len(card.controls):
            raise Thrown("Chunk: no such object (control %d of %d)"
                         % (n, len(card.controls)))
        return card.controls[n - 1]

    def p_atom(self):
        # ws() first, for the reason riptide's own p_atom now gives: these
        # branches are anchored regexes and a leading space makes every one
        # of them miss.
        self.ws()
        rest = self.s[self.i:]

        m = re.match(r'the\s+number\s+of\s+controls\s+of\s+'
                     r'(this\s+card|card\s+(?:"[^"]*"|\d+|[A-Za-z_]\w*))',
                     rest, re.I)
        if m:
            self.i += m.end()
            return len(self.card_of(m.group(1)).controls)

        m = re.match(r'the\s+(?:(short|long|abbreviated)\s+)?(\w+)\s+of\s+'
                     + _CTL_OF_CARD, rest, re.I)
        if m:
            self.i += m.end()
            return _ctl_prop_get(self.control_at(m.group(3), m.group(4)),
                                 m.group(2).lower())

        # `the effective filename of this stack` - the path the Settings
        # screen derives its default wallet-file location from. Answered with
        # a path INSIDE THE SANDBOX, so the default the app computes is a
        # place this gate is allowed to write, and the derivation itself
        # (which walks back to the containing folder) is really exercised.
        m = re.match(r'the\s+(?:effective\s+)?filename\s+of\s+this\s+stack\b',
                     rest, re.I)
        if m:
            self.i += m.end()
            return os.path.join(self.ip.world.sandbox, "coinXTWallet.livecode")

        return super().p_atom()


class WalletInterp(DB.DemoInterp):
    def eval_expr(self, expr, env):
        return WalletExpr(self, env).parse(expr)

    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        world = self.world

        if re.match(r'create\s+image\s*$', line, re.I):
            world.create("image")
            return i + 1

        m = re.match(r'(hide|show)\s+image\s+(.+)$', line, re.I)
        if m:
            name = str(LCS._disp(self.eval_expr(m.group(2), env)))
            ctl = world.resolve("image", name)
            if ctl is None:
                raise Thrown('Chunk: no such object (image "%s")' % name)
            ctl.props["visible"] = m.group(1).lower() == "show"
            return i + 1

        m = re.match(r'set\s+the\s+(\w+)\s+of\s+' + _CTL_OF_CARD
                     + r'\s+to\s+(.+)$', line, re.I)
        if m:
            ctl = WalletExpr(self, env).control_at(m.group(2), m.group(3))
            value = self.eval_expr(m.group(4), env)
            prop = m.group(1).lower()
            if prop == "name":
                ctl.name = str(value)
            elif prop in DB.RECT_PROPS:
                DB._rect_set(ctl, prop, value)
            else:
                ctl.props[prop] = value
            return i + 1

        return super()._exec_stmt(body, i, env)


# ==========================================================================
# natives
# ==========================================================================

# EVERY SodiumXT STAND-IN, DECLARED. Checked against what is actually wired
# at boot (see run()), so this is a declaration the build compares rather than
# a comment nobody has to keep true.
SODIUM_MODELS = {
    "sxversion": "a fixed string; the wallet only needs it to ANSWER",
    "sxrandombytes": "DETERMINISTIC counter-seeded bytes - a boot that minted "
                     "a fresh seed each run could not be compared to anything",
    "sxpwsaltbytes": "16, argon2id's salt length",
    "sxpwmemsensitive": "argon2id's 'sensitive' memlimit, as a number to pass "
                        "on",
    "sxpwhash": "blake2b(password || salt), the model the oracle already "
                "proves against sodiumxt's own C KAT - NOT argon2id",
    "sxaeadencrypt": "nonce-prefixed and authenticated (HMAC-SHA256 over "
                     "nonce, ad and ciphertext) so the wallet file's framing, "
                     "its associated data and every refusal path around it "
                     "are exercised honestly - but NOT XChaCha20-Poly1305",
    "sxaeaddecrypt": "its inverse, verifying the tag BEFORE returning "
                     "anything, which is what makes the tamper check real",
    "sxhmacsha256": "hashlib.hmac, which is what sodiumxt's is",
    "sxsha3_256": "hashlib.sha3_256, likewise",
    "sxmemequal": "a constant-time-shaped byte compare",
    "sxbin2hex": "exact",
    "sxhex2bin": "exact",
}


def _b(s):
    return str(s).encode("latin-1")


def _s(b):
    return b.decode("latin-1")


def install_sodium():
    counter = [0]

    def randombytes(a):
        n = int(LCS._n(a[0]))
        counter[0] += 1
        seed = hashlib.sha256(b"wallet-boot-%d" % counter[0]).digest()
        return _s((seed * (n // 32 + 1))[:n])

    def pwhash(a):
        return _s(hashlib.blake2b(_b(a[0]) + _b(a[1]),
                                  digest_size=int(LCS._n(a[2]))).digest())

    def _stream(key, nonce, n):
        out = b""
        while len(out) < n:
            out += hashlib.sha256(key + nonce
                                  + bytes([len(out) // 32])).digest()
        return out[:n]

    def aead_encrypt(a):
        msg, ad, key = _b(a[0]), _b(a[1]), _b(a[2])
        nonce = hashlib.sha256(b"wb-nonce" + key + ad + msg).digest()[:24]
        ct = bytes(x ^ y for x, y in zip(msg, _stream(key, nonce, len(msg))))
        tag = hmac.new(key, nonce + ad + ct, hashlib.sha256).digest()[:16]
        return _s(nonce + ct + tag)

    def aead_decrypt(a):
        blob, ad, key = _b(a[0]), _b(a[1]), _b(a[2])
        if len(blob) < 40:
            raise Thrown("SodiumXT: sxAeadDecrypt: too short")
        nonce, ct, tag = blob[:24], blob[24:-16], blob[-16:]
        want = hmac.new(key, nonce + ad + ct, hashlib.sha256).digest()[:16]
        if not hmac.compare_digest(tag, want):
            raise Thrown("SodiumXT: sxAeadDecrypt: authentication failed")
        return _s(bytes(x ^ y for x, y in
                        zip(ct, _stream(key, nonce, len(ct)))))

    LCS.HASHES.update({
        "sxversion": lambda a: "SodiumXT 1.0 (modelled by check-wallet-boot)",
        "sxrandombytes": randombytes,
        "sxpwsaltbytes": lambda a: 16,
        "sxpwmemsensitive": lambda a: 1073741824,
        "sxpwhash": pwhash,
        "sxaeadencrypt": aead_encrypt,
        "sxaeaddecrypt": aead_decrypt,
        "sxhmacsha256": lambda a: _s(hmac.new(_b(a[0]), _b(a[1]),
                                              hashlib.sha256).digest()),
        "sxsha3_256": lambda a: _s(hashlib.sha3_256(_b(a[0])).digest()),
        "sxmemequal": lambda a: hmac.compare_digest(_b(a[0]), _b(a[1])),
        "sxbin2hex": lambda a: _b(a[0]).hex(),
        "sxhex2bin": lambda a: _s(bytes.fromhex(str(LCS._disp(a[0])))),
        # OnionXT answers its version probe and nothing else: the wallet must
        # boot OFFLINE here. Any deeper ox* call is a loud failure, which is
        # what it should be - it would mean the boot path dialled something.
        "oxversion": lambda a: "OnionXT 1.0",
    })


def install_coin():
    if not os.path.exists(COIN_SO):
        _die("the committed library %s is missing, so there is nothing to "
             "boot against" % os.path.relpath(COIN_SO, SUITE))
    lib = ctypes.CDLL(COIN_SO)
    WV.CSV.wire_hashes(lib)
    WV.wire_signing(lib)
    return lib


# ==========================================================================
# the source
# ==========================================================================

def build_source(path=None):
    """The shipped file, minus its `script "..."` line, with the ENGINE's own
    compile-time refusal applied first. NO REWRITES: unlike riptide, this
    stack was written inside the modelled subset, and an empty rewrite list
    is the honest state rather than a list nobody has noticed going stale.

    `path` names a file other than the shipped one - which only
    tools/test-wallet-boot.py passes, so the fixtures can boot a mutated
    copy and require this gate to fail on it."""
    with open(path or DEMO, "r", encoding="utf-8") as fh:
        src = fh.read()
    src = re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', src, count=1)
    DB._refuse_nonliteral_constants(src, _die)
    if re.search(r'^\s*if .+ then .+ else ', src, re.M):
        _die("a one-line `if ... then ... else ...` appeared in the shipped "
             "file")
    return src


# ==========================================================================
# the checks
# ==========================================================================

SCREENS = ["wallet", "receive", "addresses", "send", "coins", "history",
           "tools", "network", "log", "settings"]
CODES = ["wl", "rc", "ad", "sd", "cn", "hs", "tl", "nw", "lg", "st"]

# One UTXO set, planted directly into the wallet's own state. Values and
# txids are arbitrary but FIXED, because every number this gate asserts is
# derived from them.
UTXOS = [
    {"txid": "a" * 64, "vout": 0, "value": 250000, "confirmations": 12},
    {"txid": "b" * 64, "vout": 1, "value": 90000, "confirmations": 3},
    {"txid": "c" * 64, "vout": 0, "value": 40000, "confirmations": 0},
]


def plant_utxos(ip, world):
    """Fill sWaUtxos from UTXOS, using the wallet's own address records so the
    script types and derivation paths are the ones it would really see."""
    addrs = ip.globals.get("swaaddresses") or {}
    n = int(LCS._n(addrs.get("n", 0)))
    if n < len(UTXOS):
        return False
    out = {"n": len(UTXOS)}
    for i, u in enumerate(UTXOS, 1):
        rec = dict(addrs[str(i)])
        out[str(i)] = {
            "txid": u["txid"], "vout": u["vout"], "value": u["value"],
            "confirmations": u["confirmations"], "height": u["confirmations"],
            "address": rec.get("address", ""), "script": rec.get("script", ""),
            "path": rec.get("path", ""), "pubkey": rec.get("pubkey", ""),
            "chain": rec.get("chain", 0), "index": rec.get("index", 0),
            "selected": "", "frozen": "",
        }
    ip.globals["swautxos"] = out
    return True


def _fld(world, name):
    ctl = world.anywhere(name)
    return "" if ctl is None else ctl.content


def click(ip, world, name):
    world.target = ("button", name)
    try:
        ip.call("mouseUp", [])
    finally:
        world.target = None


def run(c, path=None):
    sandbox = tempfile.mkdtemp(prefix="wallet-boot-")
    world = DB.World(sandbox)
    try:
        src = build_source(path)
        try:
            ip = WalletInterp(src, world)
        except Exception as exc:                        # noqa: BLE001
            c.ck("the stack script parses", False,
                 "%s: %s" % (type(exc).__name__, exc))
            return
        c.ck("the stack script parses (%d handlers, %d constants)"
             % (len(ip.handlers), len(ip.constants)), True)

        DB.install_common(world)
        install_sodium()
        install_coin()

        # THE DECLARED MODELS ARE CHECKED AGAINST WHAT IS ACTUALLY WIRED. A
        # list of stand-ins in a docstring is a comment; a list the build
        # compares is a declaration. This file's first draft had
        # SODIUM_MODELS read by nothing - the same shape as the dead
        # constants its own subject matter was found carrying.
        #
        # ONE DIRECTION ONLY, and the reason is whose list it is. Every name
        # SODIUM_MODELS declares must really be wired, or the declaration is
        # describing a machine this gate is not running. The reverse - every
        # wired sx* being declared here - is not asserted, because riptide's
        # install_pure_natives wires several more (ed25519, kdf, secretbox)
        # that the wallet never calls and that riptide's own header declares.
        installed = set(k for k in LCS.HASHES if k.startswith("sx"))
        c.eq("every declared SodiumXT stand-in is really wired (%d sx* "
             "natives present)" % len(installed),
             sorted(set(SODIUM_MODELS) - installed), [])

        # ---- THE BOOT -----------------------------------------------------
        try:
            ip.call("preOpenStack", [])
            ip.call("openStack", [])
            c.ck("preOpenStack and openStack ran to completion", True)
        except Exception as exc:                        # noqa: BLE001
            c.ck("preOpenStack and openStack ran to completion", False,
                 "%s: %s" % (type(exc).__name__, exc))
            return

        c.ck("the boot leaves the screen lock balanced", world.locked == 0,
             "depth %d" % world.locked)

        # every control the demo's own registry names was built
        reg = [n for n in str(ip.constants.get("kWaScControls", "")).split(",")
               if n]
        missing = [n for n in reg if world.anywhere(n) is None]
        c.ck("all %d registered controls exist" % len(reg), not missing,
             "missing: %s" % ",".join(missing[:8]))

        # and nothing was built that the registry does not name: an
        # unregistered control is one the boot self-check can never miss.
        # The kit's own derived names are excluded - uiSection builds a
        # "<name>Line" divider and uiPill a "<name>Bg" rounded rectangle,
        # both of which belong to the kit's gate and not to this app's
        # registry.
        named = set(n.lower() for n in reg)
        extra = sorted(ct.name for cd in world.cards for ct in cd.controls
                       if ct.name and "_" in ct.name
                       and not ct.name.endswith("Line")
                       and not ct.name.endswith("Bg")
                       and ct.name.lower() not in named)
        c.ck("the registry names every control the boot builds", not extra,
             "unregistered (%d): %s" % (len(extra), ",".join(extra)))

        # ---- the capability probe -----------------------------------------
        c.ck("the probe found CoinXT", ip.globals.get("swahavecoin") == "true",
             repr(ip.globals.get("swahavecoin")))
        c.ck("the probe found SodiumXT",
             ip.globals.get("swahavesodium") == "true",
             repr(ip.globals.get("swahavesodium")))
        c.ck("the wallet comes up OFFLINE",
             ip.globals.get("swabackend") == "offline",
             repr(ip.globals.get("swabackend")))

        # ---- the boot self-check ------------------------------------------
        try:
            delivered = ip.deliver_sends(rounds=3)
            c.ck("queued boot messages deliver (%s)"
                 % (",".join(sorted(set(delivered))) or "none"), True)
        except Exception as exc:                        # noqa: BLE001
            c.ck("queued boot messages deliver", False,
                 "%s: %s" % (type(exc).__name__, exc))
        failed = str(ip.globals.get("sscfailed", ""))
        passed = str(ip.globals.get("sscpassed", ""))
        report = _fld(world, "lg_boot")
        c.ck("the boot self-check reports zero failures (%s passed)" % passed,
             failed == "0",
             "%s failed:\n       %s" % (failed, "\n       ".join(
                 ln for ln in report.split("\n") if "FAIL" in ln) or report[-400:]))
        c.ck("the boot self-check actually ran something",
             passed.isdigit() and int(passed) > 0, "passed=%r" % passed)

        # ---- every screen, reached the way a person reaches it ------------
        # ONE loop, not two. The rail click and the sweep are checked together
        # because clicking nv_<code> IS what runs waShow, and running the two
        # separately paid for twenty full repaints to assert what twelve
        # assert - each repaint re-derives and re-formats every table over the
        # whole address window, which is the most expensive thing this gate
        # does.
        #
        # The sweep is the one piece of this stack a reader cannot check by
        # reading: it works by control INDEX over a card of 250-odd controls,
        # and it is right only if every other screen's controls hide and the
        # chrome never does.
        bad, routed = [], True
        for code, screen in zip(CODES, SCREENS):
            try:
                click(ip, world, "nv_" + code)
            except Exception as exc:                    # noqa: BLE001
                c.ck("clicking nv_%s routes and paints" % code, False,
                     "%s: %s" % (type(exc).__name__, exc))
                routed = False
                break
            if ip.globals.get("swascreen") != screen:
                bad.append("nv_%s left the screen at %r"
                           % (code, ip.globals.get("swascreen")))
            for ct in world.cards[0].controls:
                if len(ct.name) < 3 or ct.name[2] != "_":
                    continue
                pfx = ct.name[:2]
                if pfx in ("nv", "ui"):
                    if ct.props.get("visible") is False:
                        bad.append("%s hidden on %s" % (ct.name, screen))
                    continue
                want = pfx == code
                if bool(ct.props.get("visible", True)) is not want:
                    bad.append("%s visible=%r on %s"
                               % (ct.name, ct.props.get("visible"), screen))
        if routed:
            c.ck("every rail button routes, paints, and leaves exactly one "
                 "screen visible with the rail untouched",
                 not bad, "; ".join(bad[:6]))
            try:
                click(ip, world, "nv_refresh")
                c.ck("and Refresh runs on top of all of it", True)
            except Exception as exc:                    # noqa: BLE001
                c.ck("and Refresh runs on top of all of it", False,
                     "%s: %s" % (type(exc).__name__, exc))
        c.ck("the click router left the screen lock balanced",
             world.locked == 0, "depth %d" % world.locked)

        drive(c, ip, world, sandbox)

        try:
            ip.call("closeStack", [])
            c.ck("closeStack tears down cleanly", True)
        except Exception as exc:                        # noqa: BLE001
            c.ck("closeStack tears down cleanly", False,
                 "%s: %s" % (type(exc).__name__, exc))
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def drive(c, ip, world, sandbox):
    """The flows a person actually runs, driven through the real click router
    so the routing, the paint and the state change are all in the loop. Every
    number asserted here comes from the same oracle the vector gate uses."""

    def put_field(name, text):
        ctl = world.anywhere(name)
        if ctl is None:
            raise AssertionError("no field %r" % name)
        ctl.content = text

    # ---- the boot wallet is the published test seed on testnet ------------
    c.eq("the boot wallet is on testnet", ip.globals.get("swanetwork"),
         "testnet")
    REF = WV.REF
    cr = REF.cr
    mnemonic = str(ip.constants.get("kWaTestMnemonic", ""))
    master = cr.bip32_master(cr.bip39_seed(mnemonic, ""))
    acct = cr.bip32_path(master,
                         REF.derivation_path("p2wpkh", "testnet", 0))
    neutered = dict(acct)
    neutered["seckey"] = b""

    xpub = str(ip.globals.get("swaaccountxpub", ""))
    c.eq("the account xpub is the one the oracle derives", xpub,
         REF.xkey_encode(neutered,
                         REF.xkey_version("testnet", "p2wpkh", True), False))

    addrs = ip.globals.get("swaaddresses") or {}
    n = int(LCS._n(addrs.get("n", 0)))
    c.eq("both chains are prefilled", n,
         2 * int(LCS._n(ip.constants.get("kWaPrefill", 0))))
    first = str(addrs.get("1", {}).get("address", "")) if n else ""
    leaf = cr.bip32_ckd(cr.bip32_ckd(acct, 0), 0)
    c.eq("the first receive address is BIP-84's published one for this seed",
         first,
         REF.address_for_spk("testnet", REF.spk_p2wpkh(leaf["pubkey"])))

    # ---- Receive: the QR is really built ---------------------------------
    click(ip, world, "nv_rc")
    click(ip, world, "rc_showQr")
    qr = world.anywhere("rc_qr")
    bmp = str(qr.props.get("text", "")) if qr is not None else ""
    c.ck("the Receive screen paints a real BMP into its image",
         bmp[:2] == "BM" and len(bmp) > 1000,
         "%d bytes, magic %r" % (len(bmp), bmp[:2]))
    uri = _fld(world, "rc_uri")
    c.ck("and the BIP-21 URI names the shown address",
         uri.startswith("bitcoin:") and first in uri, repr(uri[:80]))

    # ---- Send: a real spend, signed, against the oracle -------------------
    click(ip, world, "nv_sd")
    if not plant_utxos(ip, world):
        c.ck("the wallet has addresses to plant coins on", False)
        return
    ip.call("waRecomputeBalance", [])
    c.eq("the balance is the planted total",
         int(LCS._n((ip.globals.get("swabalance") or {}).get("confirmed", 0))),
         sum(u["value"] for u in UTXOS if u["confirmations"] > 0))

    put_field("sd_to", "%s,0.0005" % first)
    put_field("sd_rate", "2")
    click(ip, world, "sd_preview")
    out = _fld(world, "sd_out")
    c.ck("previewing a spend produces a summary and no error",
         "sat/vB" in out or "vsize" in out.lower(), repr(out[:120]))
    click(ip, world, "sd_sign")
    raw = str(ip.globals.get("swalastraw", ""))
    c.ck("signing produces a raw transaction", len(raw) > 200 and
         all(ch in "0123456789abcdef" for ch in raw.lower()),
         "%d hex chars" % len(raw))
    if raw:
        dec = REF.tx_decode(bytes.fromhex(raw))
        c.ck("the oracle decodes it as a segwit spend of one of our coins",
             (len(dec["vin"]) >= 1 and dec["vin"][0]["txid"] in
              [u["txid"] for u in UTXOS]), repr(dec["vin"][0]["txid"][:16]))
        c.ck("its inputs signal RBF",
             all(v["sequence"] == 0xFFFFFFFD for v in dec["vin"]),
             repr([hex(v["sequence"]) for v in dec["vin"]]))
        c.ck("every output pays a dust-clearing amount",
             all(o["value"] >= 294 for o in dec["vout"]),
             repr([o["value"] for o in dec["vout"]]))

    # ---- Send: the same spend as a PSBT, round-tripped through Tools -----
    click(ip, world, "sd_toPsbt")
    psbt = str(ip.globals.get("swalastpsbt", ""))
    c.ck("the same spend exports as a PSBT", psbt.startswith("cHNidP"),
         repr(psbt[:12]))
    if psbt:
        import base64
        parsed = REF.psbt_parse(base64.b64decode(psbt))
        c.ck("the oracle parses that PSBT and finds our inputs",
             len(parsed["inputs"]) >= 1, repr(len(parsed["inputs"])))
        click(ip, world, "nv_tl")
        put_field("tl_hex", psbt)
        click(ip, world, "tl_hold")
        c.ck("Tools accepts it and says what it is",
             "input" in _fld(world, "tl_out").lower(),
             repr(_fld(world, "tl_out")[:100]))
        click(ip, world, "tl_psbtSign")
        signed = str(ip.globals.get("swalastpsbt", ""))
        c.ck("signing the PSBT changes it and keeps it a PSBT",
             signed.startswith("cHNidP") and signed != psbt, "unchanged"
             if signed == psbt else repr(signed[:12]))
        click(ip, world, "tl_psbtFinal")
        c.ck("finalising it yields a network-ready transaction",
             "final" in _fld(world, "tl_out").lower()
             or len(str(ip.globals.get("swalastraw", ""))) > 200,
             repr(_fld(world, "tl_out")[:100]))

    # ---- Tools: sign and verify a message, and the tamper case ----------
    click(ip, world, "nv_tl")
    put_field("tl_msgAddr", "")
    put_field("tl_msg", "boot gate")
    click(ip, world, "tl_msgSign")
    sig = _fld(world, "tl_msgSig")
    c.ck("a message signs to a 65-byte base64 signature",
         len(sig) == 88 and sig.endswith("="), repr(sig[:16]))
    click(ip, world, "tl_msgVerify")
    c.ck("and the wallet verifies its own signature",
         "VALID" in _fld(world, "tl_out").upper()
         and "NOT" not in _fld(world, "tl_out").upper()[:40],
         repr(_fld(world, "tl_out")[:100]))
    # THE CASE TRAP, driven end to end: a Base58 address differing only in
    # case is a DIFFERENT address, and the engine's `is` would call it equal.
    addr = _fld(world, "tl_msgAddr")
    if addr and addr[:1] in "1mn2":
        put_field("tl_msgAddr", addr.swapcase())
        click(ip, world, "tl_msgVerify")
        c.ck("a case-mangled Base58 address does NOT verify",
             "VALID" not in _fld(world, "tl_out").upper()
             or "NOT VALID" in _fld(world, "tl_out").upper(),
             repr(_fld(world, "tl_out")[:100]))
        put_field("tl_msgAddr", addr)

    # ---- Settings: the wallet file, sealed and re-opened ------------------
    # THE SAVED WALLET IS MADE DISTINGUISHABLE FIRST. Forget resets to the
    # demonstration wallet, which derives the SAME account key the boot did -
    # so "the key changed" and "the key came back" would both hold with no
    # file involved at all, and neither check would mean anything. A label
    # the default does not carry is what makes the round trip observable.
    click(ip, world, "nv_st")
    ip.globals["swalabel"] = "Boot gate wallet"
    path = os.path.join(sandbox, "boot.dat")
    put_field("st_path", path)
    put_field("st_password", "boot-gate-passphrase")
    click(ip, world, "st_save")
    c.ck("saving writes a sealed file", os.path.isfile(path),
         "status: %s" % _fld(world, "uiStatus")[:80])
    if os.path.isfile(path):
        head = open(path, "rb").read(64).decode("latin-1")
        c.ck("the file's header is readable and says it is sealed",
             "sealed" in head, repr(head[:48]))
        c.ck("and the seed is NOT in it",
             str(ip.constants.get("kWaTestMnemonic", "")).encode("latin-1")
             not in open(path, "rb").read(), "the mnemonic is in the file")
        c.eq("and the password does not stay on the Settings screen",
             _fld(world, "st_password"), "")
        click(ip, world, "st_forget")
        c.eq("Forget returns to the demonstration wallet",
             str(ip.globals.get("swalabel", "")), "Demonstration wallet")
        c.eq("and leaves no seed, passphrase or pasted key on screen",
             (_fld(world, "wl_mnemonic"), _fld(world, "wl_pass"),
              _fld(world, "wl_xkey")), ("", "", ""))
        put_field("st_path", path)
        put_field("st_password", "boot-gate-passphrase")
        click(ip, world, "st_load")
        c.eq("loading it back restores the saved wallet",
             str(ip.globals.get("swalabel", "")), "Boot gate wallet")
        c.eq("with the same account key", str(ip.globals.get(
            "swaaccountxpub", "")), xpub)
        # tampering is CAUGHT, which is the whole point of the associated data
        blob = bytearray(open(path, "rb").read())
        blob[-1] ^= 0x01
        open(path, "wb").write(bytes(blob))
        click(ip, world, "st_load")
        c.ck("a tampered file is REFUSED, not silently half-loaded",
             "wrong" in _fld(world, "uiStatus").lower()
             or "could not" in _fld(world, "uiStatus").lower()
             or "tamper" in _fld(world, "uiStatus").lower(),
             repr(_fld(world, "uiStatus")[:120]))

    # ---- the log recorded all of it --------------------------------------
    click(ip, world, "nv_lg")
    c.ck("the log is not empty", len(_fld(world, "lg_text")) > 0)


def main(argv):
    # `--check` too, because that is the spelling this member's other gates
    # take and the one a maintainer will reach for first.
    # LINE-BUFFERED. This gate runs for minutes and writes to a pipe or a
    # file in every context that matters, where Python block-buffers - so a
    # run that is deriving forty addresses looks identical to a run that has
    # hung, which is the same "it looks finished / it looks stuck" confusion
    # the suite harness's own completeness trailer exists to end.
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except (AttributeError, ValueError):
        pass
    terse = "--terse" in argv or "--check" in argv
    path = None
    if "--file" in argv:
        path = argv[argv.index("--file") + 1]
    c = Checker(terse)
    c.note("booting %s" % os.path.relpath(path or DEMO, SUITE))
    run(c, path)
    if c.failed:
        print("check-wallet-boot: FAILED (%d of %d checks)" % (c.failed, c.n))
        return 1
    # A FLOOR, for the same reason the vector gate has one: "everything
    # passed" and "almost nothing ran" print the same way.
    if c.n < 30:
        print("check-wallet-boot: FAILED - only %d checks ran, expected at "
              "least 30. The boot stopped early." % c.n)
        return 1
    print("check-wallet-boot: OK (%d checks; the shipped stack boots, sweeps, "
          "routes, spends, seals and re-opens)" % c.n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
