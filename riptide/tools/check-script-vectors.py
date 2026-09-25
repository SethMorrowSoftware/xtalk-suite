#!/usr/bin/env python3
"""check-script-vectors.py - run the SHIPPED src/riptide.livecodescript
against the oracle's vectors, headlessly, through nostrxt's lcs-interp.py.

WHY THIS EXISTS. Until this file, riptide's whole vector spine was
ORACLE-ONLY: tools/riptide_reference.py proves the EXPECTED answers are
right, tests/riptide_golden_test.py pins them in Python, and
tools/check-selftest-vectors.py proves the harness constants match - but
NOTHING proved the SCRIPT derives them. The only thing that had ever read
src/riptide.livecodescript was check-livecodescript.py, which validates
balance, quoting and the token traps and cannot tell whether a handler
computes the right bytes. That is precisely the gap the member's own
CLAUDE.md names as its most expensive class of bug, and the gap CoinXT and
NostrXT each closed with their own copy of this gate.

It paid for itself on its first run, twice over, and NEITHER defect was in
the shipped script - which is worth saying plainly, because a new tool's
first findings are the ones most likely to be the tool's own (nostrxt
learned that the expensive way and wrote it down: suspect the probe first,
with evidence).

  - The INTERPRETER mis-modelled a negative chunk range, clamping instead of
    counting from the end, so `char -3 to -1 of "abcdef"` came back "abcde".
    Latent rather than active: neither coinxt's nor nostrxt's source uses the
    form, so no existing gate had ever read a wrong answer from it. It
    surfaced here on `byte 10 to -1 of pFileBytes`, the idiom rsOpenMasterSeed
    has used since phase 1. Fixed at the source in both copies, with both
    dependent members' gates re-run to prove nothing moved.
  - The ORACLE crashed on a tampered signature: _verify_ed25519 decompressed
    the signature's R point without the not-a-point guard its public-key path
    already had, so a corrupted signature raised TypeError instead of
    answering False. Every earlier negative test had tampered with the
    MESSAGE, never the signature, so nothing had ever reached that line.

One thing in the shipped script did change as a result, and it was a
readability call rather than a bug: the media-tag reader now takes its
40-hex tail by positive indices, because the length is pinned one line above
and an explicit span is easier to check than a negative one.

WHAT IT IS NOT. An approximation of the engine, not the engine. Nothing
here promotes a handler out of "verified statically; needs an OXT pass" -
what it settles is LOGIC, not parser behaviour. If this file and the engine
disagree, the engine is right. The interpreter's own header carries the
modelled-subset contract and its named divergences. One more is named here:
its numeric comparisons are pure IEEE, and on 2026-09-24 an engine answered
one differently (a 2^53 + 1 seq accepted through a quotient bound this gate
refused), so tier 1c replays the u64 bound under the engine's own comparison
rule (named by that day's third run and the engine source; suite engine note
2.10) and two ruled-out candidates kept as margin, and statically refuses any
comparison against a quotient in the library.

THE SOURCE REWRITES, AND WHY THEY ARE ASSERTED. riptide was written before
this gate existed and uses three spellings outside the interpreter's
modelled subset. The line between what got FIXED in the interpreter and what
gets REWRITTEN here is deliberate: lcs-interp.py is shared byte-identical
with CoinXT's copy and drift-gated, so every change there rides on two other
members' gates. A wrong ANSWER earns that risk (the negative-range bug
above, fixed at the source). Three missing SPELLINGS do not - they are
syntax the interpreter has simply never been taught, riptide is the only
member that writes them, and teaching them means new parser paths under two
members that would gain nothing.

So this file rewrites those three forms into equivalent ones the interpreter
already models, and the rewrites are NAMED and COUNTED. Every one must match
at least once or the gate FAILS: a rewrite that silently stops applying
would leave the gate quietly testing a file nobody ships, which is this
tree's own recurring failure shape (a gate that looks like it checks
something and does not). The rewrites are behaviour-preserving by
inspection; each is listed in REWRITES below with what it stands in for.

THE NAMED STAND-INS, all of them declared rather than hidden:
  - sxSignKeypairFromSeed is a COMMAND WITH OUT-PARAMETERS, which the
    interpreter does not model at all. rsIdentityKeys - and only that one
    handler - is replaced by the shim in SHIM below, whose ed25519 comes
    from the oracle. rsIdentityKeys is phase-1 code that passed on a real
    engine in 2026-08-12, so it is not what this gate is for.
  - sxSignDetached / sxSignVerifyDetached are the oracle's RFC 8032
    ed25519, which is anchored to the cross-project BEP44 conformance
    vector and sodiumxt's own C KAT at oracle import.
  - sxKdfDerive is hashlib.blake2b, the model the oracle already proves
    against sodiumxt's C KAT. A faithful model, not a stub.
  - sxSecretBox / sxSecretBoxOpen are a MODEL, and the only real stand-in
    here: authenticated (HMAC over nonce and ciphertext, verified before
    anything is returned) and nonce-prefixed, so it has the shape the app
    code depends on, but it is NOT XSalsa20-Poly1305. What it therefore
    exercises is rsSealAppState/rsOpenAppState's own framing, caps, header
    and UTF-8 round trip - which is the code this member owns. The
    cryptography underneath is libsodium's and is proved by sodiumxt.
  - sxRandomBytes is a deterministic counter, for the reason NostrXT's gate
    gives: a gate that draws real entropy cannot reproduce its own failures.

The CoinXT crypto is REAL. cxSha256, cxSchnorrSign, cxSchnorrVerify,
cxXOnlyPubkey and cxSeckeyIsValid are bound by ctypes to the committed
library a packaged extension binds:
    <coinxt>/src/code/x86_64-linux/coinxt.so
so the phase-8 signatures under test are genuine BIP-340 over genuine
libsecp256k1, and the vectors they are compared against come from an
independent implementation (nostrxt/tools/nostr_reference.py, which anchors
itself to the published BIP-340/NIP-19/BIP-173 sets at import).

THE SIBLINGS, AND HOW THEY ARE FOUND. This gate reaches into two other
members: nostrxt, for the interpreter (tools/lcs-interp.py) and the nx*
layer the shipped script composes (src/nostrxt.livecodescript), both needed
before anything runs; and coinxt, for the binary above. sibling() below
resolves each the same way: the directory beside this member in the suite
tree, the repository cloned beside it under its member name in a standalone
checkout, or wherever XTALK_SIBLING_NOSTRXT / XTALK_SIBLING_COINXT /
XTALK_SIBLINGS point (docs/MEMBER-REPO-SPLIT.md). An absent nostrxt stops
the gate at import with the clone to run; an absent coinxt is the tier-2
skip below.

TWO TIERS, so the gate is useful without the sibling binary:
  1. PURE, always: everything with no CoinXT call in it.
  2. COMPOSED, when coinxt.so is present: the whole phase-8 rail.
A missing library SKIPS tier 2 loudly, naming the repository to clone; it
never passes silently. With XTALK_REQUIRE_SIBLINGS=1 the skip is a FAILURE
instead - for the lane that means to settle tier 2, where a skip and a pass
exit 0 alike (the CROSSMEMBER_REQUIRE_ALL shape).

Usage:
  python3 tools/check-script-vectors.py            # per-check detail
  python3 tools/check-script-vectors.py --check    # terse (the gate set)
"""
import ctypes
import hashlib
import hmac
import importlib.util
import os
import re
import sys

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


