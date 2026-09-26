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
comparison against a quotient in the library. Tier 1d (2026-09-25) does the
same for ORDERING: rsSeqCompare, rsIsWireInt and the two ingest verifiers
near 2^53, where the rule calls integers one apart equal, each after a
seeded copy of the spelling that shipped has read right under IEEE and wrong
under the engine's rule (the bridge's seq agreement with tier 2, since only
a bridge that verifies over the real CoinXT reaches it). Tier 1e
(2026-09-26) reads the HARNESS, not the library: the shape of its fourth
numeric compare probe line, and the plain interpreter's refusal of each of
its six items (suite engine note 2.11's forms that only an engine can read).

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


# What a row reads when the interpreter REFUSED the comparison deciding it
# (LCS.Indistinct, since 2026-09-25): the engine's tolerant comparison
# answers that pair differently from IEEE, so no answer here is the engine's.
INDISTINCT = ("NOT ANSWERED: the interpreter refused a comparison the engine "
              "answers differently from IEEE (LCS.Indistinct)")


def u64_call(ip, name, args):
    try:
        return ip.call(name, args)
    except LCS.Imprecise:
        return PAST_2P53
    except LCS.Indistinct:
        return INDISTINCT


def u64_parsed(out):
    """True when rsParseHead's answer is a parsed head, not a refusal.
    Never asked of INDISTINCT: the callers pass that through as itself (a
    non-empty text, it would read here as a parsed head)."""
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
                     # PAST_2P53 and INDISTINCT stand as themselves: read
                     # through u64_parsed, a refusal was a "parses" answer
                     # (2026-09-26; tier 1c's seq-0 fixture holds it)
                     out if out is PAST_2P53 or out is INDISTINCT
                     else u64_parsed(out),
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
# DOCUMENTED). That rule reproduces all eight readings of the first two
# probe lines, and the harness's third line then read its consequences on
# an engine (Linux, then Windows, 2026-09-25, alike): the absolute branch
# near zero, the integer
# threshold between 2^48 and 2^49, and the constant itself to the digit
# (N is N + 1 true at N = 450359962737050, false one below; 2^52 / 10 lies
# between). The fixture below re-proves the rule against every one of
# those recorded numeric answers on every run.
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
# the engine's rule must read the probes' fourteen recorded numeric answers
# through the interpreter, while each margin model misreads at least one of
# them (the reason it is margin and not the rule).

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


def _model_ieee(a, b):
    """Exact IEEE comparison, REPLAYED. Not one of ENGINE_MODELS: since
    2026-09-25 the plain interpreter refuses (LCS.Indistinct) a comparison
    the engine answers differently from IEEE, so a fixture that must show
    what IEEE answers - why no headless gate saw a seeded defect before that
    date - replays it through a model like the others."""
    return a, b

# The engine's recorded answers to the harness's numeric compare probes,
# each expression as the harness spells it (riptide/CLAUDE.md's ledger).
# Probe 1 was read in the 2026-09-24 second run and probe 2 in the third
# (Windows); the 2026-09-25 Linux run read both again, answer for answer,
# and read probe 3 for the first time, exactly as the engine source's rule
# predicted. The ladder is the harness's rstUlpLadder under a fixture name.
#
# Probe 3 enters at its item 3. Its items 1 and 2 ("1e999" is "2e999" and
# "1e5" is "100000", both true on the engine) are not comparisons of two
# numbers but text becoming a number (strtod: suite engine note 2.11). Since
# 2026-09-25 the interpreter ports that parse and REFUSES both (it answered
# false, by the text, before), but it never reaches the number comparison a
# model swaps, so holding a model to them here would test the parse, not
# the rule: coinxt's check-script-vectors tier 0 holds the interpreter to
# them instead. Pure IEEE reads the fourteen below as
# true,true,true,true,true,true,1,1 then true,true,true,true,false,false.
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
    # probe 3, items 3 to 8 (Linux and Windows, 2026-09-25): the absolute
    # branch near
    # zero (1e-15 is within MC_EPSILON of 0, 1e-14 is not), integers one
    # apart at 2^49 (8 DBL_EPSILON: equal) and 2^48 (16: told apart), and
    # N against N + 1 either side of 2^52 / 10 = 450359962737049.6, which
    # reads the constant to the digit
    ("1 / 1000000000000000 > 0", "false"),
    ("1 / 100000000000000 > 0", "true"),
    ("562949953421312 < 562949953421313", "false"),
    ("281474976710656 < 281474976710657", "true"),
    ("450359962737050 is 450359962737051", "true"),
    ("450359962737049 is 450359962737050", "false"),
]


def _probe_plain(interp):
    """The PLAIN interpreter's answers to PROBE_READINGS: a value where it
    answers, "refused" where it will not (LCS.Indistinct)."""
    out = []
    for expr, _want in PROBE_READINGS:
        try:
            out.append(str(LCS._disp(interp.eval_expr(expr, {}))))
        except LCS.Indistinct:
            out.append("refused")
    return out


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
    head and PAST_2P53 alike mean: not refused. A call the interpreter
    refused to decide reads INDISTINCT, never True or False: until
    2026-09-26 it read "not refused" in both places (a non-empty answer to
    u64_parsed, a status other than "refused"), which is the answer the
    models' fixtures below expect of the old bound."""
    head = u64_call(interp, "rsParseHead",
                    [u64_head_with_seq(b"\x00\x20" + b"\x00" * 5 + b"\x01")])
    total = u64_call(interp, "rsBtxoStreamStep",
                     [u64_btxo_header(2 ** 53 + 1), "header"])
    return [head if head is INDISTINCT else not u64_parsed(head),
            total if total is INDISTINCT else u64_status(total) == "refused"]


# A comparison the engine answers TRUE at seq 0 (`0 is 1e-15`: inside
# MC_EPSILON of zero, engine note 2.10) and the plain interpreter therefore
# refuses, seeded just before rsReadBEu64's return: on an engine it would
# refuse a valid seq 0, and headlessly tier 1b's table read the refusal as
# "seq 0 parses" and passed (2026-09-26). Never shipped; a fixture.
_U64_RETURN = "   return tHi * 4294967296 + tLo\nend rsReadBEu64\n"
SEQ0_REFUSED_LINES = ("   if tHi * 4294967296 + tLo is 0.000000000000001 then\n"
                      "      return empty\n"
                      "   end if\n")


