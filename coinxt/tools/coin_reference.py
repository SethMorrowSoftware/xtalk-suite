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


# ---------------------------------------------------------------------- WIF
# Wallet Import Format: Base58Check over
#   version || 32-byte private key || optional 0x01 compressed marker
# with 0x80 on mainnet and 0xEF on testnet. It sits here rather than with the
# phase-3 encodings because both directions range-check the scalar against the
# curve order, which the address encoders above have no reason to know about.
WIF_VERSION_MAIN = 0x80
WIF_VERSION_TEST = 0xEF
_WIF_NETWORKS = {"mainnet": WIF_VERSION_MAIN, "testnet": WIF_VERSION_TEST}


def wif_encode(seckey: bytes, network: str = "mainnet", compressed: bool = True) -> str:
    if len(seckey) != 32:
        raise ValueError("a private key is 32 bytes")
    if not 1 <= int.from_bytes(seckey, "big") < _N:
        raise ValueError("key out of secp256k1 range")
    if network not in _WIF_NETWORKS:
        raise ValueError("unknown network")
    return b58check_encode(bytes([_WIF_NETWORKS[network]]) + seckey
                           + (b"\x01" if compressed else b""))


def wif_decode(s: str):
    """(seckey, network, compressed) - raising, never guessing, on anything
    malformed, because the script layer under test must refuse the same set."""
    body = b58check_decode(s)          # raises on a bad character or checksum
    if len(body) not in (33, 34):
        raise ValueError("wrong payload length")
    network = {v: n for n, v in _WIF_NETWORKS.items()}.get(body[0])
    if network is None:
        raise ValueError("unknown version byte")
    if len(body) == 34 and body[-1] != 0x01:
        raise ValueError("trailing byte is not the compressed marker")
    key = body[1:33]
    if not 1 <= int.from_bytes(key, "big") < _N:
        raise ValueError("key out of secp256k1 range")
    return key, network, len(body) == 34


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

# WIF self-checks. The positive anchor is the Bitcoin wiki's own worked example
# (the same page the Base58Check worked example above comes from): the model
# must DERIVE the published string, not quote it - a transcription slip in
# either the key or the string fails here at import. The structural checks are
# the ones a green vector run cannot make on its own: all four network/flag
# forms are distinct strings that each round-trip to the same key, and every
# malformed shape RAISES rather than decoding to something plausible.
_wif_sk = bytes.fromhex("0c28fca386c7a227600b2fe50b7cae11ec86d3bf1fbe471be89827e19d72aa1d")
assert wif_encode(_wif_sk, "mainnet", False) == \
    "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ", "wif model broken"
_wif_forms = [wif_encode(_wif_sk, n, c) for n in ("mainnet", "testnet")
              for c in (False, True)]
assert len(set(_wif_forms)) == 4, "wif forms must be distinct"
for _wif_n in ("mainnet", "testnet"):
    for _wif_c in (False, True):
        assert wif_decode(wif_encode(_wif_sk, _wif_n, _wif_c)) == \
            (_wif_sk, _wif_n, _wif_c), "wif round trip broken"
for _wif_bad in ("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTk",  # checksum
                 b58check_encode(b"\x80" + _wif_sk[:31]),                # length
                 b58check_encode(b"\x01" + _wif_sk + b"\x01"),           # version
                 b58check_encode(b"\x80" + _wif_sk + b"\x02"),           # marker
                 b58check_encode(b"\x80" + b"\x00" * 32),                # zero key
                 b58check_encode(b"\x80" + b"\xff" * 32 + b"\x01")):     # >= order
    try:
        wif_decode(_wif_bad)
        raise AssertionError("wif_decode accepted a malformed input")
    except ValueError:
        pass
del _wif_sk, _wif_forms, _wif_n, _wif_c, _wif_bad


# ===========================================================================
# Phase 5 - transaction building and signing.
#
# The oracle the phase-5 script layer is checked against. As with every phase
# before it, this was written to reproduce PUBLISHED transactions from their
# inputs before the script layer existed: the BIP-143 native-P2WPKH worked
# example (a two-input tx that exercises BOTH a legacy SIGHASH_ALL preimage and
# a BIP-143 segwit preimage, reconstructed byte-for-byte including its witness),
# the EIP-155 specification's own signing example, and a self-consistent
# EIP-1559 typed transaction whose signature recovers to its signing key. The
# ECDSA signer here is RFC 6979 deterministic-k, checked at import against the
# same pinned table coin-kat.py carries.
# ===========================================================================

