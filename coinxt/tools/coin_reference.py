#!/usr/bin/env python3
"""coin_reference.py - the reference implementation of CoinXT's phase-3
encodings and phase-4 BIP-39/BIP-32 layers, and the PUBLISHED vectors they are
pinned to.

This is the oracle src/coinxt.livecodescript is checked against. It was written
BEFORE the script and validated against the published vectors first, on purpose:
a vector captured from the script's own output would only prove the script
agrees with itself.

It ships no cryptography of its own beyond what a test oracle needs - Keccak-256
and a RIPEMD-160 fallback are inlined only because Python has no Keccak and
OpenSSL 3 often withholds RIPEMD-160, and both self-check against a published
digest at import. Nothing here is loaded by the extension.

Used by tools/check-script-vectors.py (which runs the real script against these)
and by tools/check-selftest-vectors.py (which re-derives the harness constants).
"""
import hashlib
import hmac
import os
import re

# --------------------------------------------------------------------- base58
B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def sha256(b): return hashlib.sha256(b).digest()
def hash256(b): return sha256(sha256(b))


def hash160(b):
    h = hashlib.new("ripemd160") if _have_rmd() else None
    if h is None:
        return _ripemd160_pure(sha256(b))
    h.update(sha256(b))
    return h.digest()


def _have_rmd():
    try:
        hashlib.new("ripemd160")
        return True
    except Exception:
        return False


def b58encode(b: bytes) -> str:
    n = int.from_bytes(b, "big") if b else 0
    out = ""
    while n > 0:
        n, r = divmod(n, 58)
        out = B58[r] + out
    # leading zero bytes become leading '1's, one for one
    pad = 0
    for c in b:
        if c == 0:
            pad += 1
        else:
            break
    return "1" * pad + out


def b58decode(s: str) -> bytes:
    n = 0
    for ch in s:
        i = B58.find(ch)
        if i < 0:
            raise ValueError("bad base58 character")
        n = n * 58 + i
    body = b""
    while n > 0:
        n, r = divmod(n, 256)
        body = bytes([r]) + body
    pad = 0
    for ch in s:
        if ch == "1":
            pad += 1
        else:
            break
    return b"\x00" * pad + body


def b58check_encode(payload: bytes) -> str:
    return b58encode(payload + hash256(payload)[:4])


def b58check_decode(s: str) -> bytes:
    raw = b58decode(s)
    if len(raw) < 5:
        raise ValueError("too short")
    body, chk = raw[:-4], raw[-4:]
    if hash256(body)[:4] != chk:
        raise ValueError("bad checksum")
    return body


# --------------------------------------------------------- bech32 / bech32m
CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
BECH32M_CONST = 0x2BC830A3


def bech32_polymod(values):
    gen = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        b = chk >> 25
        chk = ((chk & 0x1FFFFFF) << 5) ^ v
        for i in range(5):
            chk ^= gen[i] if ((b >> i) & 1) else 0
    return chk


def bech32_hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def bech32_verify(hrp, data, spec):
    const = BECH32M_CONST if spec == "bech32m" else 1
    return bech32_polymod(bech32_hrp_expand(hrp) + data) == const


def bech32_create_checksum(hrp, data, spec):
    const = BECH32M_CONST if spec == "bech32m" else 1
    values = bech32_hrp_expand(hrp) + data
    polymod = bech32_polymod(values + [0, 0, 0, 0, 0, 0]) ^ const
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]


def bech32_encode(hrp, data, spec):
    combined = data + bech32_create_checksum(hrp, data, spec)
    return hrp + "1" + "".join([CHARSET[d] for d in combined])


def bech32_decode(bech):
    if any(ord(x) < 33 or ord(x) > 126 for x in bech):
        return (None, None, None)
    if bech.lower() != bech and bech.upper() != bech:
        return (None, None, None)
    bech = bech.lower()
    pos = bech.rfind("1")
    if pos < 1 or pos + 7 > len(bech) or len(bech) > 90:
        return (None, None, None)
    if not all(x in CHARSET for x in bech[pos + 1:]):
        return (None, None, None)
    hrp = bech[:pos]
    data = [CHARSET.find(x) for x in bech[pos + 1:]]
    for spec in ("bech32", "bech32m"):
        if bech32_verify(hrp, data, spec):
            return (hrp, data[:-6], spec)
    return (None, None, None)