def seed_refused_seq0(text, fail):
    """TEXT with SEQ0_REFUSED_LINES before rsReadBEu64's one return."""
    found = text.count(_U64_RETURN)
    if found != 1:
        fail("tier 1c's seq-0 refusal fixture expects rsReadBEu64 to end in "
             "ONE `return tHi * 4294967296 + tLo`, and found %d; without it "
             "tier 1b's refusal reading goes untested" % found)
    return text.replace(_U64_RETURN, SEQ0_REFUSED_LINES + _U64_RETURN)


def check_u64_engine_models(c, ip, src, fail):
    c.note("tier 1c: the u64 bound under the engine's comparison rule and "
           "two margin models")
    probe = LCS.Interp(PROBE_LADDER)
    want = [w for _expr, w in PROBE_READINGS]
    c.ck("fixture: the plain interpreter REFUSES each probe the engine read "
         "differently from IEEE (IEEE reads true x6, 1, 1 and true x4, "
         "false x2) and answers the five it read the same - its refusal held "
         "to fourteen observations",
         _probe_plain(probe),
         ["true", "refused", "refused", "refused", "true", "refused",
          "refused", "refused",
          "refused", "true", "refused", "true", "refused", "false"])
    for index, (name, model) in enumerate(ENGINE_MODELS):
        with engine_model(model):
            got = _probe_answers(probe)
        if index == 0:
            c.ck("fixture: %s reads the fourteen numeric answers the engine "
                 "gave (probes 1 and 2 on Windows 2026-09-24; those and "
                 "probe 3's items 3-8 on Linux and on Windows 2026-09-25)"
                 % name, got, want)
        else:
            c.ck("fixture: %s misreads at least one of them (margin, not "
                 "the rule)" % name, got != want, True)
    old = LCS.Interp(seed_old_bound(src, fail))
    c.ck("fixture: the plain interpreter REFUSES to decide the "
         "pre-2026-09-24 bound at 2^53+1 (head, BTXO total) - it answered "
         "the IEEE way until 2026-09-25, which is why every headless gate "
         "was green over it", _refuses_2p53p1(old), [INDISTINCT, INDISTINCT])
    # A REFUSAL IS NEVER A ROW'S ANSWER (2026-09-26): tier 1b's table must
    # read a refused seq-0 comparison as the refusal, not as a parsed head.
    refused = LCS.Interp(seed_refused_seq0(src, fail))
    c.ck("fixture: a comparison the plain interpreter refuses at seq 0 "
         "reads as that refusal in tier 1b's table, never as `parses`",
         [got for label, got, _w in u64_rows(refused)
          if label.startswith("rsParseHead: seq 0 ")], [INDISTINCT])
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


# --------------------------------------------------------------------------
# tier 1d: wire integers ORDERED exactly (rsSeqCompare, 2026-09-25)
# --------------------------------------------------------------------------
#
# WHY. Tier 1c settled a BOUND; this is the same engine rule meeting an
# ORDER. Under the engine's comparison (10 DBL_EPSILON of the smaller; suite
# engine note 2.10) two integers one apart compare EQUAL from
# 450359962737050, and d apart from about d x 4.5e14. rsIngestHead's and
# rsIngestBridge's rollback gates were `tSeq < pMinSeq`, their seq agreement
# `is not`, and their sanity bounds `>= 9007199254740992`, all over wire
# integers accepted up to 2^53 - 1: near 2^53 a head up to 19 OLDER than the
# watermark passed the rollback gate, and the demo's LAN replay guards
# dropped newer records. IEEE orders every one of those exactly, so this
# interpreter, and every gate on it, could not see any of it. The library
# now orders through rsSeqCompare (the u32 halves) and bounds through
# rsIsWireInt (the high half).
#
# WHAT. The comparison table, rsIngestHead driven end to end near 2^53 with
# heads the oracle signs, and rsIngestBridge's rollback gate (a junk value:
# that gate answers before any signature), under IEEE and under every
# ENGINE_MODELS model: the shipped library must read every row right under
# all four. The bridge's seq AGREEMENT needs a bridge that really verifies,
# so it runs with tier 2 (check_seq_order_bridge, below).
#
# FIXTURE FIRST. Three seeded defects, each the spelling that shipped:
#   A. rsSeqCompare answering with bare `<` and `>` (the naive helper);
#   B. the ingest verifiers' own old lines (`tSeq < pMinSeq`, and `is not`
#      for the seq agreement) put back in place of the helper;
#   C. rsIsWireInt's bound spelled against 2^53 itself (`>=`).
# Each must read its rows RIGHT under IEEE (the reason no headless gate saw
# it) and WRONG under the engine's rule (the reason it had to go). A model
# that cannot see the defect that shipped cannot vouch for its fix. The
# margin models are not required to catch them: an absolute 1e-6 tolerance
# orders integers one apart exactly by construction. Since 2026-09-25 the
# PLAIN interpreter refuses (LCS.Indistinct) a comparison the engine and
# IEEE answer differently, so each defect's plain leg must be REFUSED at
# exactly the rows the engine reads wrong, and IEEE is REPLAYED
# (_model_ieee) for the rows-right half.

T53 = 2 ** 53

