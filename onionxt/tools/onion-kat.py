#!/usr/bin/env python3
"""
onion-kat.py - known-answer vectors for OnionXT's pure-compute paths.

OnionXT itself adds NO cryptography (CLAUDE.md rule 1): the ed25519 identity is a
SodiumXT call and the SHA-512 / SHA3-256 primitives are SodiumXT features (docs/08).
This tool is a *reference cross-check*, not a second implementation that ships. It
exists to answer the conformance question doc 09 (item 11) raises: the determinism
claim "seed -> .onion" has a known answer worth pinning, so an OXT implementer can
validate the livecodescript base32 and the address<->key mapping against fixed
vectors, and a SodiumXT implementer can confirm the seed->ed25519 pubkey and the
seed->expanded-key steps against libsodium.

What it pins:
  1. base32 (RFC 4648 lowercase, no padding) encode/decode round-trips - the exact
     bit-packing OnionXT does in script.
  2. The v3 .onion address = base32(PUBKEY || CHECKSUM || VERSION), with
     CHECKSUM = SHA3-256(".onion checksum" || PUBKEY || 0x03)[:2] and VERSION = 0x03.
     Verified here against two real, published onion addresses so the logic is ground
     truth, not a self-referential guess.
  3. The ed25519 seed -> public key (what SodiumXT sxSignKeypairFromSeed yields) and
     the seed -> 64-byte Tor ED25519-V3 expanded secret key (SHA-512(seed), clamped,
     scalar||prefix) that ADD_ONION ED25519-V3:<key> wants (docs/04, the expanded-key
     gotcha). The curve math is the RFC 8032 reference and is self-checked against the
     standard 2*B / 3*B / 5*B multiples on startup, so a broken transcription fails
     loudly instead of pinning a wrong vector.
  4. The two SodiumXT ABI-6 primitives OnionXT composes, pinned so an implementer can
     confirm the library and SodiumXT agree: sxSignSeedToExpandedKey (seed = 0x42 x 32)
     and sxHmacSha256 (RFC 4231 HMAC-SHA256 Test Case 2).

Pure standard library only (hashlib has sha512/sha3_256/hmac; the ed25519 group math
is inlined), so it runs anywhere CI runs with no third-party dependency.

Usage:
  python3 tools/onion-kat.py            # print the vectors
  python3 tools/onion-kat.py --check    # self-test only, exit non-zero on any failure
"""

import hashlib
import hmac
import sys

# --------------------------------------------------------------------------- base32
# RFC 4648 base32, lowercase, no padding. This is pure byte manipulation (no crypto)
# and is exactly what OnionXT implements in livecodescript. Encode packs input bytes
# MSB-first into 5-bit groups; decode reverses it and drops the <5 leftover bits of
# the final group (the canonical v3 case has none: 35 bytes = 280 bits = 56*5 exactly).
_B32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567"


def base32_encode(data):
    bits = 0
    value = 0
    out = []
    for byte in data:
        value = (value << 8) | byte
        bits += 8
        while bits >= 5:
            bits -= 5
            out.append(_B32_ALPHABET[(value >> bits) & 0x1F])
    if bits > 0:                       # zero-pad the final partial group on the right
        out.append(_B32_ALPHABET[(value << (5 - bits)) & 0x1F])
    return "".join(out)


def base32_decode(text):
    text = text.lower()
    bits = 0
    value = 0
    out = bytearray()
    for ch in text:
        value = (value << 5) | _B32_ALPHABET.index(ch)
        bits += 5
        if bits >= 8:
            bits -= 8
            out.append((value >> bits) & 0xFF)
    return bytes(out)


# ----------------------------------------------------------------- v3 onion address
ONION_VERSION = b"\x03"
CHECKSUM_PREFIX = b".onion checksum"


def onion_checksum(pubkey):
    return hashlib.sha3_256(CHECKSUM_PREFIX + pubkey + ONION_VERSION).digest()[:2]


def address_from_pubkey(pubkey):
    if len(pubkey) != 32:
        raise ValueError("ed25519 public key must be 32 bytes")
    return base32_encode(pubkey + onion_checksum(pubkey) + ONION_VERSION) + ".onion"


