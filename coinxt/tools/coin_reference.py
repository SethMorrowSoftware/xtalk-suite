#!/usr/bin/env python3
"""coin_reference.py - the reference implementation of CoinXT's phase-3
encodings, and the PUBLISHED vectors they are pinned to.

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