# (a, b, the exact answer, label). The rows the engine's rule blurs are
# marked by BLURRED_ROWS below; the rest pin the halves' own edges, small
# values, equality, the decimal-text spelling an event seq arrives in, and
# the domain's refusals (empty: what makes every caller fail closed).
SEQ_ORDER_ROWS = [
    (T53 - 1, T53 - 2, "above", "2^53-1 vs 2^53-2"),
    (T53 - 2, T53 - 1, "below", "2^53-2 vs 2^53-1"),
    (T53 - 1, T53 - 20, "above", "2^53-1 vs 2^53-20 (19 apart)"),
    (T53 - 1, T53 - 21, "above", "2^53-1 vs 2^53-21 (20 apart)"),
    (450359962737051, 450359962737050, "above",
     "450359962737051 vs 450359962737050 (the first blurred pair)"),
    (450359962737050, 450359962737051, "below",
     "450359962737050 vs 450359962737051"),
    (450359962737050, 450359962737049, "above",
     "450359962737050 vs 450359962737049 (just below the blur)"),
    (T53 - 1, T53 - 1, "equal", "2^53-1 vs itself"),
    (450359962737050, 450359962737050, "equal", "450359962737050 vs itself"),
    (4294967296, 4294967295, "above", "2^32 vs 2^32-1 (high halves differ)"),
    (4294967297, 4294967296, "above", "2^32+1 vs 2^32 (low halves differ)"),
    (7, 6, "above", "7 vs 6"),
    (0, 1, "below", "0 vs 1"),
    (0, 0, "equal", "0 vs 0"),
    ("9007199254740991", "9007199254740990", "above",
     "2^53-1 vs 2^53-2 as decimal TEXT (an event seq's spelling)"),
    ("0012", 12, "equal", "the VALUE is compared: 0012 is 12"),
    (T53, 0, "", "2^53 is outside the domain"),
    (0, T53, "", "on either side"),
    (-1, 0, "", "a negative operand"),
    ("1.5", 1, "", "a fraction"),
    ("seven", 0, "", "a non-number"),
    ("", 0, "", "an empty operand"),
]
BLURRED_ROWS = ["2^53-1 vs 2^53-2", "2^53-2 vs 2^53-1",
                "2^53-1 vs 2^53-20 (19 apart)",
                "450359962737051 vs 450359962737050 (the first blurred pair)",
                "450359962737050 vs 450359962737051",
                "2^53-1 vs 2^53-2 as decimal TEXT (an event seq's spelling)"]

# Seeded defect A: the helper with bare operators, domain check kept, so the
# rows it gets wrong are the ORDER rows only.
NAIVE_SEQ_COMPARE = "\n".join([
    "function rsSeqCompare pA, pB",
    "   if not rsIsWireInt(pA) then",
    "      return empty",
    "   end if",
    "   if not rsIsWireInt(pB) then",
    "      return empty",
    "   end if",
    "   if pA < pB then",
    "      return \"below\"",
    "   end if",
    "   if pA > pB then",
    "      return \"above\"",
    "   end if",
    "   return \"equal\"",
    "end rsSeqCompare"])

# Seeded defect C: the bound as every builder and verifier spelled it before
# 2026-09-25.
OLD_WIRE_INT = "\n".join([
    "private function rsIsWireInt pValue",
    "   if pValue is not an integer then",
    "      return false",
    "   end if",
    "   if pValue < 0 then",
    "      return false",
    "   end if",
    "   if pValue >= 9007199254740992 then",
    "      return false",
    "   end if",
    "   return true",
    "end rsIsWireInt"])

# Seeded defect B: (the shipped text, the line it replaced), each of which
# must match exactly once.
OLD_INGEST_LINES = [
    ('   put rsSeqCompare(tSeq, pMinSeq) into tOrder\n'
     '   if tOrder is not "above" and tOrder is not "equal" then\n'
     '      rsSetError "rsIngestHead: this head is older',
     '   if tSeq < pMinSeq then\n'
     '      rsSetError "rsIngestHead: this head is older'),
    ('   if rsSeqCompare(tHead["seq"], tSeq) is not "equal" then',
     '   if tHead["seq"] is not tSeq then'),
    ('   put rsSeqCompare(tSeq, pMinSeq) into tOrder\n'
     '   if tOrder is not "above" and tOrder is not "equal" then\n'
     '      rsSetError "rsIngestBridge: this bridge is older',
     '   if tSeq < pMinSeq then\n'
     '      rsSetError "rsIngestBridge: this bridge is older'),
    ('   if rsSeqCompare(tRec["seq"], tSeq) is not "equal" then',
     '   if tRec["seq"] is not tSeq then'),
]


def _swap_handler(text, name, new, fail, private=False):
    rx = re.compile(r'^%sfunction %s\b.*?^end %s$'
                    % ("private " if private else "", name, name),
                    re.M | re.S)
    found = len(rx.findall(text))
    if found != 1:
        fail("tier 1d's fixture expects exactly ONE %s handler to seed, and "
             "found %d; without it the models would be trusted untested"
             % (name, found))
    return rx.sub(lambda _m: new, text)


def seed_naive_compare(text, fail):
    return _swap_handler(text, "rsSeqCompare", NAIVE_SEQ_COMPARE, fail)


def seed_old_wire_int(text, fail):
    return _swap_handler(text, "rsIsWireInt", OLD_WIRE_INT, fail,
                         private=True)


def seed_old_ingest(text, fail):
    for new, old in OLD_INGEST_LINES:
        if text.count(new) != 1:
            fail("tier 1d's fixture expects the shipped line %r exactly once "
                 "and found it %d times; the seeded defect would be a file "
                 "nobody shipped" % (new.split("\n")[-1][:60],
                                     text.count(new)))
        text = text.replace(new, old)
    return text


# What a row reads when the plain interpreter REFUSED the comparison that
# decides it (LCS.Indistinct): the engine and IEEE part there.
REFUSED_ROW = "refused (LCS.Indistinct)"


def seq_order_answers(interp):
    """{label: rsSeqCompare's answer} over SEQ_ORDER_ROWS, REFUSED_ROW where
    the interpreter refused to decide it."""
    out = {}
    for a, b, _want, label in SEQ_ORDER_ROWS:
        try:
            out[label] = str(interp.call("rsSeqCompare", [a, b]))
        except LCS.Indistinct:
            out[label] = REFUSED_ROW
    return out


def _order_identity():
    seed = REF["identity_seed"](bytes([0x42] * 32))
    return seed, REF["ed25519_publickey"](seed).hex()


def _mutable_event(interp, salt, bep44_seq, value, seed, handle):
    """A dhtMutableItem event, key for key what btPoll drains: VALUE signed
    by the oracle at BEP44_SEQ under SALT. The seq crosses as decimal TEXT,
    the way torrentxt decodes a native integer."""
    buf = interp.call("rsBep44SignBuf",
                      [salt, bep44_seq, interp.call("rsBencodeBytes", [value])])
    if not buf:
        raise RuntimeError("rsBep44SignBuf refused seq %d: %s"
                           % (bep44_seq, interp.call("rsLastError", [])))
    sig = REF["ed25519_sign"](to_bytes(buf), seed)
    return {"publicKey": handle, "salt": salt, "seq": str(bep44_seq),
            "value": value, "signature": sig.hex()}