def convertbits(data, frombits, tobits, pad=True):
    acc = 0
    bits = 0
    ret = []
    maxv = (1 << tobits) - 1
    max_acc = (1 << (frombits + tobits - 1)) - 1
    for value in data:
        if value < 0 or (value >> frombits):
            return None
        acc = ((acc << frombits) | value) & max_acc
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad:
        if bits:
            ret.append((acc << (tobits - bits)) & maxv)
    elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
        return None
    return ret


def segwit_encode(hrp, witver, witprog):
    spec = "bech32" if witver == 0 else "bech32m"
    ret = bech32_encode(hrp, [witver] + convertbits(witprog, 8, 5), spec)
    if segwit_decode(hrp, ret) == (None, None):
        return None
    return ret


def segwit_decode(hrp, addr):
    hrpgot, data, spec = bech32_decode(addr)
    if hrpgot != hrp or data is None or len(data) < 1:
        return (None, None)
    decoded = convertbits(data[1:], 5, 8, False)
    if decoded is None or len(decoded) < 2 or len(decoded) > 40:
        return (None, None)
    if data[0] > 16:
        return (None, None)
    if data[0] == 0 and len(decoded) != 20 and len(decoded) != 32:
        return (None, None)
    if (data[0] == 0 and spec != "bech32") or (data[0] != 0 and spec != "bech32m"):
        return (None, None)
    return (data[0], decoded)