# The repository behind each sibling this gate reaches for, by member
# directory name, so an absent one is reported with the clone to run.
SIBLING_REPOS = {
    "coinxt": "https://github.com/SethMorrowSoftware/CoinXT",
    "nostrxt": ("https://github.com/SethMorrowSoftware/NostrXT (published "
                "from its nostrxt/ directory in "
                "https://github.com/SethMorrowSoftware/xtalk-suite)"),
}


def sibling_missing(name, path):
    """One paragraph for an absent sibling file: the path looked for, the
    member that owns it, the repository to clone and the two overrides."""
    return ("%s is not present: it belongs to the %s member, which is not "
            "beside this checkout. Clone %s beside this checkout as ../%s, "
            "or point XTALK_SIBLING_%s / XTALK_SIBLINGS at it."
            % (path, name, SIBLING_REPOS[name], name,
               name.upper().replace("-", "_")))


SCRIPT = os.path.join(MEMBER, "src", "riptide.livecodescript")
NOSTR_SCRIPT = os.path.join(sibling("nostrxt"), "src",
                            "nostrxt.livecodescript")
INTERP = os.path.join(sibling("nostrxt"), "tools", "lcs-interp.py")
COIN_SO = os.path.join(sibling("coinxt"), "src", "code", "x86_64-linux",
                       "coinxt.so")

# Both nostrxt files are needed before anything runs - the interpreter to
# load at all, the nx* layer to build the source - so their absence is
# settled here, as one paragraph and no traceback, rather than by whichever
# open() happened to reach them first. Exit 2: a setup problem, not a
# vector failure, and the same code the sibling gates use for it.
for _path in (INTERP, NOSTR_SCRIPT):
    if not os.path.isfile(_path):
        print("check-script-vectors: " + sibling_missing("nostrxt", _path),
              file=sys.stderr)
        sys.exit(2)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


LCS = _load("lcs_interp", INTERP)

REF = {}
with open(os.path.join(HERE, "riptide_reference.py"), "r",
          encoding="utf-8") as _f:
    exec(compile(_f.read(), os.path.join(HERE, "riptide_reference.py"),
                 "exec"), REF)


# --------------------------------------------------------------------------
# The source rewrites. (name, why, apply) - each must fire at least once.
# --------------------------------------------------------------------------

def _rw_count_in(line):
    return re.sub(r'\bthe number of (bytes|chars|characters|lines|items|keys)'
                  r' in\b', r'the number of \1 of', line)


def _rw_one_line_if(line):
    """`if COND then STMT` on one line -> the block form.

    riptide uses this 90 times; the interpreter models only the block form.
    Equivalent by construction, and riptide never writes a one-line
    `if ... then ... else ...` (asserted below), so there is no else branch
    to lose."""
    m = re.match(r'^(\s*)if (.+?) then (.+)$', line)
    if not m or m.group(3).strip().startswith("--"):
        return line
    ind, cond, stmt = m.groups()
    return "%sif %s then\n%s   %s\n%send if" % (ind, cond, ind, stmt, ind)


def _rw_binary_encode(line):
    """binaryEncode / div / mod -> named stand-ins.

    The interpreter models neither the binaryEncode builtin nor the `div`
    and `mod` operators. These three lines are the ONLY places riptide uses
    either, and each is a pure big-endian integer packer - the stand-ins
    below do exactly what binaryEncode's "n"/"N"/"NN" formats do."""
    line = line.replace(
        'binaryEncode("NN", pNum div 4294967296, pNum mod 4294967296)',
        'rstBEu64(pNum)')
    line = re.sub(r'binaryEncode\("N", (.+?)\)$', r'rstBEu32(\1)', line)
    line = re.sub(r'binaryEncode\("n", (.+?)\)$', r'rstBEu16(\1)', line)
    return line


REWRITES = [
    ("the number of X in Y -> of Y",
     "the interpreter models only the `of` spelling of a chunk count",
     _rw_count_in),
    ("one-line `if ... then STMT` -> block form",
     "the interpreter models only the block form of `if`",
     _rw_one_line_if),
    ("binaryEncode / div / mod -> named packers",
     "the interpreter models neither the builtin nor the two operators",
     _rw_binary_encode),
]

# rsIdentityKeys, and only it, is replaced: its sxSignKeypairFromSeed is a
# command with OUT-PARAMETERS, which the interpreter cannot express. Phase-1
# code, engine-passed 2026-08-12, and not what this gate exists to check.
SHIM = """
function rsIdentityKeys pSeed
   local tOut
   if the number of bytes of pSeed is not 32 then
      return empty
   end if
   put rstEdPub(pSeed) into tOut["publicKey"]
   put pSeed into tOut["secretKey"]
   put rstEdPubHex(pSeed) into tOut["handle"]
   return tOut
end rsIdentityKeys
"""


def strip_script_header(text):
    return re.sub(r'^script\s+"[^"]*"[^\n]*\n', '', text, count=1)


def build_source(fail):
    with open(SCRIPT, "r", encoding="utf-8") as fh:
        rip = fh.read()
    if re.search(r'^\s*if .+ then .+ else ', rip, re.M):
        fail("a one-line `if ... then ... else ...` appeared in the shipped "
             "file; the one-line rewrite would silently drop its else branch")
    hits = dict((name, 0) for name, _why, _fn in REWRITES)
    out = []
    for line in strip_script_header(rip).split("\n"):
        for name, _why, fn in REWRITES:
            new = fn(line)
            if new != line:
                hits[name] += 1
                line = new
        out.append(line)
    for name, why, _fn in REWRITES:
        if hits[name] == 0:
            fail("the rewrite %r matched NOTHING. It stands in for: %s. A "
                 "rewrite that stops applying leaves this gate testing a "
                 "file nobody ships - fix the rewrite or remove it." %
                 (name, why))
    with open(NOSTR_SCRIPT, "r", encoding="utf-8") as fh:
        core = strip_script_header(fh.read())
    return core + "\n" + "\n".join(out) + "\n" + SHIM, hits


# --------------------------------------------------------------------------
# natives
# --------------------------------------------------------------------------

def to_bytes(s):
    return str(s).encode("latin-1")


def to_str(b):
    return b.decode("latin-1")