def ingest_events(interp):
    """The events ingest_rows drives, near 2^53: built and signed under IEEE
    by INTERP before any model is switched on (the builders are not what is
    under test here; tier 1d's top-of-range rows are), so only the ingest
    calls run under a model."""
    seed, handle = _order_identity()

    def head(seq):
        out = interp.call("rsBuildHead", [seq, "n", "", "", "", ""])
        if not out:
            raise RuntimeError("rsBuildHead refused seq %d: %s"
                               % (seq, interp.call("rsLastError", [])))
        return out

    events = {
        "top-2": _mutable_event(interp, "riptide-head", T53 - 2,
                                head(T53 - 2), seed, handle),
        "top-20": _mutable_event(interp, "riptide-head", T53 - 20,
                                 head(T53 - 20), seed, handle),
        # author-signed, BEP44 seq one above the embedded seq
        "skew": _mutable_event(interp, "riptide-head", T53 - 1,
                               head(T53 - 2), seed, handle),
        # a bridge event whose rollback gate must answer before any
        # signature or parse: the value is junk on purpose
        "bridge": {"publicKey": handle, "salt": "riptide-nostr",
                   "seq": str(T53 - 2), "value": "junk",
                   "signature": "00" * 64},
    }
    return events, handle


def ingest_rows(interp, events, handle):
    """(key, label, got, want) for rsIngestHead and rsIngestBridge near
    2^53. A refusal row reads the error too, so a record refused by the
    WRONG gate (a later signature check, say) does not pass for the right
    one."""
    rows = []
    refused = object()

    def ingest(name, event, watermark):
        try:
            out = interp.call(name, [event, handle, watermark])
        except LCS.Indistinct:
            return refused, ""
        return out, str(interp.call("rsLastError", []))

    def row(key, label, out, got, want):
        rows.append((key, label, REFUSED_ROW if out is refused else got,
                     want))

    out, err = ingest("rsIngestHead", events["top-2"], T53 - 1)
    row("head-1-older",
        "rsIngestHead: a head ONE older than a 2^53-1 watermark is "
        "refused by the rollback gate", out,
        [out in ("", {}), "older" in err], [True, True])
    out, err = ingest("rsIngestHead", events["top-20"], T53 - 1)
    row("head-19-older",
        "rsIngestHead: a head 19 older than a 2^53-1 watermark is "
        "refused by the rollback gate", out,
        [out in ("", {}), "older" in err], [True, True])
    out, _err = ingest("rsIngestHead", events["top-2"], T53 - 2)
    row("head-refresh",
        "rsIngestHead: the SAME seq at 2^53-2 ingests (a refresh), "
        "its seq exact", out,
        isinstance(out, dict) and str(LCS._n(out["seq"])), str(T53 - 2))
    out, _err = ingest("rsIngestHead", events["top-2"], T53 - 3)
    row("head-newer",
        "rsIngestHead: a head one NEWER than the watermark ingests", out,
        isinstance(out, dict), True)
    out, err = ingest("rsIngestHead", events["skew"], 0)
    row("head-skew",
        "rsIngestHead: a signed head whose embedded seq sits one "
        "below its BEP44 seq is refused as a disagreement", out,
        [out in ("", {}), "disagree" in err], [True, True])
    out, err = ingest("rsIngestBridge", events["bridge"], T53 - 1)
    row("bridge-1-older",
        "rsIngestBridge: a bridge one older than a 2^53-1 "
        "watermark is refused by the ROLLBACK gate (before any "
        "signature)", out, [out in ("", {}), "older" in err],
        [True, True])
    out, err = ingest("rsIngestBridge", events["bridge"], T53 - 2)
    row("bridge-equal",
        "rsIngestBridge: at an equal watermark the rollback gate "
        "passes it on (the junk value is refused later, for "
        "another reason)", out, "older" in err, False)
    return rows


def top_of_range_rows(interp):
    """The bound at 2^53 - 1 through the builders and the BEP44 buffer:
    accepted, exactly, and 2^53 refused. A call the interpreter refused to
    decide (LCS.Indistinct) reads REFUSED_ROW."""
    v = interp.call("rsBencodeBytes", ["hi"])

    def built(name, args):
        try:
            return bool(interp.call(name, args))
        except LCS.Indistinct:
            return REFUSED_ROW

    return [
        ("rsBep44SignBuf: seq 2^53-1 is accepted",
         built("rsBep44SignBuf", ["riptide-head", T53 - 1, v]), True),
        ("rsBep44SignBuf: seq 2^53 is refused",
         built("rsBep44SignBuf", ["riptide-head", T53, v]), False),
        ("rsBuildHead: seq 2^53-1 builds",
         built("rsBuildHead", [T53 - 1, "n", "", "", "", ""]), True),
        ("rsLanBuildDraft: seq 2^53-1 builds",
         built("rsLanBuildDraft", ["dev", T53 - 1, "x", MASTER]), True),
        # the one builder that had NO upper bound before 2026-09-25: a total
        # past 2^53 was split as a rounded double
        ("rsBtxoHeader: total 2^53-1 builds",
         built("rsBtxoHeader", ["x", T53 - 1, 0]), True),
        ("rsBtxoHeader: total 2^53 is refused",
         built("rsBtxoHeader", ["x", T53, 0]), False),
    ]