# ------------------------------------------------------------------- keccak
def keccak256(b: bytes) -> bytes:
    """Keccak-256 (Ethereum, 0x01 padding), NOT SHA3-256. Pure python so the
    model has no third-party dependency; checked against the published
    keccak256("") answer on import."""
    RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A,
          0x8000000080008000, 0x000000000000808B, 0x0000000080000001,
          0x8000000080008081, 0x8000000000008009, 0x000000000000008A,
          0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
          0x000000008000808B, 0x800000000000008B, 0x8000000000008089,
          0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
          0x000000000000800A, 0x800000008000000A, 0x8000000080008081,
          0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
    ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
           [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
    M = (1 << 64) - 1

    def rol(x, n):
        return ((x << n) | (x >> (64 - n))) & M

    def keccak_f(A):
        for rnd in range(24):
            C = [A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4] for x in range(5)]
            D = [C[(x - 1) % 5] ^ rol(C[(x + 1) % 5], 1) for x in range(5)]
            for x in range(5):
                for y in range(5):
                    A[x][y] ^= D[x]
            B = [[0] * 5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    B[y][(2 * x + 3 * y) % 5] = rol(A[x][y], ROT[x][y])
            for x in range(5):
                for y in range(5):
                    A[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y]) & M) & B[(x + 2) % 5][y]
            A[0][0] ^= RC[rnd]
        return A

    rate = 136  # 1088 bits for Keccak-256
    padded = bytearray(b)
    padded.append(0x01)
    while len(padded) % rate != 0:
        padded.append(0x00)
    padded[-1] ^= 0x80
    A = [[0] * 5 for _ in range(5)]
    for off in range(0, len(padded), rate):
        block = padded[off:off + rate]
        for i in range(rate // 8):
            x, y = i % 5, i // 5
            A[x][y] ^= int.from_bytes(block[i * 8:(i + 1) * 8], "little")
        A = keccak_f(A)
    out = b""
    for i in range(4):
        x, y = i % 5, i // 5
        out += A[x][y].to_bytes(8, "little")
    return out[:32]


# ---------------------------------------------------------------------- RLP
def rlp_encode(item):
    if isinstance(item, bytes):
        if len(item) == 1 and item[0] < 0x80:
            return item
        return _rlp_len(len(item), 0x80) + item
    payload = b"".join(rlp_encode(x) for x in item)
    return _rlp_len(len(payload), 0xC0) + payload


def _rlp_len(n, offset):
    if n < 56:
        return bytes([offset + n])
    be = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([offset + 55 + len(be)]) + be


def rlp_decode(data: bytes):
    item, rest = _rlp_item(data)
    if rest:
        raise ValueError("trailing bytes after the RLP item")
    return item


def _rlp_item(data):
    if not data:
        raise ValueError("empty input")
    p = data[0]
    if p < 0x80:
        return data[:1], data[1:]
    if p < 0xB8:
        n = p - 0x80
        if len(data) < 1 + n:
            raise ValueError("truncated string")
        if n == 1 and data[1] < 0x80:
            raise ValueError("non-canonical single byte")
        return data[1:1 + n], data[1 + n:]
    if p < 0xC0:
        ln = p - 0xB7
        if len(data) < 1 + ln:
            raise ValueError("truncated length")
        n = int.from_bytes(data[1:1 + ln], "big")
        if n < 56:
            raise ValueError("non-canonical length")
        if data[1] == 0:
            raise ValueError("leading zero in length")
        if len(data) < 1 + ln + n:
            raise ValueError("truncated string")
        return data[1 + ln:1 + ln + n], data[1 + ln + n:]
    if p < 0xF8:
        n = p - 0xC0
        body, rest = data[1:1 + n], data[1 + n:]
        if len(body) < n:
            raise ValueError("truncated list")
        return _rlp_list(body), rest
    ln = p - 0xF7
    n = int.from_bytes(data[1:1 + ln], "big")
    if n < 56:
        raise ValueError("non-canonical list length")
    if data[1] == 0:
        raise ValueError("leading zero in list length")
    body, rest = data[1 + ln:1 + ln + n], data[1 + ln + n:]
    if len(body) < n:
        raise ValueError("truncated list")
    return _rlp_list(body), rest


def _rlp_list(body):
    out = []
    while body:
        item, body = _rlp_item(body)
        out.append(item)
    return out


# ------------------------------------------------------------------ addresses
def p2pkh(pubkey: bytes, version=0x00) -> str:
    return b58check_encode(bytes([version]) + hash160(pubkey))


def p2wpkh(pubkey: bytes, hrp="bc") -> str:
    return segwit_encode(hrp, 0, hash160(pubkey))


def p2tr(xonly: bytes, hrp="bc") -> str:
    return segwit_encode(hrp, 1, xonly)


def eth_address(pubkey65: bytes) -> str:
    assert len(pubkey65) == 65 and pubkey65[0] == 0x04
    return "0x" + keccak256(pubkey65[1:])[-20:].hex()


def eip55(addr: str) -> str:
    a = addr.lower().replace("0x", "")
    h = keccak256(a.encode()).hex()
    return "0x" + "".join(
        c.upper() if (not c.isdigit() and int(h[i], 16) >= 8) else c
        for i, c in enumerate(a))


# ------------------------------------------------------- pure ripemd160 fallback
def _ripemd160_pure(msg: bytes) -> bytes:
    import struct
    K = [0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E]
    KK = [0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000]
    R = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
         7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
         3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
         1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
         4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13]
    RR = [5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
          6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
          15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
          8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
          12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11]
    S = [11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
         7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
         11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
         11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
         9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6]
    SS = [8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
          9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
          9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
          15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
          8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11]
    M = 0xFFFFFFFF

    def rol(x, n): return ((x << n) | (x >> (32 - n))) & M

    def f(j, x, y, z):
        if j < 16: return x ^ y ^ z
        if j < 32: return (x & y) | (~x & z) & M
        if j < 48: return (x | (~y & M)) ^ z
        if j < 64: return (x & z) | (y & ~z & M)
        return x ^ (y | (~z & M))

    ml = len(msg)
    msg = msg + b"\x80" + b"\x00" * ((55 - ml) % 64) + struct.pack("<Q", ml * 8)
    h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
    for off in range(0, len(msg), 64):
        X = list(struct.unpack("<16I", msg[off:off + 64]))
        a, b, c, d, e = h
        aa, bb, cc, dd, ee = h
        for j in range(80):
            t = (rol((a + f(j, b, c, d) + X[R[j]] + K[j // 16]) & M, S[j]) + e) & M
            a, e, d, c, b = e, d, rol(c, 10), b, t
            t = (rol((aa + f(79 - j, bb, cc, dd) + X[RR[j]] + KK[j // 16]) & M, SS[j]) + ee) & M
            aa, ee, dd, cc, bb = ee, dd, rol(cc, 10), bb, t
        t = (h[1] + c + dd) & M
        h = [t, (h[2] + d + ee) & M, (h[3] + e + aa) & M,
             (h[4] + a + bb) & M, (h[0] + b + cc) & M]
    return b"".join(x.to_bytes(4, "little") for x in h)


# Self-check on import: a model that is wrong makes every pinned vector wrong.
assert keccak256(b"").hex() == \
    "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", "keccak model broken"
assert _ripemd160_pure(b"abc").hex() == "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc", "ripemd model broken"


# ============================================================================
# Phase 4: BIP-39 and BIP-32.
#
# The secp256k1 arithmetic below is written out longhand rather than imported.
# That is the point: the thing under test is a binding over trezor-crypto, so an
# oracle that also called trezor-crypto would only prove trezor agrees with
# itself. Textbook affine formulas over a 250-line-per-second prime field are
# plenty fast for a few dozen derivations, and they are auditable by eye.
# ============================================================================

_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
_G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
      0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _pt_add(p, q):
    if p is None:
        return q
    if q is None:
        return p
    if p[0] == q[0] and (p[1] + q[1]) % _P == 0:
        return None
    if p == q:
        lam = 3 * p[0] * p[0] * pow(2 * p[1], _P - 2, _P) % _P
    else:
        lam = (q[1] - p[1]) * pow(q[0] - p[0], _P - 2, _P) % _P
    x = (lam * lam - p[0] - q[0]) % _P
    return (x, (lam * (p[0] - x) - p[1]) % _P)


def _pt_mul(k, p=None):
    p, r = p or _G, None
    while k:
        if k & 1:
            r = _pt_add(r, p)
        p, k = _pt_add(p, p), k >> 1
    return r


def _compress(pt):
    return bytes([2 + (pt[1] & 1)]) + pt[0].to_bytes(32, "big")


def _decompress(b: bytes):
    x = int.from_bytes(b[1:33], "big")
    y = pow((x * x * x + 7) % _P, (_P + 1) // 4, _P)
    return (x, y if y & 1 == b[0] - 2 else _P - y)


def pubkey(sk: bytes) -> bytes:
    """The compressed public key for a 32-byte private key."""
    return _compress(_pt_mul(int.from_bytes(sk, "big")))


# ------------------------------------------------------------------- BIP-39
def _load_wordlist():
    """Parsed straight out of the vendored upstream table, so the oracle and
    the shim cannot drift apart on WHICH list they use. That the list is the
    normative one is a separate claim, checked by its published SHA-256 in the
    assert at the bottom of this file."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "native", "vendor", "bip39_english.c")
    body = open(path).read().split(
        "BIP39_WORDLIST_ENGLISH[BIP39_WORD_COUNT] = {", 1)[1].rsplit("};", 1)[0]
    return re.findall(r'"([a-z]+)"', body)


WORDLIST = _load_wordlist()

# The SHA-256 of the canonical newline-joined english.txt, as published with
# BIP-39. This is what makes "the normative list" a checked claim.
WORDLIST_SHA256 = "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"


def bip39_mnemonic(entropy: bytes) -> str:
    bits = "".join(f"{b:08b}" for b in entropy)
    bits += "".join(f"{b:08b}" for b in sha256(entropy))[:len(entropy) * 8 // 32]
    return " ".join(WORDLIST[int(bits[i:i + 11], 2)] for i in range(0, len(bits), 11))


def bip39_entropy(mnemonic: str) -> bytes:
    words = mnemonic.split()
    bits = "".join(f"{WORDLIST.index(w):011b}" for w in words)
    ent_len = len(words) * 4 // 3
    ent = int(bits[:ent_len * 8], 2).to_bytes(ent_len, "big")
    cs = len(words) // 3
    if bits[ent_len * 8:] != "".join(f"{b:08b}" for b in sha256(ent))[:cs]:
        raise ValueError("bad checksum")
    return ent


def bip39_seed(mnemonic: str, passphrase: str = "") -> bytes:
    return hashlib.pbkdf2_hmac("sha512", " ".join(mnemonic.split()).encode(),
                               ("mnemonic" + passphrase).encode(), 2048, 64)


# ------------------------------------------------------------------- BIP-32
XPRV, XPUB, HARDENED = 0x0488ADE4, 0x0488B21E, 0x80000000


def bip32_master(seed: bytes) -> dict:
    I = hmac.new(b"Bitcoin seed", seed, hashlib.sha512).digest()
    return {"seckey": I[:32], "pubkey": pubkey(I[:32]), "chaincode": I[32:],
            "depth": 0, "index": 0, "parentfp": b"\0\0\0\0"}


def bip32_ckd(node: dict, i: int) -> dict:
    if i >= HARDENED:
        if not node["seckey"]:
            raise ValueError("hardened from a public node")
        data = b"\0" + node["seckey"] + i.to_bytes(4, "big")
    else:
        data = node["pubkey"] + i.to_bytes(4, "big")
    I = hmac.new(node["chaincode"], data, hashlib.sha512).digest()
    t = int.from_bytes(I[:32], "big")
    if t == 0 or t >= _N:
        raise ValueError("invalid tweak")
    out = {"chaincode": I[32:], "depth": node["depth"] + 1, "index": i,
           "parentfp": hash160(node["pubkey"])[:4]}
    if node["seckey"]:
        k = (t + int.from_bytes(node["seckey"], "big")) % _N
        if k == 0:
            raise ValueError("invalid child")
        out["seckey"] = k.to_bytes(32, "big")
        out["pubkey"] = pubkey(out["seckey"])
    else:
        p = _pt_add(_pt_mul(t), _decompress(node["pubkey"]))
        if p is None:
            raise ValueError("point at infinity")
        out["seckey"], out["pubkey"] = b"", _compress(p)
    return out


def bip32_path(node: dict, path: str) -> dict:
    parts = path.split("/")
    if parts[0] not in ("m", "M"):
        raise ValueError("path must start with m")
    for part in parts[1:]:
        hard = part[-1] in "'hH"
        node = bip32_ckd(node, int(part[:-1] if hard else part) + (HARDENED if hard else 0))
    return node


def bip32_serialize(node: dict, private: bool) -> str:
    ver = XPRV if private else XPUB
    key = b"\0" + node["seckey"] if private else node["pubkey"]
    return b58check_encode(ver.to_bytes(4, "big") + bytes([node["depth"]])
                           + node["parentfp"] + node["index"].to_bytes(4, "big")
                           + node["chaincode"] + key)


# Phase-4 self-checks, same rule as the phase-3 ones above: an oracle that is
# wrong makes every vector it pins wrong, so it proves itself against published
# values at import.
assert hashlib.sha256(("\n".join(WORDLIST) + "\n").encode()).hexdigest() == WORDLIST_SHA256, \
    "the vendored BIP-39 wordlist is not the normative one"
assert len(WORDLIST) == 2048 and WORDLIST == sorted(WORDLIST), "wordlist shape broken"
assert _compress(_G).hex() == \
    "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", "curve model broken"
assert bip32_serialize(bip32_master(bytes.fromhex("000102030405060708090a0b0c0d0e0f")), True) == \
    "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6Ln" \
    "F5kejMRNNU3TGtRBeJgk33yuGBxrMPHi", "bip32 model broken"
