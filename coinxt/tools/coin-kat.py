#!/usr/bin/env python3
"""coin-kat.py - known-answer vectors for the CoinXT native shim.

CoinXT wraps trezor-crypto behind the cnx_ ABI. Unlike a pure-script library, the
native shim IS testable headless: this harness builds the shared library from the
vendored source, drives it through ctypes, and checks every deterministic output
against a PUBLIC known-answer vector, cross-checked against an independent
implementation (Python's hashlib) before pinning. It is the CoinXT analogue of
OnionXT's onion-kat.py.

Phase 1 covers the whole hash surface: Keccak-256, SHA3-256, SHA-256, SHA-512,
RIPEMD-160, HMAC-SHA256/512, and PBKDF2-HMAC-SHA512 (the BIP-39 mnemonic-to-seed
KDF), plus the shim's fail-closed guards. Phase 2 adds secp256k1: public keys,
RFC 6979 deterministic ECDSA, verification (including what it must REJECT),
recoverable signing, ecrecover, and ECDH. Later phases extend this file with
BIP-32 / BIP-39 wallet vectors and the script-side encoders (once those exist).

Every digest is pinned to a PUBLIC vector AND, where Python ships an independent
implementation of the same primitive, cross-checked against it live. RIPEMD-160
is the exception: OpenSSL 3 moved it to the legacy provider, so hashlib often
cannot supply it. There the published vectors stand alone and the harness says
so rather than silently skipping the check.

For the curve the independent implementation is the `ecdsa` package, which is
optional: without it the published RFC 6979 vectors still run and the harness
says the cross-library leg was skipped. With it, the harness proves the claim
the implementation plan actually asks for - that a signature CoinXT produced
verifies in a mainstream library, and that a signature that library produced
verifies in CoinXT.

Usage:
  python3 coin-kat.py            # build + run the vectors, print each result
  python3 coin-kat.py --check    # same, but terse: one OK line or a non-zero exit

If no C compiler is available, the harness prints a clear skip line and exits 0
(so a docs-only environment does not fail); where cc exists, it runs for real.
"""

import ctypes
import hashlib
import hmac as pyhmac
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
NATIVE = os.path.normpath(os.path.join(HERE, "..", "native"))
VENDOR = os.path.join(NATIVE, "vendor")

# Published Keccak-256 (Ethereum, 0x01 padding) vectors. These are burned-in,
# widely-cited answers; SHA3-256 is cross-checked live against hashlib instead.
KECCAK256 = {
    b"": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
    b"abc": "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
}
SHA3_INPUTS = [b"", b"abc", b"The quick brown fox jumps over the lazy dog"]

# Published SHA-2 vectors (FIPS 180-4 examples). Also cross-checked against
# hashlib below, which is the independent implementation.
SHA256 = {
    b"": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    b"abc": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
}
SHA512 = {
    b"": ("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
          "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"),
    b"abc": ("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
             "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"),
}

# The published RIPEMD-160 vectors from the algorithm's own specification. These
# stand alone: hashlib usually cannot provide ripemd160 on OpenSSL 3, so there is
# no second opinion available for this one primitive (reported, never skipped).
RIPEMD160 = {
    b"": "9c1185a5c5e9fc54612808977ee8f548b2258d31",
    b"a": "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe",
    b"abc": "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc",
    b"message digest": "5d0689ef49d2fae572b881b123a85ffa21595f36",
}

# RFC 4231 HMAC test cases 1 and 2 (key, message) -> (sha256 mac, sha512 mac).
HMAC_CASES = [
    (b"\x0b" * 20, b"Hi There",
     "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
     "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde"
     "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"),
    (b"Jefe", b"what do ya want for nothing?",
     "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
     "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554"
     "9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"),
]

# The BIP-39 mnemonic-to-seed vector everyone knows: the all-"abandon" sentence
# with the passphrase "TREZOR". This is the exact shape CoinXT will use the KDF
# for (salt = "mnemonic" + passphrase, 2048 iterations, a 64-byte seed), so it
# pins the real call, not just the primitive.
BIP39_MNEMONIC = (b"abandon abandon abandon abandon abandon abandon "
                  b"abandon abandon abandon abandon abandon about")
BIP39_SALT = b"mnemonicTREZOR"
BIP39_ITERS = 2048
BIP39_SEED = ("c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553"
              "1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04")

# ---------------------------------------------------------------------------
# Phase 4: BIP-39's wordlist and BIP-32's derivation chain.
# ---------------------------------------------------------------------------
# BIP-39 identifies the English wordlist by the SHA-256 of its canonical
# newline-joined form. It is the whole interoperability claim in 32 bytes.
BIP39_WORDLIST_SHA256 = \
    "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"

# BIP-32 test vector 1: the seed, and the private key at each level of
# m/0'/1/2'/2/1000000000 as the BIP publishes it. Walking this with the two
# tweak exports is what proves they are a real CKDpriv/CKDpub pair rather than
# merely self-consistent arithmetic.
BIP32_SEED = "000102030405060708090a0b0c0d0e0f"
BIP32_CHAIN = [
    (0x80000000, "edb2e14f9ee77d26dd93b4ecede8d16ed408ce149b6cd80b0715a2d911a0afea"),
    (1, "3c6cb8d0f6a264c91ea8b5030fadaa8e538b020f0a387421a12de9319dc93368"),
    (0x80000002, "cbce0d719ecf7431d88e6a89fa1483e02e35092af60c042b1df2ff59fa424dca"),
    (2, "0f479245fb19a38a1954c5c7c0ebab2f9bdfd96a17563ef28a6a4b1a2a764ef4"),
    (1000000000, "471b76e389e528d6de6d816857e012c5455051cad6660850e58372a6c3e6e7c8"),
]

# ---------------------------------------------------------------------------
# Phase 2: secp256k1.
# ---------------------------------------------------------------------------
SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

# Private key 1 is the generator G and private key 2 is 2G, so these two are the
# most-published public keys on the curve and need no second opinion to trust.
PUBKEYS = [
    (1,
     "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
     "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
     "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"),
    (2,
     "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
     "04c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
     "1ae168fea63dc339a3c58419466ceaeef7f632653266d0e1236431a950cfe52a"),
]

# RFC 6979 deterministic ECDSA over secp256k1 with SHA-256, as (private key,
# message, r||s). These are the widely republished vectors for this exact curve
# and hash; the signature is low-s, which is what both Bitcoin relay policy
# (BIP-62) and Ethereum consensus require and what upstream always emits.
#
# They are the whole point of the phase: because RFC 6979 makes the nonce a pure
# function of (key, digest), a signature is reproducible, so it can be PINNED.
# The native code still draws OS entropy for side-channel blinding on every
# call - that blinding cancels out of the result algebraically, and the
# determinism check at the end of this section is what proves it empirically
# rather than by reading the arithmetic.
RFC6979 = [
    (1, b"Satoshi Nakamoto",
     "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8"
     "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"),
    (1, b"All those moments will be lost in time, like tears in rain. Time to die...",
     "8600dbd41e348fe5c9465ab92d23e3db8b98b873beecd930736488696438cb6b"
     "547fe64427496db33bf66019dacbf0039c04199abb0122918601db38a72cfc21"),
    (0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140,
     b"Satoshi Nakamoto",
     "fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d0"
     "6b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebed3f153d10d93bed5"),
    (1, b"Everything should be made as simple as possible, but not simpler.",
     "33a69cd2065432a30f3d1ce4eb0d59b8ab58c74f27c41a7fdb5696ad4e6108c9"
     "6f807982866f785d3f6418d24163ddae117b7db4d5fdf0071de069fa54342262"),
]

# A recoverable signature and the key it recovers to. Unlike the four above this
# is not a published vector (recoverable ECDSA has no canonical vector set), so
# it was PINNED ONLY AFTER the 64-byte half was verified in the independent
# Python `ecdsa` library and the recovered key was checked to equal the signer.
# It guards the one byte those published vectors cannot: the recovery id.
RECOVERABLE_SK = "18e14a7b6a307f426a94f8114701e7c8e774e7f9a47e2c2035db29a206321725"
RECOVERABLE_MSG = b"CoinXT recoverable vector"
RECOVERABLE_SIG = ("7c2ace7a3b9079e5d2cf1ba5b01ae4942f9a9ed9b1a7b89b256f9754113187f2"
                   "2299d0cecba3ac960a8dc89b69d1859e20512c992db7ce8bd99649efbabae789"
                   "01")
RECOVERABLE_PUB = ("0450863ad64a87ae8a2fe83c1af1a8403cb53f53e486d8511dad8a04887e5b235"
                   "22cd470243453a299fa9e77237716103abc11a1df38855ed6f2ee187e9c582ba6")

# ECDH. Also pinned only after being reproduced independently (a * B computed
# with `ecdsa`'s point arithmetic). The value is the RAW shared point, 0x04 ||
# X || Y, not a key: see cnx_ecdh on why nothing is hashed here.
ECDH_A = "11223344556677889900aabbccddeeff00112233445566778899aabbccddeeff"
ECDH_B = "0fedcba987654321fedcba987654321fedcba987654321fedcba9876543210fe"
ECDH_POINT = ("04283ac952766cd1d14796687a482fad6f1799c736b2a096ef860c8c4bc2f234b2"
              "e9b6dab6c944216415d2df49de199ef71e3bad81ac3d72553fd0ce73a1760610")