def pubkey_from_address(address):
    core = address[:-6] if address.endswith(".onion") else address
    raw = base32_decode(core)
    if len(raw) != 35 or raw[34:35] != ONION_VERSION:
        raise ValueError("not a v3 onion address")
    return raw[:32]


# ------------------------------------------------------------- ed25519 (RFC 8032)
# The reference twisted-Edwards group math. This is NOT what OnionXT ships (SodiumXT
# owns ed25519); it is here only to derive and cross-check the seed-based vectors.
_P = 2 ** 255 - 19
_D = (-121665 * pow(121666, _P - 2, _P)) % _P
_Q = 2 ** 252 + 27742317777372353535851937790883648493


def _sha512(b):
    return hashlib.sha512(b).digest()


def _pt_add(P, Q):
    A = (P[1] - P[0]) * (Q[1] - Q[0]) % _P
    B = (P[1] + P[0]) * (Q[1] + Q[0]) % _P
    C = 2 * P[3] * Q[3] * _D % _P
    D = 2 * P[2] * Q[2] % _P
    E, F, G, H = B - A, D - C, D + C, B + A
    return (E * F % _P, G * H % _P, F * G % _P, E * H % _P)


def _pt_mul(s, P):
    Q = (0, 1, 1, 0)                   # neutral element in extended coordinates
    while s > 0:
        if s & 1:
            Q = _pt_add(Q, P)
        P = _pt_add(P, P)
        s >>= 1
    return Q


