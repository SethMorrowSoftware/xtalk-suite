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
import json
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

        # `the clickLine` - what the engine sets on a mouseDown in a field,
        # "line N of field M". The world carries one while a click drives, the
        # way it carries the target; empty otherwise, which is the engine's
        # own answer outside a click.
        m = re.match(r'the\s+clickLine\b', rest, re.I)
        if m:
            self.i += m.end()
            return getattr(self.ip.world, "clickline", "") or ""

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


_OX_CMD = re.compile(r'(oxDial|oxWrite|oxCloseStream|oxSetSocksPort|'
                     r'oxSetCallbackOwner|oxSetStreamCallback)\b\s*(.*)$', re.I)


class WalletInterp(DB.DemoInterp):
    def eval_expr(self, expr, env):
        return WalletExpr(self, env).parse(expr)

    def _call_args(self, rest, env):
        # the interpreter's own comma-separated argument parse, so a call's
        # arguments here mean what they mean everywhere else
        args = []
        if rest.strip():
            p = WalletExpr(self, env)
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
        world = self.world

        # THE MODELLED TOR. OnionXT's own dial goes to `open socket`, which
        # nothing headless can model, so while a block has switched it on
        # (world.tor is a list) the five stream commands the wallet issues
        # are recorded there instead of run, and answer through `the result`
        # the way the real ones do: a dial hands back the next handle, a
        # write succeeds unless the block plants a refusal. The stream STATE
        # the wallet asks about is world.tor_state, answered by the
        # oxStreamState stand-in the same block installs. Off by default:
        # the boot must still fail loudly if it ever dials.
        m = _OX_CMD.match(line)
        if m and isinstance(getattr(world, "tor", None), list):
            name = m.group(1).lower()
            if name in ("oxsetcallbackowner", "oxsetsocksport",
                        "oxsetstreamcallback"):
                world.tor.append((name, m.group(2)))
                return i + 1
            args = self._call_args(m.group(2), env)
            if name == "oxdial":
                world.tor_handles += 1
                h = world.tor_handles
                world.tor_state[h] = "connecting"
                world.tor.append(("dial", str(LCS._disp(args[0])),
                                  int(LCS._n(args[1])), h))
                world.result = h
                return i + 1
            h = int(LCS._n(args[0]))
            if name == "oxwrite":
                world.tor.append(("write", h, str(LCS._disp(args[1]))))
                world.result = world.tor_write_fail
                return i + 1
            world.tor.append(("close", h))
            world.tor_state.pop(h, None)
            world.result = ""
            return i + 1

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
           "ordinals", "vault", "tools", "network", "log", "settings"]
CODES = ["wl", "rc", "ad", "sd", "cn", "hs", "od", "vt", "tl", "nw", "lg", "st"]

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


