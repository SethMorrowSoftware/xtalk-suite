#!/usr/bin/env python3
"""check-script-vectors.py - run the SHIPPED src/coinxt.livecodescript against
the published vectors, and check its constants against the reference.

WHY THIS EXISTS, AND WHAT IT IS WORTH. Phase 3 is pure LiveCodeScript, and OXT
cannot compile or run a .livecodescript headlessly. Every other layer of CoinXT
has something that executes it before a human sees it - the shim has
tools/coin-kat.py, the binding has the ASan self-test and the committed-library
driver in CI - and the encoders had nothing. That is a bad gap to leave in
Base58Check and bech32 specifically: a transcription slip in an alphabet or a
checksum constant does not crash, it produces a VALID-LOOKING WRONG ADDRESS.

So this runs the real file. tools/lcs-interp.py interprets the LiveCodeScript
subset the encoders are written in, the hash handlers they call are supplied by
the REAL native library through ctypes, and the answers are compared against
tools/coin_reference.py, which reproduces the published vectors independently.

WHAT IT DOES NOT DO. It does not replace the OXT pass and it promotes nothing
out of "verified statically". The interpreter is an approximation of the engine:
it models the documented semantics of the subset used and refuses everything
else, but only a real engine settles parser behaviour. What this buys is that a
LOGIC error is found here, in CI, instead of in a scarce engine session.

Two tiers, so it is useful in both environments:
  1. CONSTANTS, always, no compiler needed. The alphabets, the generator
     constants, the bech32m constant and the version bytes are extracted from
     the script text and compared against the reference.
  2. VECTORS, when a C compiler is available: the whole encoder surface driven
     through the interpreter against BIP-173, BIP-350, EIP-55, the RLP
     yellow-paper examples and a Base58Check worked example.
A missing compiler SKIPS tier 2 loudly; it never passes silently.

IT IS SLOW, AND THAT IS THE PRICE, NOT A DEFECT. Tier 2 takes a couple of
minutes, because it interprets the real file statement by statement and phase 4
does a lot of statements: a 24-word mnemonic round trip alone is a binary search
per word, and an xprv is base58 long division over 82 bytes. Profiling shows no
hot spot to fix - the cost is spread evenly over the expression parser, which is
what "runs the real text" means. Do not trade vectors away for seconds here; in
a money library the vectors are the product.

Usage:
  python3 tools/check-script-vectors.py            # per-check detail
  python3 tools/check-script-vectors.py --check    # terse
"""

import ctypes
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(ROOT, "src", "coinxt.livecodescript")
NATIVE = os.path.join(ROOT, "native")
VENDOR = os.path.join(NATIVE, "vendor")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


REF = _load("coin_reference", os.path.join(HERE, "coin_reference.py"))
LCS = _load("lcs_interp", os.path.join(HERE, "lcs-interp.py"))


class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.problems = []
        self.count = 0

    def ck(self, name, got, want):
        self.count += 1
        if got != want:
            self.problems.append(f"{name}\n      got  {got!r}\n      want {want!r}")
        elif not self.terse:
            print(f"  ok   {name}")

    def note(self, text):
        if not self.terse:
            print(text)


# --------------------------------------------------------------------- tier 0
def check_interp_model(c):
    """Pin the interpreter's chunk semantics to the engine-observed facts.

    The engine ignores ONE trailing delimiter when it counts chunks, and the
    2026-08-10 engine pass proved what happens when the model disagrees: the
    "m/" negative vector passed against an interpreter in which the check
    fires, while the engine never ran it. Now that cxHdDerivePath refuses a
    trailing separator outright, no script vector would notice the model
    regressing back to a bare split() - so the rule is pinned HERE, directly,
    against the facts the engine showed.
    """
    c.note("tier 0: the interpreter's chunk model (engine-observed 2026-08-10)")
    ip = LCS.Interp("")

    def ev(expr, **env):
        return LCS._Expr(ip, dict(env)).parse(expr)

    c.ck('one trailing delimiter is invisible: "m," is ONE item',
         ev('the number of items of "m,"'), 1)
    c.ck('only one is: "a,," is two items', ev('the number of items of "a,,"'), 2)
    c.ck('"," is one (empty) item', ev('the number of items of ","'), 1)
    c.ck("the empty string has zero items", ev('the number of items of ""'), 0)
    c.ck('there is no empty second item of "m,"', ev('item 2 of "m,"'), "")
    c.ck("lines follow the same rule", ev("the number of lines of t", t="a\n"), 1)


# --------------------------------------------------------------------- tier 1
def check_constants(c, text):
    """The tables that are transcribed by hand, compared against the reference.

    An alphabet is 58 characters in a specific order that IS the digit mapping;
    one transposed pair silently decodes to a different number. This is the
    cheapest possible check for the likeliest possible bug.
    """
    c.note("constants (no compiler needed)")
    consts = dict(re.findall(r'^constant\s+(\w+)\s*=\s*"([^"]*)"', text, re.M))
    nums = dict(re.findall(r'^constant\s+(\w+)\s*=\s*(-?\d+)\s*$', text, re.M))
    c.ck("the Base58 alphabet matches the reference",
         consts.get("kCxBase58Alphabet"), REF.B58)
    c.ck("the bech32 charset matches the reference",
         consts.get("kCxBech32Charset"), REF.CHARSET)
    c.ck("the hex digits are lowercase 0-f", consts.get("kCxHexDigits"), "0123456789abcdef")
    c.ck("the bech32m constant matches BIP-350",
         int(nums.get("kCxBech32mConst", -1)), REF.BECH32M_CONST)
    c.ck("the bech32 length cap is 90", int(nums.get("kCxBech32MaxLen", -1)), 90)
    c.ck("the mainnet P2PKH version byte is 0", int(nums.get("kCxVersionP2PKH", -1)), 0)
    c.ck("the mainnet HRP is bc", consts.get("kCxHrpMainnet"), "bc")
    # The polymod generator constants live inline, not as named constants.
    gen = re.search(r'put\s+"([\d,]+)"\s+into\s+tGen', text)
    want = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    c.ck("the bech32 polymod generator constants match BIP-173",
         [int(x) for x in gen.group(1).split(",")] if gen else None, want)