def _recover_x(y, sign):
    x2 = (y * y - 1) * pow(_D * y * y + 1, _P - 2, _P) % _P
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P != 0:
        x = x * pow(2, (_P - 1) // 4, _P) % _P
    if (x & 1) != sign:
        x = _P - x
    return x


_GY = 4 * pow(5, _P - 2, _P) % _P
_GX = _recover_x(_GY, 0)
_G = (_GX, _GY, 1, _GX * _GY % _P)


def _pt_compress(P):
    zinv = pow(P[2], _P - 2, _P)
    x = P[0] * zinv % _P
    y = P[1] * zinv % _P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def expanded_key_from_seed(seed):
    """The 64-byte Tor ED25519-V3 expanded secret key: SHA-512(seed), the first 32
    bytes clamped into the scalar a, concatenated with the prefix RH = h[32:64]."""
    if len(seed) != 32:
        raise ValueError("seed must be 32 bytes")
    h = bytearray(_sha512(seed))
    a = bytearray(h[:32])
    a[0] &= 0xF8
    a[31] &= 0x7F
    a[31] |= 0x40
    return bytes(a) + bytes(h[32:])    # 64 bytes; base64 this for ADD_ONION


def pubkey_from_seed(seed):
    """The ed25519 public key SodiumXT sxSignKeypairFromSeed would return: the
    clamped scalar times the base point, compressed."""
    scalar = int.from_bytes(expanded_key_from_seed(seed)[:32], "little")
    return _pt_compress(_pt_mul(scalar, _G))


# ------------------------------------------------------------------- self-checks
# Unambiguous ground truth so a broken build cannot pin a wrong vector.
_REAL_ONIONS = [
    "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion",  # torproject.org
    "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion",  # DuckDuckGo
]
# Standard low multiples of the ed25519 base point (well-known constants).
_BASE_MULTIPLES = {
    2: "c9a3f86aae465f0e56513864510f3997561fa2c9e85ea21dc2292309f3cd6022",
    3: "d4b4f5784868c3020403246717ec169ff79e26608ea126a1ab69ee77d1b16712",
    5: "edc876d6831fd2105d0b4389ca2e283166469289146e2ce06faefe98b22548df",
}
# The two SodiumXT ABI-6 primitives OnionXT composes (docs/08 gaps #1 and #3).
# sxSignSeedToExpandedKey(seed = 0x42 x 32):
_EXPANDED_KEY_SEED42 = (
    "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6ee"
    "da66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90"
)
# sxHmacSha256(key="Jefe", msg="what do ya want for nothing?") = RFC 4231 Test Case 2:
_HMAC_JEFE = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"


def hmac_sha256(key, message):
    return hmac.new(key, message, hashlib.sha256).digest()


def self_check():
    failures = []
    # base32 round-trips over lengths that do and do not fall on 5-bit boundaries.
    for sample in (b"", b"\x00", b"onionxt", bytes(range(35)), bytes(range(32))):
        if base32_decode(base32_encode(sample)) != sample:
            failures.append(f"base32 round-trip failed for {sample!r}")
    # ed25519 group math against the standard base-point multiples.
    for n, hexval in _BASE_MULTIPLES.items():
        if _pt_compress(_pt_mul(n, _G)).hex() != hexval:
            failures.append(f"ed25519 {n}*B mismatch")
    # v3 address logic against real, published onions (checksum + full round-trip).
    for onion in _REAL_ONIONS:
        pub = pubkey_from_address(onion)
        if address_from_pubkey(pub) != onion:
            failures.append(f"address round-trip failed for {onion}")
    # SodiumXT ABI-6 composition vectors.
    if expanded_key_from_seed(bytes([0x42]) * 32).hex() != _EXPANDED_KEY_SEED42:
        failures.append("sxSignSeedToExpandedKey vector (seed 0x42 x 32) mismatch")
    if hmac_sha256(b"Jefe", b"what do ya want for nothing?").hex() != _HMAC_JEFE:
        failures.append("sxHmacSha256 RFC 4231 TC2 vector mismatch")
    return failures


def main(argv):
    failures = self_check()
    if failures:
        for f in failures:
            print("FAIL:", f)
        return 1
    if "--check" in argv:
        print("onion-kat: self-check OK")
        return 0

    print("# OnionXT known-answer vectors (generated by tools/onion-kat.py)")
    print("# OnionXT ships none of this crypto; these pin the pure-compute results so")
    print("# the livecodescript base32/address code and a SodiumXT backend can be checked.\n")

    print("## base32 (RFC 4648 lowercase, no padding)")
    for sample in (b"onionxt", bytes(range(5)), bytes(range(32))):
        print(f"  {sample.hex():<64} -> {base32_encode(sample)}")

    print("\n## v3 onion address round-trips against real published services")
    for onion in _REAL_ONIONS:
        pub = pubkey_from_address(onion)
        print(f"  {onion}")
        print(f"    pubkey   = {pub.hex()}")
        print(f"    checksum = {onion_checksum(pub).hex()}   version = 03")

    print("\n## deterministic onion from a 32-byte seed (SodiumXT composition)")
    print("#  seed -> sxSignKeypairFromSeed -> ed25519 pubkey -> oxAddressFromPublicKey")
    print("#  seed -> SHA-512 + clamp -> 64-byte ED25519-V3 expanded key (ADD_ONION input)")
    for seed_hex in (
        "00" * 32,
        "9d61b19deffebc3a6d75a980182b10ab7d54bfed3c964073a0ee172f3daa6232",
    ):
        seed = bytes.fromhex(seed_hex)
        pub = pubkey_from_seed(seed)
        expanded = expanded_key_from_seed(seed)
        print(f"  seed       = {seed_hex}")
        print(f"    pubkey   = {pub.hex()}")
        print(f"    address  = {address_from_pubkey(pub)}")
        print(f"    expanded = {expanded.hex()}")

    print("\n## SodiumXT ABI-6 primitives OnionXT composes (pin these against SodiumXT)")
    print("#  sxSignSeedToExpandedKey(seed) -- deterministic onion (docs/08 gap #1, SHIPPED)")
    print(f"  seed=0x42 x 32 -> expanded = {expanded_key_from_seed(bytes([0x42]) * 32).hex()}")
    print("#  sxHmacSha256(key, msg) -- SAFECOOKIE control auth (docs/08 gap #3, SHIPPED)")
    print("#  RFC 4231 Test Case 2:")
    print(f'  key="Jefe" msg="what do ya want for nothing?" -> {hmac_sha256(b"Jefe", b"what do ya want for nothing?").hex()}')
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