def install_pure_natives():
    """Everything that needs no CoinXT."""
    LCS.HASHES.update({
        "tolower": lambda a: str(LCS._disp(a[0])).lower(),
        "toupper": lambda a: str(LCS._disp(a[0])).upper(),
        "rstbeu64": lambda a: to_str(int(LCS._n(a[0])).to_bytes(8, "big")),
        "rstbeu32": lambda a: to_str(int(LCS._n(a[0])).to_bytes(4, "big")),
        "rstbeu16": lambda a: to_str(int(LCS._n(a[0])).to_bytes(2, "big")),
        "sxhex2bin": lambda a: to_str(bytes.fromhex(str(LCS._disp(a[0])))),
        "sxbin2hex": lambda a: to_bytes(a[0]).hex(),
        "sxmemequal": lambda a: to_bytes(a[0]) == to_bytes(a[1]),
        "rstedpub": lambda a: to_str(REF["ed25519_publickey"](to_bytes(a[0]))),
        "rstedpubhex": lambda a: REF["ed25519_publickey"](
            to_bytes(a[0])).hex(),
        "sxsigndetached": lambda a: to_str(
            REF["ed25519_sign"](to_bytes(a[0]), to_bytes(a[1]))),
        "sxsignverifydetached": lambda a: REF["_verify_ed25519"](
            to_bytes(a[0]), to_bytes(a[1]), to_bytes(a[2])),
        "sxkdfderive": lambda a: to_str(REF["kdf_derive"](
            to_bytes(a[0]), int(str(LCS._disp(a[1]))), int(LCS._n(a[3])),
            context=to_bytes(a[2]))),
    })

    counter = [0]

    def sxrandombytes(args):
        n = int(LCS._n(args[0]))
        counter[0] += 1
        seed = hashlib.sha256(b"rs-gate-%d" % counter[0]).digest()
        return to_str((seed * (n // 32 + 1))[:n])

    def secretbox(args):
        """MODEL, not XSalsa20-Poly1305 (see the header). Nonce-prefixed and
        authenticated, so the framing and every refusal path around it is
        exercised honestly; the real cipher is sodiumxt's to prove."""
        msg, key = to_bytes(args[0]), to_bytes(args[1])
        nonce = hashlib.sha256(b"rs-nonce" + key + msg).digest()[:24]
        stream = b""
        while len(stream) < len(msg):
            stream += hashlib.sha256(key + nonce + bytes([len(stream) // 32])
                                     ).digest()
        ct = bytes(a ^ b for a, b in zip(msg, stream[:len(msg)]))
        mac = hmac.new(key, nonce + ct, hashlib.sha256).digest()[:16]
        return to_str(nonce + ct + mac)

    def secretboxopen(args):
        blob, key = to_bytes(args[0]), to_bytes(args[1])
        if len(blob) < 40:
            raise LCS.Thrown("SodiumXT: sxSecretBoxOpen: too short")
        nonce, ct, mac = blob[:24], blob[24:-16], blob[-16:]
        want = hmac.new(key, nonce + ct, hashlib.sha256).digest()[:16]
        if not hmac.compare_digest(mac, want):
            raise LCS.Thrown("SodiumXT: sxSecretBoxOpen: bad tag")
        stream = b""
        while len(stream) < len(ct):
            stream += hashlib.sha256(key + nonce + bytes([len(stream) // 32])
                                     ).digest()
        return to_str(bytes(a ^ b for a, b in zip(ct, stream[:len(ct)])))

    LCS.HASHES.update({"sxrandombytes": sxrandombytes,
                       "sxsecretbox": secretbox,
                       "sxsecretboxopen": secretboxopen})


def install_coin_natives():
    """The REAL committed CoinXT, via ctypes. Returns False when absent."""
    if not os.path.exists(COIN_SO):
        return False
    lib = ctypes.CDLL(COIN_SO)
    sigs = [
        ("cnx_sha256", [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]),
        ("cnx_seckey_verify", [ctypes.c_char_p, ctypes.c_size_t]),
        ("cnx_xonly_pubkey_from_seckey",
         [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p,
          ctypes.c_size_t]),
        ("cnx_schnorr_sign",
         [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t,
          ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]),
        ("cnx_schnorr_verify",
         [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t,
          ctypes.c_char_p, ctypes.c_size_t]),
    ]
    for name, argtypes in sigs:
        fn = getattr(lib, name)
        fn.restype = ctypes.c_int
        fn.argtypes = argtypes

    def cxsha256(a):
        d = to_bytes(a[0])
        out = ctypes.create_string_buffer(32)
        if lib.cnx_sha256(d, len(d), out) != 0:
            raise LCS.Thrown("CoinXT: cxSha256 failed")
        return to_str(out.raw[:32])

    def cxseckeyisvalid(a):
        sk = to_bytes(a[0])
        rc = lib.cnx_seckey_verify(sk, len(sk))
        if rc == 0:
            return True
        if rc in (-1, -2, -4):
            return False
        raise LCS.Thrown("CoinXT: cxSeckeyIsValid refused the call")

    def cxxonlypubkey(a):
        sk = to_bytes(a[0])
        out = ctypes.create_string_buffer(32)
        if lib.cnx_xonly_pubkey_from_seckey(sk, len(sk), out, 32) != 0:
            raise LCS.Thrown("CoinXT: cxXOnlyPubkey failed")
        return to_str(out.raw[:32])

    def cxschnorrsign(a):
        sk, msg = to_bytes(a[0]), to_bytes(a[1])
        aux = to_bytes(a[2]) if len(a) > 2 else b""
        out = ctypes.create_string_buffer(64)
        if lib.cnx_schnorr_sign(sk, len(sk), msg, len(msg), aux, len(aux),
                                out, 64) != 0:
            raise LCS.Thrown("CoinXT: cxSchnorrSign failed")
        return to_str(out.raw[:64])

    def cxschnorrverify(a):
        pk, msg, sig = to_bytes(a[0]), to_bytes(a[1]), to_bytes(a[2])
        rc = lib.cnx_schnorr_verify(pk, len(pk), msg, len(msg), sig, len(sig))
        if rc == 0:
            return True
        if rc == -5:
            return False
        raise LCS.Thrown("CoinXT: cxSchnorrVerify refused the call")

    LCS.HASHES.update({
        "cxsha256": cxsha256, "cxseckeyisvalid": cxseckeyisvalid,
        "cxxonlypubkey": cxxonlypubkey, "cxschnorrsign": cxschnorrsign,
        "cxschnorrverify": cxschnorrverify,
    })
    return True


# --------------------------------------------------------------------------

class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.n = 0
        self.failed = 0
        self.skipped = 0

    def note(self, text):
        if not self.terse:
            print("-- %s" % text)

    def ck(self, label, got, want):
        self.n += 1
        if got == want:
            if not self.terse:
                print("  ok   %s" % label)
        else:
            self.failed += 1
            print("  FAIL %s\n       got  %r\n       want %r"
                  % (label, got, want))

    def skip(self, label, why):
        self.skipped += 1
        print("  SKIP %s (%s)" % (label, why))


MASTER = to_str(bytes([0x42] * 32))
AUX = "00" * 32


def check_u64_bound(c, ip):
    """The 2^53 refusal, and the ceilings that DEPEND on it, driven end to end.

    This section exists because of a regression, not a theory. rsReadBEu64 was
    given a 2^53 bound on 2026-09-08 and ten of its THIRTEEN call sites were
    guarded. One of the three misses was rsBtxoParseHeader, and the miss did
    not merely leave a gap - it INVERTED an existing guard. Before the bound an
    absurd declared total arrived as a rounded enormous number and
    rsBtxoStreamStep's `> kRsBtxoMaxTotal` ceiling refused it; after the bound
    it arrived EMPTY, and `empty > 8589934592` is false under both the engine's
    string fallback and this interpreter's numeric coercion. A peer declaring
    8 GiB was refused and the same peer declaring 18 exabytes was admitted.

    So the checks below are deliberately written as a MONOTONIC table rather
    than as isolated refusals: a bound that only ever refuses is
    indistinguishable from a parser that is simply broken, and the defect this
    guards against was precisely non-monotonic.

    The table itself is u64_rows(), shared with tier 1c, which replays it
    under the engine's comparison rule and two more candidates: two passes
    over one table can never drift into testing different rows.
    """
    c.note("tier 1b: the 2^53 u64 bound and the ceilings that depend on it")
    for label, got, want in u64_rows(ip):
        c.ck(label, got, want)


def u64_head_with_seq(seq8):
    """An RSH1 head whose only variable is its eight seq bytes."""
    b  = b"RSH1" + seq8 + bytes([1]) + b"n"
    b += b"ab" * 20 + b"cd" * 20 + bytes([0]) + b"ef" * 20
    return to_str(b)


def u64_btxo_header(total):
    """A BTXO header declaring TOTAL bytes (eight big-endian bytes)."""
    name = b"x.bin"
    b  = b"BTXO" + bytes([1]) + bytes([0])
    b += bytes([(len(name) >> 8) & 255, len(name) & 255]) + name
    b += bytes([(total >> (8 * i)) & 255 for i in range(7, -1, -1)])
    return to_str(b)


U64_BTXO_CEIL = 8589934592          # kRsBtxoMaxTotal

U64_SEQ_ROWS = [
    (b"\x00" * 8, "seq 0", True),
    (b"\x00\x1f\xff\xff\xff\xff\xff\xff", "seq 2^53-1", True),
    (b"\x00\x20\x00\x00\x00\x00\x00\x00", "seq 2^53 (representable)", True),
    (b"\x00\x20\x00\x00\x00\x00\x00\x01", "seq 2^53+1", False),
    (b"\xff" * 8, "seq 2^64-1", False)]

U64_TOTAL_ROWS = [
    (1024, "1 KiB", "header"),
    (U64_BTXO_CEIL, "exactly the 8 GiB ceiling", "header"),
    (U64_BTXO_CEIL + 1, "8 GiB + 1", "refused"),
    (2 ** 53, "2^53", "refused"),
    (2 ** 53 + 1, "2^53+1 (the regression case)", "refused"),
    (2 ** 64 - 1, "2^64-1 (the big lie)", "refused")]


# What a row reads when the bound let a u64 PAST 2^53 through. The
# interpreter refuses to compute such an integer (LCS.Imprecise, which no
# script `try` can swallow) where an engine would carry on with a rounded
# number, so that refusal of the ARITHMETIC is the evidence that the BOUND
# did not fire - and a row must report it as a named failure, never die on
# it as a traceback.
PAST_2P53 = ("NOT REFUSED: the bound let a value past 2^53 reach the "
             "arithmetic after it (an engine would carry on, rounded)")


def u64_call(ip, name, args):
    try:
        return ip.call(name, args)
    except LCS.Imprecise:
        return PAST_2P53


def u64_parsed(out):
    """True when rsParseHead's answer is a parsed head, not a refusal."""
    return bool(out) and out != ""


def u64_status(out):
    """rsBtxoStreamStep's status, or whatever came back instead."""
    return out.get("status") if isinstance(out, dict) else str(out)


def u64_rows(ip):
    """Every row of the monotonic table as (label, got, want)."""
    rows = []
    for seq8, label, should_parse in U64_SEQ_ROWS:
        out = u64_call(ip, "rsParseHead", [u64_head_with_seq(seq8)])
        rows.append(("rsParseHead: %s %s"
                     % (label, "parses" if should_parse else "refused"),
                     out if out is PAST_2P53 else u64_parsed(out),
                     should_parse))
    out = u64_call(ip, "rsParseHead",
                   [u64_head_with_seq(b"\x00\x20\x00\x00\x00\x00\x00\x00")])
    rows.append(("rsParseHead: 2^53 comes back exact, not a rounded neighbour",
                 str(LCS._n(out["seq"])) if isinstance(out, dict)
                 else repr(out), "9007199254740992"))
    for total, label, want in U64_TOTAL_ROWS:
        out = u64_call(ip, "rsBtxoStreamStep",
                       [u64_btxo_header(total), "header"])
        rows.append(("rsBtxoStreamStep: declared total %s -> %s"
                     % (label, want), u64_status(out), want))
    return rows


# --------------------------------------------------------------------------
# tier 1c: the u64 bound under ENGINE COMPARISON MODELS (2026-09-24)
# --------------------------------------------------------------------------
#
# WHY. On 2026-09-24 an OXT engine (Win32, the suite paste's riptide fold)
# ACCEPTED a head seq of 2^53 + 1 that every gate here refused. The bound
# was `if tHi > (9007199254740992 - tLo) / 4294967296`; at hi = 2^21, lo = 1
# the right side is 2097151.99999999977, and pure IEEE - which is what the
# interpreter computes in, being Python floats - puts that below 2097152, so
# tier 1b refused the record and stayed green. The two sides differ by about
# 2.3e-10, a relative 1.1e-16, and the engine did not answer that the IEEE
# way. The accept is OBSERVED. The harness then printed two probe lines, and
# the day's third run named the rule (riptide/CLAUDE.md's ledger; suite
# engine note 2.10): a RELATIVE tolerance between 8 and 16 DBL_EPSILON,
# the same at 1 and at 8. The engine source says exactly which: two unequal
# numbers are EQUAL when they differ by less than MC_EPSILON = 10
# DBL_EPSILON of the SMALLER magnitude, or by less than MC_EPSILON outright
# when that magnitude is below it (engine/src/exec-logic.cpp, sysdefs.h;
# DOCUMENTED). That rule reproduces all eight probe readings, and the
# fixture below re-proves it on every run.
#
# WHAT. Tier 1b's table again, once per model below. Each model changes only
# the ANSWER of a numeric comparison, at the interpreter's two comparison
# sites; the arithmetic under it stays exact. The first model is the
# engine's rule. The other two were ruled out by the probes as the EXACT
# rule and stay as margin: a bound decided on exact small integers (the fix:
# the u32 halves against 2^21) answers the same under all three, which says
# the fix does not lean on the one constant.
#
# FIXTURE FIRST (the fixture-before-gate law). The pre-2026-09-24 handler is
# kept below, verbatim bar its comment, as the seeded defect. Before any
# model is trusted to pass the shipped bound, it must reproduce BOTH halves
# of the finding on the old one: IEEE refuses 2^53 + 1 (why the gates were
# green), and the model accepts it (what the engine did). A model that cannot
# see the defect that shipped cannot vouch for its fix. Each model must also
# have reached a comparison site at all: the hook keys on the interpreter's
# function names, so a rename there would silently turn every model back
# into IEEE - and the fixture's "accepts" leg would then fail loudly. And
# the engine's rule must read the probes' eight recorded answers through the
# interpreter, while each margin model misreads at least one of them (the
# reason it is margin and not the rule).

DBL_EPSILON = 2.220446049250313e-16
MC_EPSILON = DBL_EPSILON * 10.0


def _model_engine(a, b):
    """The engine's own rule (engine/src/exec-logic.cpp, MCLogicCompareTo
    and MCLogicIsEqualTo): unequal numbers are equal when they differ by less
    than MC_EPSILON of the smaller magnitude, or by less than MC_EPSILON when
    that magnitude is below MC_EPSILON."""
    if a == b:
        return a, b
    smaller = min(abs(a), abs(b))
    if smaller < MC_EPSILON:
        same = abs(a - b) < MC_EPSILON
    else:
        same = abs(a - b) / smaller < MC_EPSILON
    return (a, a) if same else (a, b)


def _model_absolute(a, b):
    """Equal when within 1e-6: an absolute tolerance."""
    return (a, a) if abs(a - b) < 1e-6 else (a, b)


def _model_digits15(a, b):
    """Both operands rounded through 15 significant digits first."""
    return float("%.15g" % a), float("%.15g" % b)


ENGINE_MODELS = [
    ("the engine's rule (10 DBL_EPSILON of the smaller)", _model_engine),
    ("an absolute 1e-6 tolerance", _model_absolute),
    ("a 15-significant-digit round trip", _model_digits15),
]

# The engine's recorded answers to the harness's first two probe lines
# (numeric compare probe 1 read in the 2026-09-24 second run, probe 2 in the
# third; riptide/CLAUDE.md's ledger), each expression as the harness spells
# it. The ladder is the harness's rstUlpLadder under a fixture name. Pure
# IEEE reads true,true,true,true,true,true,1,1.
PROBE_LADDER = "\n".join([
    "function probeUlpLadder pBase, pUlps",
    "   local tStep",
    "   put 1 into tStep",
    "   repeat while tStep <= 1073741824",
    "      if pBase + tStep / pUlps > pBase then",
    "         return tStep",
    "      end if",
    "      multiply tStep by 2",
    "   end repeat",
    "   return 0",
    "end probeUlpLadder"])
PROBE_READINGS = [
    ("1 + 1 / 10000000 > 1", "true"),
    ("1 + 1 / 2251799813685248 > 1", "false"),
    ("2097152 > (9007199254740992 - 1) / 4294967296", "false"),
    ("1 + 23 / 4503599627370496 > 1 + 22 / 4503599627370496", "false"),
    ("1 / 10000000000 > 0", "true"),
    ("1073741824 + 1 / 2097152 > 1073741824", "false"),
    ("probeUlpLadder(1, 4503599627370496)", "16"),
    ("probeUlpLadder(8, 562949953421312)", "16"),
]


def _probe_answers(interp):
    """The interpreter's answers to PROBE_READINGS, spelled as the engine
    printed them."""
    return [str(LCS._disp(interp.eval_expr(expr, {})))
            for expr, _want in PROBE_READINGS]


class _ModelNum(object):
    """One operand of one comparison, answering the six comparisons by an
    engine model. The hook hands these out only at a comparison site, where
    the value is compared and then dropped, so no arithmetic ever sees one."""
    __slots__ = ("v", "model")

    def __init__(self, v, model):
        self.v = v
        self.model = model

    def _pair(self, other):
        return self.model(self.v,
                          other.v if isinstance(other, _ModelNum) else other)

    def __eq__(self, other):
        a, b = self._pair(other)
        return a == b

    def __ne__(self, other):
        a, b = self._pair(other)
        return a != b

    def __lt__(self, other):
        a, b = self._pair(other)
        return a < b

    def __le__(self, other):
        a, b = self._pair(other)
        return a <= b

    def __gt__(self, other):
        a, b = self._pair(other)
        return a > b

    def __ge__(self, other):
        a, b = self._pair(other)
        return a >= b

    __hash__ = None


class engine_model(object):
    """While active, every numeric comparison the interpreter makes answers
    by MODEL. The interpreter coerces both operands of `< <= > >= <>` (in
    _Expr.p_cmp) and of a numeric `is` / `=` (in _eq) through its module
    function _n, so wrapping _n's result for those two callers - and only
    them - moves every comparison and nothing else. `fired` counts the
    wrapped operands, so a caller can prove the hook reached a site."""
    SITES = ("p_cmp", "_eq")

    def __init__(self, model):
        self.model = model
        self.fired = 0
        self.real = None

    def __enter__(self):
        real = self.real = LCS._n

        def hooked(v):
            out = real(v)
            if (sys._getframe(1).f_code.co_name in self.SITES
                    and isinstance(out, (int, float))
                    and not isinstance(out, bool)):
                self.fired += 1
                return _ModelNum(out, self.model)
            return out

        LCS._n = hooked
        return self

    def __exit__(self, *_exc):
        LCS._n = self.real
        return False


# The handler as it shipped from 2026-09-08 until 2026-09-24, comment cut -
# the seeded defect of tier 1c and of the quotient scan. Kept VERBATIM: the
# point of a seeded defect is that it is the one that actually shipped.
OLD_READ_BEU64 = "\n".join([
    "private function rsReadBEu64 pBytes",
    "   local tHi, tLo",
    "   put rsReadBEu32(byte 1 to 4 of pBytes) into tHi",
    "   put rsReadBEu32(byte 5 to 8 of pBytes) into tLo",
    "   if tHi > (9007199254740992 - tLo) / 4294967296 then",
    "      return empty",
    "   end if",
    "   return tHi * 4294967296 + tLo",
    "end rsReadBEu64"])
OLD_BOUND_LINE = "if tHi > (9007199254740992 - tLo) / 4294967296 then"

_READ_BEU64_RX = re.compile(
    r'^private function rsReadBEu64 pBytes$.*?^end rsReadBEu64$',
    re.M | re.S)


def seed_old_bound(text, fail):
    """TEXT with its one rsReadBEu64 replaced by the pre-2026-09-24 one."""
    found = len(_READ_BEU64_RX.findall(text))
    if found != 1:
        fail("tier 1c's fixture expects exactly ONE rsReadBEu64 handler to "
             "seed the old bound into, and found %d; without it the models "
             "would be trusted untested" % found)
    return _READ_BEU64_RX.sub(lambda _m: OLD_READ_BEU64, text)


def _refuses_2p53p1(interp):
    """[head refused?, BTXO total refused?] for a u64 of 2^53 + 1. A parsed
    head and PAST_2P53 alike mean: not refused."""
    head = u64_call(interp, "rsParseHead",
                    [u64_head_with_seq(b"\x00\x20" + b"\x00" * 5 + b"\x01")])
    total = u64_call(interp, "rsBtxoStreamStep",
                     [u64_btxo_header(2 ** 53 + 1), "header"])
    return [not u64_parsed(head), u64_status(total) == "refused"]


def check_u64_engine_models(c, ip, src, fail):
    c.note("tier 1c: the u64 bound under the engine's comparison rule and "
           "two margin models")
    probe = LCS.Interp(PROBE_LADDER)
    want = [w for _expr, w in PROBE_READINGS]
    c.ck("fixture: under IEEE the probes read true,true,true,true,true,true,"
         "1,1 - the answers the engine did NOT give",
         _probe_answers(probe),
         ["true", "true", "true", "true", "true", "true", "1", "1"])
    for index, (name, model) in enumerate(ENGINE_MODELS):
        with engine_model(model):
            got = _probe_answers(probe)
        if index == 0:
            c.ck("fixture: %s reads the eight answers the engine gave "
                 "(probes 1 and 2, 2026-09-24)" % name, got, want)
        else:
            c.ck("fixture: %s misreads at least one of them (margin, not "
                 "the rule)" % name, got != want, True)
    old = LCS.Interp(seed_old_bound(src, fail))
    c.ck("fixture: under IEEE the pre-2026-09-24 bound REFUSES 2^53+1 "
         "(head, BTXO total) - why every headless gate was green over it",
         _refuses_2p53p1(old), [True, True])
    for name, model in ENGINE_MODELS:
        with engine_model(model) as hook:
            got = _refuses_2p53p1(old)
        c.ck("fixture: under %s it ACCEPTS 2^53+1 (head, BTXO total), as "
             "the engine did on 2026-09-24" % name, got, [False, False])
        c.ck("fixture: %s reached the interpreter's comparison sites" % name,
             hook.fired > 0, True)
    for name, model in ENGINE_MODELS:
        with engine_model(model) as hook:
            rows = u64_rows(ip)
        for label, got, want in rows:
            c.ck("[%s] %s" % (name, label), got, want)
        c.ck("[%s] the model reached the comparison sites" % name,
             hook.fired > 0, True)


# The quotient scan: the static half of the same rule, over the whole
# library rather than tier 1c's table. A logical line (comments cut: --, #,
# // and /* */; string literals blanked; `\` continuations joined) that both
# DIVIDES and COMPARES is refused; a one-line `if COND then STMT` is judged
# as its two halves, so a condition that divides is refused and a statement
# that merely divides is not. Its bound is its question: a quotient put into
# a variable first and compared on a later line passes it, which is why tier
# 1c exists too. It reads the LIBRARY only; the harness's numeric probe
# compares against quotients on purpose, and the demo's own code was swept
# by hand on 2026-09-24 and has no `/` in it (its three `div`s centre two
# fields and format a log line; none is compared). The fixtures pin the comment
# and literal handling first, because comments-versus-literals has changed
# a scanner's answer in this tree three times (root CLAUDE.md).
_COMPARES_RX = re.compile(r'[<>=]|\bis\b', re.I)
_ONE_LINE_IF_RX = re.compile(r'^\s*(?:else\s+)?if\s+(.+?)\s+then\s+(\S.*)$',
                             re.I)

# (source, the line numbers the scan must report)
QUOTIENT_SCAN_FIXTURES = [
    ("-- if a / b > c, in a comment", []),
    ('put "http://x/y > z" into t', []),
    ("# a / b > c after a hash", []),
    ("put a / b into c // x > y after a slash comment", []),
    ("/* a / b > c\nstill a / b > c */ put 1 into x", []),
    ("if tDT <= 0 then put 1 / 60 into tDT", []),
    ("return trunc(pA / pB)", []),
    ("if tX > \\\n      tA / tB then", [1]),
    ("if tHi > (9007199254740992 - tLo) / 4294967296 then", [1]),
    ("if (a / b) is 2 then return empty", [1]),
    ("if x then put (a / b <> c) into t", [1]),
]


def _logical_code_lines(text):
    """(first line number, code) per logical line of a .livecodescript."""
    in_block = False
    pending, start = "", None
    for number, raw in enumerate(text.split("\n"), start=1):
        out, i, in_str = [], 0, False
        while i < len(raw):
            ch = raw[i]
            if in_block:
                if raw.startswith("*/", i):
                    in_block = False
                    i += 2
                else:
                    i += 1
                continue
            if in_str:
                out.append('"' if ch == '"' else " ")
                in_str = ch != '"'
                i += 1
                continue
            if ch == '"':
                in_str = True
                out.append(ch)
            elif raw.startswith("/*", i):
                in_block = True
                i += 2
                continue
            elif raw.startswith("--", i) or raw.startswith("//", i) \
                    or ch == "#":
                break
            else:
                out.append(ch)
            i += 1
        code = "".join(out)
        if start is None:
            start = number
        if code.rstrip().endswith("\\"):
            pending += code.rstrip()[:-1] + " "
            continue
        yield start, pending + code
        pending, start = "", None


def _divides_and_compares(code):
    return "/" in code and _COMPARES_RX.search(code) is not None


def quotient_comparisons(text):
    """[(line, code)] for every logical line that compares a quotient."""
    out = []
    for number, code in _logical_code_lines(text):
        m = _ONE_LINE_IF_RX.match(code)
        if m:
            hit = "/" in m.group(1) or _divides_and_compares(m.group(2))
        else:
            hit = _divides_and_compares(code)
        if hit:
            out.append((number, " ".join(code.split())))
    return out


def check_no_quotient_comparisons(c, fail):
    c.note("tier 1c: no comparison against a quotient in the library")
    for source, want in QUOTIENT_SCAN_FIXTURES:
        c.ck("fixture: the quotient scan reports %r at %r"
             % (source.split("\n")[0][:40], want),
             [n for n, _code in quotient_comparisons(source)], want)
    with open(SCRIPT, "r", encoding="utf-8") as fh:
        shipped = fh.read()
    seeded = [code for _line, code in
              quotient_comparisons(seed_old_bound(shipped, fail))]
    c.ck("fixture: the scan flags the pre-2026-09-24 bound when it is "
         "seeded back", OLD_BOUND_LINE in seeded, True)
    c.ck("the shipped library compares against no quotient",
         quotient_comparisons(shipped), [])


def check_capacity_arithmetic(c, ip):
    """The numbers that MOVE when kRsMaxRecord moves, pinned headlessly.

    kRsMaxRecord went 1000 -> 996 on 2026-09-08 (BEP44's cap is on the BENCODED
    value, so a 1000-byte raw record is 1005 on the wire and every node refuses
    it). Six assertions in riptide's harness were derived from the old number
    and went stale with it - and NOTHING could see them, because that harness
    only runs on an engine. They shipped wrong for a day.

    So they are pinned here as well, where they run on every push. The chunk
    boundary case is the one worth keeping honest: a 999-byte pad plus a
    two-byte character used to straddle a 1000-byte boundary and no longer
    does, so that test would have kept PASSING its count assertion while
    silently no longer testing a split character. 995 puts the boundary back
    inside the character.
    """
    c.note("the capacity arithmetic that rides on kRsMaxRecord")
    c.ck("rsPostTextCapacity(0)", str(LCS._n(ip.call("rsPostTextCapacity", [0]))), "876")
    c.ck("rsPostTextCapacity(8)", str(LCS._n(ip.call("rsPostTextCapacity", [8]))), "556")
    parts = ip.call("rsChunkPostText", ["0123456789" * 250])
    c.ck("2500 bytes splits 996/996/508",
         [len(parts[k]) for k in sorted(parts, key=lambda x: int(x))], [996, 996, 508])
    c.ck("15936 bytes is exactly 16 chunks",
         len(ip.call("rsChunkPostText", ["x" * 15936])), 16)
    c.ck("15937 bytes is refused, never truncated",
         ip.call("rsChunkPostText", ["x" * 15937]) in ("", {}), True)
    split = ip.call("rsChunkPostText", ["a" * 995 + "\u00e9"])
    c.ck("a 2-byte char still STRADDLES the chunk boundary",
         [len(split[k]) for k in sorted(split, key=lambda x: int(x))], [996, 1])


def check_pure(c, ip, V):
    c.note("tier 1: the pure paths (no CoinXT needed)")
    c.ck("the subkey registry has not shifted under the new rows",
         [ip.constants.get("kRsSubkeyIdentity"),
          ip.constants.get("kRsSubkeyDm"),
          ip.constants.get("kRsSubkeyLan"),
          ip.constants.get("kRsSubkeyNostr"),
          ip.constants.get("kRsSubkeyAppState")],
         ["1", "2", "3", "4", "5"])
    # PREFIX-FREE, not merely distinct - and this check used to be the weaker
    # one, which is why the bug it now catches shipped. These tags are
    # RAW-CONCATENATED in front of the signed body, so if tag A is a prefix of
    # tag B the two preimage grammars overlap and a signature minted for one
    # rail verifies on the other. `len({...}) == 3` cannot see that: the old
    # admission tag "riptide-lan" and the sync tag "riptide-lan-s" are unequal
    # (so it passed) and yet one is a prefix of the other (so an attacker-chosen
    # challenge nonce beginning "-s" made the two preimages byte-identical).
    # Inequality is the wrong property for a concatenated domain separator.
    _domains = [ip.constants.get(n) for n in
                ("kRsNostrDomain", "kRsLanDomain", "kRsLanSyncDomain")]
    _domains.append("riptide-lan-w")      # the welcome tag, a literal in-source
    _bad = sorted("%s is a prefix of %s" % (a, b)
                  for a in _domains for b in _domains
                  if a is not None and b is not None and a != b and b.startswith(a))
    c.ck("every raw-concat signature domain is PREFIX-FREE of the others",
         _bad, [])
    c.ck("and there are still four distinct ones", len(set(_domains)), 4)
    c.ck("the RSN1 body and record lengths agree with the layout",
         [ip.constants.get("kRsNostrBridgeBody"),
          ip.constants.get("kRsNostrBridgeLen")], [148, 276])

    c.note("post building, and the delimiter discipline around it")
    # rsBuildPost is phase-2 code, but it was SPLIT in 2026-08-29 so its
    # inner body could set the itemDelimiter behind a save/restore. These
    # two checks are what make that refactor safe to have done: the bytes
    # must be unchanged, and the delimiter must survive - including across
    # the SEVEN refusal exits, which is where a per-exit restore would have
    # been forgotten.
    id_seed = to_str(REF["identity_seed"](bytes([0x42] * 32)))
    post1 = ip.call("rsBuildPost",
                    [1754870400, REF["ZERO_TARGET"], "hello, riptide", "",
                     id_seed])
    c.ck("rsBuildPost still matches the golden post byte for byte",
         to_bytes(post1).hex(), V["post1"])
    post2 = ip.call("rsBuildPost",
                    [1754870460, V["post1Target"], "second post", "ee" * 20,
                     id_seed])
    c.ck("...and with a media list too", to_bytes(post2).hex(), V["post2"])

    def delim_survives(label, thunk):
        was = LCS.set_item_delimiter("|")
        try:
            thunk()
            c.ck(label, LCS.ITEM_DELIMITER[0], "|")
        finally:
            LCS.set_item_delimiter(was)

    delim_survives("rsBuildPost leaves the itemDelimiter as it found it",
                   lambda: ip.call("rsBuildPost",
                                   [1754870400, REF["ZERO_TARGET"], "x", "",
                                    id_seed]))
    delim_survives("...even when it REFUSES (the exit a per-exit restore "
                   "forgets)",
                   lambda: ip.call("rsBuildPost",
                                   [1754870400, REF["ZERO_TARGET"], "x",
                                    "00" * 20, id_seed]))
    delim_survives("rsAssembleChunkText leaves it alone on refusal too",
                   lambda: ip.call("rsAssembleChunkText", ["", {}]))
    # rsPersonaAllows had the SAME leak and was fixed in the same pass, but
    # it cannot be driven here: it uses `is not among the items of`, which
    # the interpreter does not model. Its delimiter discipline and its full
    # truth table are asserted in the folded suite harness instead, which is
    # where the guard belongs anyway. Named rather than silently omitted.
    c.skip("rsPersonaAllows' delimiter discipline",
           "`is among the items of` is outside the interpreter's subset; "
           "the folded harness asserts the guard on the engine")

    c.note("the app-state store: framing, caps and refusals")
    sealed = ip.call("rsSealAppState", ["hello state", MASTER])
    c.ck("a sealed store carries the RIPTAPP1 header",
         sealed[:9], "RIPTAPP1S")
    c.ck("it round trips", ip.call("rsOpenAppState", [sealed, MASTER]),
         "hello state")
    other = to_str(bytes([0x43] * 32))
    c.ck("a different master cannot open it",
         ip.call("rsOpenAppState", [sealed, other]), "")
    c.ck("a foreign magic is refused",
         ip.call("rsOpenAppState", ["XIPTAPP1S" + sealed[9:], MASTER]), "")
    c.ck("a truncated file is refused",
         ip.call("rsOpenAppState", [sealed[:8], MASTER]), "")
    tampered = sealed[:-1] + chr(ord(sealed[-1]) ^ 1)
    c.ck("a tampered store is refused",
         ip.call("rsOpenAppState", [tampered, MASTER]), "")
    c.ck("an over-cap state refuses rather than truncating",
         ip.call("rsSealAppState", ["x" * 1048577, MASTER]), "")
    c.ck("a unicode state survives the round trip",
         ip.call("rsOpenAppState",
                 [ip.call("rsSealAppState",
                          [to_str("café ✓".encode("utf-8")),
                           MASTER]), MASTER]),
         to_str("café ✓".encode("utf-8")))


def check_composed(c, ip, V):
    c.note("tier 2: the phase-8 rail, executed over the real committed CoinXT")

    c.note("the secp256k1 validity ladder")
    c.ck("a valid candidate passes through unchanged",
         ip.call("rsNostrSeckeyFrom", ["42" * 32]), "42" * 32)
    c.ck("the all-zeros candidate steps to SHA-256 of itself",
         ip.call("rsNostrSeckeyFrom", ["00" * 32]),
         hashlib.sha256(bytes(32)).hexdigest())
    order = "%064x" % REF["_NOSTR"]["N"]
    c.ck("the group order n steps forward too",
         ip.call("rsNostrSeckeyFrom", [order]),
         hashlib.sha256(bytes.fromhex(order)).hexdigest())
    c.ck("a short candidate is refused",
         ip.call("rsNostrSeckeyFrom", ["42" * 31]), "")
    c.ck("a non-hex candidate is refused",
         ip.call("rsNostrSeckeyFrom", ["zz" + "42" * 31]), "")

    c.note("the Nostr identity")
    keys = ip.call("rsNostrKeys", [MASTER])
    c.ck("the x-only public key matches the oracle",
         keys["pubkey"], V["nostrPubkey"])
    c.ck("the npub matches the oracle", keys["npub"], V["nostrNpub"])
    c.ck("rsNostrKeys hands back NO secret material",
         sorted(keys.keys()), ["npub", "pubkey"])
    c.ck("the exported secret key matches the oracle",
         ip.call("rsNostrExportSeckey", [MASTER]), V["nostrSeckey"])

    c.note("the RSN1 bridge, byte for byte")
    br = ip.call("rsBuildBridge", [1, 1754870800, MASTER, AUX])
    c.ck("the record is byte-identical to the oracle's",
         to_bytes(br).hex(), V["bridge"])
    c.ck("it is exactly 276 bytes", len(br), 276)
    rec = ip.call("rsVerifyBridge", [br, "", ""])
    c.ck("verify recovers the handle", rec["handle"], V["handle"])
    c.ck("verify recovers the nostr key", rec["nostrPub"], V["nostrPubkey"])
    c.ck("verify recovers the seq", str(rec["seq"]), "1")
    c.ck("verify recovers the timestamp", str(rec["timestamp"]), "1754870800")
    c.ck("both expectations together still verify",
         ip.call("rsVerifyBridge",
                 [br, V["handle"], V["nostrPubkey"]])["handle"], V["handle"])
    c.ck("a wrong expected handle is refused",
         ip.call("rsVerifyBridge", [br, "ab" * 32, ""]), "")
    c.ck("a wrong expected nostr key is refused",
         ip.call("rsVerifyBridge", [br, "", "ab" * 32]), "")

    c.note("every field of the signed span is load-bearing")
    for pos, what in [(5, "the handle"), (69, "the nostr key"),
                      (140, "the seq"), (148, "the timestamp"),
                      (150, "the ed25519 signature"),
                      (214, "the BIP-340 signature")]:
        bad = br[:pos - 1] + chr(ord(br[pos - 1]) ^ 1) + br[pos:]
        c.ck("a tamper in %s is refused" % what,
             ip.call("rsVerifyBridge", [bad, "", ""]), "")
    c.ck("a short record is refused", ip.call("rsParseBridge", [br[:-1]]), "")
    c.ck("a long record is refused",
         ip.call("rsParseBridge", [br + "x"]), "")
    c.ck("a foreign magic is refused",
         ip.call("rsParseBridge", ["X" + br[1:]]), "")

    c.note("the DHT seam validates everything else BEFORE the session")
    # The phase-2 decision, kept: with a dead session handle these must
    # still reach their real refusal, or the checks below can only ever run
    # on a machine that has torrentxt - which is where a harness assertion
    # quietly starts passing for the wrong reason.
    c.ck("a non-RSN1 record is refused before the session is looked at",
         ip.call("rsPublishBridge", [0, "junk", to_str(bytes(32))]), False)
    c.ck("...naming the parse, not the session",
         "RSN1" in ip.call("rsLastError", []), True)
    c.ck("a seed that is not the bridge's handle is refused",
         ip.call("rsPublishBridge", [0, br, to_str(bytes([0x43] * 32))]),
         False)
    c.ck("...naming the seed, not the session",
         "signing seed" in ip.call("rsLastError", []), True)
    c.ck("only then does the dead session become the reason",
         "session" in (ip.call("rsPublishBridge",
                               [0, br, REF["identity_seed"](
                                   bytes([0x42] * 32)).decode("latin-1")])
                       or ip.call("rsLastError", [])), True)

    c.note("kind-1 notes and the media convention")
    note = ip.call("rsNostrNoteEvent", [1754870400, "hello, riptide", ""])
    signed = ip.call("rsNostrSignEvent", [note, MASTER, AUX])
    c.ck("the note id matches the oracle", signed["id"], V["noteEventId"])
    c.ck("the note signature matches the oracle",
         signed["sig"], V["noteEventSig"])
    media = ip.call("rsNostrNoteEvent", [1754870460, "second post", "ee" * 20])
    signed_media = ip.call("rsNostrSignEvent", [media, MASTER, AUX])
    c.ck("a note with media matches the oracle's id",
         signed_media["id"], V["noteMediaEventId"])
    c.ck("its canonical serialization is byte-exact",
         ip.call("nxEventSerialize", [signed_media]), V["noteMediaEventSer"])
    c.ck("the info-hash survives the round trip through the tag",
         ip.call("rsNostrMediaTags", [signed_media]), "ee" * 20)
    c.ck("an empty note is refused",
         ip.call("rsNostrNoteEvent", [1754870400, "", ""]), "")
    c.ck("the all-zeros info-hash is refused",
         ip.call("rsNostrNoteEvent", [1754870400, "x", "00" * 20]), "")
    c.ck("a malformed info-hash is refused",
         ip.call("rsNostrNoteEvent", [1754870400, "x", "zz" * 20]), "")
    c.ck("a negative timestamp is refused",
         ip.call("rsNostrNoteEvent", [-1, "x", ""]), "")
    c.ck("an `r` tag that is not a magnet URI is ignored, not fetched",
         ip.call("rsNostrMediaTags",
                 [ip.call("nxEventBuild",
                          [1, "x", {"1": {"1": "r",
                                          "2": "https://example.com/"}},
                           1754870400])]), "")

    c.note("the bridge as a NIP-78 event, and the republish attack")
    bev = ip.call("rsNostrBridgeEvent", [br, MASTER, 1754870800, AUX])
    c.ck("the bridge event id matches the oracle",
         bev["id"], V["bridgeEventId"])
    c.ck("the bridge event signature matches the oracle",
         bev["sig"], V["bridgeEventSig"])
    c.ck("its canonical serialization is byte-exact",
         ip.call("nxEventSerialize", [bev]), V["bridgeEventSer"])
    back = ip.call("rsNostrBridgeFromEvent",
                   [ip.call("nxEventToJson", [bev])])
    c.ck("the bridge comes back out of its own event",
         back["handle"], V["handle"])
    other = to_str(bytes([0x43] * 32))
    stolen = ip.call("rsNostrBridgeEvent", [br, other, 1754870800, AUX])
    c.ck("somebody else's bridge inside my signed event is REFUSED",
         ip.call("rsNostrBridgeFromEvent",
                 [ip.call("nxEventToJson", [stolen])]), "")
    c.ck("a non-bridge kind is refused",
         ip.call("rsNostrBridgeFromEvent",
                 [ip.call("nxEventToJson",
                          [ip.call("rsNostrSignEvent",
                                   [note, MASTER, AUX])])]), "")
    c.ck("garbage JSON is refused, not thrown",
         ip.call("rsNostrBridgeFromEvent", ["not json at all"]), "")


def main(argv):
    terse = "--check" in argv
    c = Checker(terse)
    failures = []

    def fail(msg):
        print("check-script-vectors: %s" % msg)
        sys.exit(1)

    src, hits = build_source(fail)
    try:
        ip = LCS.Interp(src)
    except Exception as exc:                       # noqa: BLE001
        fail("the shipped script did not parse under the interpreter: %s: %s"
             % (type(exc).__name__, exc))
    install_pure_natives()
    V = REF["golden_vectors"]()

    if not terse:
        print("-- rewrites applied: " + ", ".join(
            "%s x%d" % (n, hits[n]) for n, _w, _f in REWRITES))
    check_pure(c, ip, V)
    check_u64_bound(c, ip)
    check_u64_engine_models(c, ip, src, fail)
    check_no_quotient_comparisons(c, fail)
    check_capacity_arithmetic(c, ip)
    if install_coin_natives():
        check_composed(c, ip, V)
    elif os.environ.get("XTALK_REQUIRE_SIBLINGS"):
        # Same split, and the same env-var shape, as CROSSMEMBER_REQUIRE_ALL
        # (tests/cross-member-test.py) and COINXT_REQUIRE_CROSSCHECK
        # (coinxt/tools/coin-kat.py): a skip is right for a contributor whose
        # checkout has no siblings beside it, and wrong for CI, where a skip
        # and a pass both exit 0 and print almost the same thing. A lane that
        # means to settle tier 2 sets XTALK_REQUIRE_SIBLINGS, and the skip is
        # a failure there - one that still names the clone to run.
        print("check-script-vectors: " + sibling_missing("coinxt", COIN_SO))
        c.ck("tier 2 ran (XTALK_REQUIRE_SIBLINGS is set, so a missing coinxt "
             "is a failure, not a skip)", "absent", "present")
    else:
        c.skip("tier 2 (the whole phase-8 rail)",
               sibling_missing("coinxt", COIN_SO))

    if c.failed:
        print("check-script-vectors: %d of %d check(s) FAILED"
              % (c.failed, c.n))
        return 1
    print("check-script-vectors: OK (%d checks; the shipped script executed "
          "against the oracle%s)"
          % (c.n, ", %d skipped" % c.skipped if c.skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