def check_seq_order(c, ip, src, fail):
    c.note("tier 1d: wire integers ordered exactly (rsSeqCompare), under "
           "IEEE and the engine's comparison rule")
    want = dict((label, w) for _a, _b, w, label in SEQ_ORDER_ROWS)
    engine_name, engine_rule = ENGINE_MODELS[0]

    # A: the naive helper
    naive = LCS.Interp(seed_naive_compare(src, fail))
    got = seq_order_answers(naive)
    c.ck("fixture A: the plain interpreter REFUSES the naive helper at "
         "exactly the blurred rows (the engine and IEEE part on each) and "
         "reads the rest right",
         (sorted(label for label in want if got[label] == REFUSED_ROW),
          sorted(label for label in want
                 if got[label] not in (want[label], REFUSED_ROW))),
         (sorted(BLURRED_ROWS), []))
    with engine_model(_model_ieee):
        got = seq_order_answers(naive)
    c.ck("fixture A: under IEEE (replayed) the naive `<`/`>` helper reads "
         "every row right - why no headless gate could see the defect "
         "before 2026-09-25", got, want)
    with engine_model(engine_rule):
        got = seq_order_answers(naive)
    c.ck("fixture A: under %s the naive helper calls exactly the blurred "
         "rows EQUAL" % engine_name,
         sorted(label for label in want if got[label] != want[label]),
         sorted(BLURRED_ROWS))
    c.ck("fixture A: ... and every one of them reads \"equal\"",
         sorted(set(got[label] for label in BLURRED_ROWS)), ["equal"])

    # B: the ingest verifiers' old lines
    old = LCS.Interp(seed_old_ingest(src, fail))
    events, handle = ingest_events(old)
    rows = ingest_rows(old, events, handle)
    c.ck("fixture B: the plain interpreter REFUSES the old ingest lines at "
         "both replayed heads, the skewed head and the older bridge, and "
         "reads the rest right (refused, then misread)",
         ([key for key, _l, got, _w in rows if got == REFUSED_ROW],
          [key for key, _l, got, w in rows if got not in (w, REFUSED_ROW)]),
         (["head-1-older", "head-19-older", "head-skew", "bridge-1-older"],
          []))
    with engine_model(_model_ieee):
        rows = ingest_rows(old, events, handle)
    c.ck("fixture B: under IEEE (replayed) the old ingest lines read every "
         "ingest row right (the rows they misread, listed)",
         [key for key, _l, got, w in rows if got != w], [])
    with engine_model(engine_rule):
        rows = ingest_rows(old, events, handle)
    c.ck("fixture B: under %s the old lines let both replayed heads, the "
         "skewed head and the older bridge through" % engine_name,
         [key for key, _l, got, w in rows if got != w],
         ["head-1-older", "head-19-older", "head-skew", "bridge-1-older"])

    # C: the bound against 2^53 itself
    oldb = LCS.Interp(seed_old_wire_int(src, fail))
    c.ck("fixture C: the plain interpreter REFUSES the old `>=` bound at "
         "2^53-1 at every top-of-range row, and answers 2^53 (equal operands)",
         [got for _l, got, _w in top_of_range_rows(oldb)],
         [REFUSED_ROW, False, REFUSED_ROW, REFUSED_ROW, REFUSED_ROW, False])
    with engine_model(_model_ieee):
        got = [g for _l, g, _w in top_of_range_rows(oldb)]
    c.ck("fixture C: under IEEE (replayed) the old `>=` bound accepts 2^53-1 "
         "at every top-of-range row", got,
         [True, False, True, True, True, False])
    with engine_model(engine_rule):
        got = [g for _l, g, _w in top_of_range_rows(oldb)]
    c.ck("fixture C: under %s it REFUSES 2^53-1 at every one (the engine "
         "calls 2^53-1 and 2^53 equal)" % engine_name, got,
         [False, False, False, False, False, False])

    # the shipped library, under IEEE and every model
    events, handle = ingest_events(ip)
    for name, model in [("IEEE", None)] + ENGINE_MODELS:
        if model is None:
            got = seq_order_answers(ip)
            rows = ingest_rows(ip, events, handle)
            tops = top_of_range_rows(ip)
            fired = None
        else:
            with engine_model(model) as hook:
                got = seq_order_answers(ip)
                rows = ingest_rows(ip, events, handle)
                tops = top_of_range_rows(ip)
            fired = hook.fired
        for _a, _b, w, label in SEQ_ORDER_ROWS:
            c.ck("[%s] rsSeqCompare %s -> %r" % (name, label, w),
                 got[label], w)
        for _key, label, g, w in rows:
            c.ck("[%s] %s" % (name, label), g, w)
        for label, g, w in tops:
            c.ck("[%s] %s" % (name, label), g, w)
        if fired is not None:
            c.ck("[%s] the model reached the comparison sites" % name,
                 fired > 0, True)


# --------------------------------------------------------------------------
# tier 1d, the bridge's seq AGREEMENT (needs the real CoinXT)
# --------------------------------------------------------------------------
#
# WHY SEPARATE. rsIngestBridge checks the embedded seq against the BEP44
# seq LAST, after both signatures and rsVerifyBridge, so only a bridge that
# really verifies reaches it - and rsVerifyBridge checks a BIP-340 signature,
# which needs CoinXT. check_seq_order's bridge rows use a junk value and stop
# at the rollback gate, so until this tier existed NOTHING executed the
# agreement line: deleting its refusal left all 297 checks green (review,
# 2026-09-25), and the folded harness's own "a seq disagreeing with the
# bridge's embedded seq is refused" changed the seq WITHOUT re-signing, so
# the BEP44 signature refused it first (the seq is inside the signed
# buffer; the harness re-signs now). Runs where tier 2 runs; a lane that
# sets XTALK_REQUIRE_SIBLINGS fails when it cannot.
#
# WHAT. A bridge the SHIPPED builder signs at embedded seq 2^53 - 2, offered
# twice with an oracle-signed BEP44 layer: at seq 2^53 - 2 (it ingests,
# exactly) and at 2^53 - 1 (an author-signed skew one apart, which must be
# refused BY THE AGREEMENT CHECK). Fixture B's old `is not` must read both
# right under IEEE (replayed: _model_ieee), let the skew through under the
# engine's rule, and be refused by the plain interpreter at the skew alone.

def bridge_order_events(interp):
    """(events, handle): the bridge rows' events, built and signed under
    IEEE before any model is switched on."""
    seed, handle = _order_identity()
    rec = interp.call("rsBuildBridge", [T53 - 2, 1754870800, MASTER, AUX])
    if not rec:
        raise RuntimeError("rsBuildBridge refused seq 2^53-2: %s"
                           % interp.call("rsLastError", []))
    return {
        "match": _mutable_event(interp, "riptide-nostr", T53 - 2, rec, seed,
                                handle),
        "skew": _mutable_event(interp, "riptide-nostr", T53 - 1, rec, seed,
                               handle),
    }, handle