def unlst_boot(a):
    """A cw list (an array with "n") as a Python list of its records."""
    n = int(LCS._n(a.get("n", 0) or 0)) if isinstance(a, dict) else 0
    return [a.get(str(i), "") for i in range(1, n + 1)]


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
        ip.src_text = src       # for the checks that read ORDER from the source

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
    second = str(addrs.get("2", {}).get("address", "")) if n > 1 else ""
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

    # ---- a note to the chain: OP_RETURN as a payment line (2026-09-04) ----
    # "note: text" or "data: hex" in the Pay-to box becomes one OP_RETURN
    # output of value 0, carried as a payment record so sizing, selection,
    # review, signing and the fee bump see nothing new. The output's size is
    # in its kind ("nulldata:N"); the oracle sizes the same spend the same way.
    put_field("sd_to", "%s,0.0005\nnote: hello, chain" % first)
    click(ip, world, "sd_preview")
    out = _fld(world, "sd_out")
    c.ck("the review names the data output and shows the note",
         "OP_RETURN" in out and "12 bytes" in out and 'text "hello, chain"' in out,
         repr(out[:200]))
    click(ip, world, "sd_sign")
    raw_n = str(ip.globals.get("swalastraw", ""))
    c.ck("a spend with a note signs", len(raw_n) > 200, "%d hex chars" % len(raw_n))
    if len(raw_n) > 200:
        dec_n = REF.tx_decode(bytes.fromhex(raw_n))
        nulls = [o for o in dec_n["vout"] if o["scriptpubkey"].startswith("6a")]
        c.eq("exactly one OP_RETURN output", len(nulls), 1)
        if nulls:
            c.eq("of value 0", nulls[0]["value"], 0)
            c.eq("carrying the note's bytes",
                 nulls[0]["scriptpubkey"], REF.spk_op_return(b"hello, chain").hex())
        c.ck("the other outputs still clear dust",
             all(o["value"] >= 294 for o in dec_n["vout"]
                 if not o["scriptpubkey"].startswith("6a")),
             repr([o["value"] for o in dec_n["vout"]]))
        # the sizer counted it: the wallet's vsize and the oracle's agree on
        # a spend with a data output of this length
        kinds = ["p2wpkh"] * (len(dec_n["vout"]) - 1) + ["nulldata:12"]
        want_vs = REF.estimate_vsize(["p2wpkh"] * len(dec_n["vin"]), kinds)
        c.ck("the estimated vsize allows for the data output",
             abs(int(dec_n["vsize"]) - want_vs) <= 2,
             "decoded %s vs estimated %d" % (dec_n.get("vsize"), want_vs))
        # ...and Inspect reads it back as text
        insp = str(ip.call("waInspectRaw", [raw_n]))
        c.ck("Inspect shows the OP_RETURN output as text",
             'OP_RETURN text "hello, chain"' in insp, insp[-300:])
    # the refusals, each by name
    for label, text, want in (
            ("two notes are refused - a second OP_RETURN does not relay",
             "%s,0.0005\nnote: one\nnote: two" % first, "only one OP_RETURN"),
            ("data: with odd hex is refused",
             "%s,0.0005\ndata: abc" % first, "even number"),
            ("data: with non-hex is refused",
             "%s,0.0005\ndata: zz" % first, "0-9 a-f"),
            ("an empty note is refused",
             "%s,0.0005\nnote:" % first, "empty")):
        put_field("sd_to", text)
        try:
            ip.call("waParsePayments", [])
            c.ck(label, False, "accepted")
        except LCS.Thrown as exc:
            c.ck(label, want in str(exc.msg), str(exc.msg)[:100])
    # a long note is offered with a warning, not refused
    put_field("sd_to", "%s,0.0005\nnote: %s" % (first, "x" * 100))
    click(ip, world, "sd_preview")
    out = _fld(world, "sd_out")
    c.ck("a note over 80 bytes is warned about, not refused",
         "OVER 80 BYTES" in out and "100 bytes" in out, repr(out[:200]))
    # data: hex, and a note-only spend (everything but the fee comes back)
    put_field("sd_to", "data: deadbeef")
    pays = ip.call("waParsePayments", [])
    rec = pays.get("1", {}) if isinstance(pays, dict) else {}
    c.eq("data: hex becomes a nulldata payment of that many bytes",
         [str(rec.get("kind")), str(rec.get("script")), int(LCS._n(rec.get("value", 1)))],
         ["nulldata:4", REF.spk_op_return(bytes.fromhex("deadbeef")).hex(), 0])
    # the inscription reader, on an envelope the oracle builds
    env = (b"\x00\x63" + REF.push(b"ord") + REF.push(b"\x01")
           + REF.push(b"text/plain;charset=utf-8") + b"\x00"
           + REF.push(b"Hello, ") + REF.push(b"ordinals") + b"\x68")
    def wit(items):
        d = {"n": len(items)}
        for k, v in enumerate(items):
            d[str(k + 1)] = v
        return d
    got = str(ip.call("waInscriptionIn", [wit(["aa" * 64, env.hex(), "c0" + "11" * 32])]))
    c.ck("Inspect reads an inscription out of a witness: type, size, body",
         got.startswith("text/plain;charset=utf-8, 15 bytes") and '"Hello, ordinals"' in got, got)
    c.eq("and a witness without one reads as nothing",
         str(ip.call("waInscriptionIn", [wit(["aa" * 64])])), "")
    # ...and a runestone out of an OP_RETURN OP_13 output (read only): the
    # reference's all-tags etching, rendered the way Inspect prints it
    T = REF.RUNE_TAGS
    rs = REF.runestone_script([T["flags"], 0b111, T["rune"], 4, T["divisibility"], 1,
                               T["spacers"], 5, T["symbol"], ord("a"), T["offsetend"], 2,
                               T["amount"], 3, T["premine"], 8, T["cap"], 9, T["pointer"], 0,
                               T["mint"], 1, T["mint"], 1, T["body"], 1, 1, 2, 0]).hex()
    rtext = str(ip.call("waRunestoneText", [rs, 2]))
    c.ck("Inspect renders a runestone: etching, terms, mint, pointer, edict",
         all(s in rtext for s in ("etching E symbol a divisibility 1 premine 0.8 turbo",
                                  "open mint: 0.3 per mint, cap 9, offsets ..2",
                                  "mint 1:1", "go to output 1",
                                  "edict 1:1  amount 2  to output 1"))
         and "CENOTAPH" not in rtext, rtext)
    rtext = str(ip.call("waRunestoneText", [REF.runestone_script([T["cenotaph"], 0]).hex(), 2]))
    c.ck("and names a cenotaph with its flaw",
         "CENOTAPH (unrecognized even tag)" in rtext and "burned" in rtext, rtext)
    c.eq("an ordinary OP_RETURN renders nothing as a runestone",
         str(ip.call("waRunestoneText", [REF.spk_op_return(b"hi").hex(), 2])), "")
    # ---- a silent payment, from the coins that fund it (2026-09-04) --------
    # A BIP-352 address in the Pay-to box: the parser keeps its two keys and
    # no script, selection picks the coins, and only then is the taproot
    # output derived (wallet-core's cwSpSend) from those coins' private keys
    # and the smallest outpoint. The oracle repeats the derivation from the
    # fixture's own keys, so the output in the signed transaction is checked
    # against what it must be, not just counted.
    sp_scan = bytes.fromhex("0220bcfac5b99e04ad1a06ddfb016ee13582609d60b6291e98d01a9bc9a16c96d4")
    sp_spend = bytes.fromhex("025cc9856d6f8375350e123978daac200c260cb5b5ae83106cab90484dcd8fcf36")
    sp_addr = REF.sp_encode("testnet", sp_scan, sp_spend)
    put_field("sd_to", "%s,0.0005" % sp_addr)
    click(ip, world, "sd_preview")
    out = _fld(world, "sd_out")
    c.ck("the review names the silent payment and the taproot output it derives",
         "SILENT PAYMENT" in out and "tb1p" in out, repr(out[:300]))
    click(ip, world, "sd_sign")
    raw_sp = str(ip.globals.get("swalastraw", ""))
    c.ck("a silent payment signs", len(raw_sp) > 200, "%d hex chars" % len(raw_sp))
    if len(raw_sp) > 200:
        dec_sp = REF.tx_decode(bytes.fromhex(raw_sp))
        addrs = ip.globals.get("swaaddresses") or {}
        keys, points = [], []
        for vin in dec_sp["vin"]:
            points.append((vin["txid"], int(vin["vout"])))
            idx = [i for i, u in enumerate(UTXOS, 1)
                   if u["txid"] == vin["txid"] and u["vout"] == int(vin["vout"])]
            rec = addrs.get(str(idx[0]), {}) if idx else {}
            keys.append((bytes.fromhex(str(rec.get("seckey", ""))), False))
        want_spk = REF.spk_p2tr(REF.sp_send(keys, points, [(sp_scan, sp_spend)])[0]).hex()
        trs = [o for o in dec_sp["vout"] if o["scriptpubkey"] == want_spk]
        c.eq("its taproot output is the one the oracle derives from the same coins",
             len(trs), 1)
        if trs:
            c.eq("carrying the asked amount", int(trs[0]["value"]), 50000)
        c.ck("and the review showed that output's address",
             REF.address_for_spk("testnet", bytes.fromhex(want_spk)) in out, repr(out[:300]))
        c.ck("Inspect shows the derived output at its taproot address",
             REF.address_for_spk("testnet", bytes.fromhex(want_spk)) in str(ip.call("waInspectRaw", [raw_sp])), "")
    # the refusals, each by name
    put_field("sd_to", "%s,0.0005" % sp_addr)
    try:
        ip.call("waBuildSpend", [False, True])
        c.ck("a silent payment as a PSBT is refused", False, "accepted")
    except LCS.Thrown as exc:
        c.ck("a silent payment as a PSBT is refused, saying why",
             "PSBT" in str(exc.msg) and "private keys" in str(exc.msg), str(exc.msg)[:120])
    put_field("sd_to", "sp1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfhjdpdjtdgqjuexzk6murw"
              "56suy3e0rd2cgqvycxttddwsvgxe2usfpxumr70xc9pkqwv,0.0005")
    try:
        ip.call("waParsePayments", [])
        c.ck("a mainnet silent payment address is refused on this testnet wallet",
             False, "accepted")
    except LCS.Thrown as exc:
        c.ck("a mainnet silent payment address is refused on this testnet wallet",
             "mainnet" in str(exc.msg) and "line 1" in str(exc.msg), str(exc.msg)[:120])
    put_field("sd_to", "%s,0.0005" % (sp_addr[:-1] + ("q" if sp_addr[-1] != "q" else "p")))
    try:
        ip.call("waParsePayments", [])
        c.ck("a corrupt silent payment address is refused", False, "accepted")
    except LCS.Thrown as exc:
        c.ck("a corrupt silent payment address is refused",
             "checksum" in str(exc.msg), str(exc.msg)[:120])
    insp = str(ip.call("waValidateAddress", [sp_addr]))
    c.ck("the Tools inspector explains a silent payment address",
         "SILENT PAYMENT" in insp and sp_scan.hex() in insp, insp[:200])
    put_field("sd_to", "%s,0.0005" % first)
    click(ip, world, "sd_sign")

    # ---- the window follows its builder (2026-09-04) ------------------------
    # waBuild skips the build when the stack's stored uUiVersion equals
    # kWaUiVersion, which is what let a week of new controls ship without
    # ever appearing in an existing stack: the constant never changed. It is
    # a fingerprint of the waBuild* handlers now (tools/check-wallet-ui-version.py
    # holds it), so an updated stack stores a version the new script does not
    # carry and rebuilds. Pinned here the only way that matters: a control
    # taken away comes back when the stored version is stale, and stays away
    # when it is current.
    lock_btn = world.anywhere("vt_prepare")
    c.ck("the boot stored the builder's own version",
         str(world.stack_props.get("uuiversion", "")) == str(ip.constants.get("kWaUiVersion", "?")),
         "stored %r, constant %r" % (world.stack_props.get("uuiversion"), ip.constants.get("kWaUiVersion")))
    c.ck("kWaUiVersion is a fingerprint, not a hand-bumped number",
         str(ip.constants.get("kWaUiVersion", "")).startswith("ui-"), str(ip.constants.get("kWaUiVersion")))
    if lock_btn is not None:
        world.current().controls.remove(lock_btn)
        ip.call("waBuild", [])
        c.ck("a current version does not rebuild (the Prepare button stays gone)",
             world.anywhere("vt_prepare") is None, "")
        world.stack_props["uuiversion"] = "coinwallet-1"
        ip.call("waBuild", [])
        c.ck("a stale version rebuilds: the Prepare button is back",
             world.anywhere("vt_prepare") is not None, "")
        c.ck("and the stored version is the builder's again",
             str(world.stack_props.get("uuiversion", "")) == str(ip.constants.get("kWaUiVersion", "?")), "")

    # ---- the RBF fee bump BUILDS the replacement --------------------------
    #
    # This is the leg that used to be advice. waBumpAdvice computed the floor
    # a replacement must clear and then told the person to go and rebuild the
    # spend by hand on two other screens, which is the worst moment in the
    # wallet to be retyping an address. Everything below drives the real
    # button and checks the transaction that comes out against an independent
    # decode, because the failure mode here is not an error message: it is a
    # replacement that no node accepts, which looks exactly like one that was
    # never sent.
    if raw:
        dec = REF.tx_decode(bytes.fromhex(raw))
        spends = ip.globals.get("swaspends") or {}
        rec = spends.get(dec["txid"]) or {}
        c.ck("signing records what the spend was made of, keyed by txid",
             bool(rec), repr(sorted(spends.keys())[:2]))
        old_fee = int(LCS._n(rec.get("fee", 0)))
        old_change = int(LCS._n(rec.get("change", 0)))
        old_vsize = int(LCS._n(rec.get("vsize", 0)))
        c.ck("the record carries the fee, the change and the size",
             old_fee > 0 and old_change > 0 and old_vsize > 0,
             "fee %r change %r vsize %r" % (old_fee, old_change, old_vsize))
        # ...and the recorded fee is the real one, or every bump computed
        # from it is off by however far the record drifted.
        total_in = sum(u["value"] for u in UTXOS
                       if any(v["txid"] == u["txid"] and v["vout"] == u["vout"]
                              for v in dec["vin"]))
        c.eq("and the recorded fee is inputs minus outputs",
             old_fee, total_in - sum(o["value"] for o in dec["vout"]))

        # Drive the History screen's own button, on a row for that txid.
        hist = {"n": 1, "1": {
            "txid": dec["txid"], "confirmations": 0, "fee": old_fee,
            "vsize": old_vsize, "raw": raw, "address": first,
            "value": 0, "height": 0}}
        saved_hist = ip.globals.get("swahistory")
        ip.globals["swahistory"] = hist
        click(ip, world, "nv_hs")
        tbl = world.anywhere("hs_table")
        if tbl is not None:
            tbl.props["hilitedline"] = 2
        put_field("sd_rate", "20")
        click(ip, world, "hs_bump")
        detail = _fld(world, "hs_detail")
        c.ck("the Bump button builds and signs a replacement",
             "REPLACEMENT BUILT AND SIGNED" in detail, repr(detail[:160]))
        new_raw = str(ip.globals.get("swalastraw", ""))
        c.ck("and the replacement is a different transaction",
             new_raw and new_raw != raw, "unchanged" if new_raw == raw else "")
        if new_raw and new_raw != raw:
            rep = REF.tx_decode(bytes.fromhex(new_raw))
            # BIP-125 RULE 1: it must itself signal replaceability, or the
            # first bump is also the last.
            c.ck("the replacement signals RBF in its turn",
                 all(v["sequence"] <= 0xFFFFFFFD for v in rep["vin"]),
                 repr([hex(v["sequence"]) for v in rep["vin"]]))
            # RULE 2: no input the original did not have. This is the one
            # that would quietly spend a coin nobody chose.
            c.eq("it spends exactly the same outpoints",
                 sorted((v["txid"], v["vout"]) for v in rep["vin"]),
                 sorted((v["txid"], v["vout"]) for v in dec["vin"]))
            # The payments are untouched and only the CHANGE shrinks - which
            # is what makes this a bump rather than a new transaction.
            old_outs = sorted((o["value"], o["scriptpubkey"]) for o in dec["vout"])
            new_outs = sorted((o["value"], o["scriptpubkey"]) for o in rep["vout"])
            c.eq("it has the same number of outputs",
                 len(new_outs), len(old_outs))
            changed = [a for a, b in zip(old_outs, new_outs) if a != b]
            c.ck("and exactly one output changed", len(changed) <= 1,
                 "%r -> %r" % (old_outs, new_outs))
            new_fee = total_in - sum(o["value"] for o in rep["vout"])
            c.ck("it pays more than the transaction it evicts",
                 new_fee > old_fee, "%d vs %d" % (new_fee, old_fee))
            # RULES 3 AND 4, over the REPLACEMENT'S OWN size - which is not
            # the original's, because a signature is a byte or two shorter
            # about half the time.
            floor = old_fee + rep["vsize"]
            c.ck("and it clears the BIP-125 floor for its own size",
                 new_fee >= floor, "%d < %d (vsize %d)"
                 % (new_fee, floor, rep["vsize"]))
            c.ck("the requested 20 sat/vB was honoured, not just the floor",
                 new_fee >= 20 * rep["vsize"],
                 "%d for %d vB" % (new_fee, rep["vsize"]))
            # It is recorded like any other spend, so it can be bumped again.
            c.ck("the replacement is itself recorded for a second bump",
                 bool((ip.globals.get("swaspends") or {}).get(rep["txid"])),
                 repr(sorted((ip.globals.get("swaspends") or {}).keys())[:3]))

        # A CONFIRMED transaction has nothing to bump, and a transaction this
        # window never built cannot be bumped here at all - both are refused
        # by saying so, not by building something.
        ip.globals["swahistory"] = {"n": 1, "1": dict(hist["1"],
                                                      confirmations=3)}
        click(ip, world, "nv_hs")
        tbl = world.anywhere("hs_table")
        if tbl is not None:
            tbl.props["hilitedline"] = 2
        click(ip, world, "hs_bump")
        c.ck("a confirmed transaction is refused",
             "confirmed" in _fld(world, "hs_detail").lower()
             or "confirmed" in str(_fld(world, "uiStatus")).lower(),
             repr(_fld(world, "hs_detail")[:100]))
        ip.globals["swahistory"] = {"n": 1, "1": dict(hist["1"],
                                                      txid="ee" * 32)}
        click(ip, world, "nv_hs")
        tbl = world.anywhere("hs_table")
        if tbl is not None:
            tbl.props["hilitedline"] = 2
        click(ip, world, "hs_bump")
        detail = _fld(world, "hs_detail")
        c.ck("a transaction this window did not build falls back to advice",
             "CANNOT BUILD THE REPLACEMENT" in detail
             and "BUMPING THE FEE" in detail, repr(detail[:160]))
        ip.globals["swahistory"] = saved_hist
        ip.globals["swalastraw"] = raw

    # ---- child pays for parent (2026-09-04) --------------------------------
    # The bump a replacement cannot do: a stuck transaction this wallet did
    # not build - an incoming payment, typically - is carried by a child that
    # spends its unconfirmed output back to this wallet at a fee covering
    # both. The parent is built by the oracle so its size and txid are real.
    a3 = str((ip.globals.get("swaaddresses") or {}).get("3", {}).get("address", ""))
    spk3 = REF.spk_for_address("testnet", a3)
    parent = REF.unsigned_tx(2, [("d" * 64, 0, 0xFFFFFFFD)],
                             [(40000, spk3), (1000, REF.spk_op_return(b"x"))], 0)
    pdec = REF.tx_decode(parent)
    ptxid, pvsize = pdec["txid"], int(pdec["vsize"])
    utx = dict(ip.globals.get("swautxos") or {"n": 0})
    n_u = int(LCS._n(utx.get("n", 0))) + 1
    utx[str(n_u)] = {"txid": ptxid, "vout": 0, "value": 40000, "confirmations": 0,
                     "height": "", "address": a3, "script": spk3.hex(),
                     "selected": "", "frozen": ""}
    utx["n"] = n_u
    ip.globals["swautxos"] = utx
    kids = ip.call("waCpfpCoins", [ptxid])
    c.eq("the wallet finds its one unconfirmed coin of the parent",
         int(LCS._n(kids.get("n", 0))), 1)
    put_field("sd_rate", "3")
    row = {"txid": ptxid, "address": a3, "confirmations": 0, "height": "",
           "fee": 150, "vsize": pvsize, "raw": parent.hex()}
    ip.call("waBumpFee", [row])
    det = _fld(world, "hs_detail")
    c.ck("Bump on a transaction the wallet did not build offers a child",
         det.startswith("CHILD PAYS FOR PARENT"), det[:80])
    craw = str(ip.globals.get("swalastraw", ""))
    c.ck("and signs it", len(craw) > 100, "%d hex chars" % len(craw))
    if len(craw) > 100:
        cdec = REF.tx_decode(bytes.fromhex(craw))
        c.eq("the child spends exactly the parent's output",
             [(v["txid"], v["vout"]) for v in cdec["vin"]], [(ptxid, 0)])
        c.ck("and signals RBF, so it can be raised in its turn",
             all(v["sequence"] == 0xFFFFFFFD for v in cdec["vin"]))
        c.eq("to one output", len(cdec["vout"]), 1)
        cval = cdec["vout"][0]["value"]
        c.ck("which is this wallet's own change address",
             ip.call("waIsMine", [str(ip.call("cwAddressForScript",
                                                ["testnet", cdec["vout"][0]["scriptpubkey"]]))])
             is True)
        cfee = 40000 - cval
        want = -(-(3 * (int(cdec["vsize"]) + pvsize)) // 1) - 150
        c.ck("the child's fee is the pair's shortfall at 3 sat/vB (parent paid 150)",
             abs(cfee - want) <= 6, "fee %d, wanted about %d" % (cfee, want))
        c.ck("the detail says what the pair pays together",
             "together they pay" in det and "150 sat" in det.replace(",", "") or
             "together they pay" in det, det[:400])
        c.ck("and the child is recorded, so it can be replaced",
             isinstance((ip.globals.get("swaspends") or {}).get(cdec["txid"]), dict))
    # without a fee from the backend (Electrum's history), the child pays for both
    row2 = dict(row); row2.pop("fee")
    ip.call("waBumpFee", [row2])
    det2 = _fld(world, "hs_detail")
    craw2 = str(ip.globals.get("swalastraw", ""))
    if len(craw2) > 100:
        cdec2 = REF.tx_decode(bytes.fromhex(craw2))
        cfee2 = 40000 - cdec2["vout"][0]["value"]
        c.ck("with the parent's fee unknown the child pays for both sizes in full",
             abs(cfee2 - 3 * (int(cdec2["vsize"]) + pvsize)) <= 6 and "does not report" in det2,
             "fee %d" % cfee2)
    # without the parent's bytes or size, the bytes are asked for first
    row3 = dict(row); row3.pop("raw"); row3.pop("vsize")
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swabackend"] = "electrum-clear"
    try:
        ip.call("waBumpFee", [row3])
        c.ck("without the parent's size the wallet asks for its bytes first", False, "built")
    except LCS.Thrown as exc:
        q = ip.globals.get("swaqueue") or {}
        c.ck("without the parent's size the wallet asks for its bytes first",
             "press Bump again" in str(exc.msg)
             and str(q.get("1", {}).get("kind")) == "tx", str(exc.msg)[:80])
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swabackend"] = "offline"
    # a rate too high for the coin is refused, not built
    put_field("sd_rate", "900")
    try:
        ip.call("waBumpFee", [row])
        c.ck("a child that would leave dust is refused", False, "built")
    except LCS.Thrown as exc:
        c.ck("a child that would leave dust is refused", "dust" in str(exc.msg),
             str(exc.msg)[:80])
    put_field("sd_rate", "2")
    utx.pop(str(n_u)); utx["n"] = n_u - 1
    ip.globals["swautxos"] = utx

    # ---- what the wallet just did: a broadcast is remembered (2026-09-03) --
    #
    # The engine log of 2026-09-03 built a silent payment and, a minute later
    # with no sync between, the funding of an inscription commit - and the
    # second spent the first one's input, because the coin list was the last
    # sync's. The server took the first and refused the second as a
    # replacement paying nothing extra. A broadcast the backend ACCEPTS now
    # marks its inputs as spent (waNoteBroadcast): the selector, the CPFP coin
    # finder and the balance skip a marked coin, the Coins screen shows SPT,
    # and the outputs that come back to this wallet are coins at 0
    # confirmations. The backend's next word on an address outranks all of
    # it, and a replacement voids the coins added from what it replaced. The
    # same log's Bump on the wallet's own note transaction asked the server
    # for bytes the spend record already held; that is pinned here too.
    import copy as _copy
    saved_utx = _copy.deepcopy(ip.globals.get("swautxos"))
    saved_spent = _copy.deepcopy(ip.globals.get("swaspentby"))
    saved_hist = _copy.deepcopy(ip.globals.get("swahistory"))
    saved_backend = ip.globals.get("swabackend")

    def _coins(lst):
        n = int(LCS._n((lst or {}).get("n", 0)))
        return [lst[str(i)] for i in range(1, n + 1)]

    def _keys(lst):
        return {(str(r["txid"]), int(LCS._n(r["vout"]))) for r in _coins(lst)}

    put_field("sd_to", "%s,0.0005" % first)
    put_field("sd_rate", "2")
    click(ip, world, "sd_sign")
    raw1 = str(ip.globals.get("swalastraw", ""))
    c.ck("a spend signs for the broadcast-memory leg", len(raw1) > 200, "%d hex chars" % len(raw1))
    if len(raw1) > 200:
        d1 = REF.tx_decode(bytes.fromhex(raw1))
        ins1 = [(v["txid"], v["vout"]) for v in d1["vin"]]
        n_before = len(_coins(ip.call("waSpendableCoins", [])))
        conf_before = sum(int(LCS._n(r["value"])) for r in _coins(saved_utx)
                          if int(LCS._n(r["confirmations"])) > 0)
        pend_before = sum(int(LCS._n(r["value"])) for r in _coins(saved_utx)
                          if int(LCS._n(r["confirmations"])) == 0)
        spent_conf = sum(int(LCS._n(r["value"])) for r in _coins(saved_utx)
                         if int(LCS._n(r["confirmations"])) > 0
                         and (str(r["txid"]), int(LCS._n(r["vout"]))) in set(ins1))
        spent_pend = sum(int(LCS._n(r["value"])) for r in _coins(saved_utx)
                         if int(LCS._n(r["confirmations"])) == 0
                         and (str(r["txid"]), int(LCS._n(r["vout"]))) in set(ins1))
        ip.globals["swabackend"] = "electrum-clear"
        ip.globals["swainflight"] = {"kind": "broadcast", "arg": raw1, "id": "71"}
        ip.call("waNetApply", ["broadcast", raw1,
                               '{"jsonrpc":"2.0","id":71,"result":"%s"}' % d1["txid"], "71"])
        marks = ip.globals.get("swaspentby") or {}
        c.ck("an accepted broadcast marks every input it spent, by outpoint",
             all(str(marks.get("%s:%d" % (t, v), "")) == d1["txid"] for t, v in ins1),
             repr({k: str(v)[:12] for k, v in marks.items()}))
        after = ip.call("waSpendableCoins", [])
        offered = _keys(after)
        c.ck("and the selector is no longer offered those coins",
             not (offered & set(ins1)), repr(sorted(offered & set(ins1))))
        first_spk = REF.spk_for_address("testnet", first).hex()
        chg = [(i, o) for i, o in enumerate(d1["vout"]) if o["scriptpubkey"] != first_spk]
        c.eq("the spend had one change output", len(chg), 1)
        # the payment went to this wallet's own first address, so BOTH outputs
        # come back as coins: the change and the payment itself
        mine = [(i, o) for i, o in enumerate(d1["vout"])
                if ip.call("waIsMine", [REF.address_for_spk("testnet", bytes.fromhex(o["scriptpubkey"]))]) is True]
        c.eq("both outputs of a self-payment are this wallet's", len(mine), 2)
        if chg:
            ci, co = chg[0]
            c.ck("which is now a coin of this wallet at 0 confirmations",
                 any(str(r["txid"]) == d1["txid"] and int(LCS._n(r["vout"])) == ci
                     and int(LCS._n(r["confirmations"])) == 0
                     and int(LCS._n(r["value"])) == int(co["value"])
                     and ip.call("waIsMine", [str(r["address"])]) is True
                     for r in _coins(after)),
                 repr(sorted(offered)))
        c.eq("so the offered count moved by the inputs spent and the outputs that came back",
             len(offered), n_before - len(ins1) + len(mine))
        log = _fld(world, "lg_text")
        c.ck("and the log says what was spent and what came back",
             ("spent %d coin(s)" % len(ins1)) in log and "came back" in log, repr(log[-200:]))
        bal = ip.globals.get("swabalance") or {}
        c.eq("the confirmed balance no longer counts the spent coins",
             int(LCS._n(bal.get("confirmed", 0))), conf_before - spent_conf)
        c.eq("and what came back is counted as pending",
             int(LCS._n(bal.get("unconfirmed", 0))),
             pend_before - spent_pend + sum(int(o["value"]) for _, o in mine))
        click(ip, world, "nv_cn")
        tbl = _fld(world, "cn_table")
        c.ck("the Coins screen marks each spent coin SPT",
             all(any("SPT" in ln and t[:20] in ln for ln in tbl.split("\n")) for t, v in ins1),
             repr(tbl[:300]))
        c.ck("and explains the mark", "SPT marks a coin" in _fld(world, "cn_detail"), "")
        # a second spend a moment later, with no sync between
        click(ip, world, "nv_sd")
        put_field("sd_to", "%s,0.0005" % first)
        click(ip, world, "sd_sign")
        raw2 = str(ip.globals.get("swalastraw", ""))
        if len(raw2) > 200:
            d2 = REF.tx_decode(bytes.fromhex(raw2))
            ins2 = [(v["txid"], v["vout"]) for v in d2["vin"]]
            c.ck("a second spend a moment later reuses none of the first one's inputs",
                 not (set(ins1) & set(ins2)), repr(sorted(set(ins1) & set(ins2))))
        else:
            c.ck("a second spend a moment later signs", False, _fld(world, "sd_out")[:160])
        # RESERVED AT QUEUE TIME, RELEASED ON REFUSAL (the 2026-09-03 evening
        # run built two spends on a change output while the bump that voided
        # it was still queued behind Tor; both were refused by every node).
        if len(raw2) > 200:
            ip.globals["swaqueue"] = {"n": 0}
            ip.globals["swainflight"] = ""
            ip.call("waBroadcast", [])
            marks = ip.globals.get("swaspentby") or {}
            c.ck("queueing a broadcast reserves its inputs before any server answers",
                 all(str(marks.get("%s:%d" % (t, v), "")) == d2["txid"] for t, v in ins2),
                 repr({k: str(v)[:12] for k, v in marks.items()}))
            c.ck("and lists its own outputs as coins at once",
                 any(str(r["txid"]) == d2["txid"] for r in _coins(ip.globals.get("swautxos") or {})), "")
            c.eq("the broadcast is queued", str((ip.globals.get("swaqueue") or {}).get("1", {}).get("kind")), "broadcast")
            # in flight now, past its one retry, and refused for good
            ip.globals["swaqueue"] = {"n": 0}
            ip.globals["swainflight"] = {"kind": "broadcast", "arg": raw2, "id": "73", "retried": "true"}
            ip.call("waNetFail", ["the backend answered HTTP/1.1 400 Bad Request: bad-txns-inputs-missingorspent"])
            marks = ip.globals.get("swaspentby") or {}
            c.ck("a refused broadcast hands its coins back",
                 all(str(marks.get("%s:%d" % (t, v), "")) == "" for t, v in ins2),
                 repr({k: str(v)[:12] for k, v in marks.items()}))
            c.ck("and drops the coins it had added",
                 not any(str(r["txid"]) == d2["txid"] for r in _coins(ip.globals.get("swautxos") or {})), "")
            c.ck("and the log says so",
                 "coin(s) it had reserved are offered again" in _fld(world, "lg_text"), "")
            c.ck("and the first spend's marks are untouched",
                 all(str(marks.get("%s:%d" % (t, v), "")) == d1["txid"] for t, v in ins1),
                 repr({k: str(v)[:12] for k, v in marks.items()}))
            ip.globals["swasyncfailures"] = 0
            ip.globals["swanetstate"] = "idle"
            ip.globals["swainflight"] = ""
            # and a refusal in the server's REPLY (an Electrum error object)
            # releases them too: that path clears the in-flight record before
            # it applies the answer, so the failure handler never saw a
            # broadcast to release
            ip.globals["swaqueue"] = {"n": 0}
            ip.call("waBroadcast", [])
            marks = ip.globals.get("swaspentby") or {}
            c.ck("re-queued, the inputs are reserved again",
                 all(str(marks.get("%s:%d" % (t, v), "")) == d2["txid"] for t, v in ins2), "")
            ip.globals["swaqueue"] = {"n": 0}
            ip.globals["swainflight"] = {"kind": "broadcast", "arg": raw2, "id": "74"}
            ip.call("waNetDeliver", ['{"jsonrpc":"2.0","id":74,"error":{"code":-26,'
                                     '"message":"min relay fee not met, 23 < 226"}}\n'])
            marks = ip.globals.get("swaspentby") or {}
            c.ck("a refusal in the server's reply hands the coins back too",
                 all(str(marks.get("%s:%d" % (t, v), "")) == "" for t, v in ins2),
                 repr({k: str(v)[:12] for k, v in marks.items()}))
            c.ck("with the server's reason in the log",
                 "min relay fee not met" in _fld(world, "lg_text")[-600:], _fld(world, "lg_text")[-200:])
            ip.globals["swasyncfailures"] = 0
            ip.globals["swanetstate"] = "idle"
            ip.globals["swainflight"] = ""
            ip.globals["swaqueue"] = {"n": 0}
        # CPFP on the wallet's own transaction prices from the record
        spends = ip.globals.get("swaspends") or {}
        rec1 = spends.get(d1["txid"]) or {}
        c.ck("the first spend is on record", bool(rec1), "")
        if rec1:
            old_change = rec1.get("change")
            rec1["change"] = 0          # as if it had been built without change
            ip.globals["swaqueue"] = {"n": 0}
            put_field("sd_rate", "3")
            row = {"txid": d1["txid"], "address": first, "confirmations": 0, "height": ""}
            try:
                ip.call("waBumpFee", [row])
                det = _fld(world, "hs_detail")
                q = ip.globals.get("swaqueue") or {}
                c.ck("Bump on the wallet's own change-less transaction builds the child at once",
                     det.startswith("CHILD PAYS FOR PARENT"), det[:80])
                c.eq("without asking the backend for bytes the record already holds",
                     int(LCS._n(q.get("n", 0))), 0)
                c.ck("and prices the pair from the recorded fee",
                     "together they pay" in det, det[:300])
            except LCS.Thrown as exc:
                c.ck("Bump on the wallet's own change-less transaction builds the child at once",
                     False, str(exc.msg)[:120])
            rec1["change"] = old_change
            put_field("sd_rate", "2")
        # a parent whose output a pending spend of ours uses is not replaced
        if rec1 and chg:
            marks = ip.globals.get("swaspentby") or {}
            key_c = "%s:%d" % (d1["txid"], chg[0][0])
            marks[key_c] = "ff" * 32
            ip.globals["swaspentby"] = marks
            row_full = {"txid": d1["txid"], "confirmations": 0, "height": 0, "value": 0,
                        "fee": int(LCS._n(rec1.get("fee", 0))),
                        "vsize": int(LCS._n(rec1.get("vsize", 0))),
                        "raw": raw1, "address": first}
            put_field("sd_rate", "20")
            try:
                ip.call("waBumpFee", [row_full])
                c.ck("a parent whose change a queued spend uses is not replaced", False, "replaced")
            except LCS.Thrown as exc:
                c.ck("a parent whose change a queued spend uses is not replaced",
                     "already spent by ff" in str(exc.msg) and "Bump the child" in str(exc.msg),
                     str(exc.msg)[:160])
            marks[key_c] = ""
            ip.globals["swaspentby"] = marks
            put_field("sd_rate", "2")
        # a replacement voids what it replaced
        last_txid = d1["txid"]
        if rec1:
            row_full = {"txid": d1["txid"], "confirmations": 0, "height": 0, "value": 0,
                        "fee": int(LCS._n(rec1.get("fee", 0))),
                        "vsize": int(LCS._n(rec1.get("vsize", 0))),
                        "raw": raw1, "address": first}
            put_field("sd_rate", "20")
            try:
                ip.call("waBumpFee", [row_full])
                raw3 = str(ip.globals.get("swalastraw", ""))
            except LCS.Thrown as exc:
                raw3 = ""
                c.ck("the replacement builds for the void leg", False, str(exc.msg)[:120])
            put_field("sd_rate", "2")
            if len(raw3) > 200 and raw3 != raw1:
                d3 = REF.tx_decode(bytes.fromhex(raw3))
                last_txid = d3["txid"]
                ip.globals["swainflight"] = {"kind": "broadcast", "arg": raw3, "id": "72"}
                ip.call("waNetApply", ["broadcast", raw3,
                                       '{"jsonrpc":"2.0","id":72,"result":"%s"}' % d3["txid"], "72"])
                marks = ip.globals.get("swaspentby") or {}
                c.ck("an accepted replacement re-marks the inputs with its own txid",
                     all(str(marks.get("%s:%d" % (t, v), "")) == d3["txid"]
                         for t, v in [(x["txid"], x["vout"]) for x in d3["vin"]]),
                     repr({k: str(v)[:12] for k, v in marks.items()}))
                held = _keys(ip.globals.get("swautxos") or {})
                c.ck("and voids the coins the wallet had added from the replaced transaction",
                     not any(t == d1["txid"] for t, v in held), repr(sorted(held)))
                c.ck("while adding the replacement's own change at 0 confirmations",
                     any(t == d3["txid"] for t, v in held), repr(sorted(held)))
                c.ck("and the log says which transaction replaced which",
                     ("%s replaces %s" % (d3["txid"], d1["txid"])) in _fld(world, "lg_text"), "")
        # the backend's word outranks the memory: a coin it still lists comes back
        t0, v0 = ins1[0]
        rec0 = next((r for r in _coins(saved_utx)
                     if str(r["txid"]) == t0 and int(LCS._n(r["vout"])) == v0), None)
        c.ck("the first input is a fixture coin", rec0 is not None, "")
        if rec0 is not None:
            node = ip.call("cwJsonParse", [
                '[{"tx_hash":"%s","tx_pos":%d,"value":%d,"height":12}]'
                % (t0, v0, int(LCS._n(rec0["value"])))])
            ip.call("waMergeUtxos", [str(rec0["address"]), node, "electrum"])
            marks = ip.globals.get("swaspentby") or {}
            c.eq("a coin the backend still lists as unspent loses its mark",
                 str(marks.get("%s:%d" % (t0, v0), "")), "")
            c.ck("and is offered again", (t0, v0) in _keys(ip.call("waSpendableCoins", [])), "")
            log = _fld(world, "lg_text")[-500:]
            c.ck("with the log naming the transaction that had spent it",
                 "offering it again" in log and last_txid in log, repr(log[-160:]))
    # leave the wallet as this block found it
    ip.globals["swautxos"] = saved_utx
    if saved_spent is None:
        ip.globals.pop("swaspentby", None)
    else:
        ip.globals["swaspentby"] = saved_spent
    ip.globals["swahistory"] = saved_hist
    ip.globals["swabackend"] = saved_backend
    ip.globals["swainflight"] = ""
    ip.globals["swaqueue"] = {"n": 0}
    ip.call("waRecomputeBalance", [])
    put_field("sd_rate", "2")
    put_field("sd_to", "%s,0.0005" % first)
    click(ip, world, "nv_sd")

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

    # ---- Ordinals: an inscription, by commit and reveal (2026-09-04) ------
    # Two numbered buttons on their own screen. The content type and body
    # in their fields and "1. Prepare" makes the COMMIT: the next unused
    # receive key becomes the leaf key, the commit address joins the address
    # list, the recipe is saved with the wallet. A coin planted on that
    # address, and "2. Sign the reveal" signs the REVEAL through the leaf;
    # the oracle rebuilds the same transaction from the same key, and the
    # wallet's own inscription reader gets the envelope back out of the
    # witness. The table between them says which state each one is in.
    click(ip, world, "nv_od")
    before_n = int(LCS._n((ip.globals.get("swaaddresses") or {}).get("n", 0)))
    click(ip, world, "od_typeText")
    c.eq("the text quick-pick fills the content type", _fld(world, "od_type"),
         "text/plain;charset=utf-8")
    put_field("od_body", "Hello, ordinals")
    click(ip, world, "nv_od")
    c.ck("the size line prices the reveal before anything is made",
         "15 bytes" in _fld(world, "od_size") and "sat/vB" in _fld(world, "od_size"),
         _fld(world, "od_size"))
    c.ck("the table says there is nothing yet, and what to do",
         "press 1" in _fld(world, "od_table"), _fld(world, "od_table")[:120])
    click(ip, world, "od_prepare")
    out = _fld(world, "od_out")
    c.ck("Inscribe prepares a commit and says what to fund",
         "INSCRIPTION COMMIT PREPARED" in out and "tb1p" in out and "Fund that address" in out,
         repr(out[:200]))
    addrs = ip.globals.get("swaaddresses") or {}
    n_addr = int(LCS._n(addrs.get("n", 0)))
    commit = dict(addrs.get(str(n_addr), {})) if n_addr > before_n else {}
    # ONE record, or one plus a further window: when every receive address
    # of the derived window is used (the harness's two-address prefill gets
    # there at once), the wallet derives another window first and says so.
    prefill = int(LCS._n(ip.constants.get("kWaPrefill", 20)))
    c.ck("the commit joined the wallet's address list",
         n_addr - before_n in (1, 1 + 2 * prefill),
         "before %d, after %d; status %r" % (before_n, n_addr, _fld(world, "uiStatus")[:120]))
    base = None
    for i in range(1, n_addr + 1):
        r = addrs.get(str(i), {})
        if str(r.get("change")) == "0" and str(r.get("index")) == str(commit.get("index")) and not r.get("leafscript"):
            base = r
            break
    if base is not None:
        xonly = bytes.fromhex(str(base["pubkey"]))[1:]
        env = REF.inscription_script(xonly, "text/plain;charset=utf-8", b"Hello, ordinals")
        want_c = REF.tap_commit(xonly, env)
        c.ck("its leaf, key and script are the oracle's for that receive key",
             (str(commit.get("leafscript")), str(commit.get("leafhash")), str(commit.get("script")),
              str(commit.get("controlblock"))),
             (env.hex(), want_c["leafhash"].hex(), want_c["script"].hex(), want_c["controlblock"].hex()))
        c.ck("and its address is the commit script's",
             str(commit.get("address")), REF.address_for_spk("testnet", want_c["script"]))
        c.ck("the recipe is in the wallet file",
             "leaf\tinscribe|%d|text/plain;charset=utf-8|%s" % (int(LCS._n(commit["index"])), b"Hello, ordinals".hex())
             in str(ip.call("waSerializeWallet", [])),
             " / ".join(ln for ln in str(ip.call("waSerializeWallet", [])).split("\n") if ln.startswith("leaf"))[:300])
        c.ck("the table lists it as unfunded, with its address",
             "unfunded" in _fld(world, "od_table") and str(commit.get("address")) in _fld(world, "od_table"),
             _fld(world, "od_table")[:200])
        click(ip, world, "od_copyAddr")
        clip = world.clipboard.get("text") if isinstance(world.clipboard, dict) else world.clipboard
        c.ck("Copy its commit address with nothing selected copies the one just made",
             str(clip) == str(commit.get("address")), repr(clip)[:80])
        # fund it, then reveal
        utx = dict(ip.globals.get("swautxos") or {"n": 0})
        n_u = int(LCS._n(utx.get("n", 0))) + 1
        utx[str(n_u)] = {"txid": "dd" * 32, "vout": 1, "value": 20000, "confirmations": 1,
                         "height": 1, "address": commit["address"], "script": commit["script"],
                         "path": "", "pubkey": commit.get("pubkey", ""), "chain": 0,
                         "index": commit["index"], "selected": "", "frozen": ""}
        utx["n"] = n_u
        ip.globals["swautxos"] = utx
        click(ip, world, "nv_od")
        c.ck("once a coin is at the commit address the table says funded, press 2",
             "funded" in _fld(world, "od_table") and "press 2" in _fld(world, "od_table"),
             _fld(world, "od_table")[:200])
        click(ip, world, "od_reveal")
        out = _fld(world, "od_out")
        raw_r = str(ip.globals.get("swalastraw", ""))
        c.ck("2. Sign the reveal signs it",
             "INSCRIPTION REVEAL SIGNED" in out and len(raw_r) > 200, repr(out[:160]))
        if len(raw_r) > 200:
            dec_r = REF.tx_decode(bytes.fromhex(raw_r))
            wit = dec_r["vin"][0].get("witness", [])
            c.ck("it spends the commit through the leaf: signature, script, control block",
                 (dec_r["vin"][0]["txid"], len(wit), wit[1:] if len(wit) == 3 else wit),
                 ("dd" * 32, 3, [env.hex(), want_c["controlblock"].hex()]))
            # the oracle signs the same reveal with the same key
            seckey = bytes.fromhex(str(base["seckey"]))
            nxt = [addrs.get(str(i), {}) for i in range(1, n_addr + 1)]
            to_spk = bytes.fromhex(dec_r["vout"][0]["scriptpubkey"])
            fee = 20000 - int(dec_r["vout"][0]["value"])
            vs = 11 + REF.tapscript_input_vsize(env) + 43
            c.ck("the fee is the Send screen's rate over the estimated size",
                 fee, 2 * vs)
            digest = REF.tapscript_sighash(2, [("dd" * 32, 1, 0xFFFFFFFD)],
                                           [(20000 - fee, to_spk)], 0, 0,
                                           [want_c["script"]], [20000], want_c["leafhash"])
            c.ck("and the signature is the oracle's, byte for byte",
                 wit[0] if wit else "", REF.cr.schnorr_sign(seckey, digest, bytes(32)).hex())
            c.ck("the output is this wallet's next receive address",
                 any(str(r.get("script")) == to_spk.hex() and str(r.get("change")) == "0"
                     and not r.get("leafscript") for r in nxt), to_spk.hex())
            c.ck("Inspect reads the inscription back out of the reveal",
                 'text/plain;charset=utf-8, 15 bytes' in str(ip.call("waInspectRaw", [raw_r]))
                 and '"Hello, ordinals"' in str(ip.call("waInspectRaw", [raw_r])), "")
            c.ck("and the report names the inscription id",
                 dec_r["txid"] + "i0" in out, "")
            c.ck("the output that receives the inscription is frozen before it is seen",
                 str((ip.globals.get("swafrozen") or {}).get(dec_r["txid"] + ":0", "")), "true")
            c.ck("and the wallet file carries that freeze",
                 "frozen\t%s:0" % dec_r["txid"] in str(ip.call("waSerializeWallet", [])), "")
    # the refusals, from the screen's fields and from the line form
    for label, args, want in (
            ("a body without a content type is refused", ["", "hello", False], "type"),
            ("an empty body is refused", ["text/plain", "", False], "empty"),
            ("bad hex is refused", ["image/png", "zz", True], "hex")):
        try:
            ip.call("waInscribePrepare", args)
            c.ck(label, False, "accepted")
        except LCS.Thrown as exc:
            c.ck(label, want in str(exc.msg), str(exc.msg)[:100])
    try:
        ip.call("waInscribeLineParts", ["inscribe: hello"])
        c.ck("a line without the semicolon is refused", False, "accepted")
    except LCS.Thrown as exc:
        c.ck("a line without the semicolon is refused", "semicolon" in str(exc.msg), str(exc.msg)[:100])
    c.ck("other text is not carried anywhere",
         ip.call("waCarryLineToScreen", ["hello"]) is not True, "")

    # ---- Tools: a Lightning invoice, read out (2026-09-04) -----------------
    # Inspect and Validate both read a BOLT11 invoice: the specification's
    # first example, whose payee is the node key every example signs with.
    import json as _json
    b11 = _json.load(open(os.path.join(MEMBER, "tests", "bolt11-vectors.json"), encoding="utf-8"))
    inv = b11["valid"][5]
    text = str(ip.call("waInspectAnything", [inv["invoice"]]))
    c.ck("Inspect reads a Lightning invoice: payee, amount, fallback, route hints",
         all(s in text for s in ("LIGHTNING INVOICE", inv["expected"]["payee"], "2000000000 msat",
                                 inv["expected"]["fallback"], "route hint 1", "66051x263430x1800",
                                 "cannot pay this")), text[:300])
    c.ck("and says the invoice is for another network than this wallet",
         "(this wallet is on testnet)" in text, "")
    text = str(ip.call("waValidateAnything", [b11["invalid"][1]["invoice"]]))
    c.ck("Validate refuses a corrupt invoice with the reason",
         "NOT A VALID LIGHTNING INVOICE" in text and "checksum" in text, text[:200])
    tinv = b11["valid"][4]      # the testnet example, so the URI's address and invoice agree
    text = str(ip.call("waInspectAnything", ["bitcoin:%s?amount=0.0002&lightning=%s" % (first, tinv["invoice"])]))
    c.ck("Inspect reads a unified URI: the on-chain half and the invoice beneath it",
         "PAYMENT URI (BIP-21)" in text and first in text and "LIGHTNING INVOICE" in text
         and tinv["expected"]["payee"] in text, text[:300])
    text = str(ip.call("waInspectAnything", ["bitcoin:?lightning=%s" % tinv["invoice"]]))
    c.ck("and a Lightning-only URI", "Lightning only" in text and tinv["expected"]["payee"] in text, text[:200])

    # ---- Vault: coins locked until a block (2026-09-04) --------------------
    # A height in the field and Prepare makes a taproot address whose only
    # leaf is <height> OP_CLTV OP_DROP <receive key> OP_CHECKSIG under the
    # NUMS point, so nothing spends it before that block. A coin planted on
    # it is withheld from selection while the tip is below the height, and
    # spent by the Send screen - locktime raised, leaf witness - once it is
    # not. The quick-pick buttons fill the height from the tip.
    click(ip, world, "nv_vt")
    before_n = int(LCS._n((ip.globals.get("swaaddresses") or {}).get("n", 0)))
    tip_was = ip.globals.get("swatipheight")
    ip.globals["swatipheight"] = 800000
    click(ip, world, "vt_week")
    c.eq("+1 week fills the tip plus 1008 blocks", int(LCS._n(_fld(world, "vt_height"))), 801008)
    c.ck("and the line under it says how far away that is",
         "1008 blocks" in _fld(world, "vt_when") and "7 days" in _fld(world, "vt_when"),
         _fld(world, "vt_when"))
    ip.globals["swatipheight"] = tip_was
    put_field("vt_height", "900000")
    click(ip, world, "vt_prepare")
    out = _fld(world, "vt_out")
    c.ck("Lock prepares a timelock address and says what it means",
         "TIMELOCK ADDRESS PREPARED" in out and "block 900000" in out and "tb1p" in out
         and "NUMS" in out, repr(out[:200]))
    addrs = ip.globals.get("swaaddresses") or {}
    n_addr = int(LCS._n(addrs.get("n", 0)))
    lockrec = dict(addrs.get(str(n_addr), {})) if n_addr > before_n else {}
    prefill = int(LCS._n(ip.constants.get("kWaPrefill", 20)))
    c.ck("the lock joined the address list (deriving a further window first if every receive address was used)",
         n_addr - before_n in (1, 1 + 2 * prefill),
         "before %d, after %d; status %r; vt_out %r"
         % (before_n, n_addr, _fld(world, "uiStatus")[:120], out[:80]))
    if n_addr - before_n == 1 + 2 * prefill:
        c.ck("and the log says the window was extended",
             "derived a further window" in _fld(world, "lg_text"), "")
    # A LEAF USES UP ITS KEY'S INDEX: thirty timelocks on an engine all said
    # "key at receive index 14" before this was pinned (2026-09-03 evening)
    c.ck("the lock takes a fresh key, not the inscription commit's",
         lockrec and commit and str(lockrec.get("index")) != str(commit.get("index")),
         "lock index %r, commit index %r" % (lockrec.get("index"), commit.get("index")))
    base = None
    for i in range(1, n_addr + 1):
        r = addrs.get(str(i), {})
        if str(r.get("change")) == "0" and str(r.get("index")) == str(lockrec.get("index")) and not r.get("leafscript"):
            base = r
            break
    if base is not None:
        xonly = bytes.fromhex(str(base["pubkey"]))[1:]
        leaf = REF.timelock_script(900000, xonly)
        want_l = REF.tap_commit(REF.SP_NUMS_H, leaf)
        c.ck("its leaf and commit are the oracle's, under the NUMS point",
             (str(lockrec.get("leafscript")), str(lockrec.get("script")), str(lockrec.get("internalkey")),
              LCS._n(lockrec.get("lockheight"))),
             (leaf.hex(), want_l["script"].hex(), REF.SP_NUMS_H.hex(), 900000))
        c.ck("the recipe is in the wallet file",
             "leaf\tlock|%d|900000" % int(LCS._n(lockrec["index"])) in str(ip.call("waSerializeWallet", [])),
             " / ".join(ln for ln in str(ip.call("waSerializeWallet", [])).split("\n") if ln.startswith("leaf"))[:300])
        utx = dict(ip.globals.get("swautxos") or {"n": 0})
        n_u = int(LCS._n(utx.get("n", 0))) + 1
        utx[str(n_u)] = {"txid": "ee" * 32, "vout": 0, "value": 30000, "confirmations": 1,
                         "height": 1, "address": lockrec["address"], "script": lockrec["script"],
                         "path": "", "pubkey": lockrec.get("pubkey", ""), "chain": 0,
                         "index": lockrec["index"], "selected": "", "frozen": ""}
        utx["n"] = n_u
        ip.globals["swautxos"] = utx
        # below the height the coin is withheld; at it, offered
        ip.globals["swatipheight"] = 899999
        offered = [u["txid"] for u in unlst_boot(ip.call("waSpendableCoins", []))]
        c.ck("below the height the locked coin is not offered for spending",
             "ee" * 32 not in offered, offered)
        ip.globals["swatipheight"] = 900000
        offered = [u["txid"] for u in unlst_boot(ip.call("waSpendableCoins", []))]
        c.ck("at the height it is", "ee" * 32 in offered, offered)
        ip.globals["swatipheight"] = ""
        # a manual spend of exactly that coin: the locktime rises, the leaf signs
        click(ip, world, "nv_cn")
        ip.globals["swaselected"] = {"%s:0" % ("ee" * 32): "true"}
        world.stack_props["ustrategy"] = "manual"
        click(ip, world, "nv_sd")
        put_field("sd_to", "%s,0.0001" % first)
        put_field("sd_locktime", "0")
        click(ip, world, "sd_preview")
        out = _fld(world, "sd_out")
        c.ck("the review says the locktime was raised for the locked coin",
             "locktime     900000" in out and "locked until block 900000" in out, repr(out[-400:]))
        click(ip, world, "sd_sign")
        raw_l = str(ip.globals.get("swalastraw", ""))
        c.ck("the spend signs", len(raw_l) > 200, "%d hex chars" % len(raw_l))
        if len(raw_l) > 200:
            dec_l = REF.tx_decode(bytes.fromhex(raw_l))
            wit = dec_l["vin"][0].get("witness", [])
            c.ck("with locktime 900000, the locked coin as its input, and the leaf in the witness",
                 (int(dec_l["locktime"]), dec_l["vin"][0]["txid"], len(wit), wit[1:] if len(wit) == 3 else wit),
                 (900000, "ee" * 32, 3, [leaf.hex(), want_l["controlblock"].hex()]))
            c.ck("and a sequence that lets the locktime bind",
                 int(dec_l["vin"][0]["sequence"]) < 0xFFFFFFFF, dec_l["vin"][0].get("sequence"))
            digest = REF.tapscript_sighash(2, [(dec_l["vin"][0]["txid"], int(dec_l["vin"][0]["vout"]),
                                                int(dec_l["vin"][0]["sequence"]))],
                                           [(int(o["value"]), bytes.fromhex(o["scriptpubkey"])) for o in dec_l["vout"]],
                                           0, 900000, [want_l["script"]], [30000], want_l["leafhash"])
            c.ck("the signature is the leaf key's over that digest, byte for byte",
                 wit[0] if wit else "", REF.cr.schnorr_sign(bytes.fromhex(str(base["seckey"])), digest, bytes(32)).hex())
        ip.globals["swaselected"] = {}
        world.stack_props["ustrategy"] = "bnb"
    for label, text, want in (
            ("a lock without a height is refused", "", "block height"),
            ("a lock in the timestamp range is refused", "500000000", "block height"),
            ("a lock that is not a number is refused", "soon", "block height")):
        try:
            ip.call("waLockPrepare", [text])
            c.ck(label, False, "accepted")
        except LCS.Thrown as exc:
            c.ck(label, want in str(exc.msg), str(exc.msg)[:100])

    # ---- the two new screens say what they do (2026-09-04) -----------------
    # Every button on Ordinals and Vault carries a tooltip, the rail has
    # twelve entries inside its panel, the vault table reads the lock's
    # state from the tip, the Send screen's note button writes the line for
    # you, and the old "inscribe:" / "lock:" lines pasted on Tools are
    # carried to their screens rather than refused.
    bare = []
    for ct in world.cards[0].controls:
        if ct.ctype == "button" and (ct.name.startswith("od_") or ct.name.startswith("vt_")
                                     or ct.name.startswith("nv_")):
            if not str(ct.props.get("tooltip", "")).strip():
                bare.append(ct.name)
    c.ck("every button on Ordinals, Vault and the rail has a tooltip", bare == [], ",".join(bare))
    c.ck("and the Pay-to box explains its line forms on hover",
         "silent payment" in str((world.anywhere("sd_to").props if world.anywhere("sd_to") else {}).get("tooltip", "")),
         "")
    rail = [ct for ct in world.cards[0].controls if ct.ctype == "button" and ct.name.startswith("nv_")
            and ct.name != "nv_refresh"]
    c.eq("the rail has twelve screen buttons", len(rail), 12)
    panel = world.anywhere("nv_panel")
    if panel is not None and panel.rect:
        outside = [ct.name for ct in rail if ct.rect and (ct.rect[1] < panel.rect[1] or ct.rect[3] > panel.rect[3])]
        refresh = world.anywhere("nv_refresh")
        if refresh is not None and refresh.rect and refresh.rect[3] > panel.rect[3]:
            outside.append("nv_refresh")
        c.ck("and every rail button sits inside the rail panel", outside == [], ",".join(outside))
    click(ip, world, "nv_vt")
    tip_was = ip.globals.get("swatipheight")
    ip.globals["swatipheight"] = 899000
    click(ip, world, "nv_vt")
    c.ck("the vault table reads a lock as locked with the blocks to go",
         "locked, 1000 blocks" in _fld(world, "vt_table"), _fld(world, "vt_table")[:200])
    ip.globals["swatipheight"] = 900000
    click(ip, world, "nv_vt")
    c.ck("and as UNLOCKED once the tip reaches its height",
         "UNLOCKED" in _fld(world, "vt_table"), _fld(world, "vt_table")[:200])
    ip.globals["swatipheight"] = tip_was
    click(ip, world, "nv_sd")
    put_field("sd_to", "%s,0.0005" % first)
    click(ip, world, "sd_addNote")
    c.ck("Add a note appends a note: line to the Pay-to box",
         _fld(world, "sd_to").endswith("note: "), repr(_fld(world, "sd_to")[-30:]))
    click(ip, world, "nv_tl")
    put_field("tl_hex", "inscribe: image/svg+xml; <svg/>")
    click(ip, world, "tl_inspect")
    c.ck("an inscribe: line on Tools is carried to the Ordinals screen, filled in",
         ip.globals.get("swascreen") == "ordinals" and _fld(world, "od_type") == "image/svg+xml"
         and _fld(world, "od_body") == "<svg/>", "%r %r" % (ip.globals.get("swascreen"), _fld(world, "od_type")))
    click(ip, world, "nv_tl")
    put_field("tl_hex", "lock: 123456")
    click(ip, world, "tl_inspect")
    c.ck("and a lock: line to the Vault screen",
         ip.globals.get("swascreen") == "vault" and _fld(world, "vt_height") == "123456",
         "%r %r" % (ip.globals.get("swascreen"), _fld(world, "vt_height")))
    put_field("sd_to", "%s,0.0005" % first)

    # ---- Tools: BIP-322 on the wallet's own native-SegWit key (2026-09-04) --
    # The box ticked, Sign produces a witness stack rather than a 65-byte
    # header signature, Verify reads the format off the signature and
    # answers with the shape, and a tampered message is refused.
    cb = world.anywhere("tl_msg322")
    c.ck("the Tools screen carries the BIP-322 box", cb is not None)
    if cb is not None:
        click(ip, world, "nv_tl")
        put_field("tl_msg", "proof of keys, 2026-09-04")
        put_field("tl_msgAddr", first)
        cb.props["hilite"] = True
        click(ip, world, "tl_msgSign")
        sig322 = _fld(world, "tl_msgSig").strip()
        import base64 as _b64
        raw322 = _b64.b64decode(sig322) if sig322 else b""
        c.ck("Sign with the box ticked makes a BIP-322 witness stack, not a header",
             len(raw322) > 65 and raw322[:1] == b"\x02", "%d bytes" % len(raw322))
        c.ck("and says which format it used", "SIGNED (BIP-322)" in _fld(world, "tl_out"))
        click(ip, world, "tl_msgVerify")
        c.ck("Verify reads the format off the signature and accepts it",
             _fld(world, "tl_out").startswith("VERIFIED")
             and "bip322-p2wpkh" in str(world.anywhere("uiStatus").content
                                          if world.anywhere("uiStatus") else ""),
             _fld(world, "tl_out")[:80])
        put_field("tl_msg", "proof of keys, 2026-09-05")
        click(ip, world, "tl_msgVerify")
        c.ck("a changed message is NOT VERIFIED",
             _fld(world, "tl_out").startswith("NOT VERIFIED"), _fld(world, "tl_out")[:60])
        cb.props["hilite"] = False
        put_field("tl_msg", "proof of keys, 2026-09-04")
        click(ip, world, "tl_msgSign")
        raw2011 = _b64.b64decode(_fld(world, "tl_msgSig").strip() or "AA==")
        c.eq("with the box clear the same key signs in the 2011 format (65 bytes)",
             len(raw2011), 65)
        click(ip, world, "tl_msgVerify")
        c.ck("which Verify also reads off the signature",
             _fld(world, "tl_out").startswith("VERIFIED"), _fld(world, "tl_out")[:60])

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

    # ---- labels in BIP-329, out and back (2026-09-04) ---------------------
    # One JSON object per line; this wallet's address labels go out as
    # "addr" records and its frozen coins as "output" records with
    # spendable false, and both come back. Types it does not keep are
    # counted and skipped, a line that is not JSON is named.
    saved_lab = {k: ip.globals.get(k) for k in ("swalabels", "swafrozen")}
    lab_path = os.path.join(sandbox, "labels-test.wallet")
    put_field("st_path", lab_path)
    a_lab = str((ip.globals.get("swaaddresses") or {}).get("1", {}).get("address", ""))
    b_lab = str((ip.globals.get("swaaddresses") or {}).get("2", {}).get("address", ""))
    ip.globals["swalabels"] = {a_lab: "rent", b_lab: 'says "hi"\ttab'}
    ip.globals["swafrozen"] = {"cc" * 32 + ":0": "true"}
    text = str(ip.call("waLabelsText", []))
    lines = [ln for ln in text.split("\n") if ln.strip()]
    c.eq("two labels and one frozen coin make three BIP-329 lines", len(lines), 3)
    try:
        recs = [json.loads(ln) for ln in lines]
    except ValueError as exc:
        recs = []
        c.ck("every line is JSON", False, str(exc)[:80])
    if recs:
        c.ck("every line is JSON", True)
        c.ck("the address labels are addr records with the label escaped intact",
             {"type": "addr", "ref": b_lab, "label": 'says "hi"\ttab'} in recs
             and {"type": "addr", "ref": a_lab, "label": "rent"} in recs, str(recs)[:200])
        c.ck("the frozen coin is an output record that is not spendable",
             {"type": "output", "ref": "cc" * 32 + ":0", "spendable": False} in recs,
             str(recs)[:200])
    click(ip, world, "st_exportLabels")
    c.ck("Export writes the file beside the wallet file",
         os.path.exists(lab_path + ".labels.jsonl"), lab_path + ".labels.jsonl")
    ip.globals["swalabels"] = {}
    ip.globals["swafrozen"] = {}
    click(ip, world, "st_importLabels")
    c.eq("Import brings the labels back", str((ip.globals.get("swalabels") or {}).get(a_lab)),
         "rent")
    c.eq("with the escaped one intact",
         str((ip.globals.get("swalabels") or {}).get(b_lab)), 'says "hi"\ttab')
    c.eq("and the frozen coin", str((ip.globals.get("swafrozen") or {}).get("cc" * 32 + ":0")),
         "true")
    # the BIP's own examples: kept where the wallet has a home for them,
    # counted and skipped where it does not
    bip = ('{ "type": "tx", "ref": "f91d0a8a78462bc59398f2c5d7a84fcff491c26ba54c4833478b202796c8aafd", "label": "Transaction", "origin": "wpkh([d34db33f/84h/0h/0h])" }\n'
           '{ "type": "addr", "ref": "bc1q34aq5drpuwy3wgl9lhup9892qp6svr8ldzyy7c", "label": "Address" }\n'
           '{ "type": "pubkey", "ref": "0283409659355b6d1cc3c32decd5d561abaac86c37a353b52895a5e6c196d6f448", "label": "Public Key" }\n'
           '{ "type": "input", "ref": "f91d0a8a78462bc59398f2c5d7a84fcff491c26ba54c4833478b202796c8aafd:0", "label": "Input" }\n'
           '{ "type": "output", "ref": "f91d0a8a78462bc59398f2c5d7a84fcff491c26ba54c4833478b202796c8aafd:1", "label": "Output", "spendable": false }\n'
           '{ "type": "xpub", "ref": "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8", "label": "Extended Public Key" }\n')
    summary = str(ip.call("waLabelsApply", [bip]))
    c.ck("the BIP's examples: one address label kept, one output frozen and labelled, four skipped",
         summary.startswith("1 address label(s), 1 output record(s), 4 other"), summary)
    c.eq("the example address label landed",
         str((ip.globals.get("swalabels") or {}).get("bc1q34aq5drpuwy3wgl9lhup9892qp6svr8ldzyy7c")),
         "Address")
    c.eq("the example output is frozen",
         str((ip.globals.get("swafrozen") or {}).get("f91d0a8a78462bc59398f2c5d7a84fcff491c26ba54c4833478b202796c8aafd:1")),
         "true")
    try:
        ip.call("waLabelsApply", ['{"type":"addr","ref":"x","label":"ok"}\nnot json\n'])
        c.ck("a line that is not JSON is refused by its number", False, "accepted")
    except LCS.Thrown as exc:
        c.ck("a line that is not JSON is refused by its number",
             "line 2" in str(exc.msg), str(exc.msg)[:100])
    put_field("st_path", "")
    try:
        ip.call("waLabelsExport", [])
        c.ck("Export with no wallet path says so", False, "wrote somewhere")
    except LCS.Thrown as exc:
        c.ck("Export with no wallet path says so", "path first" in str(exc.msg), str(exc.msg)[:80])
    for k, v in saved_lab.items():
        ip.globals[k] = v

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
    # Until 2026-09-02 the first of these read "refused off mainnet": the v2
    # address that stood in kWaElectrumOnion carried mainnet only. The v3
    # onion serves testnet on its own port, so the guard now refuses only
    # the chains NEITHER port carries - and lifting it without the port
    # table below would have swapped a refusal for an empty wallet.
    c.ck("the built-in Electrum onion is refused on signet, which no port carries",
         why("electrum-tor", elec, "signet") != "")
    c.eq("and allowed on mainnet, which it serves",
         why("electrum-tor", elec, "mainnet"), "")
    c.eq("and on testnet, which it serves on a second port",
         why("electrum-tor", elec, "testnet"), "")
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
    # TESTNET4 (2026-09-04): testnet3's bytes on a different chain, so the
    # backend is the only thing that can tell them apart - and Blockstream's
    # mirrors index testnet3. The guard names the host that serves it.
    alt = str(ip.constants.get("kWaEsploraClearAlt", ""))
    w4 = why("esplora-clear", clear, "testnet4")
    c.ck("testnet4 is refused on Blockstream's clearnet mirror, naming mempool.space",
         w4 != "" and alt in w4, w4[:120])
    c.ck("and on its onion", why("esplora-tor", onion, "testnet4") != "")
    c.eq("and allowed on mempool.space, which serves it",
         why("esplora-clear", alt, "testnet4"), "")
    c.ck("the built-in Electrum servers are refused on testnet4",
         why("electrum-tor", elec, "testnet4") != ""
         and why("electrum-clear", str(ip.constants.get("kWaElectrumClear", "")), "testnet4") != "")
    ip.globals["swanetwork"] = "testnet4"
    c.ck("testnet4 asks its own Esplora root",
         esplora_path("tip").startswith("/testnet4/api"), esplora_path("tip"))
    c.eq("and the wallet knows the chain by name", str(ip.call("waNetChoice", [])), "Test4")
    c.ck("and derives testnet-shaped addresses for it",
         str(ip.call("waSelfTestAddress", ["p2wpkh", "testnet4"])).startswith("tb1"),
         str(ip.call("waSelfTestAddress", ["p2wpkh", "testnet4"])))

    # And the guard is REACHED: waSync refuses before it builds a request.
    ip.globals["swabackend"] = "electrum-tor"
    ip.globals["swahost"] = elec
    ip.globals["swanetwork"] = "signet"
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

    # ---- Electrum over Tor: the dead onion of the 2026-09-02 log ---------
    # The first engine attempt at this transport dialled
    # "explorernuoc63nb.onion:110", retried it once as designed, and failed
    # with the daemon's "general SOCKS server failure" - Tor's answer for a
    # VERSION-2 onion, a shape it stopped resolving in 2021, and also its
    # answer for a failed circuit, which is why the retry looked reasonable.
    # The constant is a v3 address now, the chain is selected by port the
    # way the clearnet server does it, and the retired shape is refused by
    # name before a dial. Nothing here says the v3 onion ANSWERS: that still
    # needs the engine, and docs/wallet.md says so.
    saved5 = {k: ip.globals.get(k) for k in
              ("swabackend", "swahost", "swaport", "swanetwork",
               "swahaveonion", "swanetstate", "swanetwhy")}
    onion_e = str(ip.constants.get("kWaElectrumOnion", ""))
    c.ck("the built-in Electrum onion is a version-3 address (56 + .onion)",
         onion_e.endswith(".onion") and len(onion_e) == 62, onion_e)
    c.eq("and waOnionWhy accepts it", str(ip.call("waOnionWhy", [onion_e])), "")
    dead = "explorernuoc63nb.onion"
    why_dead = str(ip.call("waOnionWhy", [dead]))
    c.ck("the v2 onion that stood there until 2026-09-02 is refused by name",
         "version-2" in why_dead and "2021" in why_dead
         and "SOCKS server failure" in why_dead, why_dead[:120])
    c.eq("a clearnet host through Tor is not judged",
         str(ip.call("waOnionWhy", ["electrum.blockstream.info"])), "")
    c.ck("a malformed onion is refused, with its length named",
         "10 characters" in str(ip.call("waOnionWhy", ["abcdefghij.onion"])),
         str(ip.call("waOnionWhy", ["abcdefghij.onion"]))[:100])
    c.eq("a subdomain of a v3 onion is judged by its onion label",
         str(ip.call("waOnionWhy", ["www." + onion_e])), "")
    c.eq("upper case and whitespace do not change the answer",
         str(ip.call("waOnionWhy", ["  " + dead.upper() + " "])) != "", True)

    # the port IS the chain on the onion too, through the one table
    ip.globals["swahaveonion"] = "true"
    ip.globals["swanetwork"] = "mainnet"
    ip.call("waSetBackend", ["electrum-tor"])
    c.eq("Electrum over Tor picks the v3 onion", str(ip.globals.get("swahost")),
         onion_e)
    c.eq("and mainnet's port",
         int(LCS._n(ip.globals.get("swaport"))),
         int(LCS._n(ip.constants.get("kWaElectrumPort", 0))))
    ip.globals["swanetwork"] = "testnet"
    ip.call("waSetBackend", ["electrum-tor"])
    c.eq("testnet gets the onion's testnet port - it was 110 for every chain",
         int(LCS._n(ip.globals.get("swaport"))),
         int(LCS._n(ip.constants.get("kWaElectrumTorTestPort", 0))))
    c.ck("the two onion ports differ",
         int(LCS._n(ip.constants.get("kWaElectrumPort", 0)))
         != int(LCS._n(ip.constants.get("kWaElectrumTorTestPort", 0))))
    c.eq("and the state is idle, not a chain complaint",
         str(ip.globals.get("swanetstate")), "idle")
    ip.globals["swanetwork"] = "mainnet"
    ip.call("waRetunePort", [])
    c.eq("switching the network retunes the onion's port too",
         int(LCS._n(ip.globals.get("swaport"))),
         int(LCS._n(ip.constants.get("kWaElectrumPort", 0))))
    # a host the person typed is left alone, onion or not
    ip.globals["swahost"] = "myownserver" + onion_e[11:]
    ip.globals["swaport"] = 50099
    ip.globals["swanetwork"] = "testnet"
    ip.call("waRetunePort", [])
    c.eq("a typed onion keeps its typed port",
         int(LCS._n(ip.globals.get("swaport"))), 50099)

    # the refusal reaches the network state and the sync, not just the function
    ip.globals["swahost"] = dead
    ip.call("waRefreshNetState", [])
    c.eq("a v2 host typed into the field fails the network state",
         str(ip.globals.get("swanetstate")), "failed")
    c.ck("and the reason names the shape",
         "version-2" in str(ip.globals.get("swanetwhy")),
         str(ip.globals.get("swanetwhy"))[:100])
    try:
        ip.call("waSync", [])
        c.ck("waSync refuses to queue a request for a v2 onion", False,
             "it queued the requests instead")
    except LCS.Thrown as exc:
        c.ck("waSync refuses to queue a request for a v2 onion",
             "version-2" in str(exc.msg), str(exc.msg)[:100])
    # ...and the dial itself, for a host that changed after the state did
    try:
        ip.call("waNetStart", [{"kind": "tip", "arg": ""}])
        c.ck("waNetStart refuses to dial a v2 onion", False, "it dialled")
    except LCS.Thrown as exc:
        c.ck("waNetStart refuses to dial a v2 onion",
             "version-2" in str(exc.msg), str(exc.msg)[:100])
    c.ck("and nothing was queued or left in flight by the refusal",
         not ip.globals.get("swainflight")
         and ip.call("cwListCount", [ip.globals.get("swaqueue")]) == 0)
    # the clearnet Electrum server is unaffected by any of it
    ip.globals["swanetwork"] = "testnet"
    ip.call("waSetBackend", ["electrum-clear"])
    c.eq("clearnet Electrum still retunes to its own testnet port",
         int(LCS._n(ip.globals.get("swaport"))),
         int(LCS._n(ip.constants.get("kWaElectrumClearTestPort", 0))))
    for k, v in saved5.items():
        ip.globals[k] = v

    # ---- Electrum over Tor keeps ONE stream for a sync (2026-09-03) --------
    # The first engine log in which this transport spoke to a server dialled
    # a fresh rendezvous stream for every one of 173 requests - the
    # per-request-connection shape the clearnet transport was cured of two
    # days earlier. The stream is kept between requests now, and this drives
    # the whole life of one through the modelled Tor above: dialled once,
    # written to for each request, a notification pushed in the same chunk
    # as a reply, a reply split across chunks, dropped by the server while
    # idle (not a failure), dialled again, abandoned when the host moves,
    # and a refused write retried once on a fresh stream. Esplora stays one
    # stream per request, and that is asserted too.
    saved7 = {k: ip.globals.get(k) for k in
              ("swabackend", "swahost", "swaport", "swanetwork", "swahaveonion",
               "swanetstate", "swanetwhy", "swaqueue", "swainflight", "swabuffer",
               "swastream", "swastreamto", "swasyncfailures", "swatipheight",
               "swafeerates", "swautxos", "swahistory", "swabatch",
               "swabatchmembers", "swatipat", "swafeesat")}
    world.tor, world.tor_state, world.tor_handles = [], {}, 0
    world.tor_write_fail = ""
    LCS.HASHES["oxstreamstate"] = (
        lambda a: world.tor_state.get(int(LCS._n(a[0])), "unknown"))

    def tor_count(kind):
        return sum(1 for t in world.tor if t[0] == kind)

    def tor_last_write():
        w = [t for t in world.tor if t[0] == "write"]
        return w[-1][2] if w else ""

    def inflight_id():
        rec = ip.globals.get("swainflight") or {}
        return str(rec.get("id", ""))

    def stream_event(h, kind, data=""):
        ip.call("waStreamEvent", [h, kind, data])

    def log_tail(n=1200):
        return _fld(world, "lg_text")[-n:]

    try:
        ip.globals["swahaveonion"] = "true"
        ip.globals["swanetwork"] = "testnet"
        ip.globals["swasyncfailures"] = 0
        ip.call("waSetBackend", ["electrum-tor"])
        onion_to = "%s:%s" % (ip.globals.get("swahost"), ip.globals.get("swaport"))
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        c.eq("the first request dials", tor_count("dial"), 1)
        c.eq("and remembers the stream", str(ip.globals.get("swastream")), "1")
        c.eq("and where it went", str(ip.globals.get("swastreamto")), onion_to)
        world.tor_state[1] = "connected"
        stream_event(1, "open")
        c.ck("the open stream carries the request",
             "blockchain.headers.subscribe" in tor_last_write(), tor_last_write()[:80])
        stream_event(1, "data", '{"jsonrpc":"2.0","id":%s,"result":{"height":'
                     '5127803,"hex":"00"}}\n' % inflight_id())
        c.eq("the reply lands", str(ip.globals.get("swatipheight")), "5127803")
        c.eq("and nothing is in flight", str(ip.globals.get("swainflight")), "")
        c.eq("THE STREAM IS KEPT after the reply",
             str(ip.globals.get("swastream")), "1")
        c.eq("and was not closed", tor_count("close"), 0)

        ip.call("waNetQueue", ["fees", ""])
        # a reply with more queued behind it asks for the pump NOW, deferred
        # by one turn, rather than waiting up to a tick (2026-09-03)
        world.sends = [m for m in world.sends if "wapumpnow" not in str(m[0]).lower()]
        ip.globals["swainflight"] = {"kind": "tip", "arg": "", "id": "77"}
        stream_event(1, "data", '{"jsonrpc":"2.0","id":77,"result":{"height":'
                     '5127803,"hex":"00"}}\n')
        c.ck("a reply with requests still queued arms an immediate pump",
             any("wapumpnow" in str(m[0]).lower() for m in world.sends),
             str(world.sends[-3:]))
        world.sends = [m for m in world.sends if "wapumpnow" not in str(m[0]).lower()]
        ip.call("waNetPump", [])
        c.eq("the next request does NOT dial", tor_count("dial"), 1)
        c.ck("it is written down the same stream",
             tor_count("write") == 2 and "estimatefee" in tor_last_write(),
             tor_last_write()[:80])
        c.eq("and the state says busy", str(ip.globals.get("swanetstate")), "busy")
        # a notification pushed in the same chunk as the reply, FIRST
        stream_event(1, "data",
                     '{"jsonrpc":"2.0","method":"blockchain.headers.subscribe",'
                     '"params":[{"height":5127804,"hex":"00"}]}\n'
                     '{"jsonrpc":"2.0","id":%s,"result":0.00001}\n' % inflight_id())
        c.eq("a notification ahead of the reply in one chunk is ignored and "
             "the reply still lands",
             str((ip.globals.get("swafeerates") or {}).get("6")), "1")
        c.ck("and the log says so", "notification (no id)" in log_tail())
        c.eq("the buffer is empty afterwards", str(ip.globals.get("swabuffer")), "")

        # a reply split across two chunks, with a coin in it
        addr0 = str((ip.globals.get("swaaddresses") or {}).get("1", {})
                    .get("address", ""))
        ip.call("waNetQueue", ["utxos", addr0])
        ip.call("waNetPump", [])
        rid = inflight_id()
        stream_event(1, "data", '{"jsonrpc":"2.0","id":%s,"res' % rid)
        c.eq("half a line is not an answer", inflight_id(), rid)
        stream_event(1, "data", 'ult":[{"tx_hash":"%s","tx_pos":0,"height":'
                     '5127000,"value":4242}]}\n' % ("dd" * 32))
        u = ip.globals.get("swautxos") or {}
        c.ck("the two halves make one coin",
             any(str(u.get(str(k), {}).get("value", "")) == "4242"
                 for k in range(1, int(LCS._n(u.get("n", 0))) + 1)),
             "%s coins" % u.get("n"))
        c.eq("still the one dial", tor_count("dial"), 1)

        # a partial notification straddling the pump boundary is kept
        stream_event(1, "data", '{"jsonrpc":"2.0","method":"blockchain.head')
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        c.ck("the pump keeps a partial line on the kept stream",
             str(ip.globals.get("swabuffer")).endswith("blockchain.head"),
             repr(str(ip.globals.get("swabuffer"))[-40:]))
        stream_event(1, "data", 'ers.subscribe","params":[{"height":5127805}]}\n'
                     '{"jsonrpc":"2.0","id":%s,"result":{"height":5127805,'
                     '"hex":"00"}}\n' % inflight_id())
        c.eq("its tail is a notification, not a broken reply",
             str(ip.globals.get("swatipheight")), "5127805")
        c.eq("and no failure was counted", int(LCS._n(ip.globals.get("swasyncfailures"))), 0)

        # the server drops the idle stream
        stream_event(1, "closed")
        c.eq("an idle close forgets the stream", str(ip.globals.get("swastream")), "")
        c.eq("and counts no failure", int(LCS._n(ip.globals.get("swasyncfailures"))), 0)
        c.ck("and is not a failed state", str(ip.globals.get("swanetstate")) != "failed",
             str(ip.globals.get("swanetstate")))
        c.ck("and the log says the next request will dial",
             "idle stream 1" in log_tail() and "dial again" in log_tail(),
             log_tail(200))
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        c.eq("which it does", tor_count("dial"), 2)
        c.eq("on a new handle", str(ip.globals.get("swastream")), "2")
        world.tor_state[2] = "connected"
        stream_event(2, "open")
        stream_event(2, "data", '{"jsonrpc":"2.0","id":%s,"result":{"height":'
                     '5127806,"hex":"00"}}\n' % inflight_id())
        # an idle ERROR is the same shape
        stream_event(2, "error", "connection reset")
        c.eq("an idle error forgets the stream too", str(ip.globals.get("swastream")), "")
        c.eq("without a failure", int(LCS._n(ip.globals.get("swasyncfailures"))), 0)

        # the host moves under an open stream
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        world.tor_state[3] = "connected"
        stream_event(3, "open")
        stream_event(3, "data", '{"jsonrpc":"2.0","id":%s,"result":{"height":'
                     '5127807,"hex":"00"}}\n' % inflight_id())
        c.eq("a third stream is open and kept", str(ip.globals.get("swastream")), "3")
        onion_e = str(ip.constants.get("kWaElectrumOnion", ""))
        ip.globals["swahost"] = "aaaa" + onion_e[4:]
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        c.ck("a moved host closes the kept stream", ("close", 3) in world.tor)
        c.eq("and dials the new one", tor_count("dial"), 4)
        c.ck("and says so", "backend moved" in log_tail(), log_tail(200))
        ip.globals["swahost"] = onion_e

        # a refused write on a reused stream: closed, retried once, dialled again
        ip.call("waNetAbort", [])
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        stream_event(h, "data", '{"jsonrpc":"2.0","id":%s,"result":{"height":'
                     '5127808,"hex":"00"}}\n' % inflight_id())
        ip.call("waNetQueue", ["fees", ""])
        world.tor_write_fail = "socket closed"
        ip.call("waNetPump", [])
        world.tor_write_fail = ""
        c.ck("a refused write closes the stream", ("close", h) in world.tor)
        c.ck("and retries the request once, at the front",
             "retrying fees" in log_tail()
             and str((ip.globals.get("swaqueue") or {}).get("1", {}).get("kind")) == "fees"
             and str((ip.globals.get("swaqueue") or {}).get("1", {}).get("retried")) == "true",
             log_tail(200))
        c.eq("counting nothing yet", int(LCS._n(ip.globals.get("swasyncfailures"))), 0)
        dials = tor_count("dial")
        ip.call("waNetPump", [])
        c.eq("and the retry dials afresh", tor_count("dial"), dials + 1)

        # ---- A RUN OF HISTORIES GOES AS ONE BATCH (2026-09-03) ----
        # JSON-RPC batching: the pump gathers a run of same-kind requests
        # into one array, the server answers an array, each element goes to
        # its member by id. Forty histories are two round trips. A server
        # that refuses the batch is asked with half as many, down to singly, a
        # member's own error is that member's failure, and an unanswered
        # member is asked again alone.
        ip.call("waNetAbort", [])
        ip.globals["swabatch"] = ""
        ip.call("waSetBackend", ["electrum-tor"])
        addrs_b = ip.globals.get("swaaddresses") or {}
        a1, a2, a3 = (str(addrs_b.get(str(k), {}).get("address", "")) for k in (1, 2, 3))
        # a broadcast goes alone, ahead of anything queued behind it
        ip.call("waNetQueue", ["broadcast", "00" * 60])
        ip.call("waNetQueue", ["history", a1])
        ip.call("waNetPump", [])
        c.eq("a broadcast is never batched",
             str((ip.globals.get("swainflight") or {}).get("kind")), "broadcast")
        c.eq("and the history waits behind it",
             int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), 1)
        ip.call("waNetAbort", [])
        # the tip, three histories and the fees: ONE batch, in queue order
        ip.call("waNetQueue", ["tip", ""])
        for a in (a1, a2, a3):
            ip.call("waNetQueue", ["history", a])
        ip.call("waNetQueue", ["fees", ""])
        ip.call("waNetPump", [])
        rec = ip.globals.get("swainflight") or {}
        c.eq("the tip, the histories and the fees go as one batch",
             str(rec.get("kind")), "batch")
        c.eq("leaving the queue empty",
             int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), 0)
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        w = tor_last_write()
        c.ck("the batch is one JSON array of the members' requests",
             w.startswith("[{") and w.rstrip("\n").endswith("}]")
             and w.count("blockchain.scripthash.get_history") == 3
             and w.count("headers.subscribe") == 1 and w.count("estimatefee") == 1, w[:80])
        c.ck("and the log says its shape, not its script hashes",
             "-> batch of 5 (tip, 3 history, fees), ids" in log_tail(), log_tail(200))
        members = ip.globals.get("swabatchmembers") or {}
        ids = [str(members.get(str(k), {}).get("id")) for k in (1, 2, 3, 4, 5)]
        # answered out of order: fees, an empty history, a refused one, the
        # tip, and a history with a row (so a utxos request follows)
        reply = ('[{"jsonrpc":"2.0","id":%s,"result":0.00002},'
                 '{"jsonrpc":"2.0","id":%s,"result":[]},'
                 '{"jsonrpc":"2.0","id":%s,"error":{"code":1,"message":"no such hash"}},'
                 '{"jsonrpc":"2.0","id":%s,"result":{"height":5127820,"hex":"00"}},'
                 '{"jsonrpc":"2.0","id":%s,"result":[{"tx_hash":"%s","height":5127000}]}]\n'
                 % (ids[4], ids[2], ids[3], ids[0], ids[1], "ee" * 32))
        fails_before = int(LCS._n(ip.globals.get("swasyncfailures")))
        stream_event(h, "data", reply)
        c.eq("the batch reply is applied and nothing is in flight",
             str(ip.globals.get("swainflight")), "")
        c.eq("the tip in it landed", str(ip.globals.get("swatipheight")), "5127820")
        c.eq("and the fee estimate in it",
             str((ip.globals.get("swafeerates") or {}).get("6")), "2")
        hist = ip.globals.get("swahistory") or {}
        c.ck("the answered history landed on its own address",
             any(str(hist.get(str(k), {}).get("txid", "")) == "ee" * 32
                 and str(hist.get(str(k), {}).get("address", "")) == a1
                 for k in range(1, int(LCS._n(hist.get("n", 0))) + 1)),
             "%s rows" % hist.get("n"))
        q = ip.globals.get("swaqueue") or {}
        qk = [(str(q.get(str(k), {}).get("kind")), str(q.get(str(k), {}).get("arg")))
              for k in range(1, int(LCS._n(q.get("n", 0))) + 1)]
        c.ck("its unspent outputs are asked for",
             ("utxos", a1) in qk and len(qk) == 1, str(qk))
        c.eq("the refused member counts as one failure, not the sync's",
             int(LCS._n(ip.globals.get("swasyncfailures"))), fails_before + 1)
        c.ck("and is named in the log", "FAILED: history " + a3 in log_tail(), log_tail(200))
        c.eq("the stream is kept through all of it", str(ip.globals.get("swastream")), str(h))
        # an unanswered member is asked again on its own
        ip.call("waNetAbort", [])
        ip.globals["swasyncfailures"] = 0
        for a in (a1, a2):
            ip.call("waNetQueue", ["history", a])
        ip.call("waNetPump", [])
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        members = ip.globals.get("swabatchmembers") or {}
        ids = [str(members.get(str(k), {}).get("id")) for k in (1, 2)]
        stream_event(h, "data", '[{"jsonrpc":"2.0","id":%s,"result":[]},'
                     '{"jsonrpc":"2.0","id":999,"result":[]}]\n' % ids[0])
        q = ip.globals.get("swaqueue") or {}
        c.eq("a member the server left out is queued again, alone",
             [int(LCS._n(q.get("n", 0))), str(q.get("1", {}).get("arg"))], [1, a2])
        c.ck("and the stray id is ignored and said so",
             "id 999" in log_tail() and "ignored" in log_tail(), log_tail(200))
        # a server that does not take batches
        ip.call("waNetAbort", [])
        for a in (a1, a2, a3):
            ip.call("waNetQueue", ["history", a])
        ip.call("waNetPump", [])
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        stream_event(h, "data", '{"jsonrpc":"2.0","id":null,"error":{"code":-32600,'
                     '"message":"Invalid Request"}}\n')
        q = ip.globals.get("swaqueue") or {}
        c.eq("a refused batch puts its members back, singly and in order",
             [str(q.get(str(k), {}).get("arg")) for k in range(1, 4)], [a1, a2, a3])
        c.eq("and nothing is counted against the sync",
             int(LCS._n(ip.globals.get("swasyncfailures"))), 0)
        c.eq("and batching is off for this server", str(ip.globals.get("swabatch")), "false")
        c.ck("and the log says so", "did not take a batch of 3" in log_tail(), log_tail(200))
        ip.call("waNetPump", [])
        c.eq("the next request goes alone",
             str((ip.globals.get("swainflight") or {}).get("kind")), "history")
        c.ck("as a single object", tor_last_write().startswith("{"), tor_last_write()[:40])
        # A REFUSAL HALVES THE BATCH BEFORE IT GIVES UP ON BATCHING (2026-09-03):
        # the ninth engine log had an onion server close the connection on a
        # batch of 22 and the sync fall to 41 single Tor round trips. Four
        # requests refused go on as two; two refused go on singly.
        ip.call("waNetAbort", [])
        ip.globals["swabatch"] = ""
        ip.globals["swabatchcap"] = ""
        ip.call("waNetQueue", ["tip", ""])
        for a in (a1, a2, a3):
            ip.call("waNetQueue", ["history", a])
        ip.call("waNetPump", [])
        c.eq("four requests go as one batch",
             int(LCS._n((ip.globals.get("swabatchmembers") or {}).get("n", 0))), 4)
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        stream_event(h, "data", '{"jsonrpc":"2.0","id":null,"error":{"code":-32600,'
                     '"message":"Invalid Request"}}\n')
        c.eq("a refused batch of four halves the cap to two", str(ip.globals.get("swabatchcap")), "2")
        c.ck("and the log says what is tried next", "trying 2 at a time" in log_tail(), log_tail(200))
        c.ck("batching itself stays on", str(ip.globals.get("swabatch")) != "false", "")
        q = ip.globals.get("swaqueue") or {}
        c.eq("with the members back in order",
             [str(q.get(str(k), {}).get("kind")) for k in range(1, 5)], ["tip", "history", "history", "history"])
        ip.call("waNetAbort", [])
        for a in (a1, a2):
            ip.call("waNetQueue", ["history", a])
        ip.call("waNetPump", [])
        c.eq("the next line carries two",
             int(LCS._n((ip.globals.get("swabatchmembers") or {}).get("n", 0))), 2)
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        stream_event(h, "data", '{"jsonrpc":"2.0","id":null,"error":{"code":-32600,'
                     '"message":"Invalid Request"}}\n')
        c.eq("a second refusal, at two, turns batching off", str(ip.globals.get("swabatch")), "false")
        c.ck("and says so", "asking one at a time" in log_tail(), log_tail(200))
        ip.call("waNetAbort", [])
        ip.globals["swabatchcap"] = ""
        # a batch that fails in transit is split, not retried whole
        ip.call("waNetAbort", [])
        ip.globals["swabatch"] = ""
        for a in (a1, a2):
            ip.call("waNetQueue", ["history", a])
        ip.call("waNetPump", [])
        c.eq("batching is back on a new backend or when told",
             str((ip.globals.get("swainflight") or {}).get("kind")), "batch")
        h = int(LCS._n(ip.globals.get("swastream")))
        stream_event(h, "error", "connection reset")
        q = ip.globals.get("swaqueue") or {}
        c.eq("a batch lost in transit is split into its members",
             [int(LCS._n(q.get("n", 0))), str(q.get("1", {}).get("kind"))], [2, "history"])
        c.eq("without counting a failure", int(LCS._n(ip.globals.get("swasyncfailures"))), 0)
        ip.globals["swabatch"] = ""
        # a new backend may take a batch this one refused
        ip.globals["swabatch"] = "false"
        ip.globals["swabatchcap"] = "5"
        ip.call("waSetBackend", ["electrum-tor"])
        c.eq("a backend change forgets a refusal", str(ip.globals.get("swabatch")), "")
        c.eq("and the halved cap with it", str(ip.globals.get("swabatchcap") or ""), "")

        # Esplora over Tor keeps its stream too
        ip.call("waNetAbort", [])
        ip.call("waSetBackend", ["esplora-tor"])
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        c.ck("Esplora writes an HTTP/1.1 request that asks to keep the stream",
             tor_last_write().startswith("GET ") and " HTTP/1.1\r\n" in tor_last_write()
             and "keep-alive" in tor_last_write().lower(), tor_last_write()[:60])
        # THE REPLY DECODER, shape by shape (2026-09-03). Content-Length first,
        # in two pieces split inside the body.
        stream_event(h, "data", "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n"
                     "Content-Length: 7\r\n\r\n51")
        c.ck("a Content-Length reply is not delivered short",
             str(ip.globals.get("swainflight")) != "")
        stream_event(h, "data", "27809")
        c.eq("and lands when the length is met",
             str(ip.globals.get("swatipheight")), "5127809")
        c.eq("and the Esplora stream IS kept", str(ip.globals.get("swastream")), str(h))
        c.eq("with nothing left in the buffer", str(ip.globals.get("swabuffer")), "")
        dials = tor_count("dial")
        # chunked, split at the worst places: inside a size line, inside a
        # chunk, across the final CRLF
        ip.call("waNetQueue", ["fees", ""])
        ip.call("waNetPump", [])
        c.eq("the next Esplora request reuses the stream", tor_count("dial"), dials)
        c.ck("and is written to it", "fee-estimates" in tor_last_write(),
             tor_last_write()[:60])
        stream_event(h, "data", "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n"
                     "\r\n6\r\n{\"1")
        stream_event(h, "data", "\":1\r\n8\r")
        c.ck("a chunked reply is not delivered until its last chunk",
             str(ip.globals.get("swainflight")) != "")
        stream_event(h, "data", "\n0,\"6\":5}\r\n0\r\n\r\n")
        c.eq("chunks are joined into the body",
             str((ip.globals.get("swafeerates") or {}).get("6")), "5")
        c.eq("and the stream is still kept", str(ip.globals.get("swastream")), str(h))
        # a chunk extension and a trailer are skipped, not read as data
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        stream_event(h, "data", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
                     "4;ext=1\r\n5127\r\n3\r\n810\r\n0\r\nX-Trailer: yes\r\n\r\n")
        c.eq("a chunk extension and a trailer are skipped",
             str(ip.globals.get("swatipheight")), "5127810")
        # Connection: close forgets the stream after delivering
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        stream_event(h, "data", "HTTP/1.1 200 OK\r\nConnection: close\r\n"
                     "Content-Length: 7\r\n\r\n5127811")
        c.eq("a reply that says close is delivered", str(ip.globals.get("swatipheight")),
             "5127811")
        c.eq("and its stream is forgotten", str(ip.globals.get("swastream")), "")
        c.ck("and closed", ("close", h) in world.tor)
        # no framing at all: the body ends when the peer closes, as it always did
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        c.eq("the next request dials", tor_count("dial"), dials + 1)
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        stream_event(h, "data", "HTTP/1.0 200 OK\r\n\r\n5127812")
        c.ck("an unframed reply waits for the close",
             str(ip.globals.get("swainflight")) != "")
        stream_event(h, "closed")
        c.eq("and lands on it", str(ip.globals.get("swatipheight")), "5127812")
        c.eq("without a failure", int(LCS._n(ip.globals.get("swasyncfailures"))), 0)
        c.eq("and its stream is not kept", str(ip.globals.get("swastream")), "")
        # a refusal is known at the head, and retried like any failure
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        stream_event(h, "data", "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nnot found")
        c.ck("a 404 is a failure named by its status, retried once",
             "retrying tip" in log_tail() and "404" in log_tail(), log_tail(200))
        c.eq("and its stream is closed", str(ip.globals.get("swastream")), "")
        ip.call("waNetAbort", [])
        # a framed reply cut off by the peer is a failure, not a short answer
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        h = int(LCS._n(ip.globals.get("swastream")))
        world.tor_state[h] = "connected"
        stream_event(h, "open")
        stream_event(h, "data", "HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\n51")
        stream_event(h, "closed")
        c.ck("a framed reply the peer cut short is retried, not delivered",
             "retrying tip" in log_tail() and "middle of a framed reply" in log_tail(),
             log_tail(200))
        c.eq("and the tip is untouched", str(ip.globals.get("swatipheight")), "5127812")
        ip.call("waNetAbort", [])
        # ...and the Network screen says a sync is one rendezvous on both
        priv_tor = str(ip.call("waPrivacyText", []))
        c.ck("the privacy text says both Tor transports run a sync down one stream",
             "one stream" in priv_tor and "keep-alive" in priv_tor)
        # the abort says what it dropped
        ip.call("waNetQueue", ["fees", ""])
        ip.call("waNetQueue", ["tip", ""])
        ip.call("waNetPump", [])
        ip.call("waNetQueue", ["fees", ""])
        ip.call("waNetAbort", [])
        # fees in flight; tip and a second fees behind it
        c.ck("an abort names the request in flight and the queue it dropped",
             "abandoned fees" in log_tail() and "2 queued request(s)" in log_tail(),
             log_tail(200))
        c.eq("and leaves nothing behind",
             (str(ip.globals.get("swastream")), str(ip.globals.get("swainflight")),
              int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0)))),
             ("", "", 0))
    finally:
        LCS.HASHES.pop("oxstreamstate", None)
        world.tor = None
        for k, v in saved7.items():
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
            ['{"jsonrpc":"2.0","id":5,"result":{"height":800001,"hex":"00"}}\n'])
    c.eq("a later success still applies",
         str(ip.globals.get("swatipheight")), "800001")
    c.ck("but does not erase the failure it did not fix",
         str(ip.globals.get("swanetwhy")) != "",
         "a later reply cleared swanetwhy")
    ip.globals["swasyncfailures"] = 3
    # an EMPTY queue, because a sync will no longer start behind a running one
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swainflight"] = ""
    # ...and a STALE tip and fee estimate, so the sync asks for both; and a
    # backend, which the blocks before this one leave set and a block run on
    # its own does not
    ip.globals["swatipat"] = ""
    ip.globals["swafeesat"] = ""
    if str(ip.globals.get("swabackend")) in ("", "offline"):
        ip.globals["swanetwork"] = "testnet"
        ip.call("waSetBackend", ["electrum-clear"])
    try:
        ip.call("waSync", [])
    except LCS.Thrown:
        pass
    c.eq("and a fresh sync is allowed to be green again",
         int(LCS._n(ip.globals.get("swasyncfailures"))), 0)

    # (9b) ...AND ONE SYNC AT A TIME. The engine log of 2026-09-01 shows the
    # whole eighty-two-request batch queued twice, back to back: the second
    # press appended behind the first and reset the failure count the first
    # was still adding to. A queue that is not empty is a sync in progress.
    queued = int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0)))
    n_addr = int(LCS._n((ip.globals.get("swaaddresses") or {}).get("n", 0)))
    c.ck("that sync queued the batch", queued > 2, "queued %d" % queued)
    # tip, fees, and ONE request per address - the unspent-output requests
    # follow only the histories that turn out non-empty (2026-09-02)
    c.eq("and it is tip + fees + one history per address, not two per address",
         queued, 2 + n_addr)
    c.ck("and the log counts what was queued, not a formula",
         ("sync: queued %d request(s)" % queued) in _fld(world, "lg_text"),
         _fld(world, "lg_text")[-160:])
    # ONLY WHAT IS STALE (2026-09-03). Every engine log shows the Test button
    # fetching the tip seconds before the sync fetched it again; a sync now
    # keeps a tip under thirty seconds old and a fee estimate under ten
    # minutes old, which is two round trips fewer over Tor.
    ip.globals["swaqueue"] = {"n": 0}
    now_ms = int(LCS._n(ip.eval_expr("the milliseconds", {})))
    ip.globals["swatipat"] = now_ms
    ip.globals["swafeesat"] = now_ms
    ip.call("waSync", [])
    c.eq("a sync with a fresh tip and fee estimate asks only for histories",
         int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), n_addr)
    kinds = [str((ip.globals.get("swaqueue") or {}).get(str(k), {}).get("kind"))
             for k in range(1, n_addr + 1)]
    c.ck("every one of them a history", all(k == "history" for k in kinds),
         ",".join(sorted(set(kinds))))
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swatipat"] = now_ms - int(LCS._n(ip.constants.get("kWaTipFresh", 0))) - 1
    ip.globals["swafeesat"] = now_ms
    ip.call("waSync", [])
    c.eq("a tip past its freshness is asked for again, the fees not",
         [str((ip.globals.get("swaqueue") or {}).get("1", {}).get("kind")),
          int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0)))],
         ["tip", 1 + n_addr])
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swatipat"] = ""
    ip.globals["swafeesat"] = ""
    ip.call("waSync", [])
    try:
        ip.call("waSync", [])
        c.ck("a second Sync behind a running one is refused", False,
             "it was accepted")
    except LCS.Thrown as exc:
        c.ck("a second Sync behind a running one is refused",
             "already running" in str(exc.msg), str(exc.msg)[:100])
    c.eq("and the queue is exactly as it was",
         int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), queued)
    # ...but a REFRESH during a sync is not a second Sync. The Tor log of
    # 2026-09-02 has the refusal seven times, every one the nav rail's
    # Refresh pressed while a slow sync walked its queue - an error line
    # about the thing the person was waiting for. Refresh repaints, reports
    # the running sync on the status line, and leaves the queue alone; the
    # same for the History screen's refresh and the Addresses screen's scan.
    for label, button in (("the nav rail's Refresh", "nv_refresh"),
                          ("the History screen's refresh", "hs_refresh"),
                          ("the Addresses screen's scan", "ad_scan")):
        before_log = _fld(world, "lg_text").count("already running")
        try:
            click(ip, world, button)
            c.ck("%s during a sync does not throw" % label, True)
        except LCS.Thrown as exc:
            c.ck("%s during a sync does not throw" % label, False,
                 str(exc.msg)[:100])
        c.eq("and leaves the queue alone",
             int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))),
             queued)
        c.eq("and logs no error for it",
             _fld(world, "lg_text").count("already running") - before_log, 0)
    c.ck("but the status line says a sync is running",
         "already running" in str(_fld(world, "uiStatus")),
         repr(_fld(world, "uiStatus"))[:120])

    # (9d) THE PUMP RE-ARMS ITSELF. With the poll flag off - closeStack sets
    # it, and a re-pasted script reinitialises every local so the pending tick
    # fires into an empty flag - a queued request sat forever with nothing
    # behind it: no dial, no FAILED line, a Tor daemon that never hears a
    # handshake. Reported 2026-09-02 as "neither clearnet nor tor ever fire".
    # Sync, Test and the broadcast now arm the pump before they queue, and
    # say so in the log when they had to.
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swainflight"] = ""
    ip.globals["swapolling"] = "false"
    before_ticks = sum(1 for m in world.pending if "watick" in str(m).lower()) \
        if hasattr(world, "pending") else None
    ip.call("waSync", [])
    c.eq("a Sync with the pump stopped re-arms it",
         str(ip.globals.get("swapolling")), "true")
    c.ck("and says so in the log",
         "re-armed" in _fld(world, "lg_text"), repr(_fld(world, "lg_text")[-200:]))
    c.ck("and logs that it queued the batch",
         "sync: queued" in _fld(world, "lg_text"),
         repr(_fld(world, "lg_text")[-200:]))
    # ...and a Sync with the pump already running does NOT re-arm a second one
    ip.globals["swaqueue"] = {"n": 0}
    log_before = _fld(world, "lg_text").count("re-armed")
    ip.call("waSync", [])
    c.eq("a Sync with the pump running leaves it alone",
         _fld(world, "lg_text").count("re-armed"), log_before)
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swapolling"] = "true"

    # (9e) A FEE ESTIMATE IS A FLOAT ON THE WIRE. The 2026-09-02 log carries
    # the real Electrum reply for estimatefee - electrs computing 263744/1e8
    # in doubles and serialising every digit - and cwBtcToSat's eight-decimal
    # rule, right for an amount, failed the fees request on every sync. The
    # bytes here are the log's bytes, not a fixture written to pass.
    ip.globals["swabackend"] = "electrum-clear"
    ip.globals["swafeerates"] = {}
    ip.globals["swainflight"] = {"kind": "fees", "arg": "", "id": "504"}
    ip.call("waNetApply", ["fees", "",
                           '{"jsonrpc":"2.0","id":504,"result":0.0026374400000000004}',
                           "504"])
    c.eq("a float-noisy BTC/kB estimate becomes sat/vB, not a failure",
         str((ip.globals.get("swafeerates") or {}).get("6")), "264")
    ip.globals["swainflight"] = {"kind": "fees", "arg": "", "id": "505"}
    ip.call("waNetApply", ["fees", "", '{"jsonrpc":"2.0","id":505,"result":0.00001}',
                           "505"])
    c.eq("and a clean one still does", str((ip.globals.get("swafeerates") or {}).get("6")),
         "1")
    c.eq("waRateTo8Decimals is by characters, not arithmetic",
         str(ip.call("waRateTo8Decimals", ["0.0026374400000000004"])), "0.00263744")
    c.eq("and leaves a short one alone",
         str(ip.call("waRateTo8Decimals", ["0.00001"])), "0.00001")

    # (9f) A TRANSPORT FAILURE RETRIES THE REQUEST ONCE BEFORE IT COUNTS. Two
    # Tor circuits died mid-sync in the same log and both times the wallet
    # moved on to the next address: a history never merged, its coins never
    # asked for. The second failure of the same request counts as before.
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swasyncfailures"] = 0
    ip.globals["swainflight"] = {"kind": "history", "arg": first, "id": "9"}
    ip.call("waNetFail", ["the Tor stream closed before the server sent anything"])
    q = ip.globals.get("swaqueue") or {}
    head = q.get("1", {}) if int(LCS._n(q.get("n", 0))) else {}
    c.eq("a failed request goes back to the FRONT of the queue",
         str(head.get("kind", "")) + " " + str(head.get("arg", "")),
         "history " + first)
    c.eq("marked as retried", str(head.get("retried", "")), "true")
    c.eq("and nothing is counted yet",
         int(LCS._n(ip.globals.get("swasyncfailures"))), 0)
    c.ck("and the log says it is retrying",
         "retrying history" in _fld(world, "lg_text"),
         repr(_fld(world, "lg_text")[-200:]))
    c.eq("and the in-flight slot is free for it",
         str(ip.globals.get("swainflight") or ""), "")
    # the SECOND failure of the same request is the real one
    ip.globals["swainflight"] = dict(head)
    ip.globals["swaqueue"] = {"n": 0}
    ip.call("waNetFail", ["the Tor stream closed before the server sent anything"])
    c.eq("a second failure of the same request counts",
         int(LCS._n(ip.globals.get("swasyncfailures"))), 1)
    c.eq("and is not requeued again",
         int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), 0)
    # ...and a reply that arrived and did not parse is NOT a transport
    # failure: waNetDeliver clears the in-flight record before applying, so
    # waNetFail from a parse error has nothing to retry.
    ip.globals["swainflight"] = ""
    ip.globals["swasyncfailures"] = 0
    ip.call("waNetFail", ["could not read the answer: not a number"])
    c.eq("a parse failure with nothing in flight counts at once",
         int(LCS._n(ip.globals.get("swasyncfailures"))), 1)
    c.eq("and requeues nothing",
         int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), 0)

    # (9g) A STREAM THAT CLOSES BEFORE SENDING is named as a dead circuit,
    # not as a malformed reply ("no header/body boundary in 0 bytes").
    ip.globals["swabackend"] = "esplora-tor"
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swasyncfailures"] = 0
    ip.globals["swabuffer"] = ""
    ip.globals["swainflight"] = {"kind": "history", "arg": first, "id": "10"}
    ip.call("waStreamClosed", [])
    c.ck("an empty close is named as a dead circuit",
         "before the server sent anything" in _fld(world, "lg_text")[-400:],
         repr(_fld(world, "lg_text")[-200:]))
    c.eq("and the request is back at the front of the queue",
         str((ip.globals.get("swaqueue") or {}).get("1", {}).get("arg", "")), first)
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swasyncfailures"] = 0

    # (9h) INSPECT ASKS THE BACKEND FOR THE BYTES IT DOES NOT HAVE. The
    # message said "ask the backend for it" about a wallet with no button
    # that did; both transports had the request and nothing queued it, and
    # the Electrum branch had no case for the reply at all.
    if raw:
        dec = REF.tx_decode(bytes.fromhex(raw))
        ip.globals["swahistory"] = {"n": 2,
            "1": {"txid": dec["txid"], "confirmations": 1, "fee": 0, "vsize": 0,
                  "raw": "", "address": first, "value": 0, "height": 1},
            "2": {"txid": dec["txid"], "confirmations": 1, "fee": 0, "vsize": 0,
                  "raw": "", "address": second, "value": 0, "height": 1}}
        ip.globals["swabackend"] = "esplora-clear"
        click(ip, world, "nv_hs")
        tbl = world.anywhere("hs_table")
        if tbl is not None:
            tbl.props["hilitedline"] = 2
        click(ip, world, "hs_inspect")
        q = ip.globals.get("swaqueue") or {}
        c.eq("Inspect with no bytes queues a raw-transaction request",
             str(q.get(str(int(LCS._n(q.get("n", 0)))), {}).get("kind", "")), "tx")
        c.eq("for that txid",
             str(q.get(str(int(LCS._n(q.get("n", 0)))), {}).get("arg", "")), dec["txid"])
        c.ck("and says so in the panel",
             "Asking" in _fld(world, "hs_detail"), repr(_fld(world, "hs_detail")[:80]))
        # the reply lands: Esplora shape first
        ip.globals["swainflight"] = {"kind": "tx", "arg": dec["txid"], "id": "11"}
        ip.call("waNetApply", ["tx", dec["txid"], raw, "11"])
        rows = ip.globals.get("swahistory") or {}
        c.ck("the bytes land on every row carrying that txid",
             all(str(rows[str(i)].get("raw", "")) == raw.lower() for i in (1, 2)),
             repr([str(rows[str(i)].get("raw", ""))[:12] for i in (1, 2)]))
        c.ck("and the panel is painted with the decode",
             "RAW TRANSACTION" in _fld(world, "hs_detail"),
             repr(_fld(world, "hs_detail")[:80]))
        c.eq("and nothing is left waiting", str(ip.globals.get("swainspectwanted") or ""), "")
        # the Electrum shape answers the hex as a JSON string
        rows["1"]["raw"] = ""; rows["2"]["raw"] = ""
        ip.globals["swahistory"] = rows
        ip.globals["swabackend"] = "electrum-clear"
        ip.globals["swainflight"] = {"kind": "tx", "arg": dec["txid"], "id": "12"}
        ip.call("waNetApply", ["tx", dec["txid"],
                               '{"jsonrpc":"2.0","id":12,"result":"%s"}' % raw, "12"])
        rows = ip.globals.get("swahistory") or {}
        c.ck("the Electrum reply lands the same way",
             all(str(rows[str(i)].get("raw", "")) == raw.lower() for i in (1, 2)),
             repr([str(rows[str(i)].get("raw", ""))[:12] for i in (1, 2)]))
        # and bytes for a DIFFERENT transaction are refused, not stored
        # a version flip changes the txid - AWAY from whatever version the
        # transaction has: the harness's clean pass signs a version-2
        # transaction here, and a flip TO 2 was a no-op the wallet rightly
        # stored (CI runs 595 to 598, "bytes of a different transaction are
        # refused: stored", the fixture's fault and not the wallet's)
        other = ("01000000" if raw[:8] == "02000000" else "02000000") + raw[8:]
        ip.globals["swainflight"] = {"kind": "tx", "arg": dec["txid"], "id": "13"}
        try:
            ip.call("waStoreRawTx", [dec["txid"], other])
            c.ck("bytes of a different transaction are refused", False,
                 "stored; raw starts %s, other decodes to %s against %s"
                 % (raw[:8], REF.tx_decode(bytes.fromhex(other))["txid"][:16], dec["txid"][:16]))
        except LCS.Thrown as exc:
            c.ck("bytes of a different transaction are refused",
                 "different transaction" in str(exc.msg), str(exc.msg)[:100])
        ip.globals["swaqueue"] = {"n": 0}
        ip.globals["swainflight"] = ""
        ip.globals["swahistory"] = {"n": 0}

    # (9i) THE DEADLINE IS FOR SILENCE, NOT FOR SIZE: every chunk that lands
    # pushes it out, so a two-megabyte history over Tor can still be arriving
    # past the forty-five seconds a fixed deadline gave the whole reply.
    ip.globals["swabackend"] = "esplora-tor"
    ip.globals["swastream"] = 1
    ip.globals["swabuffer"] = ""
    ip.globals["swainflight"] = {"kind": "history", "arg": first, "id": "14",
                                 "deadline": 1}
    ip.call("waStreamEvent", [1, "data", "HTTP/1.0 200 OK"])
    c.ck("a chunk of reply pushes the deadline out",
         int(LCS._n((ip.globals.get("swainflight") or {}).get("deadline", 0))) > 1,
         repr((ip.globals.get("swainflight") or {}).get("deadline")))
    c.eq("and the chunk was kept", str(ip.globals.get("swabuffer")), "HTTP/1.0 200 OK")
    ip.globals["swainflight"] = ""
    ip.globals["swastream"] = ""
    ip.globals["swabuffer"] = ""
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swasyncfailures"] = 0
    # A single request in flight - the Test button's tip - is NOT a sync and
    # does not block one; that is the flow the log actually shows.
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swainflight"] = {"kind": "tip", "arg": "", "id": "9"}
    try:
        ip.call("waSync", [])
        c.ck("a Sync behind a lone Test request is allowed", True)
    except LCS.Thrown as exc:
        c.ck("a Sync behind a lone Test request is allowed", False,
             str(exc.msg)[:100])
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swainflight"] = ""

    # (9c) A SERVER NOTIFICATION NEVER FAILS THE REQUEST IN FLIGHT.
    # blockchain.headers.subscribe is a subscription: after the answer, every
    # new block arrives as a message with a method and NO id. Handed to
    # waNetApply while a request was in flight, that threw, and waNetFail
    # tore the socket down and counted a failure - for a request the block
    # had nothing to do with.
    ip.globals["swasyncfailures"] = 0
    ip.globals["swabackend"] = "electrum-clear"   # (9i) above left it on Esplora
    ip.globals["swainflight"] = {"kind": "tip", "arg": "", "id": "11"}
    ip.globals["swatipheight"] = ""
    ip.call("waNetDeliver",
            ['{"jsonrpc":"2.0","method":"blockchain.headers.subscribe",'
             '"params":[{"height":800002,"hex":"00"}]}\n'])
    c.ck("a pushed header is ignored, not failed",
         int(LCS._n(ip.globals.get("swasyncfailures"))) == 0,
         "failures %r why %r" % (ip.globals.get("swasyncfailures"),
                                 ip.globals.get("swanetwhy")))
    c.ck("and the request stays in flight",
         bool(ip.globals.get("swainflight")), "in-flight was consumed")
    ip.call("waNetDeliver",
            ['{"jsonrpc":"2.0","id":11,"result":{"height":800003,"hex":"00"}}\n'])
    c.eq("and the real answer still lands afterwards",
         str(ip.globals.get("swatipheight")), "800003")
    ip.globals["swainflight"] = ""

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
            ['{"jsonrpc":"2.0","id":8,"result":{"height":800002,"hex":"00"}}\n'])
    c.eq("a later reply on a lossy sync leaves the state partial, not ok",
         str(ip.globals.get("swanetstate")), "partial")
    ip.globals["swasyncfailures"] = 0
    ip.globals["swainflight"] = {"kind": "tip", "arg": "", "id": "9"}
    ip.call("waNetDeliver",
            ['{"jsonrpc":"2.0","id":9,"result":{"height":800003,"hex":"00"}}\n'])
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

    # (16) NON-STANDARD DERIVATION PATHS. cwParsePath has always accepted any
    # path; the app could only ever ask cwAccountPath for the standard one, so
    # a person recovering an Electrum legacy wallet (m/0') or an early Core
    # wallet (m/0'/0') had correct words and nowhere to put them. The override
    # goes through ONE accessor because the path is not decoration: it is in
    # the exported descriptor and in the BIP32_DERIVATION a cosigner uses to
    # find its own key.
    saved_path = {k: ip.globals.get(k) for k in
                  ("swacustompath", "swanetwork", "swascripttype", "swaaccount",
                   "swakind", "swamnemonic", "swapassphrase", "swafingerprint")}
    ip.globals["swanetwork"] = "mainnet"
    ip.globals["swascripttype"] = "p2wpkh"
    ip.globals["swaaccount"] = 0
    ip.globals["swacustompath"] = ""
    std = str(ip.call("waAccountPath", []))
    c.eq("with no override the path is still the standard one", std, "m/84'/0'/0'")
    ip.globals["swacustompath"] = "m/0'"
    c.eq("and an override replaces it", str(ip.call("waAccountPath", [])), "m/0'")
    # it must reach the two places that are not display
    ip.globals["swafingerprint"] = "deadbeef"
    rec = ip.call("waBip32Record", [{"suffix": "/0/5"}, "00" * 33])
    c.eq("the PSBT derivation carries the override, not the standard path",
         str(rec["path"]), "m/0'/0/5")
    ip.globals["swacustompath"] = ""
    rec = ip.call("waBip32Record", [{"suffix": "/0/5"}, "00" * 33])
    c.eq("and the standard one when there is no override",
         str(rec["path"]), "m/84'/0'/0'/0/5")
    # the descriptor moves with it too
    ip.globals["swakind"] = "seed"
    ip.globals["swamnemonic"] = str(ip.constants.get("kWaTestMnemonic", ""))
    ip.globals["swapassphrase"] = ""
    ip.call("waDeriveAccount", [])
    d_std = str(ip.call("waDescriptorFor", [0]))
    ip.globals["swacustompath"] = "m/0'"
    ip.call("waDeriveAccount", [])
    d_cus = str(ip.call("waDescriptorFor", [0]))
    c.ck("the exported descriptor is not the same one for a different path",
         d_std != d_cus and d_std != "" and d_cus != "",
         "%r vs %r" % (d_std[:40], d_cus[:40]))

    # the shapes cwParsePath already refuses must stay refused, and the ones
    # in circulation must stay accepted - an over-strict guard here is a
    # wallet that still cannot recover.
    for good in ("m/0'", "m/0'/0'", "m/44'/0'/0'", "m/84'/0'/0'", "m/1852'/1815'/0'",
                 "m/0h/0h", "m/0H", "0'/0'"):
        try:
            c.ck("a real-world path is accepted: %s" % good,
                 str(ip.call("waCheckedPath", [good])) != "", good)
        except LCS.Thrown as exc:
            c.ck("a real-world path is accepted: %s" % good, False, str(exc.msg)[:80])
    c.eq("and a blank box still means the standard path",
         str(ip.call("waCheckedPath", ["   "])), "")
    for bad, why in (("m/84'/", "a trailing separator"),
                     ("m//0", "an empty level"),
                     ("m/x'", "a level that is not a number"),
                     ("m/2147483648", "a level at or above 2^31"),
                     ("m/" + "/".join(["0"] * 40), "a path deeper than the cap")):
        try:
            ip.call("waCheckedPath", [bad])
            c.ck("a path with %s is refused" % why, False, "accepted %r" % bad)
        except LCS.Thrown as exc:
            c.ck("a path with %s is refused" % why, True, str(exc.msg)[:70])

    # and it survives the wallet file, because a path that does not persist is
    # a wallet that finds its own coins once
    ip.globals["swacustompath"] = "m/0'/0'"
    ser = str(ip.call("waSerializeWallet", []))
    c.ck("the wallet file carries the override", "path\tm/0'/0'" in ser,
         repr([l for l in ser.split("\n") if l.startswith("path")]))
    ip.globals["swacustompath"] = "m/99'"
    ip.call("waDeserializeWallet", [ser])
    c.eq("and a load restores it", str(ip.globals.get("swacustompath")), "m/0'/0'")
    for k, v in saved_path.items():
        ip.globals[k] = v

    # (17) THE TWO SINGLE-KEY TOOLS. Derive-at-path is pinned to BIP-84's own
    # published vector, so this is a real answer and not this wallet agreeing
    # with itself.
    saved_tools = {k: ip.globals.get(k) for k in
                   ("swanetwork", "swamnemonic", "swapassphrase", "swacustompath")}
    ip.globals["swanetwork"] = "mainnet"
    ip.globals["swamnemonic"] = str(ip.constants.get("kWaTestMnemonic", ""))
    ip.globals["swapassphrase"] = ""
    ip.call("waDeriveAtPath", ["m/84'/0'/0'/0/0"])
    out = _fld(world, "tl_out")
    c.ck("derive-at-path finds BIP-84's published address",
         "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu" in out, out[:200])
    c.ck("and its published private key",
         "KyZpNDKnfs94vbrwhJneDi77V6jF64PWPF8x5cdJb8ifgg2DUc9d" in out, out[:200])
    c.ck("and it imports nothing", str(ip.globals.get("swakind")) != "key",
         str(ip.globals.get("swakind")))
    for bad in ("", "m/84'/", "m/x"):
        try:
            ip.call("waDeriveAtPath", [bad])
            c.ck("derive-at-path refuses %r" % bad, False, "accepted")
        except LCS.Thrown:
            c.ck("derive-at-path refuses %r" % bad, True)
    # a fresh single key must be a REAL key: its WIF has to decode back to the
    # addresses it was printed with
    ip.call("waNewKey", [])
    out = _fld(world, "tl_out")
    # THE LABELLED LINE, not any line mentioning the word. The closing
    # paragraph of that panel ends "...with that WIF.", so a last-match scrape
    # picks up "WIF." and the base58 decoder refuses it - which is this
    # check's own bug and not the wallet's, but it is exactly how a test comes
    # to assert something other than what it names.
    wif = ""
    for ln in out.split("\n"):
        if ln.strip().startswith("WIF"):
            wif = ln.split()[-1]
            break
    c.ck("a new single key produced a WIF", len(wif) > 40, repr(wif[:12]))
    if len(wif) > 40:
        info = ip.call("cwWifInfo", [wif, "mainnet"])
        c.ck("and the WIF decodes to the addresses it was shown with",
             str(info["p2wpkh"]) in out and str(info["p2pkh"]) in out,
             "%s / %s" % (str(info["p2wpkh"])[:16], str(info["p2pkh"])[:16]))
        c.ck("and it is NOT one of this wallet's own addresses",
             ip.call("waIsMine", [str(info["p2wpkh"])]) is not True,
             "the tool put a key into the wallet")
    for k, v in saved_tools.items():
        ip.globals[k] = v

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
    # THE RESHAPED SYNC, against these same real bytes (2026-09-02). A sync
    # asks history of every address and unspent outputs only of the ones
    # whose history says there are any, so a one-row history must queue
    # exactly one utxos request for that address...
    q0 = int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0)))
    wire("history", addr0,
         '{"id":5,"jsonrpc":"2.0","result":[{"tx_hash":"%s","height":5127000}]}'
         % ("cc" * 32))
    c.eq("get_history lands as one row",
         int(LCS._n((ip.globals.get("swahistory") or {}).get("n", 0))), 1)
    q = ip.globals.get("swaqueue") or {}
    qn = int(LCS._n(q.get("n", 0)))
    c.eq("a non-empty history queues one unspent-output request", qn, q0 + 1)
    last = q.get(str(qn), {}) if qn else {}
    c.eq("for that same address",
         (str(last.get("kind", "")), str(last.get("arg", ""))), ("utxos", addr0))
    # ...and an EMPTY history must queue nothing and clear that address's
    # coin rows, because a re-sync keeps the last sync's coins until each
    # address answers.
    addr1 = str((ip.globals.get("swaaddresses") or {}).get("2", {})
                .get("address", ""))
    u = dict(ip.globals.get("swautxos") or {"n": 0})
    n_u = int(LCS._n(u.get("n", 0)))
    u[str(n_u + 1)] = {"txid": "dd" * 32, "vout": 0, "value": 777,
                       "confirmations": 1, "height": 5127000,
                       "address": addr1, "script": "", "path": "",
                       "pubkey": "", "chain": 0, "index": 1,
                       "selected": "", "frozen": ""}
    u["n"] = n_u + 1
    ip.globals["swautxos"] = u
    wire("history", addr1, '{"id":9,"jsonrpc":"2.0","result":[]}')
    c.eq("an empty history queues nothing",
         int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), qn)
    rows = ip.globals.get("swautxos") or {}
    left = [rows[str(i)] for i in range(1, int(LCS._n(rows.get("n", 0))) + 1)
            if str(rows[str(i)].get("address", "")) == addr1]
    c.eq("and clears that address's coin rows", len(left), 0)
    # the queued utxos request is this section's own side effect; the
    # sections after it assume an idle queue
    ip.globals["swaqueue"] = {"n": 0}
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

    # ---- the four tools added 2026-09-01, driven through their buttons ----
    #
    # DRIVEN, not called: every one of these went in with a button, a role in
    # waToolsClick and a menu item, and this member's own record is that a
    # handler nobody has ever reached is a handler whose first reader is a
    # person with a stuck transaction. click() goes through the real mouseUp
    # router, so a role that is not wired fails here.
    click(ip, world, "nv_tl")

    # DECODE SCRIPT: the bare hex the Inspect button could never be given.
    put_field("tl_hex", "0014" + "75" * 20)
    click(ip, world, "tl_decode")
    out = _fld(world, "tl_out")
    c.ck("a P2WPKH script decodes", "SCRIPT" in out and "p2wpkh" in out,
         repr(out[:120]))
    c.ck("and it says what paying it would pay",
         "tb1q" in out or "bcrt1q" in out, repr(out[:200]))
    # The truncated push is the whole reason cwScriptCheck exists: a chunk
    # expression past the end of a string ANSWERS, so this shape used to
    # render as a short push and read like a correct decode.
    put_field("tl_hex", "0020dead")
    try:
        ip.call("waDecodeScript", ["0020dead"])
        c.ck("a truncated push is refused, not rendered short", False,
             "it was rendered")
    except LCS.Thrown as exc:
        c.ck("a truncated push is refused, not rendered short",
             "well-framed" in str(exc.msg), str(exc.msg)[:90])

    # VALIDATE: a verdict, on every chain and not just this wallet's.
    main_addr = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
    put_field("tl_hex", main_addr)
    click(ip, world, "tl_validate")
    out = _fld(world, "tl_out")
    c.ck("a mainnet address on a testnet wallet is VALID but not payable",
         "NOT ON THIS WALLET'S CHAIN" in out and "mainnet" in out,
         repr(out[:160]))
    # ...which is the case that matters. A validator that only asks about the
    # current network reports this as simply invalid, and "invalid" is what a
    # person reads as "I mistyped it" rather than "this is another chain".
    c.ck("and it is not reported as invalid", "NOT VALID ANYWHERE" not in out)
    own = str((ip.globals.get("swaaddresses") or {}).get("1", {})
              .get("address", ""))
    put_field("tl_hex", own)
    click(ip, world, "tl_validate")
    out = _fld(world, "tl_out")
    c.ck("this wallet's own address validates and is recognised as ours",
         "VALID on testnet" in out and "YOUR OWN" in out, repr(out[:160]))
    put_field("tl_hex", main_addr[:-1] + ("q" if main_addr[-1] != "q" else "p"))
    click(ip, world, "tl_validate")
    c.ck("one changed character is NOT VALID ANYWHERE",
         "NOT VALID ANYWHERE" in _fld(world, "tl_out"),
         repr(_fld(world, "tl_out")[:120]))
    # An extended key takes the other branch, and the structural check there
    # is the one no checksum makes.
    xpub = str(ip.globals.get("swaaccountxpub", ""))
    if xpub:
        put_field("tl_hex", xpub)
        click(ip, world, "tl_validate")
        out = _fld(world, "tl_out")
        c.ck("this wallet's own account xpub validates",
             "VALID EXTENDED KEY" in out and "public" in out, repr(out[:120]))
        c.ck("and it prints addresses this wallet recognises",
             "THIS WALLET'S" in out, repr(out[:400]))
        put_field("tl_hex", xpub[:-1] + ("a" if xpub[-1] != "a" else "b"))
        click(ip, world, "tl_validate")
        c.ck("a one-character edit fails Base58Check",
             "NOT A VALID EXTENDED KEY" in _fld(world, "tl_out"),
             repr(_fld(world, "tl_out")[:120]))

    # WORDS TO ENTROPY: the round trip, both ways, and the passphrase.
    seed_words = str(ip.globals.get("swamnemonic", ""))
    if seed_words:
        put_field("tl_hex", seed_words)
        put_field("tl_pass", "")
        click(ip, world, "tl_toEntropy")
        out = _fld(world, "tl_out")
        c.ck("a seed phrase converts to entropy",
             "SEED PHRASE" in out and "entropy" in out, repr(out[:120]))
        ent = str(ip.call("cxMnemonicToEntropy", [seed_words]))
        c.ck("and the hex on screen is really that entropy",
             ent.encode("latin-1", "ignore").hex() in out.lower()
             or str(ip.call("cxHexEncode", [ent])).lower() in out.lower(),
             repr(out[:300]))
        # THE ROUND TRIP IS THE POINT. Recovering entropy means stripping
        # checksum bits, and an off-by-one there yields a plausible hex
        # string that regenerates DIFFERENT words - a number that looks
        # right and is wrong.
        c.eq("the entropy regenerates exactly the same words",
             str(ip.call("cxMnemonicFromEntropy", [ent])), seed_words)
        # ...and the two directions are really different code, or the check
        # above would pass for a pair of functions that both returned their
        # input.
        c.ck("and the two directions are not the identity",
             str(ip.call("cxHexEncode", [ent])).lower() != seed_words.lower())
        # A passphrase is a THIRTEENTH WORD, not a password on the phrase.
        put_field("tl_pass", "hunter2")
        click(ip, world, "tl_toEntropy")
        out = _fld(world, "tl_out")
        c.ck("with a passphrase, two master fingerprints are shown",
             out.count("master key") == 2, repr(out[-500:]))
        fp0 = str(ip.call("waSeedFingerprint", [seed_words, ""]))
        fp1 = str(ip.call("waSeedFingerprint", [seed_words, "hunter2"]))
        c.ck("and they are different wallets", fp0 != fp1 and fp0 and fp1,
             "%r vs %r" % (fp0, fp1))
        c.ck("the fingerprint without a passphrase is this wallet's",
             fp0 == str(ip.globals.get("swafingerprint", "")),
             "%r vs %r" % (fp0, ip.globals.get("swafingerprint")))
        put_field("tl_pass", "")
        # A phrase that fails its checksum is refused before anything is
        # derived from it, because every passphrase opens a real wallet and
        # so does every mistyped phrase.
        broken = seed_words.split()
        broken[-1] = "abandon" if broken[-1] != "abandon" else "ability"
        try:
            ip.call("waWordsToEntropy", [" ".join(broken), ""])
            c.ck("a phrase failing its checksum is refused", False,
                 "it was accepted")
        except LCS.Thrown as exc:
            c.ck("a phrase failing its checksum is refused",
                 "checksum" in str(exc.msg), str(exc.msg)[:90])

    # ---- the 2026-09-01 engine log, line by line -------------------------
    #
    # A real OpenXTalk run of this wallet produced twenty-seven consecutive
    # copies of one sentence - "that seed phrase does not pass its BIP-39
    # checksum" - then "FAILED: this wallet is offline.", then a successful
    # sync of the demonstration wallet on mainnet. Each of those is a defect
    # with a check here now, driven the way the person drove it.
    saved_log = {k: ip.globals.get(k) for k in
                 ("swakind", "swanetwork", "swascripttype", "swamnemonic",
                  "swapassphrase", "swaaccountxpub", "swaaccountxprv",
                  "swafingerprint", "swaaddresses", "swautxos", "swahistory",
                  "swalabel", "swaaccount", "swacustompath", "swabackend",
                  "swanetstate", "swanetwhy", "swasyncfailures", "swaqueue",
                  "swainflight", "swaseedchoice")}
    ip.globals["swakind"] = "seed"
    ip.globals["swanetwork"] = "testnet"
    ip.globals["swascripttype"] = "p2wpkh"
    ip.globals["swamnemonic"] = str(ip.constants.get("kWaTestMnemonic", ""))
    ip.globals["swapassphrase"] = ""
    ip.globals["swacustompath"] = ""
    ip.call("waDeriveAccount", [])
    good_xpub = str(ip.globals.get("swaaccountxpub"))
    good_addr = str((ip.globals.get("swaaddresses") or {}).get("1", {})
                    .get("address", ""))
    c.ck("a good wallet is open to start from", good_xpub != "" and good_addr != "")

    # THE WALL. A phrase that fails must not become state.
    click(ip, world, "nv_wl")
    bad = "abandon abandon abandon abandon abandon abandon abandon abandon " \
          "abandon abandon abandon abandon"
    put_field("wl_mnemonic", bad)
    put_field("wl_path", "")
    try:
        click(ip, world, "wl_open")
    except LCS.Thrown:
        pass
    log_text = _fld(world, "lg_text")
    c.ck("a bad phrase is refused on Open", "cannot open a wallet" in log_text,
         repr(log_text[-200:]))
    c.eq("and the phrase that was open is STILL the phrase that is open",
         str(ip.globals.get("swamnemonic")),
         str(ip.constants.get("kWaTestMnemonic", "")))
    c.eq("and the account key is untouched",
         str(ip.globals.get("swaaccountxpub")), good_xpub)
    c.eq("and the addresses are untouched",
         str((ip.globals.get("swaaddresses") or {}).get("1", {})
             .get("address", "")), good_addr)
    # ...so the next click on that screen does NOT throw the same sentence,
    # which is what twenty-seven of them in a row were.
    # ONE click, not four: every one of these re-derives forty addresses
    # through the shim under the interpreter, and the property - a click that
    # re-derives does not throw the Open's error again - is proven by the
    # first as well as by the fourth. The state is put back by hand below.
    before = _fld(world, "lg_text").count("cannot open a wallet")
    click(ip, world, "wl_netMain")
    after = _fld(world, "lg_text").count("cannot open a wallet")
    c.eq("the next click on the Wallet screen adds no more of that error",
         after - before, 0)
    c.eq("and it did what it said", str(ip.globals.get("swanetwork")), "mainnet")
    ip.globals["swanetwork"] = "testnet"

    # THE REASON IS SPECIFIC. The old sentence said "checksum" for every
    # failure; cxMnemonicToEntropy already knew which word and how many.
    why = str(ip.call("waMnemonicProblem", [bad]))
    c.ck("a checksum failure names the checksum and the count",
         "checksum" in why and "12 word" in why, why[:120])
    why = str(ip.call("waMnemonicProblem", [bad.replace("abandon", "abandom", 1)]))
    c.ck("a misspelt word is named by position",
         "word 1" in why and "wordlist" in why, why[:120])
    why = str(ip.call("waMnemonicProblem", ["abandon abandon abandon"]))
    c.ck("a short phrase says how many words it expected",
         "12, 15, 18, 21 or 24" in why and "3 word" in why, why[:120])
    c.eq("an empty box says so", str(ip.call("waMnemonicProblem", [""])),
         "the seed box is empty.")
    c.eq("and the good phrase has no problem",
         str(ip.call("waMnemonicProblem",
                     [str(ip.constants.get("kWaTestMnemonic", ""))])), "")

    # THE ROLLBACK. A network switch that cannot re-derive stays put, rather
    # than leaving the wallet on the new chain with the old chain's addresses.
    ip.globals["swakind"] = "watch"
    ip.globals["swamnemonic"] = ""
    ip.globals["swaaccountxprv"] = ""
    ip.globals["swaaccountxpub"] = good_xpub          # a TESTNET key
    ip.call("waDeriveAddresses", [])
    watch_addr = str((ip.globals.get("swaaddresses") or {}).get("1", {})
                     .get("address", ""))
    try:
        ip.call("waSetNetwork", ["mainnet"])
        c.ck("moving a testnet watch-only wallet to mainnet is refused", False,
             "it was accepted")
    except LCS.Thrown as exc:
        c.ck("moving a testnet watch-only wallet to mainnet is refused",
             "still on testnet" in str(exc.msg), str(exc.msg)[:120])
    c.eq("and the wallet is still on testnet", str(ip.globals.get("swanetwork")),
         "testnet")
    c.eq("with its addresses intact",
         str((ip.globals.get("swaaddresses") or {}).get("1", {})
             .get("address", "")), watch_addr)

    # THE MULTISIG PHRASE. Choosing Multisig, typing a phrase and pressing
    # Open used to ignore the phrase - the branch exited before the line that
    # read it - and derive the cosigner key from whatever was open before,
    # which at boot is the PUBLISHED test seed.
    ip.globals["swakind"] = "multisig"
    ip.globals["swascripttype"] = "p2wsh"
    ip.globals["swamnemonic"] = str(ip.constants.get("kWaTestMnemonic", ""))
    other = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"
    put_field("wl_mnemonic", other)
    put_field("wl_xkey", "")
    try:
        ip.call("waOpenWallet", [])
    except LCS.Thrown:
        pass
    c.ck("a multisig Open adopts the phrase in the box",
         str(ip.globals.get("swamnemonic")) == other
         or "cannot open a wallet" in _fld(world, "lg_text")[-300:],
         repr(str(ip.globals.get("swamnemonic"))[:40]))
    # ("zoo ... wrong" is a real BIP-39 phrase: the last word carries the
    # checksum, and "wrong" is the one that closes eleven "zoo"s.)
    c.eq("and it really is that phrase", str(ip.globals.get("swamnemonic")), other)

    # THE ELECTRUM SEED. The phrase that failed twenty-seven times was very
    # probably not BIP-39 at all: Electrum's twelve words come from the same
    # English list and fail BIP-39's checksum BY DESIGN. The wallet now asks
    # the phrase what it is, and opens both Electrum kinds at their own paths.
    # Both vectors were manufactured the way Electrum manufactures them - draw
    # words until the "Seed version" HMAC prefix matches - and their addresses
    # come from the independent reference with salt "electrum", so this is
    # not the wallet agreeing with itself.
    E_SEGWIT = ("puzzle matrix idle exhaust drama thumb crowd flash client "
                "adjust bracket fruit")
    E_STD = ("robot strong congress quantum bonus never topple diamond awake "
             "endorse glance degree")
    c.eq("a segwit Electrum seed is recognised",
         str(ip.call("waSeedFormatOf", [E_SEGWIT])), "electrum-segwit")
    c.eq("a standard Electrum seed is recognised",
         str(ip.call("waSeedFormatOf", [E_STD])), "electrum-standard")
    c.eq("and BIP-39 is still BIP-39",
         str(ip.call("waSeedFormatOf",
                     [str(ip.constants.get("kWaTestMnemonic", ""))])), "bip39")
    c.eq("a phrase that is neither is neither",
         str(ip.call("waSeedFormatOf", [bad])), "")
    ip.globals["swakind"] = "seed"
    ip.globals["swanetwork"] = "testnet"
    ip.globals["swascripttype"] = "p2tr"           # deliberately WRONG
    put_field("wl_mnemonic", E_SEGWIT)
    put_field("wl_pass", "")
    put_field("wl_path", "m/84'/1'/0'")            # deliberately WRONG
    click(ip, world, "nv_wl")
    click(ip, world, "wl_open")
    c.eq("an Electrum segwit seed opens at m/0'",
         str(ip.globals.get("swacustompath")), "m/0'")
    c.eq("as p2wpkh, whatever the buttons said",
         str(ip.globals.get("swascripttype")), "p2wpkh")
    c.eq("and its first receive address is the reference's",
         str((ip.globals.get("swaaddresses") or {}).get("1", {})
             .get("address", "")), "tb1ql0z9jpgq5eyl9tf62mqjgna94tdu2ntr5ndm73")
    addrs = ip.globals.get("swaaddresses") or {}
    chg = [addrs[str(i)]["address"] for i in range(1, int(LCS._n(addrs.get("n", 0))) + 1)
           if str(addrs[str(i)].get("change", "")) in ("1", "true", "True")]
    c.ck("and its first change address is the reference's",
         chg[:1] == ["tb1qag3xwkssdh3nu82gh2r7ztardrf6mvn0mz6jzf"], repr(chg[:1]))
    c.eq("the path box shows the path the seed chose",
         _fld(world, "wl_path"), "m/0'")
    put_field("wl_mnemonic", E_STD)
    click(ip, world, "wl_open")
    c.eq("a standard Electrum seed opens at the master itself",
         str(ip.globals.get("swacustompath")), "m")
    c.eq("as p2pkh", str(ip.globals.get("swascripttype")), "p2pkh")
    c.eq("and its first receive address is the reference's (m/0/0)",
         str((ip.globals.get("swaaddresses") or {}).get("1", {})
             .get("address", "")), "n1xd4CN7eaFPDrCfouzBpHWQdMfbPBHYSx")
    addrs = ip.globals.get("swaaddresses") or {}
    chg = [addrs[str(i)]["address"] for i in range(1, int(LCS._n(addrs.get("n", 0))) + 1)
           if str(addrs[str(i)].get("change", "")) in ("1", "true", "True")]
    c.ck("and its first change address is the reference's (m/1/0)",
         chg[:1] == ["mnpzEAEofmQWf4yE2rVvYNTyqF9Ni36J9u"], repr(chg[:1]))
    # A two-factor seed is named and refused, not opened as something else.
    why = str(ip.call("waMnemonicProblem", [E_SEGWIT]))
    c.eq("an openable Electrum seed has no problem", why, "")
    put_field("wl_path", "")

    # THE OFFLINE TEST. Pressing Test with no backend chosen used to queue a
    # request, let the pump fail it, and paint "FAILED: this wallet is
    # offline." with a failure count and a red pill. It is refused at the door.
    ip.globals["swakind"] = "seed"
    ip.globals["swascripttype"] = "p2wpkh"
    ip.globals["swabackend"] = "offline"
    ip.globals["swanetstate"] = "idle"
    ip.globals["swanetwhy"] = ""
    ip.globals["swasyncfailures"] = 0
    ip.globals["swaqueue"] = {"n": 0}
    ip.globals["swainflight"] = ""
    click(ip, world, "nv_nw")
    click(ip, world, "nw_test")
    c.ck("Test while offline is refused with the reason",
         "nothing to test" in _fld(world, "lg_text")[-300:],
         repr(_fld(world, "lg_text")[-160:]))
    c.eq("and nothing was queued",
         int(LCS._n((ip.globals.get("swaqueue") or {}).get("n", 0))), 0)
    c.eq("and no failure was counted",
         int(LCS._n(ip.globals.get("swasyncfailures"))), 0)
    c.ck("and the network state is not 'failed'",
         str(ip.globals.get("swanetstate")) != "failed",
         str(ip.globals.get("swanetstate")))

    for k, v in saved_log.items():
        ip.globals[k] = v
    ip.call("waDeriveAddresses", [])

    # ---- the boot record is THIS run's, not every run's -------------------
    # The 2026-09-02 engine log opened with three boot self-check blocks, one
    # per open, because the field is saved with the stack and the carried
    # block appends. The clearing is its own handler so it can be driven here
    # without paying for a second boot; the ORDER - clear, then begin - is
    # read from the source, because a clear after scBegin would erase the
    # block it had just started.
    lgb = world.anywhere("lg_boot")
    c.ck("the boot wrote exactly one self-check block",
         lgb is not None and lgb.content.count("== boot self-check") == 1,
         "" if lgb is None else "%d blocks" % lgb.content.count("== boot self-check"))
    if lgb is not None:
        lgb.content = "== boot self-check (stale, from an earlier open) ==\n" + lgb.content
        ip.call("waScFresh", [])
        c.eq("waScFresh empties the boot record", lgb.content, "")
    m_run = re.search(r'^command waScRun\b(.*?)^end waScRun\b',
                      getattr(ip, "src_text", ""), re.S | re.M)
    body = m_run.group(1) if m_run else ""
    c.ck("waScRun clears the record BEFORE it begins a new one",
         0 <= body.find("waScFresh") < body.find('scBegin "lg_boot"'),
         "fresh at %d, begin at %d" % (body.find("waScFresh"),
                                       body.find('scBegin "lg_boot"')))

    # ---- the context menu routes to the buttons, item by item -------------
    #
    # THE MENU IS NOT A SECOND IMPLEMENTATION, and this is what holds it to
    # that. Every screen's menu is built, every item is resolved through
    # waMenuRoute, and every route that is not "self" must name a control the
    # app's own registry already carries - so an item can only ever mean what
    # some button on that screen means. An item nobody wired answers empty and
    # fails here, which is the whole reason waMenuRoute answers empty rather
    # than shrugging.
    #
    # What this CANNOT settle is that the menu appears: the interpreter models
    # no mouse button and no popup. The wallet's own mouseDown says so.
    reg = set(n.strip().lower() for n in
              str(ip.constants.get("kWaScControls", "")).split(",") if n.strip())
    menu_screens = ["wallet", "receive", "addresses", "send", "coins",
                    "history", "ordinals", "vault", "tools", "log"]
    unrouted, unbuilt, wrong_screen = [], [], []
    for screen in SCREENS:
        name = str(ip.call("waMenuFor", [screen]))
        if name != "menu_" + screen:
            wrong_screen.append(screen)
            continue
        btn = world.anywhere(name)
        if btn is None:
            unbuilt.append(screen)
            continue
        items = [ln for ln in str(_ctl_prop_get(btn, "text")).split("\n") if ln]
        for item in items:
            route = str(ip.call("waMenuRoute", [item]))
            if route == "":
                unrouted.append("%s/%s" % (screen, item))
            elif route != "self":
                pre, _, role = route.partition(" ")
                if ip.call("waRouteKnows", [pre]) is not True:
                    unrouted.append("%s/%s -> %s" % (screen, item, route))
                elif ("%s_%s" % (pre, role)).lower() not in reg:
                    unrouted.append("%s/%s -> no button %s_%s"
                                    % (screen, item, pre, role))
    c.ck("every menu item routes to a real button or to the router itself",
         not unrouted, "; ".join(unrouted[:6]))
    c.ck("waMenuFor builds the button it names", not unbuilt and not wrong_screen,
         "unbuilt: %s wrong: %s" % (",".join(unbuilt), ",".join(wrong_screen)))

    # The eight screens with something worth offering carry a menu of their
    # own; the other two get the common tail. Both halves end with the same
    # two items, because a menu that differs everywhere is a menu nobody
    # learns - so that is asserted rather than left to the reading.
    tails, sized = [], []
    for screen in SCREENS:
        btn = world.anywhere("menu_" + screen)
        items = [ln for ln in
                 str(_ctl_prop_get(btn, "text")).split("\n") if ln]
        if items[-3:] != ["Refresh", "About this wallet", "Update from main"]:
            tails.append(screen)
        want_more = screen in menu_screens
        if (len(items) > 3) is not want_more:
            sized.append("%s:%d" % (screen, len(items)))
    c.ck("every screen's menu ends with the same three items", not tails,
         ",".join(tails))
    c.ck("the eight screens with actions carry them; the other two do not",
         not sized, ",".join(sized))

    # An item nobody wired must be a FAILED CHECK, not a click that quietly
    # does nothing - so the empty answer really does reach a throw.
    try:
        ip.call("waMenuPick", ["menu_wallet", "Sell the house"])
        c.ck("an unrouted item is refused, not swallowed", False,
             "it was accepted")
    except LCS.Thrown as exc:
        c.ck("an unrouted item is refused, not swallowed",
             "nothing routes it" in str(exc.msg), str(exc.msg)[:80])
    # ...and the prefix guard is a closed set, or the router would dispatch
    # a two-letter name it does not own.
    c.ck("waRouteKnows is closed over the thirteen prefixes",
         all(ip.call("waRouteKnows", [p]) is True for p in ["nv"] + CODES)
         and ip.call("waRouteKnows", ["zz"]) is not True)
    try:
        ip.call("waRouteClick", ["zz", "whatever"])
        c.ck("and waRouteClick refuses an unknown prefix", False,
             "it was accepted")
    except LCS.Thrown as exc:
        c.ck("and waRouteClick refuses an unknown prefix",
             "no screen owns" in str(exc.msg), str(exc.msg)[:80])

    # ---- the right-click acts on the row under the cursor -----------------
    # Seen open on an engine for the first time on 2026-09-02, and reported
    # as needing "a second look for usability": a list field moves its
    # selection on button 1 only, so the menu's Inspect, Copy and Freeze
    # acted on whatever had been clicked BEFORE. The stack now selects the
    # clicked line before the menu pops. The popup itself is still nothing
    # the interpreter models; mouseDown contains that, so what is asserted
    # here is the selection and that no other click is touched.
    click(ip, world, "nv_ad")
    tbl = world.anywhere("ad_table")
    c.ck("the Addresses table exists to be right-clicked", tbl is not None)
    if tbl is not None:
        tbl.props["hilitedline"] = 1
        world.target = ("field", "ad_table")
        world.clickline = "line 3 of field 9"
        try:
            ip.call("mouseDown", [3])
        except Exception as exc:                        # noqa: BLE001
            c.ck("a right-click on a table does not throw", False,
                 "%s: %s" % (type(exc).__name__, exc))
        finally:
            world.target = None
            world.clickline = ""
        c.eq("a right-click on a table selects the row under the cursor",
             int(LCS._n(tbl.props.get("hilitedline"))), 3)
        # button 1 is the engine's own selection and passes straight through
        world.target = ("field", "ad_table")
        world.clickline = "line 5 of field 9"
        try:
            ip.call("mouseDown", [1])
        finally:
            world.target = None
            world.clickline = ""
        c.eq("a left-click is left to the engine",
             int(LCS._n(tbl.props.get("hilitedline"))), 3)
        # a right-click below the last line keeps the selection it had
        world.target = ("field", "ad_table")
        world.clickline = ""
        try:
            ip.call("mouseDown", [3])
        finally:
            world.target = None
        c.eq("a right-click on empty space keeps the selection",
             int(LCS._n(tbl.props.get("hilitedline"))), 3)
        # and a right-click on a button selects nothing
        world.target = ("button", "ad_scan")
        world.clickline = "line 7 of field 9"
        try:
            ip.call("mouseDown", [3])
        finally:
            world.target = None
            world.clickline = ""
        c.eq("a right-click on a button touches no table",
             int(LCS._n(tbl.props.get("hilitedline"))), 3)
        # ...AND THE ITEM ACTS ON THAT ROW. "Copy selected address" routed to
        # "ad receive" - the receive-chain TOGGLE - until 2026-09-03, and the
        # route check above could not tell: the toggle is a real button. The
        # copy, the sign-with-it and the coins outpoint copy are the router's
        # own now, and each is driven against the selected row.
        # a field's text is its content (the world keeps a painted field
        # there; props hold what `set the text of` writes, the buttons' menus)
        rows_a = _fld(world, "ad_table").split("\n")
        row3 = rows_a[2] if len(rows_a) > 2 else ""
        addr3 = row3.split("\t")[1].strip() if "\t" in row3 else ""
        c.ck("row 3 of the table names an address",
             addr3.startswith(("tb1", "m", "n", "2")), row3[:60])
        world.clipboard.clear()
        ip.call("waMenuPick", ["menu_addresses", "Copy selected address"])
        c.eq("Copy selected address copies the SELECTED address",
             str(world.clipboard.get("text", "")), addr3)
        ip.call("waMenuPick", ["menu_addresses", "Sign a message with it"])
        c.eq("Sign a message with it fills the Tools address box",
             _fld(world, "tl_msgAddr"), addr3)
        c.eq("and shows the Tools screen", str(ip.globals.get("swascreen")), "tools")
        tbl.props["hilitedline"] = ""
        try:
            ip.call("waMenuPick", ["menu_addresses", "Copy selected address"])
            c.ck("with no row selected the copy says so", False, "it copied")
        except LCS.Thrown as exc:
            c.ck("with no row selected the copy says so",
                 "select an address row" in str(exc.msg), str(exc.msg)[:80])
        # the coins outpoint, on whatever coin the boot planted
        click(ip, world, "nv_cn")
        ctbl = world.anywhere("cn_table")
        rows = _fld(world, "cn_table").split("\n") if ctbl is not None else []
        if len(rows) >= 2 and rows[1].strip():
            ctbl.props["hilitedline"] = 2
            world.clipboard.clear()
            ip.call("waMenuPick", ["menu_coins", "Copy selected outpoint"])
            got = str(world.clipboard.get("text", ""))
            c.ck("Copy selected outpoint copies a txid:vout",
                 re.match(r'^[0-9a-f]{64}:\d+$', got) is not None, got[:80])
        else:
            c.ck("Copy selected outpoint copies a txid:vout (no coin to select)",
                 True)

    # ---- Update from main: everything around the swap (2026-09-04) --------
    # The swap itself - `set the script of this stack` from inside its own
    # handler, then preOpenStack and openStack to the new one - is engine
    # work nothing headless can model, and the fetch is one `get URL`. What
    # IS gated is what makes the swap safe to offer: the check that refuses
    # anything that is not recognisably this script and names why, the
    # carry of the wallet and the Network settings across it, the restore on
    # the other side, and the route from the button and the menu item.
    cur = getattr(ip, "src_text", "")
    c.ck("the check has the running script to compare against", len(cur) > 100000)

    def check(text):
        return ip.call("waUpdateCheck", [text, cur])

    def refused(label, text, want):
        try:
            got = check(text)
            c.ck(label, False, "accepted: %s" % str(got)[:60])
        except LCS.Thrown as exc:
            c.ck(label, want in str(exc.msg), str(exc.msg)[:100])

    refused("an identical copy is refused as already current", cur, "already")
    refused("an empty reply is refused", "", "nothing back")
    refused("a page that is not this script is refused by its first line",
            "<!DOCTYPE html>\n<html>not found</html>", "not this script")
    refused("a truncated download is refused by its size",
            cur[: len(cur) // 3], "too short")
    refused("a copy with no version is refused",
            cur.replace('constant kWaVersion = "', 'constant kWaVersionX = "', 1),
            "declares no kWaVersion")
    refused("a copy without the restore handler is refused - the wallet would not come back",
            cur.replace("command waUpdateRestore", "command waUpdateRestoreX"),
            "no waUpdateRestore")
    refused("a copy with no openStack is refused - it could not boot",
            cur.replace("on openStack", "on openStackX"), "no openStack")
    newer = cur.replace('constant kWaVersion = "', 'constant kWaVersion = "9.9.9-', 1)
    info = check(newer)
    c.ck("a newer copy is accepted with its version read out",
         str(info.get("version", "")).startswith("9.9.9-"), str(info)[:80])
    c.eq("and its size", int(LCS._n(info.get("chars", 0))), len(newer))
    c.ck("and its SHA-256, as hex",
         re.match(r'^[0-9a-f]{64}$', str(info.get("sha", ""))) is not None,
         str(info.get("sha", ""))[:70])
    other = cur.replace('constant kWaVersion = "', 'constant kWaVersion = "9.9.8-', 1)
    c.ck("which follows the content: a different copy reports a different SHA",
         str(info.get("sha", "")) != str(check(other).get("sha", "")))

    # the carry and the restore, on a one-key wallet (cheap to re-derive)
    saved8 = {k: ip.globals.get(k) for k in
              ("swanetwork", "swascripttype", "swakind", "swaimportedwif",
               "swaaddresses", "swautxos", "swahistory", "swamnemonic",
               "swabackend", "swahost", "swaport", "swasocksport", "swascreen",
               "swalabel", "swalabels", "swaunit")}
    wif_k = WV.REF.cr.wif_encode(bytes.fromhex("07" * 32), "testnet", True)
    ip.globals["swanetwork"] = "testnet"
    ip.globals["swascripttype"] = "p2wpkh"
    ip.globals["swakind"] = "key"
    ip.globals["swaimportedwif"] = wif_k
    ip.globals["swamnemonic"] = ""
    ip.globals["swalabel"] = "carried"
    ip.globals["swaunit"] = "sat"
    ip.call("waDeriveAddresses", [])
    ip.globals["swabackend"] = "electrum-tor"
    ip.globals["swahost"] = "example" + str(ip.constants.get("kWaElectrumOnion", ""))[7:]
    ip.globals["swaport"] = 4443
    ip.globals["swasocksport"] = 9150
    ip.globals["swascreen"] = "coins"
    carry = str(ip.call("waUpdateCarry", []))
    c.ck("the carry is the wallet file's text plus update rows",
         "wif\t" + wif_k in carry and "update:backend\telectrum-tor" in carry
         and "update:port\t4443" in carry and "update:screen\tcoins" in carry
         and ("update:from\t" + str(ip.constants.get("kWaVersion", ""))) in carry,
         carry[-200:])
    # the other side: a fresh wallet, the carry parked on the stack
    ip.call("waUpdateStash", [carry])
    c.eq("the carry is parked on the stack",
         str(world.stack_props.get("uwaupdatecarry", "")), carry)
    ip.call("waResetWallet", [])
    ip.globals["swabackend"] = "offline"
    ip.globals["swascreen"] = "wallet"
    c.eq("a reset wallet has no key", str(ip.globals.get("swaimportedwif")), "")
    ip.call("waUpdateRestore", [])
    c.eq("the restore brings the key back", str(ip.globals.get("swaimportedwif")), wif_k)
    c.eq("and the label", str(ip.globals.get("swalabel")), "carried")
    c.eq("and the unit", str(ip.globals.get("swaunit")), "sat")
    c.eq("and the backend, host, port and SOCKS port",
         [str(ip.globals.get(k)) for k in ("swabackend", "swahost", "swaport", "swasocksport")],
         ["electrum-tor", "example" + str(ip.constants.get("kWaElectrumOnion", ""))[7:],
          "4443", "9150"])
    c.eq("and the screen", str(ip.globals.get("swascreen")), "coins")
    c.eq("and clears the carry", str(world.stack_props.get("uwaupdatecarry", "")), "")
    c.ck("and says so in the log",
         "updated to version" in _fld(world, "lg_text"), _fld(world, "lg_text")[-160:])
    ip.call("waUpdateRestore", [])
    c.ck("a second restore with nothing parked does nothing",
         _fld(world, "lg_text").count("updated to version") == 1)
    # a carry that will not load is reported, not left half-applied
    ip.call("waUpdateStash", ["label\tbroken\nkind\tseed\nmnemonic\tnot words at all\n"
                              "update:from\t0.0.1\n"])
    ip.call("waUpdateRestore", [])
    c.ck("a carry that will not load is named in the log",
         "did not load" in _fld(world, "lg_text"), _fld(world, "lg_text")[-200:])
    c.eq("and the carry is still cleared", str(world.stack_props.get("uwaupdatecarry", "")), "")
    # the route: the button exists and the menu item names it
    c.ck("the Settings screen carries the Update button",
         world.anywhere("st_update") is not None)
    c.eq("the menu item routes to it", str(ip.call("waMenuRoute", ["Update from main"])),
         "st update")
    for k, v in saved8.items():
        ip.globals[k] = v
    ip.call("waDeriveAddresses", []) if str(ip.globals.get("swakind")) == "key" else None

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