# --------------------------------------------------------------------- tier 2
def find_cc():
    for cc in (os.environ.get("CC"), "cc", "gcc", "clang"):
        if not cc:
            continue
        try:
            subprocess.run([cc, "--version"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=True)
            return cc
        except (OSError, subprocess.CalledProcessError):
            continue
    return None


def vendor_sources():
    with open(os.path.join(NATIVE, "build.sh"), encoding="utf-8") as fh:
        m = re.search(r'vendor_src="([^"]*)"', fh.read(), re.S)
    if m is None:
        raise SystemExit("check-script-vectors: could not read vendor_src from native/build.sh")
    return [os.path.join(VENDOR, p.strip()[len("$ven/"):])
            for p in m.group(1).replace("\\\n", " ").split() if p.strip()]


def build(cc, out):
    subprocess.run([cc, "-O2", "-isystem", VENDOR, "-fPIC", "-shared",
                    os.path.join(NATIVE, "coinxt.c"), *vendor_sources(), "-o", out],
                   check=True)


def wire_hashes(lib):
    """The .lcb handlers the script calls, supplied by the real shim. What is
    under test is the script's own logic over genuine crypto."""
    for fn in ("cnx_sha256", "cnx_ripemd160", "cnx_keccak256"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lib.cnx_pubkey_decompress.restype = ctypes.c_int
    lib.cnx_pubkey_decompress.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                          ctypes.c_char_p, ctypes.c_size_t]

    def digest(fn, n):
        def go(args):
            data = to_bytes(args[0])
            out = ctypes.create_string_buffer(n)
            if getattr(lib, fn)(data, len(data), out) != 0:
                raise RuntimeError(f"{fn} failed")
            return to_str(out.raw[:n])
        return go

    LCS.HASHES["cxsha256"] = digest("cnx_sha256", 32)
    LCS.HASHES["cxripemd160"] = digest("cnx_ripemd160", 20)
    LCS.HASHES["cxkeccak256"] = digest("cnx_keccak256", 32)

    def decompress(args):
        data = to_bytes(args[0])
        out = ctypes.create_string_buffer(65)
        if lib.cnx_pubkey_decompress(data, len(data), out, 65) != 0:
            raise RuntimeError("cnx_pubkey_decompress failed")
        return to_str(out.raw[:65])

    LCS.HASHES["cxpubkeydecompress"] = decompress

    # ---- phase 4: what the HD layer calls into the shim for -----------------
    lib.cnx_hmac_sha512.restype = ctypes.c_int
    lib.cnx_hmac_sha512.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                    ctypes.c_char_p, ctypes.c_size_t,
                                    ctypes.c_char_p]
    lib.cnx_pbkdf2_hmac_sha512.restype = ctypes.c_int
    lib.cnx_pbkdf2_hmac_sha512.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_uint32, ctypes.c_char_p,
                                           ctypes.c_size_t]
    lib.cnx_pubkey_from_seckey.restype = ctypes.c_int
    lib.cnx_pubkey_from_seckey.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_int, ctypes.c_char_p,
                                           ctypes.c_size_t]
    for fn in ("cnx_seckey_tweak_add", "cnx_pubkey_tweak_add"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p,
                      ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_bip39_wordlist.restype = ctypes.c_int
    lib.cnx_bip39_wordlist.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_bip39_wordlist_len.restype = ctypes.c_size_t

    def hmac512(args):
        key, msg = to_bytes(args[0]), to_bytes(args[1])
        out = ctypes.create_string_buffer(64)
        if lib.cnx_hmac_sha512(key, len(key), msg, len(msg), out) != 0:
            raise RuntimeError("cnx_hmac_sha512 failed")
        return to_str(out.raw[:64])

    def pbkdf2(args):
        pw, salt = to_bytes(args[0]), to_bytes(args[1])
        rounds, outlen = int(LCS._n(args[2])), int(LCS._n(args[3]))
        out = ctypes.create_string_buffer(outlen)
        if lib.cnx_pbkdf2_hmac_sha512(pw, len(pw), salt, len(salt), rounds,
                                      out, outlen) != 0:
            raise RuntimeError("cnx_pbkdf2_hmac_sha512 failed")
        return to_str(out.raw[:outlen])

    def publickey(args):
        sk = to_bytes(args[0])
        compressed = str(LCS._disp(args[1])).lower() == "true" if len(args) > 1 else True
        n = 33 if compressed else 65
        out = ctypes.create_string_buffer(n)
        rc = lib.cnx_pubkey_from_seckey(sk, len(sk), 1 if compressed else 0, out, n)
        if rc != 0:
            # The .lcb wrapper throws on a non-zero status; so must this, or
            # the script's own error paths would never be exercised.
            raise LCS.Thrown(f"CoinXT: cxPublicKey: status {rc}")
        return to_str(out.raw[:n])

    def tweak(fn, n):
        def go(args):
            a, t = to_bytes(args[0]), to_bytes(args[1])
            out = ctypes.create_string_buffer(n)
            rc = getattr(lib, fn)(a, len(a), t, len(t), out, n)
            if rc != 0:
                raise LCS.Thrown(f"CoinXT: {fn}: status {rc}")
            return to_str(out.raw[:n])
        return go

    def wordlist(_args):
        n = lib.cnx_bip39_wordlist_len()
        out = ctypes.create_string_buffer(n)
        if lib.cnx_bip39_wordlist(out, n) != 0:
            raise RuntimeError("cnx_bip39_wordlist failed")
        return to_str(out.raw[:n])

    LCS.HASHES["cxhmacsha512"] = hmac512
    LCS.HASHES["cxpbkdf2hmacsha512"] = pbkdf2
    LCS.HASHES["cxpublickey"] = publickey
    LCS.HASHES["cxseckeytweakadd"] = tweak("cnx_seckey_tweak_add", 32)
    LCS.HASHES["cxpubkeytweakadd"] = tweak("cnx_pubkey_tweak_add", 33)
    LCS.HASHES["cxbip39wordlist"] = wordlist


def to_bytes(s):
    return bytes(ord(ch) & 0xFF for ch in str(LCS._disp(s)))


def to_str(b):
    return "".join(chr(x) for x in b)


G33 = bytes.fromhex("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
G65 = bytes.fromhex("0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
                    "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8")

BECH32_VALID = [
    "A12UEL5L", "a12uel5l",
    "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
    "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
    "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
    "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
    "?1ezyfcl",
]
BECH32_INVALID = [
    ("an HRP character out of range", "\x201nwldj5"),
    ("an HRP character 0x7f", "\x7f1axkwrx"),
    ("longer than 90 characters",
     "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx"),
    ("no separator", "pzry9x0s0muk"),
    ("an empty HRP", "1pzry9x0s0muk"),
    ("a data character outside the charset", "x1b4n0q5v"),
    ("a checksum shorter than six characters", "li1dgmt3"),
    ("a checksum computed over an uppercase HRP", "A1G7SGD8"),
    ("an empty HRP (2)", "10a06t8"),
    ("an empty HRP (3)", "1qzzfhee"),
]
SEGWIT = [
    ("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4", "bc", 0,
     "751e76e8199196d454941c45d1b3a323f1433bd6"),
    ("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", "tb", 0,
     "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262"),
    ("bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y", "bc", 1,
     "751e76e8199196d454941c45d1b3a323f1433bd6751e76e8199196d454941c45d1b3a323f1433bd6"),
    ("BC1SW50QGDZ25J", "bc", 16, "751e"),
    ("bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", "bc", 2, "751e76e8199196d454941c45d1b3a323"),
    ("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", "bc", 1,
     "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
]
# BIP-350's rule is a PAIRING and has two halves. Testing only the v0 half
# leaves the other rule untested, which mutation testing caught: disabling the
# "v1+ must be bech32m" branch changed nothing observable. The v1-with-bech32
# case is CONSTRUCTED from the reference rather than quoted, so it is provably
# the thing being described - a valid v1 program under the WRONG checksum.
def _wrong_spec(version, prog_hex, spec):
    """A VALID address body under the WRONG checksum algorithm for its witness
    version. Both halves have to be constructed rather than quoted, and the
    reason is worth recording: BIP-350's published invalid vector for this case
    (BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T5) has a checksum that verifies as
    NEITHER bech32 nor bech32m, so a decoder rejects it at the checksum and never
    reaches the version/spec pairing at all. Mutation testing caught exactly
    that: disabling the pairing rule changed nothing observable. These two do
    reach it, because their checksums are correct - for the wrong algorithm.
    """
    prog = bytes.fromhex(prog_hex)
    return REF.bech32_encode("bc", [version] + REF.convertbits(prog, 8, 5), spec)


SEGWIT_INVALID = [
    # The published vector, kept: it is a real BIP-350 invalid case (bad checksum).
    ("a corrupt version 0 address", "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T5"),
    # And the two that actually exercise the BIP-350 pairing rule.
    ("a version 0 address carrying a VALID bech32m checksum",
     _wrong_spec(0, "751e76e8199196d454941c45d1b3a323f1433bd6", "bech32m")),
    ("a version 1 address carrying a VALID bech32 checksum",
     _wrong_spec(1, "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", "bech32")),
    ("a mixed-case address", "bc1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4"),
    ("a witness version above 16", "BC130XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ7ZWS8R"),
    ("an empty data section", "bc1gmk9yu"),
]
EIP55 = ["0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
         "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
         "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
         "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"]

# The entropy column of the official BIP-39 english vectors (trezor's
# english.json). Only the entropy is written down: the mnemonic and the seed
# come from REF, which derives them and self-checks the wordlist against the
# SHA-256 BIP-39 publishes. Copying 14 mnemonics and 14 seeds by hand would add
# 28 chances to make a transcription error and zero checking power.
BIP39_ENTROPY = [
    "00000000000000000000000000000000", "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
    "80808080808080808080808080808080", "ffffffffffffffffffffffffffffffff",
    "000000000000000000000000000000000000000000000000",
    "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
    "808080808080808080808080808080808080808080808080",
    "0000000000000000000000000000000000000000000000000000000000000000",
    "8080808080808080808080808080808080808080808080808080808080808080",
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    "9e885d952ad362caeb4efe34a8e91bd2", "c0ba5a8e914111210f2bd131f3d5e08d",
    "23db8160a31d3e0dca3688ed941adbf3",
    "066dca1a2bb7e8a1db2832148ce9933eea0f3ac9548d793112d9a95c9407efad",
]

# BIP-32's own test vectors 1, 2 and 3, written out in full because THESE are
# the published artifact - the whole point is that CoinXT's serialization
# matches the strings in the BIP, not that it matches our own model twice.
# Vector 3 is in the BIP specifically because its master private key has a
# leading zero byte, which is where "strip leading zeros" bugs surface.
BIP32_VECTORS = [
    ("000102030405060708090a0b0c0d0e0f", [
        ("m",
         "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi",
         "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"),
        ("m/0'",
         "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7",
         "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"),
        ("m/0'/1",
         "xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs",
         "xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ"),
        ("m/0'/1/2'/2/1000000000",
         "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76",
         "xpub6H1LXWLaKsWFhvm6RVpEL9P4KfRZSW7abD2ttkWP3SSQvnyA8FSVqNTEcYFgJS2UaFcxupHiYkro49S8yGasTvXEYBVPamhGW6cFJodrTHy"),
    ]),
    ("fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a2"
     "9f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542", [
        ("m",
         "xprv9s21ZrQH143K31xYSDQpPDxsXRTUcvj2iNHm5NUtrGiGG5e2DtALGdso3pGz6ssrdK4PFmM8NSpSBHNqPqm55Qn3LqFtT2emdEXVYsCzC2U",
         "xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB"),
    ]),
    ("4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4ac"
     "ba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be", [
        ("m",
         "xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6",
         "xpub661MyMwAqRbcEZVB4dScxMAdx6d4nFc9nvyvH3v4gJL378CSRZiYmhRoP7mBy6gSPSCYk6SzXPTf3ND1cZAceL7SfJ1Z3GC8vBgp2epUt13"),
    ]),
]

# The published addresses for the "abandon ... about" test mnemonic - the most
# widely cross-checked wallet in existence, and the closest thing to an
# interoperability oracle that does not require a wallet to hand. The m/84'
# entries are BIP-84's own test vectors.
BIP44_ADDRESSES = [
    ("m/44'/0'/0'/0/0", "p2pkh", "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"),
    ("m/84'/0'/0'/0/0", "p2wpkh", "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"),
    ("m/84'/0'/0'/0/1", "p2wpkh", "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g"),
    ("m/84'/0'/0'/1/0", "p2wpkh", "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el"),
    ("m/44'/60'/0'/0/0", "eth", "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"),
]


def _even_hex(n):
    """A non-negative integer as minimal big-endian hex, padded to whole bytes -
    the shape a wei-scale field crosses to the script as (cxHexDecode wants an
    even length; cxStripLeadingZeroBytes then makes it canonical for RLP)."""
    h = format(n, "x")
    return ("0" + h) if len(h) % 2 else h


def _phase5_fixture():
    """Everything the phase-5 executing checks consume, derived once from the
    oracle. The ECDSA signatures are RFC 6979 deterministic, so the oracle's
    exact (r, s) can be fed straight to the encoders here - what is under test is
    the SCRIPT's DER / sighash / varint / witness / RLP / transaction
    serialization over genuine crypto, not a signer in the interpreter."""
    ver, lock = 1, 17
    txid0 = "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff"
    txid1 = "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef"
    op0 = REF.btc_outpoint(bytes.fromhex(txid0), 0)
    op1 = REF.btc_outpoint(bytes.fromhex(txid1), 1)
    seq0, seq1 = 0xffffffee, 0xffffffff
    spk0 = "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
    spk1 = "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
    out0 = REF.btc_output(0x06b22c20, bytes.fromhex(spk0))
    out1 = REF.btc_output(0x0d519390, bytes.fromhex(spk1))
    sc0 = "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac"
    sc1 = "76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac"
    ins, outs = [(op0, seq0), (op1, seq1)], [out0, out1]
    d0 = REF.btc_sighash_legacy(ver, ins, outs, 0, bytes.fromhex(sc0), lock)
    d1 = REF.btc_sighash_segwit(ver, ins, outs, 1, bytes.fromhex(sc1), 0x23c34600, lock)
    r0, s0, _ = REF.ecdsa_sign_recoverable(
        bytes.fromhex("bbc27228ddcb9209d7fd6f36b02f7dfa6252af40bb2f1cbc7a557da8027ff866"), d0)
    r1, s1, _ = REF.ecdsa_sign_recoverable(
        bytes.fromhex("619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9"), d1)
    sig0 = REF.der_encode(r0, s0) + b"\x01"
    sig1 = REF.der_encode(r1, s1) + b"\x01"
    pub1 = "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
    wit1 = (REF.varint(2) + REF.varint(len(sig1)) + sig1
            + REF.varint(len(pub1) // 2) + bytes.fromhex(pub1))
    scriptsig0 = (bytes([len(sig0)]) + sig0).hex()
    raw, txid = REF.btc_tx(ver, ins, outs, lock,
                           [bytes([len(sig0)]) + sig0, b""],
                           [[], [sig1, bytes.fromhex(pub1)]])
    assert raw.hex() == REF.BIP143_SIGNED_TX, "fixture drifted from the oracle"
    to, sk46 = "3535353535353535353535353535353535353535", bytes.fromhex("46" * 32)
    h155 = REF.eth_legacy_sighash(9, 20 * 10**9, 21000, bytes.fromhex(to), 10**18, b"", 1)
    r155, s155, recid155 = REF.ecdsa_sign_recoverable(sk46, h155)
    raw155, txhash155 = REF.eth_legacy_encode(9, 20 * 10**9, 21000, bytes.fromhex(to),
                                              10**18, b"", 1, sk46)
    h1559 = REF.eth_1559_sighash(1, 0, 10**9, 20 * 10**9, 21000, bytes.fromhex(to), 10**17, b"")
    r1559, s1559, recid1559 = REF.ecdsa_sign_recoverable(sk46, h1559)
    raw1559, txhash1559 = REF.eth_1559_encode(1, 0, 10**9, 20 * 10**9, 21000,
                                              bytes.fromhex(to), 10**17, b"", sk46)
    return {
        "txid0": txid0, "op0": op0, "spk0": spk0,
        "outpoints": op0.hex() + "," + op1.hex(), "sequences": f"{seq0},{seq1}",
        "outputs": out0.hex() + "," + out1.hex(), "sc0": sc0, "sc1": sc1,
        "d0": d0, "d1": d1, "rs0": (r0, s0),
        "compact0": r0.to_bytes(32, "big") + s0.to_bytes(32, "big"),
        "witness1": sig1.hex() + "," + pub1, "wit1": wit1,
        # scriptSigs = [scriptsig0, ""] and witnesses = ["", wit1]: the
        # trailing-empty and leading-empty shapes the reference tx needs.
        "scriptsigs": scriptsig0 + ",", "witnesses": "," + wit1.hex(), "txid": txid,
        "ethTo": to, "ethGasPrice": _even_hex(20 * 10**9), "ethValue": _even_hex(10**18),
        "h155": h155, "recid155": recid155,
        "r155hex": r155.to_bytes(32, "big").hex(), "s155hex": s155.to_bytes(32, "big").hex(),
        "raw155": raw155, "txhash155": txhash155,
        "m1559prio": _even_hex(10**9), "m1559fee": _even_hex(20 * 10**9),
        "v1559": _even_hex(10**17), "h1559": h1559, "recid1559": recid1559,
        "r1559hex": r1559.to_bytes(32, "big").hex(), "s1559hex": s1559.to_bytes(32, "big").hex(),
        "raw1559": raw1559, "txhash1559": txhash1559,
    }


def check_vectors(c, ip):
    def call(fn, *args):
        return ip.call(fn, [to_str(a) if isinstance(a, (bytes, bytearray)) else a
                            for a in args])

    def throws(fn, *args):
        try:
            call(fn, *args)
            return False
        except LCS.Thrown:
            return True

    c.note("\nhex")
    c.ck("cxHexEncode", call("cxHexEncode", bytes.fromhex("00ff10ab")), "00ff10ab")
    c.ck("cxHexDecode accepts mixed case",
         to_bytes(call("cxHexDecode", "00FF10ab")).hex(), "00ff10ab")
    c.ck("cxHexDecode rejects an odd length", throws("cxHexDecode", "abc"), True)
    c.ck("cxHexDecode rejects a non-hex character", throws("cxHexDecode", "zz"), True)

    c.note("\ncomposed hashes")
    for data in (b"", b"abc", b"hello world"):
        c.ck(f"cxHash160({data!r})", to_bytes(call("cxHash160", data)).hex(),
             REF.hash160(data).hex())
        c.ck(f"cxHash256({data!r})", to_bytes(call("cxHash256", data)).hex(),
             REF.hash256(data).hex())

    c.note("\nBase58Check")
    payload = bytes.fromhex("00010966776006953D5567439E5E39F86A0D273BEE")
    c.ck("encodes the worked example", call("cxBase58CheckEncode", payload),
         "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM")
    c.ck("decodes it back",
         to_bytes(call("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM")).hex(),
         payload.hex())
    c.ck("rejects a corrupt checksum",
         throws("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvN"), True)
    c.ck("rejects a character outside the alphabet",
         throws("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtj0O"), True)
    for n in (1, 2, 5):
        p = bytes(n) + bytes.fromhex("deadbeef")
        c.ck(f"preserves {n} leading zero byte(s) as leading ones",
             call("cxBase58CheckEncode", p), REF.b58check_encode(p))

    c.note("\nBIP-173 valid strings")
    for s in BECH32_VALID:
        c.ck(f"accepts {s[:32]}", throws("cxBech32DecodeValues", s), False)
    c.note("\nBIP-173 invalid strings")
    for name, s in BECH32_INVALID:
        c.ck(f"rejects {name}", throws("cxBech32DecodeValues", s), True)

    c.note("\nBIP-173 / BIP-350 SegWit addresses")
    for addr, hrp, ver, prog in SEGWIT:
        c.ck(f"encodes {addr[:24]}",
             call("cxSegwitAddressEncode", hrp, ver, bytes.fromhex(prog)), addr.lower())
        got = ip.call("cxSegwitAddressDecode", [hrp, addr])
        c.ck(f"decodes {addr[:24]}",
             (int(LCS._n(got["version"])), to_bytes(got["program"]).hex()), (ver, prog))
    c.note("\nBIP-350 invalid SegWit addresses")
    for name, addr in SEGWIT_INVALID:
        c.ck(f"rejects {name}", throws("cxSegwitAddressDecode", "bc", addr), True)

    c.note("\naddresses from the generator G (private key 1)")
    c.ck("cxBtcAddressP2PKH", call("cxBtcAddressP2PKH", G33), REF.p2pkh(G33))
    c.ck("cxBtcAddressP2WPKH is the published BIP-173 vector",
         call("cxBtcAddressP2WPKH", G33), "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    c.ck("cxBtcAddressP2TR is the published BIP-350 vector",
         call("cxBtcAddressP2TR", G65[1:33]),
         "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0")
    c.ck("cxBtcAddressP2WPKH refuses an uncompressed key",
         throws("cxBtcAddressP2WPKH", G65), True)
    c.ck("cxBtcAddressP2TR refuses a 33-byte key", throws("cxBtcAddressP2TR", G33), True)
    c.ck("cxEthAddress from a compressed key", call("cxEthAddress", G33),
         REF.eth_address(G65))
    c.ck("cxEthAddress from an uncompressed key", call("cxEthAddress", G65),
         REF.eth_address(G65))

    c.note("\nEIP-55")
    for a in EIP55:
        c.ck(f"checksums {a[:12]}", call("cxEthAddressChecksum", a.lower()), a)
        c.ck(f"recognises {a[:12]} as checksummed",
             LCS._disp(call("cxEthAddressIsChecksummed", a)), "true")
    c.ck("reports an all-lowercase address as NOT checksummed",
         LCS._disp(call("cxEthAddressIsChecksummed",
                        "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")), "false")

    c.note("\nRLP")
    lorem = b"Lorem ipsum dolor sit amet, consectetur adipisicing elit"
    for data, want in ((b"dog", "83646f67"), (b"", "80"), (b"\x0f", "0f"),
                       (b"\x04\x00", "820400"), (lorem, REF.rlp_encode(lorem).hex())):
        c.ck(f"encodes {data[:20]!r}", to_bytes(call("cxRlpEncodeBytes", data)).hex(), want)
    cat_dog = to_bytes(call("cxRlpEncodeBytes", b"cat")) + to_bytes(call("cxRlpEncodeBytes", b"dog"))
    c.ck("encodes the list [cat, dog]",
         to_bytes(call("cxRlpEncodeList", cat_dog)).hex(), "c88363617483646f67")
    c.ck("encodes the empty list", to_bytes(call("cxRlpEncodeList", b"")).hex(), "c0")
    for enc, kind, payload in (("83646f67", "bytes", "646f67"), ("80", "bytes", ""),
                               ("c88363617483646f67", "list", "8363617483646f67"),
                               (REF.rlp_encode(lorem).hex(), "bytes", lorem.hex())):
        got = ip.call("cxRlpDecode", [to_str(bytes.fromhex(enc))])
        c.ck(f"decodes {enc[:14]}", (got["kind"], to_bytes(got["payload"]).hex()),
             (kind, payload))
    c.ck("rejects a single byte below 0x80 wrapped in a length prefix",
         throws("cxRlpDecode", bytes.fromhex("8100")), True)
    c.ck("rejects a leading zero in a long length",
         throws("cxRlpDecode", bytes.fromhex("b90040" + "00" * 64)), True)

    # ---- the regression set ------------------------------------------------
    # One vector per defect an adversarial review found in the code above, each
    # of which the vectors that preceded it could not catch. They are grouped
    # here rather than scattered because what they have in common is the point:
    # every one of them FAILED OPEN - a wrong answer that looked like a right
    # one - which is the only failure mode on this surface that matters.
    c.note("\nfail-closed regressions (one per defect found by review)")

    # EIP-55's whole purpose. The handler used to compare a value with itself
    # (cxEthAddressChecksum lowercases before hashing, so both sides were the
    # same string) and answered true to every mixed-case address. The four
    # positive vectors above could not see it, because a true positive is what
    # a tautology also returns.
    for name, addr in (
            ("one letter's case flipped", "0xfb6916095ca1df60bB79Ce92cE3Ea74c37c5d359"),
            ("the last letter upper-cased", "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"),
            ("every letter's case flipped", "0x5AaEB6053f3e94c9B9a09F33669435e7eF1bEaEd")):
        c.ck(f"a corrupted EIP-55 address is refused ({name})",
             LCS._disp(call("cxEthAddressIsChecksummed", addr)), "false")

    # An in-band error sentinel over arbitrary bytes is always wrong. This is a
    # real bech32m v1 address whose 32-byte witness program begins with the
    # bytes 45 52 52 4F 52, and the decoder used to read that as its own failure
    # string and reject an address this file had just produced.
    prog = b"ERROR" + bytes(range(27))
    addr = call("cxSegwitAddressEncode", "bc", 1, prog)
    c.ck("an address encodes when its program spells ERROR",
         addr, REF.segwit_encode("bc", 1, prog))
    got = ip.call("cxSegwitAddressDecode", ["bc", addr])
    c.ck("  and decodes back to the same program",
         (int(LCS._n(got["version"])), to_bytes(got["program"]).hex()), (1, prog.hex()))

    # hash160 hashes anything, so without a length and prefix check every one of
    # these produced a well-formed, checksummed, permanently unspendable address.
    for name, key in (("an empty key", b""), ("a 20-byte hash", bytes(20)),
                      ("33 bytes tagged 0x04", b"\x04" + bytes(32)),
                      ("65 bytes tagged 0x02", b"\x02" + bytes(64)),
                      ("a 34-byte key", b"\x02" + bytes(33))):
        c.ck(f"cxBtcAddressP2PKH refuses {name}", throws("cxBtcAddressP2PKH", key), True)
    c.ck("cxBtcAddressP2PKH still accepts an uncompressed key",
         call("cxBtcAddressP2PKH", G65), REF.p2pkh(G65))

    # `char (n) of` a 32-character charset returns EMPTY past the end, so an
    # out-of-range value used to emit nothing at all: a string one character
    # short, with a checksum over data that is not in it.
    c.ck("cxBech32EncodeValues refuses a value of 32",
         throws("cxBech32EncodeValues", "bc", "0,32,1", "bech32"), True)
    c.ck("cxBech32EncodeValues refuses a negative value",
         throws("cxBech32EncodeValues", "bc", "0,-1", "bech32"), True)
    c.ck("cxBech32EncodeValues refuses a fractional value",
         throws("cxBech32EncodeValues", "bc", "0,1.5", "bech32"), True)
    # An uppercase HRP used to give a MIXED-case string, which BIP-173 forbids
    # and which this file's own decoder rejects.
    c.ck("an uppercase HRP is refused rather than mixed into the output",
         throws("cxSegwitAddressEncode", "BC", 0, bytes(20)), True)
    c.ck("an empty HRP is refused", throws("cxBech32EncodeValues", "", "0", "bech32"), True)
    c.ck("a result over 90 characters is refused",
         throws("cxBech32EncodeValues", "bc", ",".join(["0"] * 90), "bech32"), True)

    # ---- phase 4 ------------------------------------------------------------
    # These matter more than anything above them, because they are the only
    # part of CoinXT that can be wrong WITHOUT FAILING. A mis-packed mnemonic
    # is still twelve English words; a mis-derived path is still a valid
    # address. Nothing tells the user until the funds are somewhere they
    # cannot reach, so every one of these is a published vector.
    c.note("\nBIP-39 (official Trezor english vectors)")
    for h in BIP39_ENTROPY:
        ent = bytes.fromhex(h)
        want = REF.bip39_mnemonic(ent)
        got = call("cxMnemonicFromEntropy", ent)
        c.ck(f"{len(ent)}-byte entropy {h[:12]} -> {len(want.split())} words", got, want)
        c.ck(f"  and back to entropy", to_bytes(call("cxMnemonicToEntropy", got)).hex(), h)
        c.ck(f"  seed with the TREZOR passphrase",
             to_bytes(call("cxMnemonicToSeed", got, "TREZOR")).hex(),
             REF.bip39_seed(want, "TREZOR").hex())
    twelve = REF.bip39_mnemonic(bytes(16))
    c.ck("an empty passphrase gives the plain seed",
         to_bytes(call("cxMnemonicToSeed", twelve, "")).hex(), REF.bip39_seed(twelve).hex())
    c.ck("cxMnemonicValidate accepts a good mnemonic",
         LCS._disp(call("cxMnemonicValidate", twelve)), "true")
    c.ck("rejects a wrong checksum word",
         LCS._disp(call("cxMnemonicValidate", " ".join(["abandon"] * 12))), "false")
    c.ck("rejects a word outside the list",
         LCS._disp(call("cxMnemonicValidate", " ".join(["zzzz"] * 11 + ["about"]))), "false")
    c.ck("rejects a word count BIP-39 does not define",
         LCS._disp(call("cxMnemonicValidate", " ".join(["abandon"] * 11))), "false")
    c.ck("normalizes tabs, newlines and runs of spaces",
         LCS._disp(call("cxMnemonicValidate", "\t " + twelve.replace(" ", "  ") + "\n")), "true")
    c.ck("cxMnemonicFromEntropy refuses a length BIP-39 does not define",
         throws("cxMnemonicFromEntropy", bytes(17)), True)
    # The wordlist reaches the script through the shim, so check the script's
    # own view of it rather than trusting that the C side got it right.
    # cxBip39Wordlist is an .lcb handler, so it comes from the wired library
    # rather than from the script; go to it the way the script's own calls do.
    wl = to_bytes(LCS.HASHES["cxbip39wordlist"]([]))
    c.ck("the wordlist the script sees is the normative one",
         hashlib.sha256(("\n".join(wl[i:i + 8].decode().rstrip(" ")
                                   for i in range(0, len(wl), 8)) + "\n").encode()).hexdigest(),
         REF.WORDLIST_SHA256)

    c.note("\nBIP-32 (official test vectors 1-3)")
    for seed_hex, paths in BIP32_VECTORS:
        master = call("cxHdFromSeed", bytes.fromhex(seed_hex))
        for path, want_prv, want_pub in paths:
            node = call("cxHdDerivePath", master, path)
            c.ck(f"seed {seed_hex[:8]} {path} xprv", call("cxXprv", node), want_prv)
            c.ck(f"seed {seed_hex[:8]} {path} xpub", call("cxXpub", node), want_pub)
    # Vector 3 exists precisely because its master private key has a leading
    # zero byte, which is where a "strip leading zeros" bignum bug shows up.
    c.note("\nBIP-32 structure")
    master = call("cxHdFromSeed", bytes.fromhex(BIP32_VECTORS[0][0]))
    acct = call("cxHdDerivePath", master, "m/0'")
    watch = call("cxHdNeuter", acct)
    c.ck("cxHdNeuter leaves the source node's private key intact",
         acct["seckey"] != "", True)
    c.ck("a watch-only node derives the same non-hardened child",
         call("cxXpub", call("cxHdDerivePath", watch, "m/1")),
         call("cxXpub", call("cxHdDerivePath", acct, "m/1")))
    c.ck("a watch-only node cannot serialize an xprv",
         throws("cxXprv", watch), True)
    c.ck("a watch-only node cannot derive a hardened child",
         throws("cxHdDerivePath", watch, "m/0'"), True)
    c.ck("h and H are accepted as hardened markers",
         call("cxXprv", call("cxHdDerivePath", master, "m/0h")), call("cxXprv", acct))
    # "m/" and "m/0'/" are the trailing-separator fail-open the 2026-08-10
    # engine pass caught: they only test anything now that lcs-interp counts
    # items the way the engine does (one trailing delimiter is invisible).
    for bad in ("0/1", "m/", "m/0'/", "/", "m/1'2", "m/ 1", "m/1e3", "m/2147483648", "m/1.0"):
        c.ck(f"rejects the path {bad!r}", throws("cxHdDerivePath", master, bad), True)
    c.ck("rejects a seed shorter than 16 bytes", throws("cxHdFromSeed", bytes(15)), True)
    c.ck("rejects a seed longer than 64 bytes", throws("cxHdFromSeed", bytes(65)), True)

    # cxHdDeriveChild is the single CKD step the path walker loops over, and it
    # is public API in its own right. Everything above reaches it only THROUGH
    # cxHdDerivePath, so a defect in argument handling at the public entry
    # point - a hardened index misread, a bad bound - would not show up.
    c.note("\nBIP-32 single-step derivation (cxHdDeriveChild)")
    _, want_h0_prv, _ = BIP32_VECTORS[0][1][1]
    c.ck("one hardened step reaches the published m/0' xprv",
         call("cxXprv", call("cxHdDeriveChild", master, 2147483648)), want_h0_prv)
    c.ck("a normal step agrees with the path walker",
         call("cxXprv", call("cxHdDeriveChild", acct, 1)),
         call("cxXprv", call("cxHdDerivePath", master, "m/0'/1")))
    c.ck("index 0 is not treated as hardened",
         call("cxXprv", call("cxHdDeriveChild", master, 0)),
         call("cxXprv", call("cxHdDerivePath", master, "m/0")))
    c.ck("each step advances the depth by one",
         int(LCS._n(call("cxHdDeriveChild", acct, 1)["depth"])), 2)
    c.ck("rejects an index at or above 2^32",
         throws("cxHdDeriveChild", master, 4294967296), True)
    c.ck("rejects a negative index", throws("cxHdDeriveChild", master, -1), True)
    c.ck("a watch-only node cannot take a hardened step",
         throws("cxHdDeriveChild", watch, 2147483648), True)

    # cxMnemonicNormalize on its own. Every other BIP-39 handler runs it first,
    # so if it were wrong they would all be wrong TOGETHER and would agree with
    # each other - the round trips above would still close.
    c.note("\nBIP-39 normalization (cxMnemonicNormalize)")
    c.ck("strips surrounding whitespace",
         call("cxMnemonicNormalize", "  " + twelve + "  "), twelve)
    c.ck("an already-clean mnemonic is unchanged",
         call("cxMnemonicNormalize", twelve), twelve)
    c.ck("it is idempotent",
         call("cxMnemonicNormalize", call("cxMnemonicNormalize", "  " + twelve + " ")),
         twelve)
    c.ck("tabs, newlines and runs of spaces collapse to single spaces",
         call("cxMnemonicNormalize", "abandon\tabandon\n  abandon "),
         "abandon abandon abandon")
    c.ck("whitespace only normalizes to empty",
         call("cxMnemonicNormalize", "   "), "")
    c.ck("a normalized mnemonic gives the same seed as the clean one",
         to_bytes(call("cxMnemonicToSeed",
                       call("cxMnemonicNormalize", "\n" + twelve + "\t"), "")).hex(),
         REF.bip39_seed(twelve).hex())

    # ---- the itemDelimiter guard ------------------------------------------
    # `item` reads the engine's CURRENT delimiter, and that is GLOBAL MUTABLE
    # STATE (templates/CLAUDE.md rule 5), so an app that set it and did not
    # restore it would get silently wrong answers here. Measured before the
    # guards went in: a hostile delimiter made cxBtcAddressP2WPKH fail outright
    # and cxMnemonicValidate answer FALSE to a perfectly good twelve-word
    # backup. Every guarded handler must now be indifferent to it, AND must hand
    # the caller's setting back untouched - including when it throws.
    c.note("\nindifference to a hostile itemDelimiter")
    hostile = "\t"
    guarded = [
        ("cxBech32EncodeValues", ("bc", "0,1,2", "bech32")),
        ("cxSegwitAddressEncode", ("bc", 0, bytes(20))),
        ("cxBtcAddressP2WPKH", (G33,)),
        ("cxBtcAddressP2TR", (G65[1:33],)),
        ("cxBtcAddressP2PKH", (G33,)),
        ("cxMnemonicToEntropy", (twelve,)),
        ("cxMnemonicValidate", (twelve,)),
    ]
    for name, args in guarded:
        want = call(name, *args)
        LCS.ITEM_DELIMITER[0] = hostile
        try:
            got = call(name, *args)
        finally:
            LCS.ITEM_DELIMITER[0] = ","
        c.ck(f"{name} is indifferent to the delimiter", got, want)
    # The decoders take their own shapes; check one of each, and the restore.
    addr = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
    want_v = int(LCS._n(ip.call("cxSegwitAddressDecode", ["bc", addr])["version"]))
    LCS.ITEM_DELIMITER[0] = hostile
    try:
        got_v = int(LCS._n(ip.call("cxSegwitAddressDecode", ["bc", addr])["version"]))
        left_ok = LCS.ITEM_DELIMITER[0] == hostile
        # ... and that a THROW does not leak a changed delimiter either.
        try:
            ip.call("cxSegwitAddressDecode", ["bc", addr[:-1] + "5"])
            threw = False
        except LCS.Thrown:
            threw = True
        left_after_throw = LCS.ITEM_DELIMITER[0] == hostile
    finally:
        LCS.ITEM_DELIMITER[0] = ","
    c.ck("cxSegwitAddressDecode is indifferent to the delimiter", got_v, want_v)
    c.ck("  and hands the caller's delimiter back", left_ok, True)
    c.ck("  a corrupt address still throws", threw, True)
    c.ck("  and the throw path restores it too", left_after_throw, True)

    c.note("\nBIP-44 end to end (mnemonic -> seed -> path -> address)")
    seed = call("cxMnemonicToSeed", twelve, "")
    for path, kind, want in BIP44_ADDRESSES:
        node = call("cxHdDerivePath", call("cxHdFromSeed", seed), path)
        if kind == "p2pkh":
            got = call("cxBtcAddressP2PKH", node["pubkey"])
        elif kind == "p2wpkh":
            got = call("cxBtcAddressP2WPKH", node["pubkey"])
        else:
            got = call("cxEthAddressChecksum", call("cxEthAddress", node["pubkey"]))
        c.ck(f"{path} -> {kind}", got, want)

    # ---- phase 5: transactions ---------------------------------------------
    # These EXECUTE the transaction layer, which is the whole point of running it
    # here: phase 5 is pure script over the phase 1-4 primitives, so a defect in
    # its serialization is invisible until something runs it - and until this set
    # existed, nothing did (the oracle rebuilds the tx, but never through the
    # script). The signatures fed to the encoders are the oracle's own RFC 6979
    # deterministic (r, s), so no signer is needed in the interpreter.
    #
    # THIS SET EARNED ITS KEEP THE DAY IT WAS WRITTEN. The whole-transaction check
    # failed on the first run and it was a real, would-be-red engine defect: the
    # BIP-143 tx has a trailing EMPTY scriptSig (input 1 is segwit, its sig is in
    # the witness), and the engine ignores ONE trailing delimiter when it counts
    # items - so cxBtcTxEncode's strict "items == tCount" guard read the list as
    # short and REFUSED to assemble the reference transaction outright. Fixed by
    # reading every list by index and bounding the guard to "too long only"; the
    # regression vector is the whole-transaction check below.
    c.note("\nphase 5: Bitcoin transaction pieces")
    F = _phase5_fixture()
    for n in (0, 1, 252, 253, 65535, 65536, 4294967295, 4294967296):
        c.ck(f"cxVarInt({n})", to_bytes(call("cxVarInt", n)).hex(), REF.varint(n).hex())
    c.ck("cxVarInt refuses a negative count", throws("cxVarInt", -1), True)
    c.ck("cxBtcOutpoint (txid reversed + LE vout)",
         to_bytes(call("cxBtcOutpoint", F["txid0"], 0)).hex(), F["op0"].hex())
    c.ck("cxBtcOutpoint refuses a 31-byte txid", throws("cxBtcOutpoint", "00" * 31, 0), True)
    c.ck("cxBtcOutput (LE amount + script)",
         to_bytes(call("cxBtcOutput", 0x06b22c20, F["spk0"])).hex(),
         REF.btc_output(0x06b22c20, bytes.fromhex(F["spk0"])).hex())

    c.note("\nphase 5: BIP-143 native-P2WPKH sighashes")
    c.ck("cxBtcSighashLegacy (input 0, SIGHASH_ALL)",
         to_bytes(call("cxBtcSighashLegacy", 1, F["outpoints"], F["sequences"], 1,
                       F["sc0"], F["outputs"], 17, 1)).hex(), F["d0"].hex())
    c.ck("cxBtcSighashSegwit (input 1, BIP-143)",
         to_bytes(call("cxBtcSighashSegwit", 1, F["outpoints"], F["sequences"], 2,
                       F["sc1"], 0x23c34600, F["outputs"], 17, 1)).hex(), F["d1"].hex())
    # The CRITICAL fail-open the review caught: a BIP-143 preimage without
    # hashOutputs signs a payment to anywhere. An empty outputs list is refused.
    c.ck("cxBtcSighashSegwit refuses an empty outputs list",
         throws("cxBtcSighashSegwit", 1, F["outpoints"], F["sequences"], 2,
                F["sc1"], 0x23c34600, "", 17, 1), True)
    c.ck("cxBtcSighashLegacy refuses an out-of-range input index",
         throws("cxBtcSighashLegacy", 1, F["outpoints"], F["sequences"], 3,
                F["sc0"], F["outputs"], 17, 1), True)
    c.ck("cxBtcSighashSegwit refuses non-parallel outpoint/sequence lists",
         throws("cxBtcSighashSegwit", 1, F["outpoints"], "4294967295", 1,
                F["sc1"], 0x23c34600, F["outputs"], 17, 1), True)

    c.note("\nphase 5: DER, witness, whole transaction")
    c.ck("cxDerEncode (input 0 signature)",
         to_bytes(call("cxDerEncode", F["compact0"])).hex(), REF.der_encode(*F["rs0"]).hex())
    c.ck("cxDerEncode refuses a signature that is not 64 bytes",
         throws("cxDerEncode", "\x00" * 63), True)
    c.ck("cxBtcWitness (count + sig + pubkey)",
         to_bytes(call("cxBtcWitness", F["witness1"])).hex(), F["wit1"].hex())
    c.ck("cxBtcWitness of an empty stack is a single 00",
         to_bytes(call("cxBtcWitness", "")).hex(), REF.varint(0).hex())
    # THE REGRESSION VECTOR. F["scriptsigs"] is "<sig0>," - a trailing empty item
    # for input 1's absent scriptSig - which the engine counts as ONE item. The
    # old strict guard refused this exact reference transaction; this asserts it
    # now assembles byte for byte. One vector per defect, per the review rule.
    c.ck("cxBtcTxEncode assembles the BIP-143 tx (trailing-empty scriptSig)",
         to_bytes(call("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"], F["sequences"],
                       F["witnesses"], F["outputs"], 17)).hex(), REF.BIP143_SIGNED_TX)
    c.ck("cxBtcTxid (non-witness serialization, reversed)",
         call("cxBtcTxid", 1, F["outpoints"], F["scriptsigs"], F["sequences"],
              F["outputs"], 17), F["txid"].hex())
    c.ck("cxBtcTxEncode refuses zero inputs",
         throws("cxBtcTxEncode", 1, "", "", "", "", F["outputs"], 17), True)
    c.ck("cxBtcTxEncode refuses a non-parallel sequence list",
         throws("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"], "4294967295",
                F["witnesses"], F["outputs"], 17), True)
    # A witness list may not carry MORE entries than inputs (the extras would be
    # dropped). A SHORT one cannot be rejected: [wit, ""] and [wit] are the same
    # string under the chunk rule, so a missing trailing witness reads as empty.
    c.ck("cxBtcTxEncode refuses a witness list longer than the input count",
         throws("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"], F["sequences"],
                F["witnesses"] + "," + F["wit1"].hex(), F["outputs"], 17), True)

    c.note("\nphase 5: Ethereum EIP-155 and EIP-1559")
    c.ck("cxEthLegacySighash matches the EIP-155 example",
         to_bytes(call("cxEthLegacySighash", 9, F["ethGasPrice"], 21000, F["ethTo"],
                       F["ethValue"], "", 1)).hex(), F["h155"].hex())
    res155 = call("cxEthLegacyEncode", 9, F["ethGasPrice"], 21000, F["ethTo"], F["ethValue"],
                  "", 1, F["recid155"], F["r155hex"], F["s155hex"])
    c.ck("cxEthLegacyEncode raw (v = 37)", res155["raw"], F["raw155"].hex())
    c.ck("cxEthLegacyEncode txhash", res155["txhash"], F["txhash155"].hex())
    c.ck("cxEth1559Sighash matches the typed-tx digest",
         to_bytes(call("cxEth1559Sighash", 1, 0, F["m1559prio"], F["m1559fee"], 21000,
                       F["ethTo"], F["v1559"], "")).hex(), F["h1559"].hex())
    res1559 = call("cxEth1559Encode", 1, 0, F["m1559prio"], F["m1559fee"], 21000, F["ethTo"],
                   F["v1559"], "", F["recid1559"], F["r1559hex"], F["s1559hex"])
    c.ck("cxEth1559Encode raw (0x02 envelope)", res1559["raw"], F["raw1559"].hex())
    c.ck("cxEth1559Encode txhash", res1559["txhash"], F["txhash1559"].hex())


def main(argv):
    terse = "--check" in argv[1:]
    c = Checker(terse)
    if not os.path.exists(SCRIPT):
        print("check-script-vectors: src/coinxt.livecodescript is missing")
        return 1
    text = open(SCRIPT, encoding="utf-8").read()

    check_interp_model(c)
    check_constants(c, text)

    cc = find_cc()
    if cc is None:
        print("check-script-vectors: SKIP the vector run (no C compiler found, so the "
              "native hashes the script calls are unavailable). The constants above "
              "still ran.")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            lib_path = os.path.join(tmp, "libcoinxt_script.so")
            try:
                build(cc, lib_path)
            except subprocess.CalledProcessError as exc:
                print(f"check-script-vectors: BUILD FAILED ({exc})")
                return 1
            wire_hashes(ctypes.CDLL(lib_path))
            ip = LCS.Interp(text)
            c.note(f"\nrunning the shipped script ({len(ip.handlers)} handlers, "
                   f"{len(ip.constants)} constants) through tools/lcs-interp.py")
            check_vectors(c, ip)

    if c.problems:
        print("check-script-vectors: FAILED")
        for p in c.problems:
            print(f"  - {p}")
        return 1
    # A FLOOR ON THE COUNT, so a refactor that quietly stops running most of the
    # vectors cannot print OK. "All the checks passed" and "hardly any checks
    # ran" look identical on the way out otherwise, and on this surface the
    # second one is indistinguishable from a green build. Raise it when the set
    # grows; it exists to catch collapse, not to track the exact number.
    floor = 20 if cc is None else 240
    if c.count < floor:
        print(f"check-script-vectors: FAILED - only {c.count} checks ran, expected at "
              f"least {floor}. Something stopped the vector set early.")
        return 1
    print(f"check-script-vectors: OK ({c.count} checks against the published vectors)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