def bridge_order_rows(interp, events, handle):
    """(key, label, got, want) for the bridge's seq agreement near 2^53. The
    refusal row reads the error, so a refusal by any OTHER gate (the
    signature, the rollback gate) does not pass for this one."""
    rows = []

    def ingest(event, watermark):
        # REFUSED_ROW where the interpreter refused to decide the call
        try:
            out = interp.call("rsIngestBridge", [event, handle, watermark])
        except LCS.Indistinct:
            return None, ""
        return out, str(interp.call("rsLastError", []))

    out, _err = ingest(events["match"], T53 - 2)
    rows.append(("bridge-match",
                 "rsIngestBridge: a real bridge at 2^53-2 ingests at an "
                 "equal watermark, its seq exact",
                 REFUSED_ROW if out is None else
                 isinstance(out, dict) and str(LCS._n(out["seq"])),
                 str(T53 - 2)))
    out, err = ingest(events["skew"], 0)
    rows.append(("bridge-skew",
                 "rsIngestBridge: a signed bridge whose embedded seq sits one "
                 "below its BEP44 seq is refused BY THE AGREEMENT CHECK",
                 REFUSED_ROW if out is None else
                 [out in ("", {}), "disagree" in err], [True, True]))
    return rows


def check_seq_order_bridge(c, ip, src, fail):
    c.note("tier 1d (bridge): the seq agreement near 2^53, over the real "
           "committed CoinXT")
    engine_name, engine_rule = ENGINE_MODELS[0]

    old = LCS.Interp(seed_old_ingest(src, fail))
    events, handle = bridge_order_events(old)
    rows = bridge_order_rows(old, events, handle)
    c.ck("fixture B (bridge): the plain interpreter REFUSES the old `is not` "
         "at the skewed bridge alone (refused, then misread)",
         ([key for key, _l, got, _w in rows if got == REFUSED_ROW],
          [key for key, _l, got, w in rows if got not in (w, REFUSED_ROW)]),
         (["bridge-skew"], []))
    with engine_model(_model_ieee):
        rows = bridge_order_rows(old, events, handle)
    c.ck("fixture B (bridge): under IEEE (replayed) the old `is not` reads "
         "both bridge rows right (the rows it misreads, listed)",
         [key for key, _l, got, w in rows if got != w], [])
    with engine_model(engine_rule):
        rows = bridge_order_rows(old, events, handle)
    c.ck("fixture B (bridge): under %s the old `is not` lets the skewed "
         "bridge through" % engine_name,
         [key for key, _l, got, w in rows if got != w], ["bridge-skew"])

    events, handle = bridge_order_events(ip)
    for name, model in [("IEEE", None)] + ENGINE_MODELS:
        if model is None:
            rows = bridge_order_rows(ip, events, handle)
            fired = None
        else:
            with engine_model(model) as hook:
                rows = bridge_order_rows(ip, events, handle)
            fired = hook.fired
        for _key, label, g, w in rows:
            c.ck("[%s] %s" % (name, label), g, w)
        if fired is not None:
            c.ck("[%s] the model reached the bridge's comparison sites"
                 % name, fired > 0, True)


# --------------------------------------------------------------------------
# tier 1e: the harness's FOURTH numeric compare probe (2026-09-26)
# --------------------------------------------------------------------------
# The harness prints a fourth diagnostic line (suite work plan 1.2 #22) that
# reads, on an engine, six text forms the family interpreter REFUSES as
# unsure because suite engine note 2.11 does not establish how the engine
# reads them: a hex integer, the C99 strtod words inf and nan, a hex float, a
# NO-BREAK SPACE at an edge, and a 385-digit run past R8L. Only an engine
# prints it, so nothing else would notice an edit that dropped an item,
# swapped one back to a form the interpreter answers (the work plan row's
# "0x.8" is "0.5" is one: MCU_strtor8 makes it text before strtod runs), let
# a throw end the harness, or counted the line as a check. This tier holds
# the line's SHAPE (the six items in order, the diagnostic prefix, the
# printed prediction, the statement at rstSectionHead's top level, every
# item inside the try whose catch keeps a throw on the line, each item's
# statements exactly, nothing counted) and runs the harness's OWN rstTextProbe,
# lifted out of the file, through the plain interpreter: each item must be
# REFUSED (LCS.Indistinct citing 2.11), and each refusal must name the
# operand the harness comment says it builds (the NaN pair, the U+00A0 edge,
# the 385 characters). A refusal is the handling probes 1-3 get too (tier
# 1c here, coinxt's check-script-vectors tier 0): no headless gate can run
# such a line, so a gate that holds the refusal is the one place a headless
# run meets it. When the engine's reading is recorded and the interpreter
# is taught it, these refusal rows are what change, beside that record.
# The shape checker is proven able to fire first, on seeded copies.

HARNESS = os.path.join(MEMBER, "tests", "riptide-selftest.livecodescript")
PROBE4_PREFIX = "numeric compare probe 4 (diagnostic;"
PROBE4_PREDICTED = "true,?,?,?,false,?"
# (item, the comparison its branch makes, a fragment its refusal must name)
PROBE4_ITEMS = [
    (1, '("0x10" is "16")', '`"0x10" is "16"`'),
    (2, '("inf" is "1e999")', '`"inf" is "1e999"`'),
    (3, '(tA is tB)', '`"nan" is "nan"`'),
    (4, '(tA is 3)', '"\\xa03"'),
    (5, '(tA is 4294967296)', '4294967296 (385 chars)'),
    (6, '("0x1.8" is "1.5")', '`"0x1.8" is "1.5"`'),
]
# Each item's statements, from its branch to the next, EXACTLY (review,
# 2026-09-26). The refusal rows below cannot see an edit that keeps every
# operand the interpreter refuses but changes what the ENGINE prints: a line
# after the comparison that overwrites its answer, or the NaN pair built as
# ONE value (`put tA into tB`), which MCLogicIsEqualTo answers true before it
# reads either, so the item would print true under every C library. Both
# passed this tier green until the bodies were pinned.
PROBE4_BODIES = {
    1: ['put ("0x10" is "16") into tOut'],
    2: ['put ("inf" is "1e999") into tOut'],
    3: ['put "n" into tA', 'put "an" after tA', 'put "na" into tB',
        'put "n" after tB', 'put (tA is tB) into tOut'],
    4: ['put numToCodepoint(160) & "3" into tA', 'put (tA is 3) into tOut'],
    5: ['put empty into tA', 'repeat with tN = 1 to 375', 'put "0" after tA',
        'end repeat', 'put "4294967296" after tA',
        'put (tA is 4294967296) into tOut'],
    6: ['put ("0x1.8" is "1.5") into tOut'],
}
_PROBE4_FN_RX = re.compile(
    r'^private function rstTextProbe pItem$.*?^end rstTextProbe$',
    re.M | re.S)