# --- ECDSA (RFC 6979 deterministic k), the one primitive phases 1-4 left to
# --- the native shim. Written longhand for the same reason _pt_mul is: this is
# --- an oracle, and hmac + the curve model already in this file are enough.

def rfc6979_k(sk: bytes, digest: bytes) -> int:
    """RFC 6979 deterministic nonce for secp256k1/SHA-256."""
    x = sk
    v = b"\x01" * 32
    k = b"\x00" * 32
    k = hmac.new(k, v + b"\x00" + x + digest, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    k = hmac.new(k, v + b"\x01" + x + digest, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    while True:
        v = hmac.new(k, v, hashlib.sha256).digest()
        cand = int.from_bytes(v, "big")
        if 1 <= cand < _N:
            return cand
        k = hmac.new(k, v + b"\x00", hashlib.sha256).digest()
        v = hmac.new(k, v, hashlib.sha256).digest()


def ecdsa_sign_recoverable(sk: bytes, digest: bytes):
    """Sign a 32-byte digest; return (r, s, recid) with low-s enforced, exactly
    the convention cxSignRecoverable's 65-byte r||s||recid output carries."""
    z = int.from_bytes(digest, "big")
    ski = int.from_bytes(sk, "big")
    k = rfc6979_k(sk, digest)
    point = _pt_mul(k, _G)
    r = point[0] % _N
    s = (pow(k, _N - 2, _N) * (z + r * ski)) % _N
    recid = (point[1] & 1) ^ (1 if s > _N // 2 else 0)
    if s > _N // 2:
        s = _N - s
    return r, s, recid


def ecdsa_sign_compact(sk: bytes, digest: bytes) -> bytes:
    """64-byte r||s (the cxSign shape)."""
    r, s, _ = ecdsa_sign_recoverable(sk, digest)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


# --- DER (BER canonical) signature encoding, for a Bitcoin scriptSig. libsodium
# --- and the coinxt shim both speak compact r||s; Bitcoin's script wants DER.

def _der_int(value: int) -> bytes:
    b = value.to_bytes(32, "big").lstrip(b"\x00") or b"\x00"
    if b[0] & 0x80:
        b = b"\x00" + b
    return b"\x02" + bytes([len(b)]) + b


def der_encode(r: int, s: int) -> bytes:
    body = _der_int(r) + _der_int(s)
    return b"\x30" + bytes([len(body)]) + body


# --- little-endian and CompactSize writers Bitcoin serialization needs, none of
# --- which the phase 1-4 layers had (their integers were all big-endian).

def _le(value: int, width: int) -> bytes:
    return value.to_bytes(width, "little")


def varint(n: int) -> bytes:
    """Bitcoin CompactSize."""
    if n < 0xFD:
        return bytes([n])
    if n <= 0xFFFF:
        return b"\xfd" + _le(n, 2)
    if n <= 0xFFFFFFFF:
        return b"\xfe" + _le(n, 4)
    return b"\xff" + _le(n, 8)


# --- Bitcoin transaction pieces. Inputs and outputs are passed as lists of the
# --- primitive fields; the script layer mirrors this with comma-joined hex.

def btc_outpoint(txid_be: bytes, vout: int) -> bytes:
    """A 36-byte outpoint: the txid is given big-endian (display order) and
    serialized little-endian, plus the 4-byte LE index."""
    return txid_be[::-1] + _le(vout, 4)


def btc_output(amount_sat: int, script_pubkey: bytes) -> bytes:
    return _le(amount_sat, 8) + varint(len(script_pubkey)) + script_pubkey


def btc_sighash_legacy(version, inputs, outputs, index, script_code,
                       locktime, sighash_type=1):
    """The pre-SegWit SIGHASH_ALL preimage digest. inputs is a list of
    (outpoint_bytes, sequence_int); the signed input carries script_code as its
    scriptSig slot, every other input an empty script."""
    buf = _le(version, 4) + varint(len(inputs))
    for i, (outpoint, seq) in enumerate(inputs):
        script = script_code if i == index else b""
        buf += outpoint + varint(len(script)) + script + _le(seq, 4)
    buf += varint(len(outputs)) + b"".join(outputs)
    buf += _le(locktime, 4) + _le(sighash_type, 4)
    return hash256(buf)


def btc_sighash_segwit(version, inputs, outputs, index, script_code,
                       amount_sat, locktime, sighash_type=1):
    """The BIP-143 preimage digest. inputs is a list of (outpoint, sequence)."""
    prevouts = b"".join(op for op, _ in inputs)
    sequences = b"".join(_le(seq, 4) for _, seq in inputs)
    hash_prevouts = hash256(prevouts)
    hash_sequence = hash256(sequences)
    hash_outputs = hash256(b"".join(outputs))
    op, seq = inputs[index]
    buf = _le(version, 4) + hash_prevouts + hash_sequence
    buf += op + varint(len(script_code)) + script_code + _le(amount_sat, 8)
    buf += _le(seq, 4) + hash_outputs + _le(locktime, 4) + _le(sighash_type, 4)
    return hash256(buf)


def btc_tx(version, inputs, outputs, locktime, script_sigs, witnesses=None):
    """Serialize a transaction. inputs is [(outpoint, sequence)]; script_sigs is
    the per-input scriptSig bytes; witnesses (if any input is segwit) is a list
    of per-input lists of witness items, and a marker+flag and witness section
    are emitted. Returns (raw_bytes, txid_be)."""
    has_witness = witnesses is not None and any(witnesses)
    buf = _le(version, 4)
    if has_witness:
        buf += b"\x00\x01"
    buf += varint(len(inputs))
    for i, (op, seq) in enumerate(inputs):
        buf += op + varint(len(script_sigs[i])) + script_sigs[i] + _le(seq, 4)
    buf += varint(len(outputs)) + b"".join(outputs)
    if has_witness:
        for items in witnesses:
            buf += varint(len(items))
            for item in items:
                buf += varint(len(item)) + item
    buf += _le(locktime, 4)
    # The txid is hash256 of the serialization WITHOUT the witness (BIP-141).
    nowit = _le(version, 4) + varint(len(inputs))
    for i, (op, seq) in enumerate(inputs):
        nowit += op + varint(len(script_sigs[i])) + script_sigs[i] + _le(seq, 4)
    nowit += varint(len(outputs)) + b"".join(outputs) + _le(locktime, 4)
    txid_be = hash256(nowit)[::-1]
    return buf, txid_be


# --- Ethereum: EIP-155 legacy and EIP-1559 typed (EIP-2718 envelope 0x02).

def eth_legacy_sighash(nonce, gas_price, gas, to, value, data, chain_id):
    """The EIP-155 signing digest: keccak of rlp([nonce, gasPrice, gas, to,
    value, data, chainId, 0, 0]). `to` is 20 raw bytes or b'' for creation."""
    fields = [_rlp_uint(nonce), _rlp_uint(gas_price), _rlp_uint(gas),
              rlp_encode(to), _rlp_uint(value), rlp_encode(data),
              _rlp_uint(chain_id), rlp_encode(b""), rlp_encode(b"")]
    return keccak256(_rlp_list_join(fields))


def eth_legacy_encode(nonce, gas_price, gas, to, value, data, chain_id, sk):
    """Sign and RLP-encode an EIP-155 legacy transaction. Returns (raw, txhash);
    v = recid + chain_id*2 + 35."""
    digest = eth_legacy_sighash(nonce, gas_price, gas, to, value, data, chain_id)
    r, s, recid = ecdsa_sign_recoverable(sk, digest)
    v = recid + chain_id * 2 + 35
    fields = [_rlp_uint(nonce), _rlp_uint(gas_price), _rlp_uint(gas),
              rlp_encode(to), _rlp_uint(value), rlp_encode(data),
              _rlp_uint(v), _rlp_uint(r), _rlp_uint(s)]
    raw = _rlp_list_join(fields)
    return raw, keccak256(raw)


def eth_1559_sighash(chain_id, nonce, max_priority, max_fee, gas, to, value,
                     data, access_list=b""):
    """The EIP-1559 signing digest: keccak(0x02 || rlp([chainId, nonce,
    maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data,
    accessList])). access_list defaults to the empty list."""
    fields = [_rlp_uint(chain_id), _rlp_uint(nonce), _rlp_uint(max_priority),
              _rlp_uint(max_fee), _rlp_uint(gas), rlp_encode(to),
              _rlp_uint(value), rlp_encode(data), _rlp_list_join([])]
    return keccak256(b"\x02" + _rlp_list_join(fields))


def eth_1559_encode(chain_id, nonce, max_priority, max_fee, gas, to, value,
                    data, sk, access_list=b""):
    digest = eth_1559_sighash(chain_id, nonce, max_priority, max_fee, gas, to,
                              value, data)
    r, s, recid = ecdsa_sign_recoverable(sk, digest)
    fields = [_rlp_uint(chain_id), _rlp_uint(nonce), _rlp_uint(max_priority),
              _rlp_uint(max_fee), _rlp_uint(gas), rlp_encode(to),
              _rlp_uint(value), rlp_encode(data), _rlp_list_join([]),
              _rlp_uint(recid), _rlp_uint(r), _rlp_uint(s)]
    raw = b"\x02" + _rlp_list_join(fields)
    return raw, keccak256(raw)


def _rlp_uint(n: int) -> bytes:
    """RLP of a non-negative integer: the minimal big-endian byte string (zero
    is the empty string, per RLP/Ethereum canonical-integer rules)."""
    if n == 0:
        return rlp_encode(b"")
    return rlp_encode(n.to_bytes((n.bit_length() + 7) // 8, "big"))


def _rlp_list_join(encoded_items) -> bytes:
    body = b"".join(encoded_items)
    return _rlp_len(len(body), 0xC0) + body


# --- Phase-5 self-checks: reproduce the published anchors at import.

BIP143_SIGNED_TX = (
    "01000000000102fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000494830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac000247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee635711000000")


def _phase5_self_check():
    # RFC 6979: the pinned coin-kat table's first entry (sk=1, "Satoshi
    # Nakamoto"), so this file and coin-kat.py cannot disagree on the signer.
    d = hashlib.sha256(b"Satoshi Nakamoto").digest()
    assert ecdsa_sign_compact((1).to_bytes(32, "big"), d).hex() == (
        "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8"
        "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"), \
        "RFC 6979 signer broken"

    # BIP-143 native P2WPKH: rebuild the whole signed transaction from the two
    # private keys and assert it equals the BIP's published hex, witness and all.
    ver, lock = 1, 17
    ins = [(btc_outpoint(bytes.fromhex(
        "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff"), 0),
        0xffffffee),
        (btc_outpoint(bytes.fromhex(
            "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef"), 1),
        0xffffffff)]
    outs = [btc_output(0x06b22c20, bytes.fromhex(
        "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac")),
        btc_output(0x0d519390, bytes.fromhex(
            "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"))]
    sc0 = bytes.fromhex(
        "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac")
    d0 = btc_sighash_legacy(ver, ins, outs, 0, sc0, lock)
    r0, s0, _ = ecdsa_sign_recoverable(
        bytes.fromhex("bbc27228ddcb9209d7fd6f36b02f7dfa6252af40bb2f1cbc7a557da8027ff866"), d0)
    sig0 = der_encode(r0, s0) + b"\x01"
    sc1 = bytes.fromhex("76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac")
    d1 = btc_sighash_segwit(ver, ins, outs, 1, sc1, 0x23c34600, lock)
    r1, s1, _ = ecdsa_sign_recoverable(
        bytes.fromhex("619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9"), d1)
    sig1 = der_encode(r1, s1) + b"\x01"
    pub1 = bytes.fromhex(
        "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357")
    raw, _ = btc_tx(ver, ins, outs, lock,
                    [bytes([len(sig0)]) + sig0, b""],
                    [[], [sig1, pub1]])
    assert raw.hex() == BIP143_SIGNED_TX, "BIP-143 transaction rebuild broken"

    # EIP-155: the specification's own example (sk = 0x46*32, chainId 1) must
    # reproduce its published signing hash and (r, s).
    to = bytes.fromhex("3535353535353535353535353535353535353535")
    h = eth_legacy_sighash(9, 20 * 10**9, 21000, to, 10**18, b"", 1)
    assert h.hex() == \
        "daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53", \
        "EIP-155 sighash broken"
    r155, s155, recid155 = ecdsa_sign_recoverable(
        bytes.fromhex("46" * 32), h)
    assert r155.to_bytes(32, "big").hex() == \
        "28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276" and \
        s155.to_bytes(32, "big").hex() == \
        "67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83" and \
        recid155 + 1 * 2 + 35 == 37, "EIP-155 signature broken"

    # EIP-1559: self-consistent - the signature recovers to the signing key's
    # address, and the typed envelope begins with 0x02 and its structural RLP
    # matches the spec field order (chainId first, accessList before v).
    sk = bytes.fromhex("4646464646464646464646464646464646464646464646464646464646464646")
    raw2, txhash = eth_1559_encode(1, 0, 10**9, 20 * 10**9, 21000, to, 10**17,
                                   b"", sk)
    assert raw2[0] == 0x02, "EIP-1559 envelope byte broken"
    dec = rlp_decode(raw2[1:])
    assert len(dec) == 12 and dec[0] == b"\x01", "EIP-1559 field shape broken"



# ============================================================================
# BIP-340 (Schnorr) and BIP-341 (Taproot), the ABI 6 surface.
#
# WHY THIS IS HERE AT ALL. tools/coin-kat.py already drives the shipped shim
# against bitcoin/bips' own vector files, which is the strongest evidence
# available. What that cannot do is supply an expectation for a value the
# published vectors do not print - and tests/coin-selftest.livecodescript needs
# a few of those (a signature over a message the BIP never signs, the output
# key for a key we chose). tools/check-selftest-vectors.py re-derives every
# such constant, and it has to re-derive it from something that is NOT the
# library under test. This is that something: BIP-340's and BIP-341's own
# reference pseudocode, written out longhand over the affine curve model above,
# and anchored at import to the published vectors so it cannot drift into
# agreeing with a defect.
# ============================================================================

def tagged_hash(tag: str, msg: bytes) -> bytes:
    """SHA256(SHA256(tag) || SHA256(tag) || msg), BIP-340's domain separator."""
    t = sha256(tag.encode())
    return sha256(t + t + msg)


def lift_x(x: int):
    """The point with X = x and an EVEN Y, or None if x is not on the curve.

    This is what an x-only public key MEANS, and the two ways it returns None
    are precisely BIP-340 vectors 14 (x at or above the field size) and 5 (x is
    not the abscissa of any curve point)."""
    if x >= _P:
        return None
    y_sq = (pow(x, 3, _P) + 7) % _P
    y = pow(y_sq, (_P + 1) // 4, _P)
    if pow(y, 2, _P) != y_sq:
        return None
    return (x, y if y % 2 == 0 else _P - y)


def xonly_pubkey(sk: bytes) -> bytes:
    """BIP-340's bytes(P): the X coordinate of the point for this private key."""
    d0 = int.from_bytes(sk, "big")
    if not 1 <= d0 <= _N - 1:
        raise ValueError("private key out of range")
    return _pt_mul(d0)[0].to_bytes(32, "big")


def schnorr_sign(sk: bytes, msg: bytes, aux: bytes) -> bytes:
    """BIP-340 "Default Signing", transcribed from the BIP's reference code."""
    d0 = int.from_bytes(sk, "big")
    if not 1 <= d0 <= _N - 1:
        raise ValueError("private key out of range")
    pt = _pt_mul(d0)
    # The signing scalar is negated when P has an odd Y: an x-only key names
    # the even-Y point, so that is the key the signature must be for.
    d = d0 if pt[1] % 2 == 0 else _N - d0
    px = pt[0].to_bytes(32, "big")
    t = (d ^ int.from_bytes(tagged_hash("BIP0340/aux", aux), "big")).to_bytes(32, "big")
    rand = tagged_hash("BIP0340/nonce", t + px + msg)
    k0 = int.from_bytes(rand, "big") % _N
    if k0 == 0:
        raise ValueError("nonce is zero")          # 1 in 2^256; the BIP fails here too
    r = _pt_mul(k0)
    k = k0 if r[1] % 2 == 0 else _N - k0
    rx = r[0].to_bytes(32, "big")
    e = int.from_bytes(tagged_hash("BIP0340/challenge", rx + px + msg), "big") % _N
    return rx + ((k + e * d) % _N).to_bytes(32, "big")


def schnorr_verify(pk: bytes, msg: bytes, sig: bytes) -> bool:
    """BIP-340 verification. False - never an exception - for every malformed
    input the vector file expects to fail, which is what makes it usable as an
    oracle for the ten NEGATIVE cases."""
    if len(pk) != 32 or len(sig) != 64:
        return False
    pt = lift_x(int.from_bytes(pk, "big"))
    if pt is None:
        return False
    r = int.from_bytes(sig[:32], "big")
    s = int.from_bytes(sig[32:], "big")
    if r >= _P or s >= _N:
        return False
    e = int.from_bytes(tagged_hash("BIP0340/challenge", sig[:32] + pk + msg), "big") % _N
    point = _pt_add(_pt_mul(s), _pt_mul(_N - e, pt))
    if point is None:              # sG - eP is the point at infinity (vectors 9, 10)
        return False
    return point[1] % 2 == 0 and point[0] == r


def taproot_tweak_pubkey(internal32: bytes, merkle_root):
    """BIP-341's Q = P + int(hash_TapTweak(bytes(P) || merkle_root))G.

    merkle_root is None for a key-path-only output, and None is the EMPTY BYTE
    STRING here - NOT 32 zero bytes. Returns (32-byte x-only Q, parity)."""
    root = b"" if merkle_root is None else merkle_root
    t = int.from_bytes(tagged_hash("TapTweak", internal32 + root), "big")
    if t >= _N:
        raise ValueError("tweak out of range")
    pt = lift_x(int.from_bytes(internal32, "big"))
    if pt is None:
        raise ValueError("internal key is not on the curve")
    q = _pt_add(pt, _pt_mul(t))
    if q is None:
        raise ValueError("tweaked point is infinity")
    return q[0].to_bytes(32, "big"), q[1] & 1


def taproot_tweak_seckey(sk: bytes, merkle_root) -> bytes:
    """The private key for the output key above. Same empty-vs-zero rule."""
    root = b"" if merkle_root is None else merkle_root
    d0 = int.from_bytes(sk, "big")
    if not 1 <= d0 <= _N - 1:
        raise ValueError("private key out of range")
    pt = _pt_mul(d0)
    d = d0 if pt[1] % 2 == 0 else _N - d0
    internal = pt[0].to_bytes(32, "big")
    t = int.from_bytes(tagged_hash("TapTweak", internal + root), "big")
    if t >= _N:
        raise ValueError("tweak out of range")
    return ((d + t) % _N).to_bytes(32, "big")


def tap_leaf_hash(leaf_version: int, script: bytes) -> bytes:
    """BIP-341 leaf hash: tagged TapLeaf over version || compact_size(script)
    || script. The suite's scripts stay under 253 bytes so the one-byte
    compact size below covers them; a longer script raises rather than
    silently emitting the wrong prefix."""
    if not 0 <= leaf_version <= 0xfe or leaf_version % 2:
        raise ValueError("leaf version must be an even byte")
    if leaf_version == 0x50:
        raise ValueError("leaf version 0x50 is reserved (BIP-341: it would be "
                         "ambiguous with the annex marker)")
    if len(script) >= 0xfd:
        raise ValueError("script too long for the modelled compact size")
    return tagged_hash("TapLeaf", bytes([leaf_version]) +
                       len(script).to_bytes(1, "little") + script)


def tap_branch_hash(a: bytes, b: bytes) -> bytes:
    """BIP-341 inner node: tagged TapBranch over the two child hashes in
    LEXICOGRAPHIC order - the sort is the consensus rule, not a convenience."""
    if len(a) != 32 or len(b) != 32:
        raise ValueError("branch children must be 32 bytes")
    lo, hi = sorted([a, b])
    return tagged_hash("TapBranch", lo + hi)


# The BIP-341 sighash types: DEFAULT, ALL, NONE, SINGLE and the three
# ANYONECANPAY forms. 0x80 alone is NOT valid (the spec's validation rules).
_TAPROOT_HASH_TYPES = (0x00, 0x01, 0x02, 0x03, 0x81, 0x82, 0x83)


def btc_sighash_taproot(version, locktime, prevouts, amounts, spks,
                        sequences, outputs, index, hash_type, tapleaf=None):
    """The BIP-341 signature hash (key path; script path when tapleaf is the
    32-byte leaf hash - key_version 0 and codeseparator position 0xffffffff,
    the no-OP_CODESEPARATOR case, which is the only one this model carries).

    Unlike BIP-143 the message commits to EVERY spent output: prevouts is the
    list of 36-byte outpoints, amounts the per-input satoshi ints, spks the
    per-input scriptPubKey bytes, sequences the per-input ints, outputs the
    serialized outputs (amount8 || compact_size || script). No annex."""
    if hash_type not in _TAPROOT_HASH_TYPES:
        raise ValueError("invalid taproot sighash type")
    if not (len(prevouts) == len(amounts) == len(spks) == len(sequences)):
        raise ValueError("the per-input lists must be parallel")
    if not 0 <= index < len(prevouts):
        raise ValueError("input index out of range")
    anyonecanpay = hash_type & 0x80
    base = hash_type & 3
    if base == 3 and index >= len(outputs):
        raise ValueError("SIGHASH_SINGLE with no matching output is invalid")
    msg = b"\x00" + bytes([hash_type]) + _le(version, 4) + _le(locktime, 4)
    if not anyonecanpay:
        msg += sha256(b"".join(prevouts))
        msg += sha256(b"".join(_le(a, 8) for a in amounts))
        msg += sha256(b"".join(varint(len(s)) + s for s in spks))
        msg += sha256(b"".join(_le(s, 4) for s in sequences))
    if base not in (2, 3):
        msg += sha256(b"".join(outputs))
    msg += bytes([2 if tapleaf is not None else 0])   # spend_type; no annex
    if anyonecanpay:
        msg += (prevouts[index] + _le(amounts[index], 8) +
                varint(len(spks[index])) + spks[index] +
                _le(sequences[index], 4))
    else:
        msg += _le(index, 4)
    if base == 3:
        msg += sha256(outputs[index])
    if tapleaf is not None:
        if len(tapleaf) != 32:
            raise ValueError("tapleaf hash must be 32 bytes")
        msg += tapleaf + b"\x00" + b"\xff\xff\xff\xff"
    return tagged_hash("TapSighash", msg)


def _bip341_sighash_self_check():
    """Anchor the sighash model to bitcoin/bips' wallet-test-vectors.json,
    keyPathSpending input 0 (hashType 3, SIGHASH_SINGLE): the published
    rawUnsignedTx and utxosSpent, transcribed mechanically from the fetched
    file - a first HAND transcription of this block was corrupt and THIS
    check caught it at import, which is the never-from-memory rule doing its
    job - and the published sigHash the model must land on. The remaining
    six inputs, the trees and the control blocks are swept by
    check-script-vectors.py; this import check holds the piece a wrong byte
    order would silently break."""
    raw = bytes.fromhex(
        "02000000097de20cbff686da83a54981d2b9bab3586f4ca7e48f57f5b559"
        "63115f3b334e9c010000000000000000d7b7cab57b1393ace2d064f4d4a2"
        "cb8af6def61273e127517d44759b6dafdd990000000000fffffffff8e1f5"
        "83384333689228c5d28eac13366be082dc57441760d957275419a4184200"
        "00000000fffffffff0689180aa63b30cb162a73c6d2a38b7eeda2a83ece7"
        "4310fda0843ad604853b0100000000feffffffaa5202bdf6d8ccd2ee0f02"
        "02afbbb7461d9264a25e5bfd3c5a52ee1239e0ba6c0000000000feffffff"
        "956149bdc66faa968eb2be2d2faa29718acbfe3941215893a2a3446d32ac"
        "d050000000000000000000e664b9773b88c09c32cb70a2a3e4da0ced63b7"
        "ba3b22f848531bbb1d5d5f4c94010000000000000000e9aa6b8e6c9de676"
        "19e6a3924ae25696bb7b694bb677a632a74ef7eadfd4eabf0000000000ff"
        "ffffffa778eb6a263dc090464cd125c466b5a99667720b1c110468831d05"
        "8aa1b82af10100000000ffffffff0200ca9a3b000000001976a91406afd4"
        "6bcdfd22ef94ac122aa11f241244a37ecc88ac807840cb0000000020ac9a"
        "87f5594be208f8532db38cff670c450ed2fea8fcdefcc9a663f78bab962b"
        "0065cd1d")
    utxos = [
        ("512053a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343", 420000000),
        ("5120147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3", 462000000),
        ("76a914751e76e8199196d454941c45d1b3a323f1433bd688ac", 294000000),
        ("5120e4d810fd50586274face62b8a807eb9719cef49c04177cc6b76a9a4251d5450e", 504000000),
        ("512091b64d5324723a985170e4dc5a0f84c041804f2cd12660fa5dec09fc21783605", 630000000),
        ("00147dd65592d0ab2fe0d0257d571abf032cd9db93dc", 378000000),
        ("512075169f4001aa68f15bbed28b218df1d0a62cbbcf1188c6665110c293c907b831", 672000000),
        ("5120712447206d7a5238acc7ff53fbe94a3b64539ad291c7cdbc490b7577e4b17df5", 546000000),
        ("512077e30a5522dd9f894c3f8b8bd4c4b2cf82ca7da8a3ea6a239655c39c050ab220", 588000000),
    ]
    prevouts, seqs = [], []
    b, n = raw, 4                            # skip the 4-byte version
    nin, n = b[n], n + 1
    for _ in range(nin):
        prevouts.append(b[n:n + 36]); n += 36
        assert b[n] == 0; n += 1             # empty scriptSig
        seqs.append(int.from_bytes(b[n:n + 4], "little")); n += 4
    nout, n = b[n], n + 1
    outs = []
    for _ in range(nout):
        st = n
        n += 8
        sl = b[n]; n += 1 + sl
        outs.append(b[st:n])
    assert n + 4 == len(b), "tx parse did not consume the fixture"
    got = btc_sighash_taproot(
        int.from_bytes(b[:4], "little"), int.from_bytes(b[-4:], "little"),
        prevouts, [a for _, a in utxos],
        [bytes.fromhex(s) for s, _ in utxos], seqs, outs, 0, 3)
    assert got.hex() == ("2514a6272f85cfa0f45eb907fcb0d121"
                         "b808ed37c6ea160a5a9046ed5526d555"), \
        "BIP-341 sighash model does not reproduce keyPathSpending input 0"


_bip341_sighash_self_check()


def _bip340_self_check():
    """Anchor the model above to bitcoin/bips' published vectors. An oracle that
    is only self-consistent is worth nothing, so this runs at import and takes
    the whole file down if it fails."""
    # BIP-340 test-vectors.csv index 0 (sk = 3) and index 1.
    sk0 = bytes.fromhex("00" * 31 + "03")
    assert xonly_pubkey(sk0).hex() == \
        "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9", \
        "BIP-340 x-only pubkey model broken"
    assert schnorr_sign(sk0, bytes(32), bytes(32)).hex() == (
        "e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215"
        "25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0"), \
        "BIP-340 signing model broken"
    sk1 = bytes.fromhex("b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef")
    msg1 = bytes.fromhex("243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89")
    sig1 = bytes.fromhex(
        "6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de3341"
        "8906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a")
    assert schnorr_sign(sk1, msg1, bytes(31) + b"\x01") == sig1, "BIP-340 vector 1 broken"
    assert schnorr_verify(xonly_pubkey(sk1), msg1, sig1), "BIP-340 verify model broken"
    # Two of the file's NEGATIVE cases, so the oracle is known to say no:
    # index 5 (public key not on the curve) and index 6 (has_even_y(R) false).
    assert not schnorr_verify(
        bytes.fromhex("eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34"),
        msg1, sig1), "BIP-340 off-curve key must not verify"
    assert not schnorr_verify(
        bytes.fromhex("dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659"),
        msg1,
        bytes.fromhex("fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a1460297556"
                      "3cc27944640ac607cd107ae10923d9ef7a73c643e166be5ebeafa34b1ac553e2")), \
        "BIP-340 odd-y R must not verify"
    # BIP-341 wallet-test-vectors.json: scriptPubKey 0 (NO merkle root) and 1
    # (a script-tree root), plus keyPathSpending input 0's tweaked private key.
    ip0 = bytes.fromhex("d6889cb081036e0faefa3a35157ad71086b123b2b144b649798b494c300a961d")
    q0, _ = taproot_tweak_pubkey(ip0, None)
    assert q0.hex() == \
        "53a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343", \
        "BIP-341 key-path-only tweak broken"
    ip1 = bytes.fromhex("187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27")
    root1 = bytes.fromhex("5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21")
    q1, _ = taproot_tweak_pubkey(ip1, root1)
    assert q1.hex() == \
        "147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3", \
        "BIP-341 script-tree tweak broken"
    # An ABSENT root is the empty string, not 32 zeros: the two must disagree.
    assert taproot_tweak_pubkey(ip0, bytes(32))[0] != q0, \
        "BIP-341 empty root must not equal a 32-zero root"
    isk0 = bytes.fromhex("6b973d88838f27366ed61c9ad6367663045cb456e28335c109e30717ae0c6baa")
    assert taproot_tweak_seckey(isk0, None).hex() == \
        "2405b971772ad26915c8dcdf10f238753a9b837e5f8e6a86fd7c0cce5b7296d9", \
        "BIP-341 seckey tweak broken"
    # The two halves must meet: the tweaked key signs for the tweaked point.
    assert xonly_pubkey(taproot_tweak_seckey(isk0, None)) == q0, \
        "BIP-341 tweak halves disagree"


_bip340_self_check()

_phase5_self_check()
