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

HOW LONG IT TAKES, SO A SLOW RUN IS NOT READ AS A STUCK ONE
-----------------------------------------------------------
Twenty-five minutes or so, and almost all of it is real work: booting derives
forty addresses through script-level BIP-32 and bech32, the Receive check
builds a QR (eight mask evaluations plus three hundred rendered rows), and
Forget-then-reload derives the window twice more. The output is line-buffered
for exactly this reason. tools/test-wallet-boot.py, which is what actually
guards this gate against going blind, cuts the address window to two and
therefore runs in a fraction of that - which is why the build runs the
fixtures FIRST.

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

    #: set by --first-failure, which ONLY tools/test-wallet-boot.py passes.
    #: A fixture's verdict is settled the moment its seeded defect is caught,
    #: and everything after that point is the gate re-proving what it has
    #: already said - which for this gate means a QR build and a
    #: Forget-then-reload, minutes of work per fixture for no extra
    #: information. A normal run never sets it and always reports in full,
    #: because there the checks AFTER a failure are exactly the ones a person
    #: needs to see.
    stop_early = False

    class Enough(Exception):
        pass

    def ck(self, label, ok, detail=""):
        super().ck(label, ok, detail)
        if not ok and self.stop_early:
            raise Checker.Enough()

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
    # THE WALLET'S OWN WORDS. It writes "VERIFIED" or "NOT VERIFIED", and the
    # first draft of this check looked for "VALID" - a word that appears
    # nowhere on that screen - so it read the verified case as a failure. The
    # negative is checked by the NOT, not by the absence of the positive,
    # because "NOT VERIFIED" contains "VERIFIED".
    c.eq("and the wallet verifies its own signature",
         _fld(world, "tl_out").split("\n")[0].strip(), "VERIFIED")
    # AND THE NEGATIVE PATH, with one character of the message changed. Not
    # with a case-mangled address, which was this check's first draft: the
    # wallet's default script type is p2wpkh, so waFirstAddress answers with a
    # BECH32 address, and bech32 is case-insensitive BY SPEC - swapping its
    # case gives the same address and the verify correctly succeeds, so the
    # check silently skipped rather than testing anything. The Base58 case
    # binding is cwMsgVerify's, and it is checked where it belongs: in the
    # vector gate's folded tier, which re-runs the message vectors with `is`
    # folded to the engine's rule.
    msg = _fld(world, "tl_msg")
    put_field("tl_msg", msg[:-1] + ("X" if msg[-1:] != "X" else "Y"))
    click(ip, world, "tl_msgVerify")
    c.eq("one changed character in the message does NOT verify",
         _fld(world, "tl_out").split("\n")[0].strip(), "NOT VERIFIED")
    put_field("tl_msg", msg)

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
        # TAMPERING IS CAUGHT, which is the whole point of authenticating the
        # header as associated data. THE PASSWORD IS RE-ENTERED FIRST: a
        # successful load clears the field (waForgetPassword), so without this
        # the wallet refuses for the right reason and the wrong one - "that
        # file is sealed. Type its password." - and the tamper path is never
        # reached at all. The gate found that itself, on the run after the
        # clearing landed.
        blob = bytearray(open(path, "rb").read())
        blob[-1] ^= 0x01
        open(path, "wb").write(bytes(blob))
        put_field("st_path", path)
        put_field("st_password", "boot-gate-passphrase")
        click(ip, world, "st_load")
        status = _fld(world, "uiStatus").lower()
        c.ck("a tampered file is REFUSED, not silently half-loaded",
             "does not open this file" in status or "altered" in status,
             repr(_fld(world, "uiStatus")[:160]))
        c.eq("and the wallet it had open is untouched",
             str(ip.globals.get("swalabel", "")), "Boot gate wallet")

    # ---- the network root, and the chain the backend actually carries ----
    # THE DEFECT THIS SECTION EXISTS FOR: a funded testnet address reported no
    # coins, because waEsploraPath emitted the MAINNET "/api" root for every
    # network while the wallet defaults to testnet. Esplora answers a foreign
    # address with a 400, and only the two Tor transports read an HTTP status
    # (waHttpCheckStatus) - the clearnet one goes through `load URL`, which
    # hands waUrlDone a body and no code, so the refusal arrived as an empty
    # result and the wallet called itself synced.
    #
    # Nothing above could see it: every check in this gate and all 461 in the
    # vector gate are about what the wallet COMPUTES, and the address, the
    # xpub and the derivation were all correct. The wrong half was where it
    # asked.
    saved = {k: ip.globals.get(k)
             for k in ("swanetwork", "swabackend", "swahost")}

    def esplora_path(kind, arg=""):
        return str(ip.call("waEsploraPath", [{"kind": kind, "arg": arg}]))

    ADDR = "tb1q6rz28mcfaxtmd6v789l9rrlrusdprr9pqcpvkl"
    for net, root in (("mainnet", ""), ("testnet", "/testnet"),
                      ("signet", "/signet")):
        ip.globals["swanetwork"] = net
        c.eq("%s asks its own utxo index" % net, esplora_path("utxos", ADDR),
             root + "/api/address/" + ADDR + "/utxo")
        c.eq("%s asks its own chain tip" % net, esplora_path("tip"),
             root + "/api/blocks/tip/height")
    # EVERY kind, not just the two above: the root is applied once inside the
    # handler so a seventh request kind cannot forget it, and this is what
    # holds that property rather than the comment claiming it.
    ip.globals["swanetwork"] = "testnet"
    for kind in ("tip", "fees", "utxos", "history", "tx", "broadcast"):
        got = esplora_path(kind, ADDR)
        c.ck("the %s request carries the testnet root" % kind,
             got.startswith("/testnet/api"), got)

    def why(backend, host, net):
        ip.globals["swabackend"] = backend
        ip.globals["swahost"] = host
        ip.globals["swanetwork"] = net
        return str(ip.call("waBackendChainWhy", []))

    elec = str(ip.constants.get("kWaElectrumOnion", ""))
    clear = str(ip.constants.get("kWaEsploraClear", ""))
    onion = str(ip.constants.get("kWaEsploraOnion", ""))
    # The Electrum case is the one that MUST be refused rather than attempted:
    # a server answers for the wrong chain with an empty list, not an error,
    # so it is indistinguishable from an unused address.
    c.ck("the built-in Electrum server is refused off mainnet",
         why("electrum-tor", elec, "testnet") != "")
    c.eq("and allowed on mainnet, which it serves",
         why("electrum-tor", elec, "mainnet"), "")
    # The guard must not over-refuse either, or it becomes the defect.
    c.eq("Esplora is allowed on testnet", why("esplora-clear", clear, "testnet"), "")
    c.eq("Esplora is allowed on signet", why("esplora-tor", onion, "signet"), "")
    c.ck("regtest is refused against every built-in host",
         all(why(b, h, "regtest") != ""
             for b, h in (("esplora-clear", clear), ("esplora-tor", onion),
                          ("electrum-tor", elec))))
    c.eq("regtest is allowed against a host the person typed themselves",
         why("esplora-clear", "127.0.0.1:3002", "regtest"), "")
    c.eq("offline is never a chain complaint", why("offline", clear, "regtest"), "")

    # And the guard is REACHED: waSync refuses before it builds a request.
    ip.globals["swabackend"] = "electrum-tor"
    ip.globals["swahost"] = elec
    ip.globals["swanetwork"] = "testnet"
    try:
        ip.call("waSync", [])
        c.ck("waSync refuses a backend that cannot serve this chain", False,
             "it queued the requests instead")
    except LCS.Thrown as exc:
        c.ck("waSync refuses a backend that cannot serve this chain",
             "Electrum" in str(exc.msg), str(exc.msg)[:120])
    for k, v in saved.items():
        ip.globals[k] = v

    # ---- the script types, per INPUT rather than per wallet --------------
    # Three defects lived here, all invisible to the vector gate because that
    # gate drives the CALCULATOR (cw*) and every one of these is in how the
    # APP chooses what to hand it.
    saved2 = {k: ip.globals.get(k) for k in
              ("swanetwork", "swascripttype", "swakind", "swaimportedwif",
               "swaaddresses", "swautxos")}
    cr2 = WV.REF.cr

    # (1) An UNCOMPRESSED key has no SegWit address - BIP-143 forbids one - so
    # the import falls back to legacy. It used to record that legacy address
    # with the type the SCREEN was set to, and waSignSpend signs by type: a
    # P2PKH output got the BIP-143 sighash and a witness with an empty
    # scriptSig, which no node accepts.
    wif_u = cr2.wif_encode(bytes.fromhex("01" * 32), "testnet", False)
    ip.globals["swanetwork"] = "testnet"
    ip.globals["swascripttype"] = "p2wpkh"
    ip.globals["swakind"] = "key"
    ip.globals["swaimportedwif"] = wif_u
    recs = ip.call("waImportedRecords", [])
    rec1 = recs.get("1", {})
    addr_u = str(rec1.get("address", ""))
    c.ck("an uncompressed key falls back to a LEGACY address",
         addr_u[:1] in "mn", addr_u)
    c.eq("and the record says the type it really is, not the screen's",
         str(rec1.get("scripttype", "")), "p2pkh")
    c.eq("waRecordType agrees with the record", 
         str(ip.call("waRecordType", [rec1])), "p2pkh")
    c.eq("while the WALLET's own type is still what a new address would be",
         str(ip.call("waInputType", [])), "p2wpkh")

    # (2) waSignSpend asked waAccountNode() before the check that excuses an
    # imported key, so a WIF wallet could not sign ANYTHING - refused with
    # "no account key yet" about a wallet holding the only key it needs.
    ip.globals["swaaddresses"] = recs
    coin = {"address": addr_u, "txid": "aa" * 32, "vout": 0, "value": 100000,
            "height": 100, "frozen": False, "selected": True}
    ins = ip.call("cwListAdd", [ip.call("waEmptyList", []),
                                ip.call("cwTxInput", ["aa" * 32, 0, 4294967293])])
    spk = ip.call("cwScriptForAddress", ["testnet", addr_u])
    outs = ip.call("cwListAdd", [ip.call("waEmptyList", []),
                                 ip.call("cwTxOutput", [90000, spk])])
    sel = ip.call("cwListAdd", [ip.call("waEmptyList", []), coin])
    raw = ""
    try:
        raw = str(ip.call("waSignSpend", [ins, outs, sel, 0]))
        c.ck("an imported key can sign at all", True)
    except LCS.Thrown as exc:
        c.ck("an imported key can sign at all", False, str(exc.msg)[:140])
    if raw:
        # (3) and it signs it as the LEGACY input it is: no segwit marker,
        # a real scriptSig. The two together are what a node checks.
        c.ck("and signs it as a legacy spend, not a segwit one",
             raw[8:12] != "0001", raw[:24])
        dec = ip.call("cwTxDecode", [raw])
        ssig = str(dec["inputs"]["1"]["scriptsig"])
        c.ck("with a real scriptSig on the input", len(ssig) > 100,
             "%d hex chars" % len(ssig))

    # A COMPRESSED key at p2sh-p2wpkh keeps its own type - the fallback must
    # not fire where a SegWit address genuinely exists.
    wif_c = cr2.wif_encode(bytes.fromhex("01" * 32), "testnet", True)
    ip.globals["swaimportedwif"] = wif_c
    ip.globals["swascripttype"] = "p2sh-p2wpkh"
    rec2 = ip.call("waImportedRecords", []).get("1", {})
    c.eq("a compressed key at p2sh-p2wpkh keeps that type",
         str(rec2.get("scripttype", "")), "p2sh-p2wpkh")
    c.ck("and gets a P2SH address", str(rec2.get("address", ""))[:1] == "2",
         str(rec2.get("address", "")))

    # waRecordType's fallback: a record from an older saved file has no
    # scripttype, and for those the wallet's type really was the answer.
    c.eq("a record with no type falls back to the wallet's",
         str(ip.call("waRecordType", [{"scripttype": ""}])), "p2sh-p2wpkh")
    for k, v in saved2.items():
        ip.globals[k] = v

    # ---- mainnet is ALLOWED, and the public seed is called out -----------
    # The published test mnemonic is what this stack pre-fills. Mainnet is not
    # refused - that is a deliberate product decision - so what the wallet
    # owes instead is a warning that cannot be missed or dismissed.
    saved3 = {k: ip.globals.get(k) for k in ("swanetwork", "swamnemonic")}
    ip.globals["swamnemonic"] = str(ip.constants.get("kWaTestMnemonic", ""))
    ip.globals["swanetwork"] = "testnet"
    c.ck("the pre-filled seed is recognised as the published one",
         ip.call("waIsPublicTestSeed", []) is True)
    warn_t = str(ip.call("waPublicSeedWarning", []))
    c.ck("and is warned about even on testnet", "PUBLISHED" in warn_t, warn_t[:80])
    ip.globals["swanetwork"] = "mainnet"
    warn_m = str(ip.call("waPublicSeedWarning", []))
    c.ck("with a DANGER warning on mainnet", warn_m.startswith("DANGER"), warn_m[:80])
    c.ck("that says the keys are derivable by anyone",
         "ANYONE" in warn_m, warn_m[:120])
    c.ck("the Wallet screen carries it",
         warn_m[:40] in str(ip.call("waWalletAdvice", [])))
    # A REAL seed on mainnet gets the ordinary mainnet line, not the danger one.
    ip.globals["swamnemonic"] = ("legal winner thank year wave sausage worth "
                                 "useful legal winner thank yellow")
    c.ck("a real seed is not called public",
         ip.call("waIsPublicTestSeed", []) is not True)
    c.eq("and gets no public-seed warning",
         str(ip.call("waPublicSeedWarning", [])), "")
    for k, v in saved3.items():
        ip.globals[k] = v

    # ---- the screen unlocks even when the build throws -------------------
    # A Windows tester saw the window build and then OXT and the IDE both
    # freeze. The mechanism is `lock screen` with an unguarded body: a throw
    # skips the unlock, nothing repaints, and the engine looks hung with no
    # error anybody can read - so the freeze HID whatever really threw.
    # waDefaults is the other half: waBuild runs from preOpenStack, before
    # any wallet state exists, and cwTypeIndex refuses an empty script type
    # (correctly - it is a closed set) with "unknown script type """.
    c.eq("the boot leaves the screen unlocked", world.locked, 0)
    c.ck("waDefaults fills the state a painter can reach",
         all(str(ip.globals.get(k, "")) != ""
             for k in ("swanetwork", "swascripttype", "swakind")),
         {k: ip.globals.get(k) for k in
          ("swanetwork", "swascripttype", "swakind")})
    # And it is IDEMPOTENT: waBoot calls waResetWallet after it, so running
    # both must not fight. Re-running defaults must change nothing.
    before = {k: ip.globals.get(k) for k in
              ("swanetwork", "swascripttype", "swakind", "swaunit")}
    ip.call("waDefaults", [])
    c.eq("waDefaults is idempotent over an opened wallet",
         {k: ip.globals.get(k) for k in before}, before)
    # The empty type really does throw, so the guard above is not decoration.
    try:
        ip.call("cwAccountPath", ["", "testnet", 0])
        c.ck("an empty script type is refused by wallet-core", False,
             "it was accepted")
    except LCS.Thrown as exc:
        c.ck("an empty script type is refused by wallet-core",
             "unknown script type" in str(exc.msg), str(exc.msg)[:90])

    # ---- the transport that needs neither TLS nor Tor --------------------
    # Every other public path needs something this engine may not have: the
    # two Esplora mirrors are HTTPS-only and the engine's TLS is unmeasured
    # here, and both Tor transports need a daemon. On a machine with neither,
    # the wallet had NO public backend and the only answer left was "run your
    # own node". Electrum's wire protocol is line-delimited JSON over a plain
    # socket, which is what `open socket` speaks.
    saved4 = {k: ip.globals.get(k) for k in
              ("swabackend", "swahost", "swaport", "swanetwork")}
    ip.globals["swanetwork"] = "mainnet"
    ip.call("waSetBackend", ["electrum-clear"])
    c.eq("clearnet Electrum picks the public server",
         str(ip.globals.get("swahost")),
         str(ip.constants.get("kWaElectrumClear", "")))
    c.eq("and mainnet's PLAIN port, not the SSL one",
         int(LCS._n(ip.globals.get("swaport"))),
         int(LCS._n(ip.constants.get("kWaElectrumClearPort", 0))))
    ip.globals["swanetwork"] = "testnet"
    ip.call("waSetBackend", ["electrum-clear"])
    c.eq("testnet gets its own port - the port IS the chain here",
         int(LCS._n(ip.globals.get("swaport"))),
         int(LCS._n(ip.constants.get("kWaElectrumClearTestPort", 0))))
    c.ck("the two ports differ, or one chain would answer for the other",
         int(LCS._n(ip.constants.get("kWaElectrumClearPort", 0)))
         != int(LCS._n(ip.constants.get("kWaElectrumClearTestPort", 0))))
    # AND IT MUST NOT REPORT ITSELF BROKEN. The checks above verified the host
    # and the port and not the resulting STATE, so they passed over a
    # transport that told every user "OnionXT did not answer" - about a
    # transport whose whole purpose is needing neither Tor nor TLS. The Tor
    # requirement was written as a deny-list ("not offline and not
    # esplora-clear") and the new transport was simply not in it.
    saved_onion = ip.globals.get("swahaveonion")
    ip.globals["swahaveonion"] = "false"          # no Tor on this machine
    ip.call("waSetBackend", ["electrum-clear"])
    c.ck("clearnet Electrum works with NO OnionXT",
         str(ip.globals.get("swanetstate")) != "failed",
         "%s / %s" % (ip.globals.get("swanetstate"), ip.globals.get("swanetwhy")))
    c.eq("and says nothing about Tor", str(ip.globals.get("swanetwhy")), "")
    ip.call("waSetBackend", ["esplora-clear"])
    c.ck("clearnet Esplora works with no OnionXT too",
         str(ip.globals.get("swanetstate")) != "failed",
         str(ip.globals.get("swanetwhy")))
    ip.call("waSetBackend", ["electrum-tor"])
    c.ck("but a TOR transport does report it",
         "OnionXT" in str(ip.globals.get("swanetwhy")),
         str(ip.globals.get("swanetwhy")))
    # The predicate itself, over every backend, so a new one cannot inherit
    # the wrong default the way this one did.
    for backend, want in (("offline", False), ("esplora-clear", False),
                          ("electrum-clear", False), ("esplora-tor", True),
                          ("electrum-tor", True)):
        c.eq("waNeedsTor(%s)" % backend,
             ip.call("waNeedsTor", [backend]) is True, want)
    ip.globals["swahaveonion"] = saved_onion
    ip.call("waSetBackend", ["electrum-clear"])

    # It must be ALLOWED on the chains it serves and refused on the others.
    c.eq("allowed on testnet", str(ip.call("waBackendChainWhy", [])), "")
    ip.globals["swanetwork"] = "mainnet"
    c.eq("allowed on mainnet", str(ip.call("waBackendChainWhy", [])), "")
    ip.globals["swanetwork"] = "signet"
    c.ck("refused on signet, which it does not carry",
         str(ip.call("waBackendChainWhy", [])) != "")
    ip.globals["swanetwork"] = "regtest"
    c.ck("refused on regtest", str(ip.call("waBackendChainWhy", [])) != "")
    # And the Network screen states what it costs, like the other three.
    ip.globals["swanetwork"] = "testnet"
    priv = str(ip.call("waPrivacyText", []))
    c.ck("the privacy text covers it", "ELECTRUM OVER CLEARNET" in priv)
    c.ck("and says it needs no TLS", "no TLS" in priv, priv[-400:][:120])
    for k, v in saved4.items():
        ip.globals[k] = v

    # ---- the audit of 2026-09-01: five defects, each pinned here ---------
    #
    # Every check below drives the handler A PERSON REACHES, not the state
    # that handler is supposed to set. That distinction is the whole reason
    # the first of them got through: the block above proves the port is right
    # after waSetBackend by writing swanetwork itself and calling
    # waSetBackend - so it could never see a network change that does not go
    # through waSetBackend, which is the one a person makes.

    saved_audit = {k: ip.globals.get(k) for k in
              ("swabackend", "swahost", "swaport", "swanetwork", "swamnemonic",
               "swainflight", "swasock", "swaqueue", "swanetstate",
               "swafeerates", "swaunit")}

    # (1) THE PORT IS THE CHAIN, AND THE NETWORK CAN MOVE WITHOUT THE BACKEND.
    # The mnemonic is emptied first only so waSetNetwork does not re-derive
    # forty addresses per call; the handler under test is unchanged by that
    # (it guards the derivation on `sWaMnemonic is not empty`), and what is
    # being checked is the port, not the derivation.
    ip.globals["swamnemonic"] = ""
    mainport = int(LCS._n(ip.constants.get("kWaElectrumClearPort", 0)))
    testport = int(LCS._n(ip.constants.get("kWaElectrumClearTestPort", 0)))
    ip.call("waSetNetwork", ["mainnet"])
    ip.call("waSetBackend", ["electrum-clear"])
    c.eq("clearnet Electrum on mainnet dials the mainnet port",
         int(LCS._n(ip.globals.get("swaport"))), mainport)
    ip.call("waSetNetwork", ["testnet"])
    c.eq("and switching the NETWORK retunes it, without touching the backend",
         int(LCS._n(ip.globals.get("swaport"))), testport)
    c.eq("the chain guard still allows that combination",
         str(ip.call("waBackendChainWhy", [])), "")
    ip.call("waSetNetwork", ["mainnet"])
    c.eq("and back again, so the guard is not one-directional",
         int(LCS._n(ip.globals.get("swaport"))), mainport)
    # A HOST SOMEBODY TYPED IS LEFT ALONE: this wallet has no port table for
    # a server it does not ship, and inventing one would be worse than
    # leaving it. An over-reaching fix is the same defect with the sign
    # flipped, which this member has recorded once already.
    ip.globals["swahost"] = "electrum.example.invalid"
    ip.globals["swaport"] = 12345
    ip.call("waSetNetwork", ["testnet"])
    c.eq("a custom Electrum host keeps the port it was given",
         int(LCS._n(ip.globals.get("swaport"))), 12345)
    # and the other backends are indifferent to it
    ip.call("waSetBackend", ["esplora-clear"])
    before = int(LCS._n(ip.globals.get("swaport")))
    ip.call("waSetNetwork", ["mainnet"])
    c.eq("Esplora's port is not the chain selector and does not move",
         int(LCS._n(ip.globals.get("swaport"))), before)

    # (2) A NETWORK CHANGE STOPS WHAT IS IN FLIGHT. The reply to a request
    # about the OTHER chain's address arrives after the addresses have been
    # re-derived, and waRecomputeBalance sums every row of sWaUtxos whatever
    # its address - so the other chain's coins land in this chain's balance.
    ip.call("waSetBackend", ["electrum-clear"])
    ip.globals["swainflight"] = {"kind": "utxos", "arg": "tb1qoldchain", "id": "3"}
    ip.globals["swasock"] = "electrum.blockstream.info:50001"
    ip.call("waSetNetwork", ["testnet"])
    c.ck("a network change abandons the request in flight",
         not str(ip.globals.get("swainflight")).strip(),
         repr(ip.globals.get("swainflight")))
    c.ck("and closes the socket it was riding on",
         not str(ip.globals.get("swasock")).strip(),
         repr(ip.globals.get("swasock")))

    # (3) A FAILURE CLOSES THE CLEARNET SOCKET, as it has always closed the
    # Tor stream. Without this the connection survives a deadline with the
    # server still owing an answer, and the next request's armed read
    # collects the previous request's reply - so waMergeUtxos, which
    # REPLACES, writes one address's coins under another's.
    ip.call("waSetBackend", ["electrum-clear"])
    ip.globals["swasock"] = "electrum.blockstream.info:50001"
    ip.globals["swainflight"] = {"kind": "utxos", "arg": "addrA", "id": "9"}
    ip.call("waNetFail", ["a deadline, in the gate"])
    c.ck("waNetFail forgets the clearnet socket",
         not str(ip.globals.get("swasock")).strip(),
         repr(ip.globals.get("swasock")))
    c.ck("and still forgets what was in flight",
         not str(ip.globals.get("swainflight")).strip(),
         repr(ip.globals.get("swainflight")))
    ip.globals["swasock"] = "electrum.blockstream.info:50001"
    ip.call("waNetAbort", [])
    c.ck("waNetAbort forgets it too, as it always did",
         not str(ip.globals.get("swasock")).strip(),
         repr(ip.globals.get("swasock")))

    # (4) A REPLY MUST ANSWER THE QUESTION THAT WAS ASKED. The id was written
    # on every request and read on no reply, on a transport where ONE socket
    # serves the whole sync. Both directions are checked: a wrong id and a
    # missing one are refused, and the RIGHT one is still accepted - an
    # over-refusing correlation check would break every working server.
    ip.call("waSetBackend", ["electrum-clear"])
    ip.globals["swatipheight"] = ""
    good = '{"jsonrpc":"2.0","id":11,"result":{"height":812345,"hex":"00"}}'
    ip.call("waNetApply", ["tip", "", good, "11"])
    c.eq("a reply whose id matches is applied",
         str(ip.globals.get("swatipheight")), "812345")
    ip.globals["swatipheight"] = "812345"
    stale = '{"jsonrpc":"2.0","id":10,"result":{"height":999999,"hex":"00"}}'
    try:
        ip.call("waNetApply", ["tip", "", stale, "11"])
        c.ck("a reply whose id does NOT match is refused", False,
             "it was applied")
    except LCS.Thrown as exc:
        c.ck("a reply whose id does NOT match is refused",
             "different question" in str(exc.msg), str(exc.msg)[:110])
    c.eq("and it changed nothing", str(ip.globals.get("swatipheight")), "812345")
    # blockchain.headers.subscribe SUBSCRIBES, so a real server pushes this
    # down the same socket at every block. It has no id and no result.
    notif = ('{"jsonrpc":"2.0","method":"blockchain.headers.subscribe",'
             '"params":[{"height":999999,"hex":"00"}]}')
    try:
        ip.call("waNetApply", ["utxos", "addrB", notif, "12"])
        c.ck("a subscription notification is refused, not believed", False,
             "it was applied")
    except LCS.Thrown as exc:
        c.ck("a subscription notification is refused, not believed",
             "notification" in str(exc.msg), str(exc.msg)[:110])

    # (5) AN AMOUNT WRITTEN INTO THE SEND BOX IS IN THE UNIT THAT BOX IS READ
    # IN. waReadUri wrote BTC unconditionally, so a BIP-21 request for 1.5
    # BTC read back as 1.5 mBTC when the display unit was mBTC: a
    # thousandfold underpayment, silent because both numbers read "1.5".
    for unit, sat in (("BTC", 150000000), ("mBTC", 150000000),
                      ("sat", 150000000), ("mBTC", 10000), ("BTC", 10000)):
        ip.globals["swaunit"] = unit
        bare = ip.call("waAmountBare", [sat])
        back = int(LCS._n(ip.call("cwParseAmount", [str(bare), unit])))
        c.eq("%d sat written as %r in %s reads back unchanged"
             % (sat, str(bare), unit), back, sat)

    # (6) A FEE RATE THAT ARRIVED OVER A SOCKET IS CHECKED BEFORE IT BECOMES
    # THE DEFAULT THE SEND SCREEN PROPOSES. Both directions again: nonsense
    # is dropped and the previous value kept, and a believable rate is taken.
    cap = int(LCS._n(ip.constants.get("kWaMaxSuggestedRate", 0)))
    c.ck("there is a ceiling on a suggested fee rate", cap > 0, repr(cap))
    ip.globals["swafeerates"] = {"1": "7", "6": "3"}
    for bad in ("-1", "0", "not-a-number", "", str(cap + 1), "900000"):
        ip.call("waSetSuggestedRate", ["6", bad])
        c.eq("a suggested rate of %r is refused" % bad,
             str((ip.globals.get("swafeerates") or {}).get("6")), "3")
    ip.call("waSetSuggestedRate", ["6", "42"])
    c.eq("and a believable one is taken",
         str((ip.globals.get("swafeerates") or {}).get("6")), "42")
    ip.call("waSetSuggestedRate", ["6", str(cap)])
    c.eq("the ceiling itself is allowed, not off by one",
         str((ip.globals.get("swafeerates") or {}).get("6")), str(cap))

    # (7) A WRITE THAT FAILS MUST NOT SWALLOW THE REQUEST. The old path forgot
    # the socket without closing it and dropped sWaInFlight on the floor, so
    # that address was never asked about again and its coins never appeared -
    # a balance that is quietly short, which is a wrong number and not a
    # smaller one. The write itself cannot be driven here (this model has no
    # socket layer), so what is pinned is the shape the fix rests on: the
    # retry puts the record back at the FRONT and keeps everything behind it.
    ip.globals["swaqueue"] = ip.call("waEmptyList", [])
    ip.call("waNetQueue", ["utxos", "addrOne"])
    ip.call("waNetQueue", ["utxos", "addrTwo"])
    q = ip.call("waQueueFirst", [{"kind": "utxos", "arg": "addrZero",
                                  "id": "0", "rewritten": "true"}])
    c.eq("a requeued request goes to the FRONT",
         str((q.get("1") or {}).get("arg")), "addrZero")
    c.eq("and nothing behind it is lost",
         int(LCS._n(ip.call("cwListCount", [q]))),
         int(LCS._n(ip.call("cwListCount", [ip.globals.get("swaqueue")]))) + 1)
    c.eq("in the order they were queued",
         str((q.get("2") or {}).get("arg")), "addrOne")

    # (8) EVERY BACKEND IS IN THE PAINT LIST. waPaintChoice only touches the
    # names it is handed, so a backend missing from that literal can never
    # show as selected - and switching TO it darkens the previously lit
    # button without lighting anything, so the screen reports NO backend
    # while one is running. Driven through the real painter and read off the
    # real controls, because the defect was a name absent from a literal and
    # nothing looked at the buttons.
    saved_paint = {k: ip.globals.get(k) for k in ("swabackend", "swanetwork")}
    ip.globals["swanetwork"] = "mainnet"
    buttons = ("nw_bOffline", "nw_bEsploraTor", "nw_bElectrumTor",
               "nw_bEsploraClear", "nw_bElectrumClear")
    for backend, button in (("offline", "nw_bOffline"),
                            ("esplora-tor", "nw_bEsploraTor"),
                            ("electrum-tor", "nw_bElectrumTor"),
                            ("esplora-clear", "nw_bEsploraClear"),
                            ("electrum-clear", "nw_bElectrumClear")):
        ip.call("waSetBackend", [backend])
        ip.call("waPaintNetwork", [])
        lit = [n for n in buttons
               if str(_ctl_prop_get(world.anywhere(n), "hilite")).lower()
               in ("true", "1")]
        c.eq("selecting %s lights exactly its own button" % backend,
             lit, [button])
    for k, v in saved_paint.items():
        ip.globals[k] = v

    # (9) A SYNC WITH A FAILED REQUEST IS NOT GREEN. waNetDeliver cleared the
    # failure state on every reply, so a scan in which one address timed out
    # went green on the next address that answered, and the wallet reported a
    # balance simply missing whatever that address holds.
    ip.globals["swanetwork"] = "mainnet"
    ip.call("waSetBackend", ["electrum-clear"])
    ip.globals["swasyncfailures"] = 0
    ip.call("waNetFail", ["a refused request, in the gate"])
    c.ck("a failed request is counted",
         int(LCS._n(ip.globals.get("swasyncfailures"))) >= 1,
         repr(ip.globals.get("swasyncfailures")))
    c.ck("and the reason says the sync is incomplete",
         "incomplete" in str(ip.globals.get("swanetwhy")),
         str(ip.globals.get("swanetwhy"))[:140])
    ip.globals["swainflight"] = {"kind": "tip", "arg": "", "id": "5"}
    ip.globals["swasock"] = ""
    ip.globals["swatipheight"] = ""
    ip.call("waNetDeliver",
            ['{"jsonrpc":"2.0","id":5,"result":{"height":800001,"hex":"00"}}'])
    c.eq("a later success still applies",
         str(ip.globals.get("swatipheight")), "800001")
    c.ck("but does not erase the failure it did not fix",
         str(ip.globals.get("swanetwhy")) != "",
         "a later reply cleared swanetwhy")
    ip.globals["swasyncfailures"] = 3
    try:
        ip.call("waSync", [])
    except LCS.Thrown:
        pass
    c.eq("and a fresh sync is allowed to be green again",
         int(LCS._n(ip.globals.get("swasyncfailures"))), 0)

    # (10) THE TWO TRANSPORTS MUST AGREE ABOUT THE SAME QUANTITY. Three times
    # over, the Esplora branch validated something and the Electrum branch
    # beside it did not - a chain tip, a broadcast txid, and whether the
    # answer was even a list. Each validator is now one handler used by both,
    # and each is checked in both directions.
    c.eq("a real height is taken",
         str(ip.call("waCheckedHeight", ["812345", "test"])), "812345")
    for bad in ("not-a-height", "<!DOCTYPE html>", "-1", ""):
        try:
            ip.call("waCheckedHeight", [bad, "test"])
            c.ck("a chain tip of %r is refused" % bad, False, "accepted")
        except LCS.Thrown as exc:
            c.ck("a chain tip of %r is refused" % bad,
                 "not a height" in str(exc.msg), str(exc.msg)[:90])
    good_txid = "ab" * 32
    c.eq("a real txid is taken",
         str(ip.call("waCheckedTxid", [good_txid, "test"])), good_txid)
    for bad in ("", "ok", "ab" * 31, "zz" * 32, "error: fee too low"):
        try:
            ip.call("waCheckedTxid", [bad, "test"])
            c.ck("a broadcast reply of %r is refused" % bad[:24], False,
                 "reported as sent")
        except LCS.Thrown as exc:
            c.ck("a broadcast reply of %r is refused" % bad[:24],
                 "NOT accepted" in str(exc.msg), str(exc.msg)[:90])

    # AN ANSWER THAT IS NOT A LIST IS NOT AN EMPTY LIST. waMergeUtxos drops
    # every record for the address before it re-fills, and cwJsonCount answers
    # 0 for a null or a string - so without this a well-formed non-list reply
    # DELETED what the address holds and reported a synced, empty wallet.
    # AND AN EMPTY LIST IS STILL A LIST. Written as a bare c.ck(..., True)
    # after the call, this was a check that could not fail - which this
    # member's own record calls the worst kind of gate, and which the entry
    # this commit adds says out loud. It asserts the absence of a throw now.
    try:
        ip.call("waCheckList", [ip.call("cwJsonParse", ["[]"]), "unspent-output"])
        c.ck("an empty list is still a list and is not refused", True)
    except LCS.Thrown as exc:
        c.ck("an empty list is still a list and is not refused", False,
             str(exc.msg)[:90])
    for bad in ("null", '"nope"', "42", "true", "{}"):
        try:
            ip.call("waCheckList", [ip.call("cwJsonParse", [bad]), "utxo"])
            c.ck("a %s result is refused, not read as empty" % bad, False,
                 "accepted")
        except LCS.Thrown as exc:
            c.ck("a %s result is refused, not read as empty" % bad,
                 "rather than a list" in str(exc.msg), str(exc.msg)[:90])
    # and end to end: a hostile non-list must leave the coins alone
    ip.call("waSetBackend", ["electrum-clear"])
    ip.globals["swautxos"] = ip.call("cwListAdd",
        [ip.call("waEmptyList", []),
         {"address": "addrK", "txid": "cc" * 32, "vout": 0, "value": 500000,
          "confirmations": 6, "height": 800000}])
    before = int(LCS._n(ip.call("cwListCount", [ip.globals.get("swautxos")])))
    try:
        ip.call("waNetApply",
                ["utxos", "addrK", '{"jsonrpc":"2.0","id":3,"result":null}', "3"])
    except LCS.Thrown:
        pass
    c.eq("a null utxo reply does not delete the address's coins",
         int(LCS._n(ip.call("cwListCount", [ip.globals.get("swautxos")]))), before)

    # (11) AND THE PILL IS THE STATE. Preserving only the sentence left the
    # indicator visible on every screen green over a sync that lost requests.
    ip.globals["swasyncfailures"] = 0
    ip.call("waNetFail", ["a lost request, in the gate"])
    ip.globals["swainflight"] = {"kind": "tip", "arg": "", "id": "8"}
    ip.globals["swasock"] = ""
    ip.call("waNetDeliver",
            ['{"jsonrpc":"2.0","id":8,"result":{"height":800002,"hex":"00"}}'])
    c.eq("a later reply on a lossy sync leaves the state partial, not ok",
         str(ip.globals.get("swanetstate")), "partial")
    ip.globals["swasyncfailures"] = 0
    ip.globals["swainflight"] = {"kind": "tip", "arg": "", "id": "9"}
    ip.call("waNetDeliver",
            ['{"jsonrpc":"2.0","id":9,"result":{"height":800003,"hex":"00"}}'])
    c.eq("and a clean sync is still ok", str(ip.globals.get("swanetstate")), "ok")

    # (12) A WALLET THAT CANNOT SIGN MUST NOT BE HOLDING KEYS. waDropSeed's own
    # comment says the status line is "now true about the state", and it was
    # not: it cleared the mnemonic and left sWaAccountXprv and the `seckey`
    # inside every derived address record where the previous seed wallet put
    # them. waAccountNode PREFERS the private half and waSeckeyFor reads the
    # record's key, so a wallet the screen called watch-only could still sign.
    saved_drop = {k: ip.globals.get(k) for k in
                  ("swakind", "swamnemonic", "swapassphrase", "swaaccountxprv",
                   "swaaddresses")}
    ip.globals["swaaccountxprv"] = "xprvSENTINEL"
    ip.globals["swamnemonic"] = "sentinel mnemonic words"
    before = int(LCS._n(ip.call("cwListCount", [ip.globals.get("swaaddresses")])))
    c.ck("the wallet has derived addresses to lose", before > 0, repr(before))
    seckeys = [k for i in range(1, before + 1)
               if str((ip.globals["swaaddresses"].get(str(i)) or {}).get("seckey", ""))]
    c.ck("and those records really do carry private keys",
         len(seckeys) > 0, "%d of %d" % (len(seckeys), before))
    ip.call("waDropSeed", [])
    c.eq("waDropSeed clears the mnemonic", str(ip.globals.get("swamnemonic")), "")
    c.eq("and the account xprv the previous wallet left",
         str(ip.globals.get("swaaccountxprv")), "")
    c.eq("and every derived record that carried a seckey with it",
         int(LCS._n(ip.call("cwListCount", [ip.globals.get("swaaddresses")]))), 0)
    for k, v in saved_drop.items():
        ip.globals[k] = v

    # (13) THE WATCH-ONLY BOX MUST REFUSE A PRIVATE KEY. The branch checked the
    # network and nothing else, so an account xprv - one character from its
    # xpub - was stored in sWaAccountXpub and then shown as "safe to hand
    # out", copied, exported and written to the wallet file as `xpub`. And it
    # was not watch-only either: waDeriveAddresses re-fills every record
    # through waAccountNode, which prefers the private half.
    saved_watch = {k: ip.globals.get(k) for k in
                   ("swakind", "swanetwork", "swascripttype", "swaaccountxpub",
                    "swaaccountxprv", "swaaddresses", "swamnemonic")}
    ip.globals["swanetwork"] = "mainnet"
    ip.globals["swascripttype"] = "p2wpkh"
    ip.globals["swakind"] = "watch"
    # THE PAIR IS DERIVED, NOT PASTED. A hand-copied zprv/zpub pair would be
    # one typo away from a checksum failure that reads like the guard working,
    # so the wallet derives its own from the published test seed and the two
    # halves are a real pair by construction.
    ip.globals["swakind"] = "seed"
    ip.globals["swamnemonic"] = str(ip.constants.get("kWaTestMnemonic", ""))
    ip.globals["swapassphrase"] = ""
    ip.call("waDeriveAccount", [])
    XPRV = str(ip.globals.get("swaaccountxprv"))
    XPUB = str(ip.globals.get("swaaccountxpub"))
    c.ck("the test seed produced a mainnet p2wpkh account pair",
         XPRV.startswith("zprv") and XPUB.startswith("zpub"),
         "%r / %r" % (XPRV[:8], XPUB[:8]))
    ip.globals["swakind"] = "watch"
    ip.globals["swamnemonic"] = ""
    ip.globals["swaaccountxpub"] = ""
    ip.globals["swaaccountxprv"] = ""
    c.ck("wallet-core can tell a private extended key from a public one",
         ip.call("cwXKeyIsPrivate", [XPRV]) is True, "cwXKeyIsPrivate(zprv)")
    c.ck("and says so the other way too",
         ip.call("cwXKeyIsPrivate", [XPUB]) is False, "cwXKeyIsPrivate(zpub)")
    world.anywhere("wl_xkey").content = XPRV
    try:
        ip.call("waOpenWallet", [])
        c.ck("the watch-only box refuses a PRIVATE extended key", False,
             "it was accepted; swaaccountxpub=%r"
             % str(ip.globals.get("swaaccountxpub"))[:24])
    except LCS.Thrown as exc:
        c.ck("the watch-only box refuses a PRIVATE extended key",
             "PRIVATE extended key" in str(exc.msg), str(exc.msg)[:110])
    c.eq("and stores nothing when it refuses",
         str(ip.globals.get("swaaccountxpub")), "")
    # and the matching PUBLIC key still opens, so the guard is not a wall
    world.anywhere("wl_xkey").content = XPUB
    try:
        ip.call("waOpenWallet", [])
        c.eq("but the matching PUBLIC key is still accepted",
             str(ip.globals.get("swaaccountxpub")), XPUB)
    except LCS.Thrown as exc:
        c.ck("but the matching PUBLIC key is still accepted", False,
             str(exc.msg)[:110])
    for k, v in saved_watch.items():
        ip.globals[k] = v

    # (14) A LABEL CANNOT FORGE A WALLET-FILE RECORD. The file is one record
    # per line, name and value split by a tab, parsed last-wins - and a label
    # is the one field a person does not type: a BIP-21 URI carries one, and
    # cwPercentDecode turns %0A into a real newline. So a payer could put
    # `Refund\nkind\twatch\nxpub\t<their key>` in an invoice and have the
    # next save-then-open replace this wallet's account key with theirs.
    tab, nl, cr = chr(9), chr(10), chr(13)
    hostile = "Refund" + nl + "kind" + tab + "watch" + nl + "xpub" + tab + "zpubEVIL"
    cleaned = str(ip.call("waSafeText", [hostile]))
    c.ck("waSafeText removes the record separators", 
         (tab not in cleaned) and (nl not in cleaned) and (cr not in cleaned),
         repr(cleaned[:60]))
    c.ck("and keeps everything else", "Refund" in cleaned and "zpubEVIL" in cleaned,
         repr(cleaned[:60]))
    c.eq("ordinary label text is untouched",
         str(ip.call("waSafeText", ["Alice's refund #3 (rent)"])),
         "Alice's refund #3 (rent)")
    # end to end through the URI reader, which is how it would actually arrive
    saved_lbl = {k: ip.globals.get(k) for k in ("swalabels", "swanetwork")}
    ip.globals["swalabels"] = {}
    ip.globals["swanetwork"] = "mainnet"
    world.anywhere("sd_to").content = (
        "bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4?amount=0.001"
        "&label=Refund%0Akind%09watch%0Axpub%09zpubEVIL")
    try:
        ip.call("waReadUri", [])
    except LCS.Thrown as exc:
        c.ck("the URI reader accepted the payment", False, str(exc.msg)[:90])
    stored = str((ip.globals.get("swalabels") or {}).get(
        "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", ""))
    c.ck("a URI label reaches the wallet with no separators in it",
         (tab not in stored) and (nl not in stored), repr(stored[:70]))
    # and the writer refuses one anyway, so a door added later is loud
    ip.globals["swalabels"] = {"bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4":
                               "Refund" + nl + "xpub" + tab + "zpubEVIL"}
    try:
        ip.call("waSerializeWallet", [])
        c.ck("and waSerializeWallet refuses to write one anyway", False,
             "it wrote the forged record")
    except LCS.Thrown as exc:
        c.ck("and waSerializeWallet refuses to write one anyway",
             "record separator" in str(exc.msg) or "separator" in str(exc.msg),
             str(exc.msg)[:110])
    for k, v in saved_lbl.items():
        ip.globals[k] = v

    # (15) THE PERSISTENT SOCKET MUST BE THE ONE THE SETTINGS NAME. Reuse was
    # tested by "is one open?" alone, so a host or port edited on the Network
    # screen reached the state and the fields and not the connection.
    ip.globals["swanetwork"] = "mainnet"
    ip.call("waSetBackend", ["electrum-clear"])
    ip.globals["swasock"] = "oldhost.example:50001"
    ip.globals["swahost"] = "newhost.example"
    ip.globals["swaport"] = 50001
    ip.globals["swainflight"] = ""
    ip.globals["swaqueue"] = ip.call("waEmptyList", [])
    ip.call("waNetQueue", ["tip", ""])
    try:
        ip.call("waNetPump", [])
    except LCS.Thrown:
        pass
    c.ck("a host change closes the socket it no longer names",
         str(ip.globals.get("swasock")) != "oldhost.example:50001",
         repr(ip.globals.get("swasock")))

    for k, v in saved_audit.items():
        ip.globals[k] = v

    # ---- the wallet boots even when openStack never fired ----------------
    # Pasting this script into a stack that is ALREADY OPEN means openStack
    # has already fired, so waBoot never runs: no probe, no wallet state. Both
    # engine-reported defects above are that one cause wearing two disguises.
    c.eq("the boot marked itself booted", str(ip.globals.get("swabooted")),
         "true")
    saved5 = {k: ip.globals.get(k) for k in
              ("swabooted", "swahavecoin", "swascripttype")}
    ip.globals["swabooted"] = ""
    ip.globals["swahavecoin"] = ""
    ip.call("waEnsureBooted", [])
    c.eq("waEnsureBooted boots a wallet that never got openStack",
         str(ip.globals.get("swabooted")), "true")
    c.eq("and the probe really ran", str(ip.globals.get("swahavecoin")), "true")
    # Idempotent: a second call must not re-probe and re-reset a live wallet.
    ip.globals["swalabel"] = "sentinel"
    ip.call("waEnsureBooted", [])
    c.eq("and a second call changes nothing",
         str(ip.globals.get("swalabel")), "sentinel")
    for k, v in saved5.items():
        ip.globals[k] = v

    # ---- the Electrum wire shapes, as a real server sends them -----------
    # THE BYTES IN THE TIP CASE ARE A REAL SERVER'S. waNetApply chose its
    # parser by backend NAME ("electrum-tor"), so the clearnet Electrum
    # transport - same protocol, different carrier - had every reply parsed as
    # ESPLORA. The tip is the first request a sync makes, so it was the first
    # to fail, and it failed by measuring a perfectly good JSON object against
    # "is this a bare integer" and blaming the server.
    #
    # All five shapes are pinned, not just the one that broke: the other four
    # go through the same dispatch and had never seen a real reply either.
    saved6 = {k: ip.globals.get(k) for k in
              ("swabackend", "swainflight", "swatipheight", "swafeerates",
               "swautxos", "swahistory")}
    ip.globals["swabackend"] = "electrum-clear"

    def wire(kind, arg, body):
        # THE ID GOES WITH IT. waNetApply correlates a reply to its request by
        # the JSON-RPC id now - on a persistent connection that is the only
        # correlation there is - so these fixtures, which are a real server's
        # bytes and carry real ids, must claim to have asked the question they
        # are answering. Taking the id OUT of the body rather than passing it
        # separately keeps the fixture and the request it answers in one place.
        m = re.search(r'"id"\s*:\s*"?([^,"}\s]+)', body)
        rid = m.group(1) if m else ""
        ip.globals["swainflight"] = {"kind": kind, "arg": arg, "id": rid}
        ip.call("waNetApply", [kind, arg, body, rid])

    wire("tip", "", '{"id":1,"jsonrpc":"2.0","result":{"height":5127803,'
                    '"hex":"00e008208dbd5e3fc1750a0000000000000000000000"}}')
    c.eq("a real server's chain tip is read", str(ip.globals.get("swatipheight")),
         "5127803")
    # estimatefee answers in BTC per KILOBYTE - a different unit from every
    # other number on that screen, so a missed conversion is a fee 100000x out.
    wire("fees", "", '{"id":2,"jsonrpc":"2.0","result":0.00001}')
    c.eq("BTC/kB is converted to sat/vB",
         str((ip.globals.get("swafeerates") or {}).get("6")), "1")
    # -1 is Electrum for "no estimate", and must not become a negative rate.
    wire("fees", "", '{"id":3,"jsonrpc":"2.0","result":-1}')
    c.eq("a -1 no-estimate leaves the rate alone",
         str((ip.globals.get("swafeerates") or {}).get("6")), "1")
    addr0 = str((ip.globals.get("swaaddresses") or {}).get("1", {})
                .get("address", ""))
    wire("utxos", addr0,
         '{"id":4,"jsonrpc":"2.0","result":[{"tx_hash":"%s","tx_pos":0,'
         '"height":5127000,"value":123456}]}' % ("bb" * 32))
    u = ip.globals.get("swautxos") or {}
    c.eq("listunspent lands as one coin", int(LCS._n(u.get("n", 0))), 1)
    c.eq("at the right address", str(u.get("1", {}).get("address", "")), addr0)
    c.eq("with the right value", int(LCS._n(u.get("1", {}).get("value", 0))),
         123456)
    wire("history", addr0,
         '{"id":5,"jsonrpc":"2.0","result":[{"tx_hash":"%s","height":5127000}]}'
         % ("cc" * 32))
    c.eq("get_history lands as one row",
         int(LCS._n((ip.globals.get("swahistory") or {}).get("n", 0))), 1)
    # A JSON-RPC error must be REPORTED, never parsed as data.
    try:
        wire("tip", "", '{"id":6,"jsonrpc":"2.0","error":{"code":-32601,'
                        '"message":"unknown method"}}')
        c.ck("a JSON-RPC error reply is refused", False, "it was accepted")
    except LCS.Thrown as exc:
        c.ck("a JSON-RPC error reply is refused",
             "refused" in str(exc.msg), str(exc.msg)[:80])
    # THE SCRIPT HASH, against an independent computation. Electrum asks by
    # SHA-256 of the scriptPubKey BYTE-REVERSED, and getting the reversal
    # wrong makes every address look unused - an empty wallet, not an error,
    # and indistinguishable from the socket bug that sat on top of it.
    import hashlib as _hl
    spk = str(ip.call("cwScriptForAddress", ["testnet", addr0]))
    c.eq("the Electrum script hash is sha256(spk) reversed",
         str(ip.call("cwElectrumScripthash", [spk])).lower(),
         _hl.sha256(bytes.fromhex(spk)).digest()[::-1].hex())
    # ...and the reversal is really happening, or the check above would pass
    # for an implementation that simply returned the digest.
    c.ck("and the reversal is not a no-op",
         str(ip.call("cwElectrumScripthash", [spk])).lower()
         != _hl.sha256(bytes.fromhex(spk)).hexdigest())
    req = str(ip.call("waElectrumRequest",
                      [{"kind": "utxos", "arg": addr0, "id": 7}]))
    c.ck("and listunspent asks for that hash",
         "blockchain.scripthash.listunspent" in req
         and str(ip.call("cwElectrumScripthash", [spk])).lower() in req.lower(),
         req[:120])

    # And the protocol predicate itself, over every backend.
    for backend, want in (("electrum-tor", True), ("electrum-clear", True),
                          ("esplora-tor", False), ("esplora-clear", False),
                          ("offline", False)):
        c.eq("waIsElectrum(%s)" % backend,
             ip.call("waIsElectrum", [backend]) is True, want)
    for k, v in saved6.items():
        ip.globals[k] = v

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
    c.stop_early = "--first-failure" in argv
    c.note("booting %s" % os.path.relpath(path or DEMO, SUITE))
    try:
        run(c, path)
    except Checker.Enough:
        print("  (stopped at the first failure, as --first-failure asked)")
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