_SECTION_HEAD_RX = re.compile(
    r'^private command rstSectionHead$.*?^end rstSectionHead$', re.M | re.S)
# the probe-4 statement's first and last physical lines, as a seed wraps them
PROBE4_OPEN = ('   put "      numeric compare probe 4 (diagnostic; the engine '
               'source" && \\\n')
PROBE4_CLOSE = 'rstTextProbe(6) & return after sLog\n'
# what a counted line would call, and the counters it would touch
_PROBE4_COUNTED_RX = re.compile(r'\b(rstCheck|rstSkip|sPass|sFail|sSkip)\b')


def _probe4_logical(body):
    """The body's logical lines: each `\\`-continued statement joined into
    one, comments cut outside string literals."""
    out, buf = [], ""
    for raw in body.split("\n"):
        code, instr = "", False
        for i, ch in enumerate(raw):
            if ch == '"':
                instr = not instr
            elif not instr and raw.startswith("--", i):
                break
            code += ch
        code = code.rstrip()
        if code.endswith("\\"):
            buf += code[:-1] + " "
            continue
        out.append((buf + code).strip())
        buf = ""
    return [ln for ln in out if ln]


def _probe4_depth(lines):
    """How many blocks (a multi-line `if`, `repeat`, `try`, `switch`) are
    open after LINES, logical lines of one handler. A one-line `if X then
    statement` opens none; `else`, `catch` and `case` neither open nor
    close. Enough for rstSectionHead, whose only blocks are these."""
    depth = 0
    for ln in lines:
        low = ln.lower()
        word = low.split()[0]
        if word == "end" and low.split()[1:2] in (["if"], ["repeat"],
                                                  ["try"], ["switch"]):
            depth -= 1
        elif word in ("else", "catch", "case", "default", "finally"):
            continue
        elif ((word == "if" and low.endswith(" then"))
              or word in ("repeat", "try", "switch")):
            depth += 1
    return depth


def probe4_shape(text):
    """What is wrong with the probe-4 line and its handler in TEXT (the
    harness source); an empty list when nothing is."""
    bad = []
    heads = _SECTION_HEAD_RX.findall(text)
    if len(heads) != 1:
        return ["expected one rstSectionHead, found %d" % len(heads)]
    head = _probe4_logical(heads[0])
    lines = [ln for ln in head if PROBE4_PREFIX in ln]
    if len(lines) != 1:
        bad.append("expected ONE statement in rstSectionHead carrying %r, "
                   "found %d" % (PROBE4_PREFIX, len(lines)))
    else:
        line = lines[0]
        # at the handler's top level, as probes 1-3 are: inside an `if` (or
        # any block) a run that reaches the section can skip the line whole
        depth = _probe4_depth(head[1:head.index(line)])
        if depth != 0:
            bad.append("the probe-4 statement sits inside %d open block(s) "
                       "of rstSectionHead, not at its top level" % depth)
        if not (line.startswith('put "') and
                line.endswith("& return after sLog")):
            bad.append("the probe-4 statement is not one `put ... & return "
                       "after sLog` (a printed line)")
        if PROBE4_PREDICTED not in line:
            bad.append("the probe-4 line does not print the source's "
                       "prediction %s" % PROBE4_PREDICTED)
        calls = re.findall(r'\brstTextProbe\((\d+)\)', line)
        if calls != [str(n) for n, _e, _f in PROBE4_ITEMS]:
            bad.append("the probe-4 line reads items %s, not 1 to 6 in "
                       "order" % ",".join(calls))
        if _PROBE4_COUNTED_RX.search(line):
            bad.append("the probe-4 line calls a counting handler")
    fns = _PROBE4_FN_RX.findall(text)
    if len(fns) != 1:
        bad.append("expected ONE `private function rstTextProbe pItem`, "
                   "found %d" % len(fns))
        return bad
    body = _probe4_logical(fns[0])[1:-1]
    if _PROBE4_COUNTED_RX.search("\n".join(body)):
        bad.append("rstTextProbe touches a counter or a counting handler")
    low = [ln.lower() for ln in body]
    if low.count("try") != 1 or low.count("end try") != 1 \
            or low.count("catch terr") != 1:
        bad.append("rstTextProbe is not ONE try / catch tErr / end try")
        return bad
    t, c, e = low.index("try"), low.index("catch terr"), low.index("end try")
    before, inside, catch, after = (body[:t], body[t + 1:c], body[c + 1:e],
                                    body[e + 1:])
    if any(re.search(r'\bis\b|[<>=]', ln) for ln in before + after
           if not ln.lower().startswith("local ")):
        bad.append("rstTextProbe compares outside its try")
    if after != ["return tOut"]:
        bad.append("rstTextProbe does not end `end try` / `return tOut`")
    if catch != ['replace return with " " in tErr',
                 'replace comma with ";" in tErr',
                 'put "threw:" && tErr into tOut']:
        bad.append("rstTextProbe's catch does not print the throw's text "
                   "on the line (returns to spaces, commas to semicolons)")
    branches = [ln for ln in inside
                if re.match(r'(else )?if pItem is \d+ then$', ln)]
    want = ["if pItem is 1 then"] + ["else if pItem is %d then" % n
                                     for n, _e, _f in PROBE4_ITEMS[1:]]
    if branches != want:
        bad.append("rstTextProbe's branches are %r, not items 1 to 6 in "
                   "order" % branches)
    else:
        marks = [inside.index(b) for b in branches] + [len(inside)]
        for (n, expr, _frag), lo, hi in zip(PROBE4_ITEMS, marks, marks[1:]):
            puts = [ln for ln in inside[lo + 1:hi]
                    if ln.startswith("put (") and ln.endswith(" into tOut")]
            if puts != ["put %s into tOut" % expr]:
                bad.append("item %d does not compare %s into tOut (%r)"
                           % (n, expr, puts))
        if marks[0] != 0 or inside[-1:] != ["end if"]:
            bad.append("rstTextProbe's try holds more than the six branches "
                       "(it must open with item 1's `if` and close with "
                       "`end if`)")
        else:
            marks[-1] = len(inside) - 1
            for n, lo, hi in zip(sorted(PROBE4_BODIES), marks, marks[1:]):
                if inside[lo + 1:hi] != PROBE4_BODIES[n]:
                    bad.append("item %d's statements are %r, not exactly %r"
                               % (n, inside[lo + 1:hi], PROBE4_BODIES[n]))
    return bad