# ---------------------------------------------------------------------------
# ABI 6: BIP-340 (Schnorr) and BIP-341 (Taproot).
# ---------------------------------------------------------------------------
# BIP-340's OFFICIAL test-vectors.csv, transcribed in full and in order.
#
#   source: https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
#   fetched: 2026-08-16
#
# Fields, in the CSV's own order: index, secret key (empty for a
# verify-only case), public key (x-only), aux_rand, message, signature,
# expected verification result, comment.
#
# TEN OF THE NINETEEN ARE NEGATIVE, and that is what this file is for. A
# Schnorr implementation that only ever sees good signatures passes every
# positive vector while accepting a forged one; indices 5 to 14 are the set
# that separates the two (a public key off the curve, has_even_y(R) false, a
# negated message, a negated s, two infinity cases, an x that is not on the
# curve, an r equal to the field size, an s equal to the group order, and a
# public key past the field size). Indices 15 to 18 were added in 2022 for
# messages of length 0, 1, 17 and 100.
BIP340_VECTORS = [
    # 0: valid
    (0, '0000000000000000000000000000000000000000000000000000000000000003', 'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9', '0000000000000000000000000000000000000000000000000000000000000000', '0000000000000000000000000000000000000000000000000000000000000000',
     'e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca821525f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0', True),
    # 1: valid
    (1, 'b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '0000000000000000000000000000000000000000000000000000000000000001', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de33418906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a', True),
    # 2: valid
    (2, 'c90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b14e5c9', 'dd308afec5777e13121fa72b9cc1b7cc0139715309b086c960e18fd969774eb8', 'c87aa53824b4d7ae2eb035a2b5bbbccc080e76cdc6d1692c4b0b62d798e6d906', '7e2d58d8b3bcdf1abadec7829054f90dda9805aab56c77333024b9d0a508b75c',
     '5831aaeed7b44bb74e5eab94ba9d4294c49bcf2a60728d8b4c200f50dd313c1bab745879a5ad954a72c45a91c3a51d3c7adea98d82f8481e0e1e03674a6f3fb7', True),
    # 3: test fails if msg is reduced modulo p or n
    (3, '0b432b2677937381aef05bb02a66ecd012773062cf3fa2549e44f58ed2401710', '25d1dff95105f5253c4022f628a996ad3a0d95fbf21d468a1b33f8c160d8f517', 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
     '7eb0509757e246f19449885651611cb965ecc1a187dd51b64fda1edc9637d5ec97582b9cb13db3933705b32ba982af5af25fd78881ebb32771fc5922efc66ea3', True),
    # 4: valid
    (4, '', 'd69c3509bb99e412e68b0fe8544e72837dfa30746d8be2aa65975f29d22dc7b9', '', '4df3c3f68fcc83b27e9d42c90431a72499f17875c81a599b566c9889b9696703',
     '00000000000000000000003b78ce563f89a0ed9414f5aa28ad0d96d6795f9c6376afb1548af603b3eb45c9f8207dee1060cb71c04e80f593060b07d28308d7f4', True),
    # 5: public key not on the curve
    (5, '', 'eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e17776969e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b', False),
    # 6: has_even_y(R) is false
    (6, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     'fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a14602975563cc27944640ac607cd107ae10923d9ef7a73c643e166be5ebeafa34b1ac553e2', False),
    # 7: negated message
    (7, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '1fa62e331edbc21c394792d2ab1100a7b432b013df3f6ff4f99fcb33e0e1515f28890b3edb6e7189b630448b515ce4f8622a954cfe545735aaea5134fccdb2bd', False),
    # 8: negated s value
    (8, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e177769961764b3aa9b2ffcb6ef947b6887a226e8d7c93e00c5ed0c1834ff0d0c2e6da6', False),
    # 9: sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 0
    (9, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '0000000000000000000000000000000000000000000000000000000000000000123dda8328af9c23a94c1feecfd123ba4fb73476f0d594dcb65c6425bd186051', False),
    # 10: sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 1
    (10, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '00000000000000000000000000000000000000000000000000000000000000017615fbaf5ae28864013c099742deadb4dba87f11ac6754f93780d5a1837cf197', False),
    # 11: sig[0:32] is not an X coordinate on the curve
    (11, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '4a298dacae57395a15d0795ddbfd1dcb564da82b0f269bc70a74f8220429ba1d69e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b', False),
    # 12: sig[0:32] is equal to field size
    (12, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f69e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b', False),
    # 13: sig[32:64] is equal to curve order
    (13, '', 'dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e177769fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141', False),
    # 14: public key is not a valid X coordinate because it exceeds the field size
    (14, '', 'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc30', '', '243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89',
     '6cff5c3ba86c69ea4b7376f31a9bcb4f74c1976089b2d9963da2e5543e17776969e89b4c5564d00349106b8497785dd7d1d713a8ae82b32fa79d5f7fc407d39b', False),
    # 15: message of size 0 (added 2022-12)
    (15, '0340034003400340034003400340034003400340034003400340034003400340', '778caa53b4393ac467774d09497a87224bf9fab6f6e68b23086497324d6fd117', '0000000000000000000000000000000000000000000000000000000000000000', '',
     '71535db165ecd9fbbc046e5ffaea61186bb6ad436732fccc25291a55895464cf6069ce26bf03466228f19a3a62db8a649f2d560fac652827d1af0574e427ab63', True),
    # 16: message of size 1 (added 2022-12)
    (16, '0340034003400340034003400340034003400340034003400340034003400340', '778caa53b4393ac467774d09497a87224bf9fab6f6e68b23086497324d6fd117', '0000000000000000000000000000000000000000000000000000000000000000', '11',
     '08a20a0afef64124649232e0693c583ab1b9934ae63b4c3511f3ae1134c6a303ea3173bfea6683bd101fa5aa5dbc1996fe7cacfc5a577d33ec14564cec2bacbf', True),
    # 17: message of size 17 (added 2022-12)
    (17, '0340034003400340034003400340034003400340034003400340034003400340', '778caa53b4393ac467774d09497a87224bf9fab6f6e68b23086497324d6fd117', '0000000000000000000000000000000000000000000000000000000000000000', '0102030405060708090a0b0c0d0e0f1011',
     '5130f39a4059b43bc7cac09a19ece52b5d8699d1a71e3c52da9afdb6b50ac370c4a482b77bf960f8681540e25b6771ece1e5a37fd80e5a51897c5566a97ea5a5', True),
    # 18: message of size 100 (added 2022-12)
    (18, '0340034003400340034003400340034003400340034003400340034003400340', '778caa53b4393ac467774d09497a87224bf9fab6f6e68b23086497324d6fd117', '0000000000000000000000000000000000000000000000000000000000000000', '99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
     '403b12b0d8555a344175ea7ec746566303321e5dbfa8be6f091635163eca79a8585ed3e3170807e7c03b720fc54c7b23897fcba0e9d0b4a06894cfd249f22367', True),
]

# BIP-341's OFFICIAL wallet test vectors, the two sections a key-path wallet
# needs.
#
#   source: https://github.com/bitcoin/bips/blob/master/bip-0341/wallet-test-vectors.json
#   fetched: 2026-08-16
#
# TAPROOT_SPK: (internal x-only key, merkle root or None, expected tweak,
# expected tweaked x-only output key, expected scriptPubKey). Entry 0 is the
# KEY-PATH-ONLY case - merkle root None, i.e. the specification's EMPTY BYTE
# STRING - which is the one that separates a correct implementation from one
# that hashes 32 zero bytes instead.
TAPROOT_SPK = [
    ('d6889cb081036e0faefa3a35157ad71086b123b2b144b649798b494c300a961d',
     None,
     'b86e7be8f39bab32a6f2c0443abbc210f0edac0e2c53d501b36b64437d9c6c70',
     '53a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343',
     '512053a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343'),
    ('187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27',
     '5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21',
     'cbd8679ba636c1110ea247542cfbd964131a6be84f873f7f3b62a777528ed001',
     '147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3',
     '5120147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3'),
    ('93478e9488f956df2396be2ce6c5cced75f900dfa18e7dabd2428aae78451820',
     'c525714a7f49c28aedbbba78c005931a81c234b2f6c99a73e4d06082adc8bf2b',
     '6af9e28dbf9d6aaf027696e2598a5b3d056f5fd2355a7fd5a37a0e5008132d30',
     'e4d810fd50586274face62b8a807eb9719cef49c04177cc6b76a9a4251d5450e',
     '5120e4d810fd50586274face62b8a807eb9719cef49c04177cc6b76a9a4251d5450e'),
    ('ee4fe085983462a184015d1f782d6a5f8b9c2b60130aff050ce221ecf3786592',
     '6c2dc106ab816b73f9d07e3cd1ef2c8c1256f519748e0813e4edd2405d277bef',
     '9e0517edc8259bb3359255400b23ca9507f2a91cd1e4250ba068b4eafceba4a9',
     '712447206d7a5238acc7ff53fbe94a3b64539ad291c7cdbc490b7577e4b17df5',
     '5120712447206d7a5238acc7ff53fbe94a3b64539ad291c7cdbc490b7577e4b17df5'),
    ('f9f400803e683727b14f463836e1e78e1c64417638aa066919291a225f0e8dd8',
     'ab179431c28d3b68fb798957faf5497d69c883c6fb1e1cd9f81483d87bac90cc',
     '639f0281b7ac49e742cd25b7f188657626da1ad169209078e2761cefd91fd65e',
     '77e30a5522dd9f894c3f8b8bd4c4b2cf82ca7da8a3ea6a239655c39c050ab220',
     '512077e30a5522dd9f894c3f8b8bd4c4b2cf82ca7da8a3ea6a239655c39c050ab220'),
    ('e0dfe2300b0dd746a3f8674dfd4525623639042569d829c7f0eed9602d263e6f',
     'ccbd66c6f7e8fdab47b3a486f59d28262be857f30d4773f2d5ea47f7761ce0e2',
     'b57bfa183d28eeb6ad688ddaabb265b4a41fbf68e5fed2c72c74de70d5a786f4',
     '91b64d5324723a985170e4dc5a0f84c041804f2cd12660fa5dec09fc21783605',
     '512091b64d5324723a985170e4dc5a0f84c041804f2cd12660fa5dec09fc21783605'),
    ('55adf4e8967fbd2e29f20ac896e60c3b0f1d5b0efa9d34941b5958c7b0a0312d',
     '2f6b2c5397b6d68ca18e09a3f05161668ffe93a988582d55c6f07bd5b3329def',
     '6579138e7976dc13b6a92f7bfd5a2fc7684f5ea42419d43368301470f3b74ed9',
     '75169f4001aa68f15bbed28b218df1d0a62cbbcf1188c6665110c293c907b831',
     '512075169f4001aa68f15bbed28b218df1d0a62cbbcf1188c6665110c293c907b831'),
]

# TAPROOT_KEYPATH: (internal private key, merkle root or None, expected
# internal x-only pubkey, expected TWEAKED private key, the BIP-341 sighash
# this input signs, and the 64-byte BIP-340 signature the specification
# publishes in its expected witness).
#
# This is the strongest vector in the file: it walks a private key all the way
# to a published witness - internal seckey -> x-only internal pubkey ->
# tweaked seckey -> BIP-340 signature over BIP-341's own sighash - so a defect
# anywhere in that chain shows up as a byte difference against bytes Bitcoin's
# own specification prints. The signatures reproduce with aux_rand = 32 zero
# bytes, which is what the vector generator used; that is asserted rather than
# assumed (a wrong aux gives a different, still-valid signature, so a harness
# that only checked "it verifies" would not notice).
TAPROOT_KEYPATH = [
    ('6b973d88838f27366ed61c9ad6367663045cb456e28335c109e30717ae0c6baa',
     None,
     'd6889cb081036e0faefa3a35157ad71086b123b2b144b649798b494c300a961d',
     '2405b971772ad26915c8dcdf10f238753a9b837e5f8e6a86fd7c0cce5b7296d9',
     '2514a6272f85cfa0f45eb907fcb0d121b808ed37c6ea160a5a9046ed5526d555',
     'ed7c1647cb97379e76892be0cacff57ec4a7102aa24296ca39af7541246d8ff14d38958d4cc1e2e478e4d4a764bbfd835b16d4e314b72937b29833060b87276c'),
    ('1e4da49f6aaf4e5cd175fe08a32bb5cb4863d963921255f33d3bc31e1343907f',
     '5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21',
     '187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27',
     'ea260c3b10e60f6de018455cd0278f2f5b7e454be1999572789e6a9565d26080',
     '325a644af47e8a5a2591cda0ab0723978537318f10e6a63d4eed783b96a71a4d',
     '052aedffc554b41f52b521071793a6b88d6dbca9dba94cf34c83696de0c1ec35ca9c5ed4ab28059bd606a4f3a657eec0bb96661d42921b5f50a95ad33675b54f'),
    ('d3c7af07da2d54f7a7735d3d0fc4f0a73164db638b2f2f7c43f711f6d4aa7e64',
     'c525714a7f49c28aedbbba78c005931a81c234b2f6c99a73e4d06082adc8bf2b',
     '93478e9488f956df2396be2ce6c5cced75f900dfa18e7dabd2428aae78451820',
     '97323385e57015b75b0339a549c56a948eb961555973f0951f555ae6039ef00d',
     'bf013ea93474aa67815b1b6cc441d23b64fa310911d991e713cd34c7f5d46669',
     'ff45f742a876139946a149ab4d9185574b98dc919d2eb6754f8abaa59d18b025637a3aa043b91817739554f4ed2026cf8022dbd83e351ce1fabc272841d2510a'),
    ('f36bb07a11e469ce941d16b63b11b9b9120a84d9d87cff2c84a8d4affb438f4e',
     'ccbd66c6f7e8fdab47b3a486f59d28262be857f30d4773f2d5ea47f7761ce0e2',
     'e0dfe2300b0dd746a3f8674dfd4525623639042569d829c7f0eed9602d263e6f',
     'a8e7aa924f0d58854185a490e6c41f6efb7b675c0f3331b7f14b549400b4d501',
     '4f900a0bae3f1446fd48490c2958b5a023228f01661cda3496a11da502a7f7ef',
     'b4010dd48a617db09926f729e79c33ae0b4e94b79f04a1ae93ede6315eb3669de185a17d2b0ac9ee09fd4c64b678a0b61a0a86fa888a273c8511be83bfd6810f'),
    ('415cfe9c15d9cea27d8104d5517c06e9de48e2f986b695e4f5ffebf230e725d8',
     '2f6b2c5397b6d68ca18e09a3f05161668ffe93a988582d55c6f07bd5b3329def',
     '55adf4e8967fbd2e29f20ac896e60c3b0f1d5b0efa9d34941b5958c7b0a0312d',
     '241c14f2639d0d7139282aa6abde28dd8a067baa9d633e4e7230287ec2d02901',
     '15f25c298eb5cdc7eb1d638dd2d45c97c4c59dcaec6679cfc16ad84f30876b85',
     'a3785919a2ce3c4ce26f298c3d51619bc474ae24014bcdd31328cd8cfbab2eff3395fa0a16fe5f486d12f22a9cedded5ae74feb4bbe5351346508c5405bcfee0'),
    ('c7b0e81f0a9a0b0499e112279d718cca98e79a12e2f137c72ae5b213aad0d103',
     '6c2dc106ab816b73f9d07e3cd1ef2c8c1256f519748e0813e4edd2405d277bef',
     'ee4fe085983462a184015d1f782d6a5f8b9c2b60130aff050ce221ecf3786592',
     '65b6000cd2bfa6b7cf736767a8955760e62b6649058cbc970b7c0871d786346b',
     'cd292de50313804dabe4685e83f923d2969577191a3e1d2882220dca88cbeb10',
     'ea0c6ba90763c2d3a296ad82ba45881abb4f426b3f87af162dd24d5109edc1cdd11915095ba47c3a9963dc1e6c432939872bc49212fe34c632cd3ab9fed429c4'),
    ('77863416be0d0665e517e1c375fd6f75839544eca553675ef7fdf4949518ebaa',
     'ab179431c28d3b68fb798957faf5497d69c883c6fb1e1cd9f81483d87bac90cc',
     'f9f400803e683727b14f463836e1e78e1c64417638aa066919291a225f0e8dd8',
     'ec18ce6af99f43815db543f47b8af5ff5df3b2cb7315c955aa4a86e8143d2bf5',
     'cccb739eca6c13a8a89e6e5cd317ffe55669bbda23f2fd37b0f18755e008edd2',
     'bbc9584a11074e83bc8c6759ec55401f0ae7b03ef290c3139814f545b58a9f8127258000874f44bc46db7646322107d4d86aec8e73b8719a61fff761d75b5dd9'),
]


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
    """The vendored translation units, READ FROM native/build.sh rather than
    listed again here.

    This used to be a second hand-maintained copy of the same list, which is a
    quiet way to lie: the harness would happily build and bless a set of sources
    that is not the set the shipped library is compiled from, and the two only
    have to diverge by one file for the KATs to be testing something nobody
    installs. build.sh is the single source of truth; a parse failure is fatal
    rather than a fallback, because a fallback would restore the same lie.
    """
    path = os.path.join(NATIVE, "build.sh")
    with open(path, encoding="utf-8") as fh:
        m = re.search(r'vendor_src="([^"]*)"', fh.read(), re.S)
    if m is None:
        raise SystemExit("coin-kat: could not read vendor_src from native/build.sh; "
                         "the harness refuses to guess which sources ship")
    files = [p.strip() for p in m.group(1).replace("\\\n", " ").split()]
    out = []
    for f in files:
        if not f.startswith("$ven/"):
            raise SystemExit(f"coin-kat: unexpected entry {f!r} in build.sh vendor_src")
        p = os.path.join(VENDOR, f[len("$ven/"):])
        if not os.path.exists(p):
            raise SystemExit(f"coin-kat: build.sh names {f} but it is not vendored")
        out.append(p)
    return out


def build_var(name, pattern=r'{}="([^"]*)"'):
    """Read one shell variable out of native/build.sh.

    Same reasoning as vendor_sources: build.sh is the single source of truth for
    what the shipped library is made of AND how it is compiled, and a second
    hand-maintained copy here is a quiet way to test something nobody installs.
    A parse failure is fatal rather than a fallback."""
    path = os.path.join(NATIVE, "build.sh")
    with open(path, encoding="utf-8") as fh:
        m = re.search(pattern.format(name), fh.read(), re.S)
    if m is None:
        raise SystemExit(f"coin-kat: could not read {name} from native/build.sh; "
                         "the harness refuses to guess how the library is built")
    return m.group(1).replace("\\\n", " ").split()


def secp_sources():
    """Upstream libsecp256k1's translation units (ABI 6: BIP-340 / BIP-341)."""
    out = []
    for f in build_var("secp_src"):
        if not f.startswith("$ven/"):
            raise SystemExit(f"coin-kat: unexpected entry {f!r} in build.sh secp_src")
        p = os.path.join(VENDOR, f[len("$ven/"):])
        if not os.path.exists(p):
            raise SystemExit(f"coin-kat: build.sh names {f} but it is not vendored")
        out.append(p)
    return out


def build_lib(cc, out_path):
    """Compile the shim, trezor-crypto and libsecp256k1 into one shared object.

    TWO GROUPS, TWO WARNING SCOPES, exactly as native/build.sh does it and for
    the same two reasons: upstream libsecp256k1 needs -Wno-unused-function
    (it compiles as one unit and leaves the disabled modules' helpers unused),
    and vendor/secp256k1.c and vendor/libsecp256k1/src/secp256k1.c share a
    BASENAME, so object files derived from it collide."""
    cflags = build_var("secp_cppflags")
    swarn = build_var("secp_warn")
    objs = []
    outdir = os.path.dirname(os.path.abspath(out_path))
    for src in secp_sources():
        obj = os.path.join(outdir, "secp_" + os.path.basename(src)[:-2] + ".o")
        subprocess.run([cc, "-O2", "-Wall", "-Wextra", *swarn, *cflags,
                        "-fPIC", "-c", src, "-o", obj], check=True)
        objs.append(obj)
    src = [os.path.join(NATIVE, "coinxt.c"), *vendor_sources()]
    cmd = [cc, "-O2", "-Wall", "-Wextra", *cflags, "-isystem", VENDOR,
           "-fPIC", "-shared", *src, *objs, "-o", out_path]
    # The shim draws blinding entropy from BCryptGenRandom on Windows; every
    # other platform gets it from libc (getrandom / arc4random_buf).
    if sys.platform.startswith("win") or out_path.endswith(".dll"):
        cmd.append("-lbcrypt")
    subprocess.run(cmd, check=True)


def load(out_path):
    lib = ctypes.CDLL(out_path)
    lib.cnx_abi_version.restype = ctypes.c_int
    # in-buffer + length -> out-buffer, the shape of every one-shot digest.
    for fn in ("cnx_keccak256", "cnx_sha3_256", "cnx_sha256", "cnx_sha512",
               "cnx_ripemd160"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    # key + msg -> mac.
    for fn in ("cnx_hmac_sha256", "cnx_hmac_sha512"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                      ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lib.cnx_pbkdf2_hmac_sha512.restype = ctypes.c_int
    lib.cnx_pbkdf2_hmac_sha512.argtypes = [
        ctypes.c_char_p, ctypes.c_size_t,   # password
        ctypes.c_char_p, ctypes.c_size_t,   # salt
        ctypes.c_uint32,                    # iterations
        ctypes.c_char_p, ctypes.c_size_t,   # out, outlen
    ]
    # ABI 5: the secret-hygiene wipe the .lcb runs on every out-buffer before
    # freeing it (internal to the binding; no public cx* wrapper exists).
    lib.cnx_memzero.restype = ctypes.c_int
    lib.cnx_memzero.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    # ---- the phase-2 curve surface ------------------------------------------
    # Every buffer crosses as pointer + size_t length, so the pubkey argument
    # carries its own length and the shim can refuse a length that disagrees
    # with the prefix byte (the overread guard; see native/coinxt.c).
    lib.cnx_seckey_verify.restype = ctypes.c_int
    lib.cnx_seckey_verify.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_pubkey_from_seckey.restype = ctypes.c_int
    lib.cnx_pubkey_from_seckey.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_int,
                                           ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_pubkey_decompress.restype = ctypes.c_int
    lib.cnx_pubkey_decompress.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                          ctypes.c_char_p, ctypes.c_size_t]
    for fn in ("cnx_ecdsa_sign", "cnx_ecdsa_sign_recoverable"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t,   # seckey
                      ctypes.c_char_p, ctypes.c_size_t,   # digest
                      ctypes.c_char_p, ctypes.c_size_t]   # out
    lib.cnx_ecdsa_verify.restype = ctypes.c_int
    lib.cnx_ecdsa_verify.argtypes = [ctypes.c_char_p, ctypes.c_size_t,  # pubkey
                                     ctypes.c_char_p, ctypes.c_size_t,  # digest
                                     ctypes.c_char_p, ctypes.c_size_t]  # sig
    lib.cnx_ecdsa_recover.restype = ctypes.c_int
    lib.cnx_ecdsa_recover.argtypes = [ctypes.c_char_p, ctypes.c_size_t,  # sig65
                                      ctypes.c_char_p, ctypes.c_size_t,  # digest
                                      ctypes.c_char_p, ctypes.c_size_t]  # out
    lib.cnx_ecdh.restype = ctypes.c_int
    lib.cnx_ecdh.argtypes = [ctypes.c_char_p, ctypes.c_size_t,   # seckey
                             ctypes.c_char_p, ctypes.c_size_t,   # pubkey
                             ctypes.c_char_p, ctypes.c_size_t]   # out
    # ---- the ABI 6 surface: BIP-340 Schnorr and the BIP-341 tweak ----------
    # Every buffer is pointer + size_t, like everything above. The two OPTIONAL
    # inputs (the BIP-340 aux_rand, the BIP-341 merkle root) are carried by
    # LENGTH: 0 means absent, and absent is NOT an all-zero value in either
    # case. ctypes passes None for a NULL char_p, which is what a length-0
    # buffer becomes.
    lib.cnx_schnorr_sign.restype = ctypes.c_int
    lib.cnx_schnorr_sign.argtypes = [ctypes.c_char_p, ctypes.c_size_t,   # seckey
                                     ctypes.c_char_p, ctypes.c_size_t,   # message
                                     ctypes.c_char_p, ctypes.c_size_t,   # aux_rand
                                     ctypes.c_char_p, ctypes.c_size_t]   # out
    lib.cnx_schnorr_verify.restype = ctypes.c_int
    lib.cnx_schnorr_verify.argtypes = [ctypes.c_char_p, ctypes.c_size_t,  # x-only key
                                       ctypes.c_char_p, ctypes.c_size_t,  # message
                                       ctypes.c_char_p, ctypes.c_size_t]  # signature
    lib.cnx_xonly_pubkey_from_seckey.restype = ctypes.c_int
    lib.cnx_xonly_pubkey_from_seckey.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                                 ctypes.c_char_p, ctypes.c_size_t]
    for fn in ("cnx_taproot_tweak_pubkey", "cnx_taproot_tweak_seckey"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t,   # internal key / seckey
                      ctypes.c_char_p, ctypes.c_size_t,   # merkle root (optional)
                      ctypes.c_char_p, ctypes.c_size_t]   # out
    for fn in ("cnx_sha256_len", "cnx_sha512_len", "cnx_ripemd160_len",
               "cnx_hmac_sha256_len", "cnx_hmac_sha512_len",
               "cnx_keccak256_len", "cnx_sha3_256_len",
               "cnx_seckey_len", "cnx_pubkey_len_compressed",
               "cnx_pubkey_len_uncompressed", "cnx_ecdsa_sig_len",
               "cnx_recoverable_sig_len", "cnx_ecdh_len",
               "cnx_schnorr_sig_len", "cnx_xonly_pubkey_len",
               "cnx_taproot_output_len"):
        getattr(lib, fn).restype = ctypes.c_size_t
    return lib


# ---------------------------------------------------------------------------
# Curve helpers. Each returns (status, bytes) so a KAT can assert on either.
# ---------------------------------------------------------------------------

def pubkey(lib, sk, compressed=True):
    n = 33 if compressed else 65
    out = ctypes.create_string_buffer(n)
    rc = lib.cnx_pubkey_from_seckey(sk, len(sk), 1 if compressed else 0, out, n)
    return rc, out.raw[:n]


def sign(lib, sk, dg, recoverable=False):
    n = 65 if recoverable else 64
    out = ctypes.create_string_buffer(n)
    fn = lib.cnx_ecdsa_sign_recoverable if recoverable else lib.cnx_ecdsa_sign
    rc = fn(sk, len(sk), dg, len(dg), out, n)
    return rc, out.raw[:n]


def recover(lib, sig65, dg):
    out = ctypes.create_string_buffer(65)
    rc = lib.cnx_ecdsa_recover(sig65, len(sig65), dg, len(dg), out, 65)
    return rc, out.raw[:65]


def ecdh(lib, sk, pub):
    out = ctypes.create_string_buffer(65)
    rc = lib.cnx_ecdh(sk, len(sk), pub, len(pub), out, 65)
    return rc, out.raw[:65]


def digest(lib, fn, data, outlen=32):
    """Drive a one-shot digest. `data` may be None to exercise the NULL path."""
    out = ctypes.create_string_buffer(outlen)
    rc = getattr(lib, fn)(data, 0 if data is None else len(data), out)
    if rc != 0:
        raise RuntimeError(f"{fn} returned {rc}")
    return out.raw.hex()


def mac(lib, fn, key, msg, outlen):
    out = ctypes.create_string_buffer(outlen)
    rc = getattr(lib, fn)(key, len(key), msg, len(msg), out)
    if rc != 0:
        raise RuntimeError(f"{fn} returned {rc}")
    return out.raw.hex()


def pbkdf2(lib, pw, salt, iters, outlen):
    out = ctypes.create_string_buffer(outlen)
    rc = lib.cnx_pbkdf2_hmac_sha512(pw, len(pw), salt, len(salt), iters, out, outlen)
    if rc != 0:
        raise RuntimeError(f"cnx_pbkdf2_hmac_sha512 returned {rc}")
    return out.raw.hex()


def main(argv):
    check = "--check" in argv[1:]

    # --lib <path>: drive an ALREADY-BUILT library instead of compiling a fresh
    # one. The default (build from source in a temp dir) is what the gates want:
    # it tests the SOURCE and cannot be fooled by a stale artifact. But a release
    # artifact needs the opposite question answered - "does THIS FILE, the one we
    # are about to ship, produce the right answers?" - and for a cross-compiled
    # Windows DLL that question can only be asked on Windows, against the exact
    # binary. Same vectors either way; only the subject changes.
    given = None
    if "--lib" in argv[1:]:
        i = argv.index("--lib")
        if i + 1 >= len(argv):
            print("coin-kat: --lib needs a path")
            return 2
        given = argv[i + 1]
        if not os.path.exists(given):
            print(f"coin-kat: --lib {given} does not exist")
            return 1

    cc = None
    if given is None:
        cc = find_cc()
        if cc is None:
            print("coin-kat: skipped (no C compiler found)")
            return 0

    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        if given is not None:
            out_path = given
            print(f"coin-kat: driving the given library {given}")
        else:
            out_path = os.path.join(tmp, "libcoinxt_kat.so")
            try:
                build_lib(cc, out_path)
            except subprocess.CalledProcessError as exc:
                print(f"coin-kat: BUILD FAILED ({exc})")
                return 1
        lib = load(out_path)

        abi = lib.cnx_abi_version()
        if abi != 6:
            problems.append(f"abi_version = {abi}, expected 6")
        elif not check:
            print(f"abi_version: {abi}")

        # Every length the LCB layer will ask the shim for, so a future edit that
        # changes one is caught here rather than by a truncated digest.
        for fn, want in (("cnx_keccak256_len", 32), ("cnx_sha3_256_len", 32),
                         ("cnx_sha256_len", 32), ("cnx_sha512_len", 64),
                         ("cnx_ripemd160_len", 20), ("cnx_hmac_sha256_len", 32),
                         ("cnx_hmac_sha512_len", 64),
                         ("cnx_schnorr_sig_len", 64), ("cnx_xonly_pubkey_len", 32),
                         ("cnx_taproot_output_len", 33)):
            got = getattr(lib, fn)()
            if got != want:
                problems.append(f"{fn}() = {got}, expected {want}")

        for data, exp in KECCAK256.items():
            got = digest(lib, "cnx_keccak256", data)
            ok = got == exp
            if not ok:
                problems.append(f"keccak256({data!r}) = {got}, expected {exp}")
            if not check:
                print(f"  keccak256({data!r:8}) {'OK' if ok else 'FAIL'}")

        for data in SHA3_INPUTS:
            got = digest(lib, "cnx_sha3_256", data)
            exp = hashlib.sha3_256(data).hexdigest()
            ok = got == exp
            if not ok:
                problems.append(f"sha3_256({data!r}) = {got}, expected {exp} (hashlib)")
            if not check:
                print(f"  sha3_256({data!r:12}...) {'OK' if ok else 'FAIL'} vs hashlib")

        # The footgun guard: Keccak-256 and SHA3-256 of the same input MUST differ.
        if digest(lib, "cnx_keccak256", b"") == digest(lib, "cnx_sha3_256", b""):
            problems.append("keccak256 and sha3_256 produced the same digest (aliased!)")

        # ---- SHA-2: published vector AND hashlib, which must agree with each other
        for data, exp in SHA256.items():
            got = digest(lib, "cnx_sha256", data)
            if got != exp:
                problems.append(f"sha256({data!r}) = {got}, expected {exp}")
            if got != hashlib.sha256(data).hexdigest():
                problems.append(f"sha256({data!r}) disagrees with hashlib")
            if not check:
                print(f"  sha256({data!r:8}) {'OK' if got == exp else 'FAIL'} vs vector + hashlib")
        for data, exp in SHA512.items():
            got = digest(lib, "cnx_sha512", data, 64)
            if got != exp:
                problems.append(f"sha512({data!r}) = {got}, expected {exp}")
            if got != hashlib.sha512(data).hexdigest():
                problems.append(f"sha512({data!r}) disagrees with hashlib")
            if not check:
                print(f"  sha512({data!r:8}) {'OK' if got == exp else 'FAIL'} vs vector + hashlib")

        # ---- RIPEMD-160: published vectors; hashlib only if this build has it
        try:
            hashlib.new("ripemd160")
            have_rmd = True
        except (ValueError, TypeError):
            have_rmd = False
        for data, exp in RIPEMD160.items():
            got = digest(lib, "cnx_ripemd160", data, 20)
            if got != exp:
                problems.append(f"ripemd160({data!r}) = {got}, expected {exp}")
            if have_rmd:
                h = hashlib.new("ripemd160", data).hexdigest()
                if got != h:
                    problems.append(f"ripemd160({data!r}) disagrees with hashlib")
        if not check:
            second = "vector + hashlib" if have_rmd else "vector only (hashlib has no ripemd160 here)"
            print(f"  ripemd160 x{len(RIPEMD160)} OK vs {second}")

        # ---- HMAC: RFC 4231 vectors AND Python's hmac module
        for key, msg, exp256, exp512 in HMAC_CASES:
            got = mac(lib, "cnx_hmac_sha256", key, msg, 32)
            if got != exp256:
                problems.append(f"hmac_sha256({msg!r}) = {got}, expected {exp256}")
            if got != pyhmac.new(key, msg, hashlib.sha256).hexdigest():
                problems.append(f"hmac_sha256({msg!r}) disagrees with python hmac")
            got = mac(lib, "cnx_hmac_sha512", key, msg, 64)
            if got != exp512:
                problems.append(f"hmac_sha512({msg!r}) = {got}, expected {exp512}")
            if got != pyhmac.new(key, msg, hashlib.sha512).hexdigest():
                problems.append(f"hmac_sha512({msg!r}) disagrees with python hmac")
        if not check:
            print(f"  hmac-sha256/512 x{len(HMAC_CASES)} OK vs RFC 4231 + python hmac")

        # ---- PBKDF2-HMAC-SHA512: the BIP-39 seed vector, plus hashlib
        got = pbkdf2(lib, BIP39_MNEMONIC, BIP39_SALT, BIP39_ITERS, 64)
        if got != BIP39_SEED:
            problems.append(f"bip39 seed = {got}, expected {BIP39_SEED}")
        ref = hashlib.pbkdf2_hmac("sha512", BIP39_MNEMONIC, BIP39_SALT,
                                  BIP39_ITERS, 64).hex()
        if got != ref:
            problems.append("pbkdf2_hmac_sha512 disagrees with hashlib")
        if not check:
            print(f"  pbkdf2-hmac-sha512 (BIP-39 seed) {'OK' if got == BIP39_SEED else 'FAIL'} vs vector + hashlib")

        # A derived length that is NOT a whole number of SHA-512 blocks exercises
        # the partial-final-block path, which a 64-byte-only test never touches.
        got = pbkdf2(lib, b"password", b"salt", 100, 100)
        ref = hashlib.pbkdf2_hmac("sha512", b"password", b"salt", 100, 100).hex()
        if got != ref:
            problems.append("pbkdf2_hmac_sha512 partial-block output disagrees with hashlib")

        # ---- the shim's own guards must FAIL CLOSED, not quietly do something else
        out = ctypes.create_string_buffer(32)
        guards = [
            ("zero iterations", lib.cnx_pbkdf2_hmac_sha512(b"pw", 2, b"salt", 4, 0, out, 32), -3),
            ("zero outlen", lib.cnx_pbkdf2_hmac_sha512(b"pw", 2, b"salt", 4, 1, out, 0), -2),
            ("NULL out", lib.cnx_sha256(b"x", 1, None), -1),
            ("NULL in with length", lib.cnx_sha256(None, 1, out), -1),
            ("NULL hmac key with length", lib.cnx_hmac_sha256(None, 1, b"m", 1, out), -1),
        ]
        for name, rc, want in guards:
            if rc != want:
                problems.append(f"guard '{name}' returned {rc}, expected {want}")
        if not check:
            print(f"  fail-closed guards x{len(guards)} OK")

        # An empty input is legal and must still produce the right digest through
        # the NULL-with-zero-length path the LCB layer can hand us.
        if digest(lib, "cnx_sha256", None) != SHA256[b""]:
            problems.append("sha256(NULL, 0) did not equal sha256 of the empty string")

        # ---- cnx_memzero (ABI 5): the .lcb's out-buffer wipe -----------------
        # Not a KAT in the digest sense - there is no published vector for
        # "zero" - but it IS a contract, and this is the file that executes the
        # committed release binaries (CI's --lib runs), so the wipe every .lcb
        # call path relies on is proven to run in the exact artifact shipped.
        # It must wipe EXACTLY len bytes (the 0xAA sentinel past len must
        # survive), treat len 0 as a successful no-op, tolerate NULL+0 per the
        # shim's firewall convention, and refuse NULL with a nonzero length.
        wipe = ctypes.create_string_buffer(b"\xaa" * 33, 33)
        if lib.cnx_memzero(wipe, 32) != 0:
            problems.append("cnx_memzero(buf, 32) did not return 0")
        if wipe.raw != b"\x00" * 32 + b"\xaa":
            problems.append("cnx_memzero did not wipe exactly len bytes "
                            f"(got {wipe.raw.hex()})")
        # A len-0 no-op cannot be probed on a zeroed buffer (a spurious zero
        # write is invisible there), so repaint byte 0 first.
        wipe[0] = b"\x55"
        if lib.cnx_memzero(wipe, 0) != 0:
            problems.append("cnx_memzero(buf, 0) is not a successful no-op")
        if wipe.raw[0] != 0x55:
            problems.append("cnx_memzero(buf, 0) wrote into the buffer")
        if lib.cnx_memzero(None, 0) != 0:
            problems.append("cnx_memzero(NULL, 0) is not tolerated")
        if lib.cnx_memzero(None, 5) != -1:
            problems.append("cnx_memzero(NULL, nonzero) did not refuse (CNX_ERR_NULL)")
        if not check:
            print("  cnx_memzero contract x6 OK")

        # ==================================================================
        # Phase 2: secp256k1.
        # ==================================================================
        for fn, want in (("cnx_seckey_len", 32), ("cnx_pubkey_len_compressed", 33),
                         ("cnx_pubkey_len_uncompressed", 65),
                         ("cnx_ecdsa_sig_len", 64), ("cnx_recoverable_sig_len", 65),
                         ("cnx_ecdh_len", 65)):
            got = getattr(lib, fn)()
            if got != want:
                problems.append(f"{fn}() = {got}, expected {want}")

        # ---- public keys: G and 2G, the two most-published points on the curve
        for sk_int, want33, want65 in PUBKEYS:
            sk = sk_int.to_bytes(32, "big")
            rc, got33 = pubkey(lib, sk, True)
            if rc != 0 or got33.hex() != want33:
                problems.append(f"pubkey33({sk_int}) = {got33.hex()} rc={rc}, expected {want33}")
            rc, got65 = pubkey(lib, sk, False)
            if rc != 0 or got65.hex() != want65:
                problems.append(f"pubkey65({sk_int}) = {got65.hex()} rc={rc}, expected {want65}")
            # Decompressing the compressed form must rebuild the uncompressed one
            # exactly (it solves the curve equation for Y and picks by parity).
            out = ctypes.create_string_buffer(65)
            rc = lib.cnx_pubkey_decompress(got33, 33, out, 65)
            if rc != 0 or out.raw[:65] != got65:
                problems.append(f"pubkey_decompress({sk_int}) did not rebuild the uncompressed key")
        if not check:
            print(f"  secp256k1 pubkeys x{len(PUBKEYS)} OK (+ decompress round-trip)")

        # ---- RFC 6979: the published deterministic signatures
        for sk_int, msg, want in RFC6979:
            sk = sk_int.to_bytes(32, "big")
            dg = hashlib.sha256(msg).digest()
            rc, got = sign(lib, sk, dg)
            if rc != 0 or got.hex() != want:
                problems.append(f"rfc6979 sign({msg[:24]!r}) = {got.hex()} rc={rc}, expected {want}")
            # Every published vector is low-s; assert it rather than assume it,
            # because a high-s signature is non-standard and would be rejected
            # by Bitcoin relay and Ethereum consensus alike.
            if int.from_bytes(got[32:], "big") > SECP256K1_ORDER // 2:
                problems.append(f"rfc6979 sign({msg[:24]!r}) produced a high-s signature")
            _, pub = pubkey(lib, sk, True)
            if lib.cnx_ecdsa_verify(pub, 33, dg, 32, got, 64) != 0:
                problems.append(f"rfc6979 sign({msg[:24]!r}) did not verify under its own key")
        if not check:
            print(f"  RFC 6979 signatures x{len(RFC6979)} OK vs published vectors (low-s, self-verifying)")

        # ---- verification must REJECT, which is the half a signing test cannot show
        sk = bytes.fromhex(RECOVERABLE_SK)
        dg = hashlib.sha256(RECOVERABLE_MSG).digest()
        rc, sig64 = sign(lib, sk, dg)
        _, pub33 = pubkey(lib, sk, True)
        _, pub65 = pubkey(lib, sk, False)
        tampered = bytearray(sig64)
        tampered[10] ^= 0x01
        _, otherpub = pubkey(lib, (int.from_bytes(sk, "big") + 1).to_bytes(32, "big"), True)
        rejects = [
            ("tampered signature", lib.cnx_ecdsa_verify(pub33, 33, dg, 32, bytes(tampered), 64), -5),
            ("wrong public key", lib.cnx_ecdsa_verify(otherpub, 33, dg, 32, sig64, 64), -5),
            ("wrong digest", lib.cnx_ecdsa_verify(pub33, 33, hashlib.sha256(b"other").digest(), 32, sig64, 64), -5),
            # THE OVERREAD GUARD. Upstream's parser reads 65 bytes whenever the
            # prefix is 0x04 and is never told the buffer length, so a 33-byte
            # key claiming to be uncompressed would be read past its end. The
            # length and the prefix have to agree before the pointer is handed
            # over, and this is the test that says they do.
            ("33 bytes with an 0x04 prefix",
             lib.cnx_ecdsa_verify(b"\x04" + pub33[1:], 33, dg, 32, sig64, 64), -4),
            ("65 bytes with an 0x02 prefix",
             lib.cnx_ecdsa_verify(b"\x02" + pub65[1:], 65, dg, 32, sig64, 64), -4),
            ("a 34-byte public key", lib.cnx_ecdsa_verify(pub33 + b"\x00", 34, dg, 32, sig64, 64), -4),
            ("an off-curve public key", lib.cnx_ecdsa_verify(b"\x02" + b"\xff" * 32, 33, dg, 32, sig64, 64), -5),
            ("a 63-byte signature", lib.cnx_ecdsa_verify(pub33, 33, dg, 32, sig64[:63], 63), -2),
        ]
        for name, rc2, want_rc in rejects:
            if rc2 != want_rc:
                problems.append(f"verify of {name} returned {rc2}, expected {want_rc}")
        if lib.cnx_ecdsa_verify(pub65, 65, dg, 32, sig64, 64) != 0:
            problems.append("verify rejected a good signature under the UNCOMPRESSED key")
        if not check:
            print(f"  verification rejects x{len(rejects)} OK (incl. the pubkey-overread guard)")

        # ---- recoverable signing and ecrecover
        rc, sig65 = sign(lib, sk, dg, recoverable=True)
        if rc != 0 or sig65.hex() != RECOVERABLE_SIG:
            problems.append(f"recoverable sign = {sig65.hex()} rc={rc}, expected {RECOVERABLE_SIG}")
        if sig65[:64] != sig64:
            problems.append("the recoverable signature's first 64 bytes differ from the plain one")
        if sig65[64] > 3:
            problems.append(f"recovery id {sig65[64]} is outside 0..3")
        rc, got = recover(lib, sig65, dg)
        if rc != 0 or got.hex() != RECOVERABLE_PUB:
            problems.append(f"recover = {got.hex()} rc={rc}, expected {RECOVERABLE_PUB}")
        if got != pub65:
            problems.append("the recovered key is not the signer's key")
        # A wrong recovery id must not yield the signer. (It usually recovers
        # SOME valid key, which is exactly why a caller must compare the result
        # against the key it expected rather than trust that recovery succeeded.)
        for wrong in range(4):
            if wrong == sig65[64]:
                continue
            rc2, got2 = recover(lib, sig65[:64] + bytes([wrong]), dg)
            if rc2 == 0 and got2 == pub65:
                problems.append(f"recovery id {wrong} also recovered the signer")
        if lib.cnx_ecdsa_recover(sig65[:64] + b"\x04", 65, dg, 32,
                                 ctypes.create_string_buffer(65), 65) != -5:
            problems.append("a recovery id of 4 was not refused")
        if not check:
            print("  recoverable sign + ecrecover OK (round-trips to the signer)")

        # ---- ECDH: both sides must land on the same point, and on the pinned one
        a, b = bytes.fromhex(ECDH_A), bytes.fromhex(ECDH_B)
        _, apub = pubkey(lib, a, True)
        _, bpub = pubkey(lib, b, True)
        rca, sa = ecdh(lib, a, bpub)
        rcb, sb = ecdh(lib, b, apub)
        if rca != 0 or rcb != 0 or sa != sb:
            problems.append("ecdh(a,B) and ecdh(b,A) disagree")
        if sa.hex() != ECDH_POINT:
            problems.append(f"ecdh point = {sa.hex()}, expected {ECDH_POINT}")
        # The uncompressed form of the same key must give the same point.
        _, bpub65 = pubkey(lib, b, False)
        if ecdh(lib, a, bpub65)[1] != sa:
            problems.append("ecdh disagreed between the compressed and uncompressed forms of B")
        if not check:
            print("  ECDH OK (symmetric, and matches the pinned point)")

        # ---- the curve's fail-closed guards
        curve_guards = [
            ("seckey 0", lib.cnx_seckey_verify(bytes(32), 32), -4),
            ("seckey == the group order",
             lib.cnx_seckey_verify(SECP256K1_ORDER.to_bytes(32, "big"), 32), -4),
            ("seckey n-1 (the largest legal key)",
             lib.cnx_seckey_verify((SECP256K1_ORDER - 1).to_bytes(32, "big"), 32), 0),
            ("seckey 1 (the smallest legal key)",
             lib.cnx_seckey_verify((1).to_bytes(32, "big"), 32), 0),
            ("a 31-byte seckey", lib.cnx_seckey_verify(bytes(31), 31), -2),
            ("a NULL seckey", lib.cnx_seckey_verify(None, 32), -1),
            ("signing with key 0", sign(lib, bytes(32), dg)[0], -4),
            # Upstream refuses an all-zero digest because such a signature can be
            # forged for ANY key; the shim surfaces that as its own code rather
            # than letting it look like a generic failure.
            ("signing an all-zero digest", sign(lib, sk, bytes(32))[0], -7),
            ("ecdh with an off-curve pubkey", ecdh(lib, a, b"\x02" + b"\xff" * 32)[0], -4),
            ("ecdh with key 0", ecdh(lib, bytes(32), bpub)[0], -4),
        ]
        for name, rc2, want_rc in curve_guards:
            if rc2 != want_rc:
                problems.append(f"curve guard '{name}' returned {rc2}, expected {want_rc}")
        if not check:
            print(f"  curve fail-closed guards x{len(curve_guards)} OK")

        # ---- determinism, which is the claim the blinding could quietly break
        # Signing draws fresh OS entropy on every call for side-channel blinding.
        # That blinding is supposed to cancel out; if it ever did not, signatures
        # would vary run to run and every pinned vector above would be a flake
        # waiting to happen. Repeat the call and require one distinct answer.
        repeats = {sign(lib, sk, dg)[1] for _ in range(32)}
        if len(repeats) != 1:
            problems.append(f"32 signings of the same input produced {len(repeats)} distinct signatures")
        if not check:
            print("  determinism OK (32 signings of one input agree despite blinding)")


        # ---- phase 4: the two BIP-32 curve steps, and the BIP-39 wordlist ----
        # These are the primitives src/coinxt.livecodescript builds HD wallets
        # out of. The script layer's own end-to-end checks live in
        # tools/check-script-vectors.py; what is pinned HERE is that the native
        # half is right, independently of any script running.
        lib.cnx_bip39_wordlist_len.restype = ctypes.c_size_t
        wl_len = lib.cnx_bip39_wordlist_len()
        if wl_len != 2048 * 8:
            problems.append(f"cnx_bip39_wordlist_len() = {wl_len}, expected {2048 * 8}")
        buf = ctypes.create_string_buffer(wl_len)
        if lib.cnx_bip39_wordlist(buf, wl_len) != 0:
            problems.append("cnx_bip39_wordlist failed")
        words = [buf.raw[i:i + 8].decode().rstrip(" ") for i in range(0, wl_len, 8)]
        # BIP-39 pins the list by the SHA-256 of its canonical newline-joined
        # form. That single hash is the whole interoperability claim: a wallet
        # restored anywhere else indexes THESE 2048 words in THIS order.
        got = hashlib.sha256(("\n".join(words) + "\n").encode()).hexdigest()
        if got != BIP39_WORDLIST_SHA256:
            problems.append(f"the BIP-39 wordlist hashes to {got}, expected {BIP39_WORDLIST_SHA256}")
        # The script binary-searches this table, so sortedness is a PRECONDITION
        # and not a nicety - an unsorted list would make cxWordIndex miss words
        # that are present, and a mnemonic would be rejected for no reason.
        if words != sorted(words):
            problems.append("the BIP-39 wordlist is not sorted by byte value")
        if len(set(words)) != 2048:
            problems.append("the BIP-39 wordlist has duplicates")
        if max(len(w) for w in words) > 8:
            problems.append("a BIP-39 word is longer than its 8-byte slot")
        if lib.cnx_bip39_wordlist(buf, wl_len - 1) != -2:
            problems.append("cnx_bip39_wordlist accepted a wrong output length")
        if not check:
            print(f"  BIP-39 wordlist OK (2048 words, sorted, hashes to the published {got[:12]}...)")

        # BIP-32 test vector 1, walked with the two tweak exports. Reproducing
        # the published chain end to end is what proves the pair is a correct
        # CKDpriv/CKDpub and not merely self-consistent.
        for fn in ("cnx_seckey_tweak_add", "cnx_pubkey_tweak_add"):
            f = getattr(lib, fn)
            f.restype = ctypes.c_int
            f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p,
                          ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]

        def sk_tweak(sk_, t_):
            o = ctypes.create_string_buffer(32)
            return lib.cnx_seckey_tweak_add(sk_, 32, t_, 32, o, 32), o.raw[:32]

        def pk_tweak(p_, t_):
            o = ctypes.create_string_buffer(33)
            return lib.cnx_pubkey_tweak_add(p_, 33, t_, 32, o, 33), o.raw[:33]

        I = pyhmac.new(b"Bitcoin seed", bytes.fromhex(BIP32_SEED), hashlib.sha512).digest()
        node_k, node_c = I[:32], I[32:]
        for i, want_k in BIP32_CHAIN:
            _, par33 = pubkey(lib, node_k, True)
            data = (b"\x00" + node_k if i >= 0x80000000 else par33) + i.to_bytes(4, "big")
            J = pyhmac.new(node_c, data, hashlib.sha512).digest()
            rc2, child = sk_tweak(node_k, J[:32])
            if rc2 != 0:
                problems.append(f"cnx_seckey_tweak_add failed at index {i}: {rc2}")
                break
            if child.hex() != want_k:
                problems.append(f"BIP-32 child at index {i} = {child.hex()}, expected {want_k}")
            if i < 0x80000000:
                # The public path must land on the same point. A hardened index
                # has no public derivation at all, which is the property that
                # makes an xpub safe to hand out above a hardened boundary.
                rc3, P = pk_tweak(par33, J[:32])
                _, want_P = pubkey(lib, child, True)
                if rc3 != 0 or P != want_P:
                    problems.append(f"cnx_pubkey_tweak_add disagrees with the private path at {i}")
            node_k, node_c = child, J[32:]
        if not check:
            print(f"  BIP-32 vector 1 OK ({len(BIP32_CHAIN)} levels; CKDpub agrees with CKDpriv)")

        order_be = SECP256K1_ORDER.to_bytes(32, "big")
        _, g33 = pubkey(lib, (1).to_bytes(32, "big"), True)
        tweak_guards = [
            # A zero tweak is refused on BOTH paths on purpose: BIP-32 allows it
            # in principle (the child would equal its parent) but accepting it on
            # one path and refusing it on the other would make private and public
            # derivation of the same child disagree about validity.
            ("zero tweak, private", sk_tweak(bytes([1] * 32), bytes(32))[0], -4),
            ("zero tweak, public", pk_tweak(g33, bytes(32))[0], -4),
            ("tweak >= n, private", sk_tweak(bytes([1] * 32), order_be)[0], -4),
            ("tweak >= n, public", pk_tweak(g33, order_be)[0], -4),
            ("zero parent key", sk_tweak(bytes(32), bytes([1] * 32))[0], -4),
            ("parent key >= n", sk_tweak(order_be, bytes([1] * 32))[0], -4),
            # The overread guard again, on the new entry point: 33 bytes with an
            # uncompressed prefix, and an uncompressed key where BIP-32 requires
            # the compressed one.
            ("33 bytes with an 0x04 prefix",
             lib.cnx_pubkey_tweak_add(b"\x04" + g33[1:], 33, bytes([1] * 32), 32,
                                      ctypes.create_string_buffer(33), 33), -4),
            ("an uncompressed parent",
             lib.cnx_pubkey_tweak_add(pubkey(lib, (1).to_bytes(32, "big"), False)[1], 65,
                                      bytes([1] * 32), 32,
                                      ctypes.create_string_buffer(33), 33), -4),
            ("a 31-byte tweak",
             lib.cnx_seckey_tweak_add(bytes([1] * 32), 32, bytes(31), 31,
                                      ctypes.create_string_buffer(32), 32), -2),
        ]
        for name, rc2, want_rc in tweak_guards:
            if rc2 != want_rc:
                problems.append(f"tweak guard '{name}' returned {rc2}, expected {want_rc}")
        if not check:
            print(f"  tweak fail-closed guards x{len(tweak_guards)} OK")

        # ==================================================================
        # ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak.
        # ==================================================================
        # These run the OFFICIAL vector files, in full and in order. Nothing
        # here is derived with the library under test: BIP340_VECTORS is
        # bitcoin/bips' own test-vectors.csv and TAPROOT_* are its own
        # wallet-test-vectors.json, both transcribed at the top of this file
        # with their source URLs. That distinction is the standing lesson of
        # this repository - an expectation generated by the implementation
        # proves only that the implementation agrees with itself.
        h = bytes.fromhex

        def schnorr_sign(sk, msg, aux):
            out = ctypes.create_string_buffer(64)
            rc = lib.cnx_schnorr_sign(sk, len(sk), msg, len(msg),
                                      aux, len(aux) if aux is not None else 0,
                                      out, 64)
            return rc, out.raw[:64]

        def schnorr_verify(pk, msg, sig):
            return lib.cnx_schnorr_verify(pk, 32, msg, len(msg), sig, 64)

        def xonly(sk):
            out = ctypes.create_string_buffer(32)
            return lib.cnx_xonly_pubkey_from_seckey(sk, 32, out, 32), out.raw[:32]

        def tweak_pub(internal, root):
            out = ctypes.create_string_buffer(33)
            rc = lib.cnx_taproot_tweak_pubkey(internal, 32, root,
                                              len(root) if root else 0, out, 33)
            return rc, out.raw[:32], out.raw[32]

        def tweak_sec(sk, root):
            out = ctypes.create_string_buffer(32)
            rc = lib.cnx_taproot_tweak_seckey(sk, 32, root,
                                              len(root) if root else 0, out, 32)
            return rc, out.raw[:32]

        signed = verified = 0
        # v_* names ON PURPOSE: this loop lives inside main(), and Python leaks
        # its loop variables past the loop body. Binding a bare `sk` here
        # silently rebound the ECDSA section's 32-byte key (line ~875) to a
        # BIP-340 vector's HEX STRING, which the cross-library check 240 lines
        # below then handed to `ecdsa`. It only failed where `ecdsa` is
        # installed - i.e. CI, not this container - so the local gate run was
        # green and the CI run was red on the same tree.
        for idx, v_sk, v_pk, v_aux, v_msg, v_sig, v_want_ok in BIP340_VECTORS:
            sk, pk, aux, msg, sig, want_ok = v_sk, v_pk, v_aux, v_msg, v_sig, v_want_ok
            got = schnorr_verify(h(pk), h(msg), h(sig))
            # CNX_OK means valid; CNX_ERR_BADSIG (-5) means "does not verify",
            # which is what the vector file's FALSE cases expect INCLUDING the
            # two whose public key is not on the curve (5 and 14). Any other
            # status would mean this shim turned a verdict into an exception.
            if got not in (0, -5):
                problems.append(f"BIP-340 vector {idx}: verify returned {got}, "
                                "which is neither valid nor 'does not verify'")
            elif (got == 0) != want_ok:
                problems.append(f"BIP-340 vector {idx}: verify said "
                                f"{'valid' if got == 0 else 'invalid'}, expected "
                                f"{'valid' if want_ok else 'invalid'}")
            else:
                verified += 1
            if not sk:
                continue
            rc, x = xonly(h(sk))
            if rc != 0 or x.hex() != pk:
                problems.append(f"BIP-340 vector {idx}: x-only pubkey = {x.hex()} "
                                f"(rc {rc}), expected {pk}")
            # Signing is 32-byte messages only (CLAUDE.md rule 3, the same rule
            # cnx_ecdsa_sign follows), so vectors 15-18 - added in 2022 for
            # messages of 0, 1, 17 and 100 bytes - are VERIFIED here and not
            # re-signed. That is a scope decision, not a gap: the four exist to
            # catch a verifier that mishandles a non-32-byte message, and the
            # verify leg above runs every one of them.
            if len(msg) != 64:
                continue
            rc, out = schnorr_sign(h(sk), h(msg), h(aux))
            if rc != 0 or out.hex() != sig:
                problems.append(f"BIP-340 vector {idx}: signature = {out.hex()} "
                                f"(rc {rc}), expected {sig}")
            else:
                signed += 1
        if not check:
            neg = sum(1 for v in BIP340_VECTORS if not v[6])
            print(f"  BIP-340 published vectors: {verified}/{len(BIP340_VECTORS)} "
                  f"verify legs agree ({neg} of them NEGATIVE), "
                  f"{signed} signatures reproduced byte for byte")

        # An ABSENT aux_rand means FRESH OS randomness, never an all-zero aux.
        # Two calls must differ, both must verify, and neither may equal the
        # aux=0 signature - which is the whole point: a shim that quietly
        # passed NULL through to upstream would produce the zero-aux signature
        # here, twice, and this is what notices.
        sk340 = h(BIP340_VECTORS[0][1])
        msg340 = h(BIP340_VECTORS[0][4])
        zero_aux_sig = h(BIP340_VECTORS[0][5])
        rc_a, sig_a = schnorr_sign(sk340, msg340, None)
        rc_b, sig_b = schnorr_sign(sk340, msg340, None)
        _, pk340 = xonly(sk340)
        if rc_a != 0 or rc_b != 0:
            problems.append(f"schnorr sign with an absent aux failed ({rc_a}, {rc_b})")
        elif sig_a == sig_b:
            problems.append("two signatures with an absent aux were IDENTICAL, so the "
                            "shim is not drawing fresh randomness")
        elif sig_a == zero_aux_sig or sig_b == zero_aux_sig:
            problems.append("an absent aux produced the ALL-ZERO-aux signature, so it "
                            "was passed through as NULL rather than replaced")
        elif schnorr_verify(pk340, msg340, sig_a) != 0 or \
                schnorr_verify(pk340, msg340, sig_b) != 0:
            problems.append("a signature made with a fresh aux does not verify")
        elif not check:
            print("  absent aux_rand: two distinct signatures, both verify, "
                  "neither is the zero-aux one")

        # BIP-341 scriptPubKey vectors: the tweak, the output key, and the
        # scriptPubKey the output key goes into.
        for i, (internal, root, want_tweak, want_out, want_spk) in enumerate(TAPROOT_SPK):
            rootb = h(root) if root else b""
            rc, out, parity = tweak_pub(h(internal), rootb)
            if rc != 0 or out.hex() != want_out:
                problems.append(f"BIP-341 scriptPubKey vector {i}: output key = "
                                f"{out.hex()} (rc {rc}), expected {want_out}")
                continue
            if not want_spk.endswith(out.hex()) or not want_spk.startswith("5120"):
                problems.append(f"BIP-341 scriptPubKey vector {i}: the output key is "
                                f"not the witness program of {want_spk}")
            # tweak_add_check is upstream's own inverse: it re-derives the
            # commitment from the internal key, the tweak and OUR parity, so a
            # wrong parity byte fails here even though every published field
            # above is x-only and cannot see it.
            if parity not in (0, 1):
                problems.append(f"BIP-341 scriptPubKey vector {i}: parity byte is {parity}")
            # THE PUBLISHED TWEAK, CHECKED AGAINST THE OTHER VENDORED LIBRARY.
            # Without this the `tweak` column would be transcribed and never
            # read, which is the shape of overstatement this repository has been
            # bitten by before. It is also the only place the two vendored
            # libraries are made to answer the same question: an x-only key IS
            # the even-Y point, so 0x02 || internal is the same point as a
            # 33-byte compressed key, and trezor-crypto's cnx_pubkey_tweak_add
            # must land on the point upstream's cnx_taproot_tweak_pubkey landed
            # on - X byte for byte, and with a prefix that agrees with our
            # parity byte. If the two ever disagreed, one of them would be
            # computing a different curve.
            comp = ctypes.create_string_buffer(33)
            rc2 = lib.cnx_pubkey_tweak_add(bytes([2]) + h(internal), 33,
                                           h(want_tweak), 32, comp, 33)
            if rc2 != 0:
                problems.append(f"BIP-341 scriptPubKey vector {i}: trezor-crypto refused "
                                f"the published tweak (rc {rc2})")
            elif comp.raw[1:33].hex() != want_out:
                problems.append(f"BIP-341 scriptPubKey vector {i}: the two vendored "
                                "libraries disagree about P + tweak*G")
            elif comp.raw[0] != (3 if parity else 2):
                problems.append(f"BIP-341 scriptPubKey vector {i}: our parity byte "
                                f"{parity} contradicts the compressed prefix "
                                f"0x{comp.raw[0]:02x} trezor-crypto produced")
        if not check:
            keypath_only = sum(1 for v in TAPROOT_SPK if v[1] is None)
            print(f"  BIP-341 scriptPubKey vectors: {len(TAPROOT_SPK)} output keys exact "
                  f"({keypath_only} with NO merkle root, {len(TAPROOT_SPK) - keypath_only} "
                  "with a script-tree root), each cross-checked against "
                  "trezor-crypto's own point addition")

        # THE CONSENSUS DISTINCTION, asserted rather than trusted: an absent
        # merkle root is the EMPTY BYTE STRING, not 32 zero bytes. If these ever
        # agreed, every key-path-only address this library produced would be
        # wrong, and it would look right.
        kp_internal = h(TAPROOT_SPK[0][0])
        _, out_empty, _ = tweak_pub(kp_internal, b"")
        rc_z, out_zeros, _ = tweak_pub(kp_internal, bytes(32))
        if rc_z != 0:
            problems.append("a 32-zero-byte merkle root was refused; it is a legal "
                            "(if useless) script commitment and must be treated as one")
        elif out_empty == out_zeros:
            problems.append("an ABSENT merkle root produced the same output key as 32 "
                            "ZERO BYTES, so the key-path-only case is being hashed wrong")
        elif not check:
            print("  an absent merkle root is NOT a zero root (different output keys)")

        # BIP-341 key-path spending: seckey -> internal pubkey -> tweaked
        # seckey -> the published witness signature over the published sighash.
        for i, (isk, root, want_ipub, want_tsk, sighash, want_sig) in enumerate(TAPROOT_KEYPATH):
            rootb = h(root) if root else b""
            rc, ipub = xonly(h(isk))
            if rc != 0 or ipub.hex() != want_ipub:
                problems.append(f"BIP-341 keypath {i}: internal pubkey = {ipub.hex()}")
                continue
            rc, tsk = tweak_sec(h(isk), rootb)
            if rc != 0 or tsk.hex() != want_tsk:
                problems.append(f"BIP-341 keypath {i}: tweaked seckey = {tsk.hex()} "
                                f"(rc {rc}), expected {want_tsk}")
                continue
            rc, sig = schnorr_sign(tsk, h(sighash), bytes(32))
            if rc != 0 or sig.hex() != want_sig:
                problems.append(f"BIP-341 keypath {i}: witness signature = {sig.hex()}")
                continue
            # And the loop the specification does not print: the PUBLIC path
            # must produce the key that PRIVATE signature verifies against.
            rc, outkey, _ = tweak_pub(ipub, rootb)
            if rc != 0 or schnorr_verify(outkey, h(sighash), sig) != 0:
                problems.append(f"BIP-341 keypath {i}: the tweaked private key does not "
                                "sign for the independently tweaked public key")
        if not check:
            print(f"  BIP-341 key-path spending: {len(TAPROOT_KEYPATH)} inputs walked "
                  "seckey -> internal pubkey -> tweaked seckey -> published witness")

        # ---- the ABI 6 fail-closed guards
        schnorr_guards = [
            ("a null seckey", lib.cnx_schnorr_sign(None, 32, msg340, 32, None, 0,
                                                   ctypes.create_string_buffer(64), 64), -1),
            ("a 31-byte seckey", lib.cnx_schnorr_sign(bytes(31), 31, msg340, 32, None, 0,
                                                      ctypes.create_string_buffer(64), 64), -2),
            ("a 31-byte message", lib.cnx_schnorr_sign(sk340, 32, bytes(31), 31, None, 0,
                                                       ctypes.create_string_buffer(64), 64), -2),
            ("a 100-byte message (signing is digests only)",
             lib.cnx_schnorr_sign(sk340, 32, bytes(100), 100, None, 0,
                                  ctypes.create_string_buffer(64), 64), -2),
            ("a 31-byte aux", lib.cnx_schnorr_sign(sk340, 32, msg340, 32, bytes(31), 31,
                                                   ctypes.create_string_buffer(64), 64), -2),
            ("a zero seckey", lib.cnx_schnorr_sign(bytes(32), 32, msg340, 32, None, 0,
                                                   ctypes.create_string_buffer(64), 64), -4),
            ("a 63-byte signature buffer",
             lib.cnx_schnorr_sign(sk340, 32, msg340, 32, None, 0,
                                  ctypes.create_string_buffer(63), 63), -2),
            ("verify with a 31-byte key",
             lib.cnx_schnorr_verify(bytes(31), 31, msg340, 32, bytes(64), 64), -2),
            ("verify with a 63-byte signature",
             lib.cnx_schnorr_verify(pk340, 32, msg340, 32, bytes(63), 63), -2),
            ("verify with a null message of nonzero length",
             lib.cnx_schnorr_verify(pk340, 32, None, 1, bytes(64), 64), -1),
            ("x-only from a zero seckey",
             lib.cnx_xonly_pubkey_from_seckey(bytes(32), 32,
                                              ctypes.create_string_buffer(32), 32), -4),
            ("x-only into a 31-byte buffer",
             lib.cnx_xonly_pubkey_from_seckey(sk340, 32,
                                              ctypes.create_string_buffer(31), 31), -2),
            ("a 5-byte merkle root",
             lib.cnx_taproot_tweak_pubkey(kp_internal, 32, bytes(5), 5,
                                          ctypes.create_string_buffer(33), 33), -2),
            ("a null merkle root claiming 32 bytes",
             lib.cnx_taproot_tweak_pubkey(kp_internal, 32, None, 32,
                                          ctypes.create_string_buffer(33), 33), -1),
            ("a 32-byte output buffer (the record is 33)",
             lib.cnx_taproot_tweak_pubkey(kp_internal, 32, None, 0,
                                          ctypes.create_string_buffer(32), 32), -2),
            # An x-only value that is not on the curve is a KEY error when the
            # caller is ASSERTING it is their internal key, and merely "does
            # not verify" when they are asking about a signature. Both are
            # asserted, because the two directions are easy to conflate.
            ("an internal key that is not on the curve",
             lib.cnx_taproot_tweak_pubkey(h(BIP340_VECTORS[5][2]), 32, None, 0,
                                          ctypes.create_string_buffer(33), 33), -4),
            ("a zero seckey to tweak",
             lib.cnx_taproot_tweak_seckey(bytes(32), 32, None, 0,
                                          ctypes.create_string_buffer(32), 32), -4),
            ("a 5-byte merkle root on the private side",
             lib.cnx_taproot_tweak_seckey(sk340, 32, bytes(5), 5,
                                          ctypes.create_string_buffer(32), 32), -2),
        ]
        for name, rc2, want_rc in schnorr_guards:
            if rc2 != want_rc:
                problems.append(f"ABI 6 guard '{name}' returned {rc2}, expected {want_rc}")
        if not check:
            print(f"  BIP-340/341 fail-closed guards x{len(schnorr_guards)} OK")

        # ---- the independent second opinion, when it is installed
        # The published vectors above already stand on their own. This block is
        # the stronger claim the plan asks for - that a CoinXT signature verifies
        # in a MAINSTREAM library, not just in CoinXT - and it SKIPS loudly
        # rather than silently when `ecdsa` is not present.
        try:
            from ecdsa import SECP256k1, SigningKey
            from ecdsa.util import sigdecode_string, sigencode_string
            have_ecdsa = True
        except ImportError:
            have_ecdsa = False
        # A skip is right for a contributor who has not installed an optional
        # package. It is WRONG for CI, where "the cross-library check silently
        # did not run" and "the cross-library check passed" print almost the
        # same thing and exit 0 either way. So CI sets COINXT_REQUIRE_CROSSCHECK
        # and the skip becomes a failure there: if a future edit drops the pip
        # install, that shows up as a red run instead of a quieter green one.
        if not have_ecdsa and os.environ.get("COINXT_REQUIRE_CROSSCHECK"):
            problems.append("COINXT_REQUIRE_CROSSCHECK is set but the `ecdsa` package "
                            "is not installed, so the cross-library check could not "
                            "run (pip install ecdsa)")
        if have_ecdsa:
            # Bound HERE, not inherited: this check pairs with the sig64/dg/pub33
            # built from RECOVERABLE_SK far above, and anything that rebinds `sk`
            # in between silently changes what is being cross-checked.
            xsk = bytes.fromhex(RECOVERABLE_SK)
            key = SigningKey.from_string(xsk, curve=SECP256k1)
            if not key.get_verifying_key().verify_digest(
                    sig64, dg, sigdecode=sigdecode_string):
                problems.append("a CoinXT signature did NOT verify in the `ecdsa` library")
            # And the reverse direction: their signature must satisfy our verify.
            theirs = key.sign_digest_deterministic(
                dg, hashfunc=hashlib.sha256, sigencode=sigencode_string)
            r = int.from_bytes(theirs[:32], "big")
            s = int.from_bytes(theirs[32:], "big")
            if s > SECP256K1_ORDER // 2:
                s = SECP256K1_ORDER - s
            low = r.to_bytes(32, "big") + s.to_bytes(32, "big")
            if lib.cnx_ecdsa_verify(pub33, 33, dg, 32, low, 64) != 0:
                problems.append("CoinXT did not verify a signature made by the `ecdsa` library")
            if not check:
                print("  cross-library OK (CoinXT signature verifies in `ecdsa`, and the reverse)")
        elif not check:
            print("  cross-library SKIPPED: the `ecdsa` package is not installed "
                  "(pip install ecdsa). The published vectors above still ran.")

    if problems:
        for p in problems:
            print("coin-kat: FAIL:", p)
        return 1
    print("coin-kat: self-check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
