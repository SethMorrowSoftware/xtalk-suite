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

Usage:
  python3 tools/check-script-vectors.py            # per-check detail
  python3 tools/check-script-vectors.py --check    # terse
"""

import ctypes
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


def main(argv):
    terse = "--check" in argv[1:]
    c = Checker(terse)
    if not os.path.exists(SCRIPT):
        print("check-script-vectors: src/coinxt.livecodescript is missing")
        return 1
    text = open(SCRIPT, encoding="utf-8").read()

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
    print(f"check-script-vectors: OK ({c.count} checks against the published vectors)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