def _probe4_seeds(text, fail):
    """Seeded copies of TEXT, each a way the line could silently lose what
    it reads: (text, what was seeded, what the shape checker must say)."""
    def swap(old, new, why, says):
        if text.count(old) != 1:
            fail("tier 1e's fixture expects %r exactly once in the harness, "
                 "and found %d; without it the shape checker goes untested"
                 % (old, text.count(old)))
        return text.replace(old, new), why, says

    seeds = [
        swap('rstTextProbe(3) & "," & ', "",
             "an item dropped from the line", "reads items 1,2,4,5,6"),
        swap("numeric compare probe 4 (diagnostic;",
             "numeric compare probe 4 (",
             "the diagnostic prefix dropped", "found 0"),
        swap("reads true,?,?,?,false,? where", "reads true,true where",
             "the printed prediction changed", "source's prediction"),
        swap('put ("0x1.8" is "1.5") into tOut',
             'put ("0x.8" is "0.5") into tOut',
             "item 6 swapped back to the row's form, which the interpreter "
             "answers", "item 6 does not compare"),
        swap('      put "threw:" && tErr into tOut',
             '      throw tErr',
             "a throw no longer printed on the line",
             "catch does not print"),
        swap("   put empty into tOut\n   try\n",
             '   put empty into tOut\n   put ("inf" is "1e999") into tOut\n'
             "   try\n",
             "a comparison outside the try, where a throw ends the harness",
             "compares outside its try"),
        swap("   return tOut\nend rstTextProbe",
             '   rstCheck (tOut is not empty), "probe 4"\n'
             "   return tOut\nend rstTextProbe",
             "the diagnostic counted as a check",
             "touches a counter or a counting handler"),
        # the review's three (2026-09-26): each passed this tier green, and
        # each changes what an engine prints while the interpreter still
        # refuses every item
        swap('         put ("inf" is "1e999") into tOut\n',
             '         put ("inf" is "1e999") into tOut\n'
             '         put "true" into tOut\n',
             "item 2's answer overwritten after its comparison",
             "item 2's statements"),
        swap('         put "na" into tB\n         put "n" after tB\n',
             '         put tA into tB\n',
             "item 3's NaN pair made ONE value, which the engine answers "
             "true before it reads either", "item 3's statements"),
        swap(PROBE4_OPEN, '   if the platform is "none" then\n' + PROBE4_OPEN,
             "the line moved inside an `if`", "not at its top level"),
    ]
    # the last seed is half built: its `if` closes after the statement
    last, why, says = seeds.pop()
    if last.count(PROBE4_CLOSE) != 1:
        fail("tier 1e's fixture expects %r exactly once in the harness, "
             "and found %d; without it the shape checker goes untested"
             % (PROBE4_CLOSE, last.count(PROBE4_CLOSE)))
    seeds.append((last.replace(PROBE4_CLOSE, PROBE4_CLOSE + "   end if\n"),
                  why, says))
    return seeds


def check_probe4(c, fail):
    c.note("tier 1e: the harness's fourth numeric compare probe (the text "
           "forms engine note 2.11 does not establish)")
    with open(HARNESS, "r", encoding="utf-8") as fh:
        text = fh.read()
    for seeded, why, says in _probe4_seeds(text, fail):
        c.ck("fixture: the shape check refuses a seeded copy with %s, "
             "saying so" % why,
             any(says in problem for problem in probe4_shape(seeded)), True)
    c.ck("the probe-4 line: one printed line of six items in order at "
         "rstSectionHead's top level, the diagnostic prefix and the "
         "source's prediction %s, each item inside rstTextProbe's try and "
         "built exactly as pinned, nothing counted" % PROBE4_PREDICTED,
         probe4_shape(text), [])
    fns = _PROBE4_FN_RX.findall(text)
    if len(fns) != 1:
        return
    # numToCodepoint names a Unicode code point (riptide's runner models it
    # the same way); installed for this tier only
    was = LCS.HASHES.get("numtocodepoint")
    LCS.HASHES["numtocodepoint"] = lambda a: chr(int(LCS._n(a[0])))
    try:
        probe = LCS.Interp(fns[0])
        for n, expr, frag in PROBE4_ITEMS:
            try:
                got = "answered %s" % (LCS._disp(
                    probe.call("rstTextProbe", [n])),)
            except LCS.Indistinct as exc:
                msg = str(exc)
                got = ("refused" if "2.11" in msg and frag in msg
                       else "refused, but naming neither 2.11 nor %s: %s"
                       % (frag, msg[:160]))
            c.ck("item %d, %s: the plain interpreter REFUSES it (the "
                 "engine's reading is owed; teach the interpreter from it)"
                 % (n, expr), got, "refused")
        c.ck("an item past 6 reads empty and never throws",
             probe.call("rstTextProbe", [7]), "")
        thrower = LCS.Interp(fns[0].replace(
            'put ("0x10" is "16") into tOut',
            'throw "seeded" & return & "a, b"'))
        c.ck("a throw inside an item prints its text in the item's place, "
             "on one line and with no comma",
             thrower.call("rstTextProbe", [1]), "threw: seeded a; b")
        swapped = LCS.Interp(fns[0].replace('("0x1.8" is "1.5")',
                                            '("0x.8" is "0.5")'))
        c.ck("fixture: the row's \"0x.8\" is \"0.5\" is ANSWERED (false: "
             "text before strtod), so the line reads the refused sibling",
             str(LCS._disp(swapped.call("rstTextProbe", [6]))), "false")
    finally:
        if was is None:
            LCS.HASHES.pop("numtocodepoint", None)
        else:
            LCS.HASHES["numtocodepoint"] = was


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
    check_seq_order(c, ip, src, fail)
    check_probe4(c, fail)
    check_capacity_arithmetic(c, ip)
    if install_coin_natives():
        check_composed(c, ip, V)
        check_seq_order_bridge(c, ip, src, fail)
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
