#!/usr/bin/env python3
# riptide_reference.py - the pure-Python oracle riptide/src/riptide.livecodescript
# is checked against.
#
# Like coinxt's coin_reference.py, this model was written BEFORE the script layer
# and validated against INDEPENDENT vectors first, on purpose: a vector captured
# from the script's own output would only prove the script agrees with itself.
# The independent anchors are:
#
#   - sxKdfDerive semantics: the C KAT in sodiumxt/tests/sodium_smoke_test.c
#     (test_kdf: master 0x01*32, id "1", ctx "SXTctx00" -> dc9d1a08...).
#     libsodium's crypto_kdf_derive_from_key is BLAKE2b with the subkey id as a
#     little-endian 64-bit salt and the 8-byte context as the personal field,
#     over an empty message, keyed by the master - exactly what hashlib.blake2b
#     exposes. Verified at import; a hashlib that disagrees fails loudly.
#   - ed25519: the RFC 8032 reference implementation, the same public-domain
#     code torrentxt/tests/bep44_golden_test.py bundles, checked against that
#     file's cross-project conformance vector (seed cac73f09... -> pub
#     672e8e0b...) and the zero-seed pubkey from sodium_smoke_test.c.
#   - the v3 onion address: SHA3-256 via hashlib plus the same base32 the
#     onionxt member pins in tools/onion-kat.py, checked against a real
#     published onion (torproject.org's).
#
# Stdlib only. No third-party packages, no network, no files read.
#
# Everything downstream (the KDF subkey tree, the identity -> onion mapping,
# inboxId / roomId, the RSH1 / RSP1 framings, BEP44 immutable targets) is
# derived from those anchored primitives, so the golden vectors in
# tests/riptide_golden_test.py and the harness constants gated by
# tools/check-selftest-vectors.py all trace to sources outside this repo.

import hashlib
import struct
import sys

# ---------------------------------------------------------------------------
# ed25519 (RFC 8032) - the reference implementation from the RFC's appendix,
# as bundled by torrentxt/tests/bep44_golden_test.py. Public domain.
# ---------------------------------------------------------------------------

_p = 2 ** 255 - 19
_L = 2 ** 252 + 27742317777372353535851937790883648493
_d = -121665 * pow(121666, _p - 2, _p) % _p


def _sha512(s):
    return hashlib.sha512(s).digest()


def _inv(x):
    return pow(x, _p - 2, _p)


_By = 4 * _inv(5) % _p
_Bx_sq = (_By * _By - 1) * _inv(_d * _By * _By + 1) % _p
_Bx = pow(_Bx_sq, (_p + 3) // 8, _p)
if (_Bx * _Bx - _Bx_sq) % _p != 0:
    _Bx = _Bx * pow(2, (_p - 1) // 4, _p) % _p
if _Bx % 2 != 0:
    _Bx = _p - _Bx
_B = (_Bx % _p, _By % _p, 1, _Bx * _By % _p)


def _pt_add(P, Q):
    (x1, y1, z1, t1) = P
    (x2, y2, z2, t2) = Q
    a = (y1 - x1) * (y2 - x2) % _p
    b = (y1 + x1) * (y2 + x2) % _p
    c = 2 * t1 * t2 * _d % _p
    dd = 2 * z1 * z2 % _p
    e = b - a
    f = dd - c
    g = dd + c
    h = b + a
    return (e * f % _p, g * h % _p, f * g % _p, e * h % _p)


def _pt_mul(s, P):
    Q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            Q = _pt_add(Q, P)
        P = _pt_add(P, P)
        s >>= 1
    return Q


def _pt_compress(P):
    (x, y, z, _t) = P
    zinv = _inv(z)
    x = x * zinv % _p
    y = y * zinv % _p
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _secret_expand(seed):
    h = _sha512(seed)
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8
    a |= 1 << 254
    return (a, h[32:])


def ed25519_publickey(seed):
    """32-byte ed25519 public key from a 32-byte seed."""
    (a, _prefix) = _secret_expand(seed)
    return _pt_compress(_pt_mul(a, _B))


def ed25519_sign(msg, seed):
    """64-byte detached signature; matches libsodium's sxSignDetached with the
    64-byte secret key sxSignKeypairFromSeed builds from the same seed."""
    (a, prefix) = _secret_expand(seed)
    A = ed25519_publickey(seed)
    r = int.from_bytes(_sha512(prefix + msg), "little") % _L
    R = _pt_compress(_pt_mul(r, _B))
    h = int.from_bytes(_sha512(R + A + msg), "little") % _L
    s = (r + h * a) % _L
    return R + int.to_bytes(s, 32, "little")


def _pt_decompress(comp):
    """RFC 8032 5.1.3 point decompression: recover x from the compressed y."""
    y = int.from_bytes(comp, "little") & ((1 << 255) - 1)
    sign = comp[31] >> 7
    u = (y * y - 1) % _p
    v = (_d * y * y + 1) % _p
    # candidate root x = u*v^3 * (u*v^7)^((p-5)/8)
    x = u * pow(v, 3, _p) % _p * pow(u * pow(v, 7, _p) % _p,
                                     (_p - 5) // 8, _p) % _p
    vxx = v * x * x % _p
    if vxx == u % _p:
        pass
    elif vxx == (-u) % _p:
        x = x * pow(2, (_p - 1) // 4, _p) % _p
    else:
        return None
    if x == 0 and sign == 1:
        return None
    if x & 1 != sign:
        x = _p - x
    return (x % _p, y % _p, 1, x * y % _p)


def _verify_ed25519(sig, msg, pub):
    """RFC 8032 verify; the oracle's own check that a signature it built (or
    one sxSignDetached built) validates under a public key. Matches
    sxSignVerifyDetached."""
    if len(sig) != 64 or len(pub) != 32:
        return False
    A = _pt_decompress(pub)
    if A is None:
        return False
    R = int.from_bytes(sig[:32], "little")
    s = int.from_bytes(sig[32:], "little")
    if s >= _L:
        return False
    h = int.from_bytes(_sha512(sig[:32] + pub + msg), "little") % _L
    sB = _pt_mul(s, _B)
    hA = _pt_mul(h, A)
    RplushA = _pt_add(_pt_decompress(sig[:32]), hA)
    return _pt_compress(sB) == _pt_compress(RplushA)


# ---------------------------------------------------------------------------
# X25519 (RFC 7748 montgomery ladder) and crypto_kx (libsodium's key
# exchange: kx secret = BLAKE2b-32(seed), kx public = X25519 base mult,
# session keys = BLAKE2b-64(q || client_pk || server_pk) split rx||tx for
# the client and tx||rx for the server, q = X25519(own_sk, peer_pk)).
#
# Anchored against a REAL libsodium (not typed from anyone's memory):
# tools/emit-kx-anchor.py loads libsodium through ctypes and prints what
# crypto_scalarmult_base / crypto_kx_seed_keypair /
# crypto_kx_{client,server}_session_keys return for the oracle's fixed
# inputs; the constants in _self_check below are that script's output
# (libsodium.so.23.3.0 = 1.0.18, Linux x86_64, 2026-08-14). Re-run the
# emitter against any libsodium to re-verify.
# ---------------------------------------------------------------------------

_A24 = 121665


def _x25519(scalar_bytes, u_bytes):
    k = int.from_bytes(scalar_bytes, "little")
    k &= (1 << 254) - 8
    k |= 1 << 254
    x1 = int.from_bytes(u_bytes, "little") & ((1 << 255) - 1)
    x2, z2 = 1, 0
    x3, z3 = x1, 1
    swap = 0
    for t in reversed(range(255)):
        k_t = (k >> t) & 1
        swap ^= k_t
        if swap:
            x2, x3 = x3, x2
            z2, z3 = z3, z2
        swap = k_t
        a = (x2 + z2) % _p
        aa = a * a % _p
        b = (x2 - z2) % _p
        bb = b * b % _p
        e = (aa - bb) % _p
        c = (x3 + z3) % _p
        d = (x3 - z3) % _p
        da = d * a % _p
        cb = c * b % _p
        x3 = (da + cb) % _p
        x3 = x3 * x3 % _p
        z3 = (da - cb) % _p
        z3 = z3 * z3 % _p
        z3 = z3 * x1 % _p
        x2 = aa * bb % _p
        z2 = e * (aa + _A24 * e) % _p
    if swap:
        x2, x3 = x3, x2
        z2, z3 = z3, z2
    return (x2 * pow(z2, _p - 2, _p) % _p).to_bytes(32, "little")


def x25519_base(scalar_bytes):
    return _x25519(scalar_bytes, (9).to_bytes(32, "little"))


def kx_seed_keypair(seed):
    """libsodium crypto_kx_seed_keypair: sk = BLAKE2b-32(seed), pk = base
    mult. Returns (pk, sk)."""
    if len(seed) != 32:
        raise ValueError("kx seed must be 32 bytes")
    sk = hashlib.blake2b(seed, digest_size=32).digest()
    return x25519_base(sk), sk


def _kx_session(q, client_pk, server_pk):
    h = hashlib.blake2b(digest_size=64)
    h.update(q)
    h.update(client_pk)
    h.update(server_pk)
    keys = h.digest()
    return keys[:32], keys[32:]


def kx_client_session_keys(client_pk, client_sk, server_pk):
    """(rx, tx) for the client, per sxKeyExchangeClient."""
    q = _x25519(client_sk, server_pk)
    return _kx_session(q, client_pk, server_pk)


def kx_server_session_keys(server_pk, server_sk, client_pk):
    """(rx, tx) for the server: the client's pair swapped."""
    q = _x25519(server_sk, client_pk)
    first, second = _kx_session(q, client_pk, server_pk)
    return second, first


# ---------------------------------------------------------------------------
# sxKdfDerive / sxHash semantics (libsodium BLAKE2b)
# ---------------------------------------------------------------------------

KDF_CONTEXT = b"riptide\x00"  # 8 bytes exactly; crypto_kdf_CONTEXTBYTES


def kdf_derive(master, subkey_id, subkey_len, context=KDF_CONTEXT):
    """libsodium crypto_kdf_derive_from_key: BLAKE2b(out=subkey_len, key=master,
    salt=LE64(subkey_id), personal=context) over an empty message."""
    if len(master) != 32:
        raise ValueError("master must be 32 bytes")
    if len(context) != 8:
        raise ValueError("context must be 8 bytes")
    return hashlib.blake2b(
        b"",
        digest_size=subkey_len,
        key=master,
        salt=struct.pack("<Q", subkey_id),
        person=context,
    ).digest()


def blake2b_hash(data, out_len):
    """sxHash: unkeyed BLAKE2b, out_len 16..64."""
    return hashlib.blake2b(data, digest_size=out_len).digest()


# The riptide subkey tree (RIPTIDE-SOCIAL-SPEC.md section 3.2)
SUBKEY_IDENTITY = 1
SUBKEY_DM = 2
SUBKEY_LAN = 3
SUBKEY_ANON_BASE = 100
SUBKEY_ANON_DM_BASE = 200


def identity_seed(master):
    return kdf_derive(master, SUBKEY_IDENTITY, 32)


def dm_seed(master):
    return kdf_derive(master, SUBKEY_DM, 32)


def lan_key(master):
    return kdf_derive(master, SUBKEY_LAN, 32)


def anon_seed(master, n):
    return kdf_derive(master, SUBKEY_ANON_BASE + n, 32)


def anon_dm_seed(master, n):
    """The anon persona's sealed-DM kx seed (spec 8.3): subkey 200+n, a
    SEPARATE subkey from the persona's ed25519 identity for the same reason
    subkey 2 is separate from subkey 1 - one seed never feeds two cipher
    schemes. With it, the WHOLE phase-4 record machinery composes for anon
    personas unchanged: build_prekey(kx_pub, anon_seed) is the persona's
    prekey (served over its onion, NEVER the DHT - the 9.3 guard),
    build_intro(..., recipient=anon_handle, ...) seals to it, and the
    recipient opens with this seed."""
    return kdf_derive(master, SUBKEY_ANON_DM_BASE + n, 32)


def handle_from_identity_seed(seed):
    """The 64-hex handle: the ed25519 public key of the identity seed.
    Equals btDhtKeypair(seedHex)["publicKey"] (tests/cross-member-test.py pins
    sodiumxt and libtorrent to the same derivation)."""
    return ed25519_publickey(seed).hex()


# ---------------------------------------------------------------------------
# v3 onion address (matches onionxt's oxAddressFromPublicKey algorithm and
# tools/onion-kat.py)
# ---------------------------------------------------------------------------

_B32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567"


def base32_lower_nopad(raw):
    bits = 0
    acc = 0
    out = []
    for b in raw:
        acc = (acc << 8) | b
        bits += 8
        while bits >= 5:
            bits -= 5
            out.append(_B32_ALPHABET[(acc >> bits) & 31])
    if bits:
        out.append(_B32_ALPHABET[(acc << (5 - bits)) & 31])
    return "".join(out)


def onion_from_pubkey(pub):
    """<56 chars>.onion: base32(pubkey || checksum || 0x03) where checksum is
    SHA3-256(".onion checksum" || pubkey || 0x03)[:2]."""
    if len(pub) != 32:
        raise ValueError("pubkey must be 32 bytes")
    ck = hashlib.sha3_256(b".onion checksum" + pub + b"\x03").digest()[:2]
    return base32_lower_nopad(pub + ck + b"\x03") + ".onion"


def pubkey_from_onion(addr):
    """The offline inverse: the first 32 decoded bytes. Structural only, no
    checksum verification (mirrors oxPublicKeyFromAddress)."""
    s = addr.lower()
    if s.endswith(".onion"):
        s = s[:-6]
    if len(s) != 56:
        raise ValueError("onion address must be 56 base32 chars")
    acc = 0
    bits = 0
    raw = bytearray()
    for ch in s:
        acc = (acc << 5) | _B32_ALPHABET.index(ch)
        bits += 5
        if bits >= 8:
            bits -= 8
            raw.append((acc >> bits) & 255)
    return bytes(raw[:32])


# ---------------------------------------------------------------------------
# Rendezvous derivations (RIPTIDE-SOCIAL-SPEC.md sections 5.1, 5.2)
# ---------------------------------------------------------------------------

INBOX_SUFFIX = b"riptide-inbox"


def inbox_id(handle_hex):
    """40-hex phantom-swarm id: BLAKE2b-20(pubkey_bytes || "riptide-inbox")."""
    return blake2b_hash(bytes.fromhex(handle_hex) + INBOX_SUFFIX, 20).hex()


def room_id(pk_a_hex, pk_b_hex, session_salt):
    """40-hex pairwise room id: BLAKE2b-20(sortedConcat(pkA, pkB) || salt).
    Sorted by lowercase hex order, which equals raw byte order, so both peers
    derive the same id regardless of who computes it."""
    a = pk_a_hex.lower()
    b = pk_b_hex.lower()
    if a <= b:
        cat = bytes.fromhex(a) + bytes.fromhex(b)
    else:
        cat = bytes.fromhex(b) + bytes.fromhex(a)
    return blake2b_hash(cat + session_salt, 20).hex()


# ---------------------------------------------------------------------------
# BEP44 helpers (torrentxt's btDhtBep44SignBuf / immutable targets)
# ---------------------------------------------------------------------------


def bencode_bytes(value):
    """bencode of a byte string: <len>:<bytes>. The only bencode shape riptide
    puts on the DHT; there is deliberately no general bencoder here."""
    return str(len(value)).encode("ascii") + b":" + value


def immutable_target(value):
    """The 40-hex DHT target of an immutable item: SHA-1 of the bencoded value
    (BEP44; what btDhtPutImmutable returns)."""
    return hashlib.sha1(bencode_bytes(value)).hexdigest()


def bep44_signbuf(salt, seq, value):
    """The canonical BEP44 signing buffer btDhtBep44SignBuf returns. value is
    the ALREADY-BENCODED v."""
    buf = b""
    if salt:
        buf += b"4:salt" + str(len(salt)).encode("ascii") + b":" + salt
    buf += b"3:seqi" + str(seq).encode("ascii") + b"e1:v"
    buf += value
    return buf


# ---------------------------------------------------------------------------
# RSH1 - the feed head record (BEP44 mutable value content, before bencoding)
#
# All framing integers big-endian; u64 as hi:u32 lo:u32 (the BTXO discipline).
# DHT targets travel as 40 ASCII hex bytes; all-zeros means "none".
# Caps are enforced by build AND parse on both sides of the wire.
# ---------------------------------------------------------------------------

HEAD_MAGIC = b"RSH1"
POST_MAGIC = b"RSP1"
KEYFILE_MAGIC = b"RIPTKEY1"
HEAD_SALT = "riptide-head"
ZERO_TARGET = "0" * 40
MAX_DISPLAY_NAME = 64  # bytes of UTF-8
MAX_MEDIA = 8
MAX_CHUNKS = 16
MAX_RECORD = 1000  # the BEP44 value cap
ONION_ADDR_LEN = 62  # "<56 chars>.onion"


def _u16(n):
    return struct.pack(">H", n)


def _u64(n):
    return struct.pack(">II", n // 4294967296, n % 4294967296)


def _hex40(target):
    t = (target or ZERO_TARGET).lower()
    if len(t) != 40 or any(c not in "0123456789abcdef" for c in t):
        raise ValueError("target must be 40 hex chars")
    return t.encode("ascii")


def build_head(seq, display_name, latest_post, prekey, onion_addr, profile_meta):
    name_b = display_name.encode("utf-8")
    if len(name_b) > MAX_DISPLAY_NAME:
        raise ValueError("display name over %d bytes" % MAX_DISPLAY_NAME)
    onion_b = (onion_addr or "").lower().encode("ascii")
    if onion_b and len(onion_b) != ONION_ADDR_LEN:
        raise ValueError("onion address must be %d chars" % ONION_ADDR_LEN)
    rec = HEAD_MAGIC
    rec += _u64(seq)
    rec += bytes([len(name_b)]) + name_b
    rec += _hex40(latest_post)
    rec += _hex40(prekey)
    rec += bytes([len(onion_b)]) + onion_b
    rec += _hex40(profile_meta)
    if len(rec) > MAX_RECORD:
        raise ValueError("head record over %d bytes" % MAX_RECORD)
    return rec


# ---------------------------------------------------------------------------
# RSP1 - the post record (BEP44 immutable item, 1..1000 bytes)
#
# magic(4) timestamp(u64) prevPostTarget(40 hex) kind(1: "D"/"C")
#   D: textLen(u16) text(UTF-8)
#   C: chunkCount(u8) then count * 40-hex chunk targets
# mediaCount(u8) then count * 40-hex info-hashes
# authorSig(64): ed25519 detached over every byte before the signature.
# ---------------------------------------------------------------------------


def _post_body(timestamp, prev_target, kind, text=b"", chunk_targets=(), media=()):
    rec = POST_MAGIC
    rec += _u64(timestamp)
    rec += _hex40(prev_target)
    rec += kind
    if kind == b"D":
        rec += _u16(len(text)) + text
    elif kind == b"C":
        if not 1 <= len(chunk_targets) <= MAX_CHUNKS:
            raise ValueError("chunk count must be 1..%d" % MAX_CHUNKS)
        rec += bytes([len(chunk_targets)])
        for t in chunk_targets:
            rec += _hex40(t)
    else:
        raise ValueError("kind must be D or C")
    if len(media) > MAX_MEDIA:
        raise ValueError("media count over %d" % MAX_MEDIA)
    rec += bytes([len(media)])
    for m in media:
        rec += _hex40(m)
    return rec


def build_post(timestamp, prev_target, text, media, identity_seed_bytes):
    """A kind-D (direct text) post, signed. text is a str; media a list of
    40-hex info-hashes; identity_seed_bytes the 32-byte identity subkey."""
    body = _post_body(
        timestamp, prev_target, b"D", text=text.encode("utf-8"), media=media
    )
    sig = ed25519_sign(body, identity_seed_bytes)
    rec = body + sig
    if len(rec) > MAX_RECORD:
        raise ValueError("post record over %d bytes" % MAX_RECORD)
    return rec


def build_post_chunked(timestamp, prev_target, chunk_targets, media, identity_seed_bytes):
    """A kind-C post whose text lives in immutable chunks named in order."""
    body = _post_body(
        timestamp, prev_target, b"C", chunk_targets=chunk_targets, media=media
    )
    sig = ed25519_sign(body, identity_seed_bytes)
    rec = body + sig
    if len(rec) > MAX_RECORD:
        raise ValueError("post record over %d bytes" % MAX_RECORD)
    return rec


# ---------------------------------------------------------------------------
# Phase 4 - the DM wire formats (RIPTIDE-SOCIAL-SPEC.md section 5)
#
# RSK1 prekey record (the immutable item a head's prekeyTarget names):
#   magic(4) kxPub(64 ascii hex) authorSig(64): ed25519 by the identity key
#   over every byte before it. Exact length 132.
# RSI1 intro (the plaintext sxSeal wraps; sealed bytes are nondeterministic):
#   magic(4) senderHandle(64 hex) senderKxPub(64 hex) recipientHandle(64 hex)
#   timestamp(u64 BE) authorSig(64). Exact length 268. The recipient handle
#   inside the signed body binds the intro to ONE inbox (no replay to a
#   third party); the timestamp lets an app apply a freshness window.
# RSM1 rp1 frame (the outer transport frame; payload stays opaque here):
#   magic(4) kind(1: "I" sealed intro / "H" secretstream header / "M" stream
#   ciphertext) payload(1..59995). The whole frame caps at the rp1 60000.
# DM inner message (the plaintext INSIDE the secretstream):
#   kind(1: "T" text / "O" sdp offer / "A" sdp answer) timestamp(u64 BE)
#   body(UTF-8, may be empty for "O"/"A"? no - body always >= 1 byte).
# ---------------------------------------------------------------------------

PREKEY_MAGIC = b"RSK1"
INTRO_MAGIC = b"RSI1"
FRAME_MAGIC = b"RSM1"
FRAME_KINDS = (b"I", b"H", b"M")
MESSAGE_KINDS = (b"T", b"O", b"A")
FRAME_MAX = 60000  # the rp1 payload cap; the frame must fit inside it


def _hex64(value):
    t = value.lower()
    if len(t) != 64 or any(c not in "0123456789abcdef" for c in t):
        raise ValueError("expected 64 hex chars")
    return t.encode("ascii")


def build_prekey(kx_pub_hex, identity_seed_bytes):
    body = PREKEY_MAGIC + _hex64(kx_pub_hex)
    return body + ed25519_sign(body, identity_seed_bytes)


def build_intro(sender_handle, sender_kx_pub_hex, recipient_handle,
                timestamp, identity_seed_bytes):
    body = INTRO_MAGIC
    body += _hex64(sender_handle)
    body += _hex64(sender_kx_pub_hex)
    body += _hex64(recipient_handle)
    body += _u64(timestamp)
    return body + ed25519_sign(body, identity_seed_bytes)


def build_dm_frame(kind, payload):
    if kind not in FRAME_KINDS:
        raise ValueError("frame kind must be I, H, or M")
    if len(payload) < 1:
        raise ValueError("frame payload must be non-empty")
    rec = FRAME_MAGIC + kind + payload
    if len(rec) > FRAME_MAX:
        raise ValueError("frame over the rp1 %d cap" % FRAME_MAX)
    return rec


def build_dm_message(kind, timestamp, body_text):
    if kind not in MESSAGE_KINDS:
        raise ValueError("message kind must be T, O, or A")
    body = body_text.encode("utf-8")
    if len(body) < 1:
        raise ValueError("message body must be non-empty")
    return kind + _u64(timestamp) + body


# ---------------------------------------------------------------------------
# Phase 6 - LAN device-mesh admission (RIPTIDE-SOCIAL-SPEC.md section 7)
#
# All your devices share one master seed, so they all derive the SAME LAN
# subkey ed25519 keypair (lan_key -> sxSignKeypairFromSeed). Admission is a
# proof that the joiner holds the master: the host sends a random challenge,
# the joiner signs "riptide-lan" || nonce || itsName under the LAN secret,
# and the host verifies against the LAN public it derives from its OWN
# master. A stranger on the same Wi-Fi cannot sign, so cannot join.
#
# The enet connect-data rider is a u32 (a protocol tag), NOT a byte buffer,
# so the challenge/response are first MESSAGES on channel 0, each an RSL1
# record. The signature binds the nonce (freshness) and the joiner's name.
# ---------------------------------------------------------------------------

LAN_MAGIC = b"RSL1"
LAN_DOMAIN = b"riptide-lan"  # signature domain separator
LAN_NONCE_BYTES = 32
LAN_MAX_NAME = 32  # bytes of UTF-8 device name


def lan_keys(master):
    """The LAN mesh ed25519 keypair (all your devices derive the same one).
    Returns (public_key_bytes, seed_bytes) - the seed IS the signing key for
    ed25519_sign, mirroring sxSignKeypairFromSeed(lan_key)."""
    seed = lan_key(master)
    return ed25519_publickey(seed), seed


def _lan_name(name):
    b = name.encode("utf-8")
    if not 1 <= len(b) <= LAN_MAX_NAME:
        raise ValueError("device name must be 1..%d bytes" % LAN_MAX_NAME)
    return b


def lan_build_challenge(name, nonce):
    """Host -> joiner: magic(4) "C" nameLen(u8) name nonce(32)."""
    if len(nonce) != LAN_NONCE_BYTES:
        raise ValueError("nonce must be %d bytes" % LAN_NONCE_BYTES)
    nb = _lan_name(name)
    return LAN_MAGIC + b"C" + bytes([len(nb)]) + nb + nonce


def lan_sig_message(nonce, name):
    return LAN_DOMAIN + nonce + _lan_name(name)


def lan_build_response(challenge_bytes, name, master):
    """Joiner -> host: magic(4) "R" nameLen(u8) name sig(64), sig ed25519 by
    the LAN key over "riptide-lan" || nonce || name."""
    nonce = _lan_parse_challenge(challenge_bytes)["nonce"]
    nb = _lan_name(name)
    _pub, seed = lan_keys(master)
    sig = ed25519_sign(lan_sig_message(nonce, name), seed)
    return LAN_MAGIC + b"R" + bytes([len(nb)]) + nb + sig


LAN_WELCOME_DOMAIN = b"riptide-lan-w"


def lan_welcome_sig_message(response_sig, host_name):
    """The bytes the welcome signature covers: a distinct domain tag, the
    joiner's own response SIGNATURE (unique per challenge nonce, so a welcome
    replays to no other handshake), and the host's name."""
    if len(response_sig) != 64:
        raise ValueError("response signature must be 64 bytes")
    return LAN_WELCOME_DOMAIN + response_sig + _lan_name(host_name)


def lan_build_welcome(response_bytes, host_name, master):
    """Host -> joiner after admission: magic(4) "W" nameLen(u8) hostName
    sig(64). MUTUAL auth: only a master-holder can sign it, so the joiner
    learns the host is genuinely one of its own devices - previously the
    admission proved the joiner to the host and nothing back."""
    resp_sig = response_bytes[-64:]
    nb = _lan_name(host_name)
    _pub, seed = lan_keys(master)
    sig = ed25519_sign(lan_welcome_sig_message(resp_sig, host_name), seed)
    return LAN_MAGIC + b"W" + bytes([len(nb)]) + nb + sig


def _lan_parse_challenge(rec):
    if len(rec) < 4 + 1 + 1 + LAN_NONCE_BYTES:
        raise ValueError("challenge too short")
    if rec[:4] != LAN_MAGIC or rec[4:5] != b"C":
        raise ValueError("not an RSL1 challenge")
    nlen = rec[5]
    if len(rec) != 6 + nlen + LAN_NONCE_BYTES:
        raise ValueError("challenge length mismatch")
    return {"name": rec[6:6 + nlen].decode("utf-8"),
            "nonce": rec[6 + nlen:]}


# ---------------------------------------------------------------------------
# Phase 6 - the SYNC records over the admitted mesh (spec section 7's
# channel discipline; added 2026-08-15 with the sync-payload build).
#
# THE AUTHENTICATION CHOICE, recorded: every sync record is signed under
# the SAME shared LAN ed25519 key the admission uses, with a DISTINCT
# domain tag ("riptide-lan-s") over the WHOLE record body, kind byte
# included. The admission welcome leaves no fresh session secret behind
# (it is mutual signature verification, not a key exchange), so the
# records sign under the one key both sides already hold; a per-handshake
# binder was rejected because a host-relayed record must verify
# identically at every admitted peer, and replay is neutralized by each
# record's monotonic/absolute APPLY semantics (draft seq strictly
# forward, feed/read state as max, presence tick strictly forward)
# rather than by the wire format. Authenticated, NOT encrypted - the
# spec's admission-only design.
# ---------------------------------------------------------------------------

LAN_SYNC_DOMAIN = b"riptide-lan-s"
LAN_MAX_DRAFT = 4096
ZERO_HANDLE = "0" * 64


def _lan_sync_sign(body, master):
    _pub, seed = lan_keys(master)
    return ed25519_sign(LAN_SYNC_DOMAIN + body, seed)


def _lan_counter(n, what):
    if not isinstance(n, int) or not 0 <= n < 2 ** 53:
        raise ValueError("%s must be a non-negative integer below 2^53"
                         % what)
    return n


def lan_build_draft(name, seq, draft_text, master):
    """Channel-0 draft sync: magic(4) "D" nameLen(u8) name seq(u64 BE)
    draftLen(u16 BE) draft(UTF-8, 0..4096 - empty means cleared) sig(64).
    The draft is ABSOLUTE state; the per-device seq is the replay/reorder
    guard (receivers apply only a strictly higher seq per device)."""
    nb = _lan_name(name)
    db = draft_text.encode("utf-8")
    if len(db) > LAN_MAX_DRAFT:
        raise ValueError("draft over %d bytes" % LAN_MAX_DRAFT)
    body = (LAN_MAGIC + b"D" + bytes([len(nb)]) + nb
            + _u64(_lan_counter(seq, "seq")) + _u16(len(db)) + db)
    return body + _lan_sync_sign(body, master)


def lan_build_feed_state(name, feed_seq, read_peer_hex, read_up_to, master):
    """Channel-0 feed-seq / read-receipt state: magic(4) "F" nameLen(u8)
    name feedSeq(u64 BE) readPeer(64 ascii hex; all-zeros = none)
    readUpTo(u64 BE) sig(64). Absolute state, applied as MAX on both
    halves - feedSeq is what keeps two devices from publishing a
    conflicting head."""
    nb = _lan_name(name)
    peer = (read_peer_hex or ZERO_HANDLE).lower()
    if len(peer) != 64 or any(c not in "0123456789abcdef" for c in peer):
        raise ValueError("read peer must be empty or 64 hex chars")
    body = (LAN_MAGIC + b"F" + bytes([len(nb)]) + nb
            + _u64(_lan_counter(feed_seq, "feed seq"))
            + peer.encode("ascii")
            + _u64(_lan_counter(read_up_to, "read-up-to")))
    return body + _lan_sync_sign(body, master)


def lan_build_presence(name, typing, tick, master):
    """Channel-1 presence/typing: magic(4) "P" nameLen(u8) name flags(u8:
    bit0 typing, other bits refused fail-closed) tick(u64 BE) sig(64).
    ABSOLUTE state, safely droppable: the per-device monotonic tick makes
    it reorder-proof without transport sequencing, and senders re-assert
    on a cadence instead of sending deltas."""
    nb = _lan_name(name)
    body = (LAN_MAGIC + b"P" + bytes([len(nb)]) + nb
            + bytes([1 if typing else 0])
            + _u64(_lan_counter(tick, "tick")))
    return body + _lan_sync_sign(body, master)


# The channel-2 decision, recorded (2026-08-16): bulk media handoff
# between admitted devices is a channel-0 POINTER record, not a new wire.
# A draft's media essentially never fits enet's 60000-byte packet budget,
# and the suite's seam law (enetxt) is that a payload over it stops being
# a message and becomes a torrent - which is the phase-3 machinery this
# repo already proved on two machines. So the "M" record carries the
# 40-hex v1 info-hash (in the phase-3 design that one value IS both the
# content address libtorrent verifies piece-by-piece AND the torrent
# linkage a magnet fetch takes), plus the file's leaf name and size for
# the receiving UI. Channel 2 stays reserved, dark.

LAN_MAX_FILE = 255  # bytes of UTF-8 file leaf name (the u8 length field)


def lan_build_handoff(name, seq, info_hash, file_name, file_size, master):
    """Channel-0 media handoff: magic(4) "M" nameLen(u8) name seq(u64 BE)
    infoHash(40 ascii lowercase hex, non-zero) fileNameLen(u8) fileName
    (UTF-8, 1..255) fileSize(u64 BE) sig(64). ABSOLUTE state - the
    device's LATEST handoff offer - with the draft record's replay guard
    (apply only a seq strictly above the last applied per device); a
    duplicate apply is harmless anyway because the fetch it points at is
    idempotent (rsMediaFetch finds before it adds)."""
    nb = _lan_name(name)
    h = info_hash.lower()
    if len(h) != 40 or any(c not in "0123456789abcdef" for c in h):
        raise ValueError("info hash must be 40 hex chars")
    if h == "0" * 40:
        raise ValueError("info hash must name real content (non-zero)")
    fb = file_name.encode("utf-8")
    if not 1 <= len(fb) <= LAN_MAX_FILE:
        raise ValueError("file name must be 1..%d bytes" % LAN_MAX_FILE)
    body = (LAN_MAGIC + b"M" + bytes([len(nb)]) + nb
            + _u64(_lan_counter(seq, "seq")) + h.encode("ascii")
            + bytes([len(fb)]) + fb
            + _u64(_lan_counter(file_size, "file size")))
    return body + _lan_sync_sign(body, master)


# ---------------------------------------------------------------------------
# Phase 7 - the anonymous persona (RIPTIDE-SOCIAL-SPEC.md section 8)
#
# An anon persona is a separate ed25519 identity (a subkey-100+n seed) that
# lives ONLY as an onion service and never touches the DHT, a torrent, or
# rp1 (the Model C invariant, section 9.3). Its handle is the ed25519
# public of the anon subkey; its .onion is that key the same way the public
# identity's is - so anon_onion(master, n) is fully derivable offline and
# equals oxCreateServiceFromSeed(anon_seed(master, n)).
#
# The BTXO framed-chunk protocol (Model C, shared with the quickshare onion
# transfer): a header, then u32-length-prefixed DATA frames, then a
# zero-length terminator, all over one Tor stream. Payload never crosses as
# a torrent - anonymity's honest cost is serving files directly.
# ---------------------------------------------------------------------------

BTXO_MAGIC = b"BTXO"
BTXO_VER = 1
BTXO_MAX_NAME = 65535  # the u16 name-length field


def anon_handle(master, index):
    """The anon persona's 64-hex handle: the ed25519 public of its subkey."""
    return ed25519_publickey(anon_seed(master, index)).hex()


def anon_onion(master, index):
    """The anon persona's .onion - the SAME key as a v3 onion, derivable
    offline; equals oxCreateServiceFromSeed(anon_seed(master, index))."""
    return onion_from_pubkey(ed25519_publickey(anon_seed(master, index)))


def btxo_header(name, total, flags=0):
    """magic(4) ver(1) flags(1) nameLen(u16 BE) name(UTF-8) total(u64 BE)."""
    nb = name.encode("utf-8")
    if len(nb) > BTXO_MAX_NAME:
        raise ValueError("name over the u16 length field")
    if not 0 <= flags <= 255:
        raise ValueError("flags is one byte")
    return (BTXO_MAGIC + bytes([BTXO_VER, flags]) + _u16(len(nb)) + nb
            + _u64(total))


def btxo_data_frame(payload):
    """length(u32 BE) then the bytes; a non-empty content frame."""
    if len(payload) < 1:
        raise ValueError("a data frame carries at least one byte")
    return struct.pack(">I", len(payload)) + payload


def btxo_terminator():
    """The zero-length frame that ends a BTXO stream."""
    return struct.pack(">I", 0)


# ---------------------------------------------------------------------------
# Spec 8.2/8.3 - the onion SERVING payloads (added 2026-08-15 with the
# transport seams). The persona's onion-httpd routes serve exactly these
# bytes: GET / is the anon feed page (deterministic HTML - a wire format,
# pinned, not a restylable template), GET /prekey is the signed RSK1
# prekey record as lowercase hex text, and POST /dm accepts the sealed
# RSI1 intro as strict hex (the script layer's rsAnonAcceptDm; its
# acceptance is seal-open crypto this pure model deliberately does not
# mirror - sxSeal has no oracle here, the same boundary phase 4 drew).
# ---------------------------------------------------------------------------

ANON_PAGE_MAX = 65536  # the finished page cap (rsAnonFeedPage refuses over)


def html_escape(text):
    """HTML text-context escape, the oxhHtmlEscape algorithm: & first."""
    return (text.replace("&", "&amp;").replace("<", "&lt;")
                .replace(">", "&gt;").replace('"', "&quot;"))


def anon_feed_page(title, entries):
    """The anon feed page as UTF-8 bytes. `entries` is the final list of
    non-empty entry strings (the script layer splits its line-delimited
    argument and skips blanks before reaching this shape)."""
    tb = title.encode("utf-8")
    if not 1 <= len(tb) <= MAX_DISPLAY_NAME:
        raise ValueError("title must be 1..%d UTF-8 bytes"
                         % MAX_DISPLAY_NAME)
    esc = html_escape(title)
    out = ("<!doctype html><html><head><meta charset='utf-8'><title>"
           + esc + "</title></head><body><h1>" + esc + "</h1><ul>")
    for entry in entries:
        out += "<li>" + html_escape(entry) + "</li>"
    out += ("</ul><p>Sealed DMs: GET /prekey (my signed RSK1 prekey "
            "record, hex), then POST your sealed intro as hex to "
            "/dm.</p></body></html>")
    page = out.encode("utf-8")
    if len(page) > ANON_PAGE_MAX:
        raise ValueError("page over %d bytes" % ANON_PAGE_MAX)
    return page


def anon_prekey_body(master, index):
    """The GET /prekey response body: persona `index`'s RSK1 prekey record
    (subkey-200+n kx public, signed by the subkey-100+n anon identity) as
    lowercase hex text - 264 chars."""
    kx_pk, _kx_sk = kx_seed_keypair(anon_dm_seed(master, index))
    return build_prekey(kx_pk.hex(), anon_seed(master, index)).hex()


# ---------------------------------------------------------------------------
# Import-time self-checks against the independent anchors. A model that
# cannot reproduce a vector it did not invent must not be consulted.
# ---------------------------------------------------------------------------


def _self_check():
    # sxKdfDerive semantics: the C KAT from sodiumxt/tests/sodium_smoke_test.c
    got = kdf_derive(b"\x01" * 32, 1, 32, context=b"SXTctx00")
    want = "dc9d1a0879b1884c4cafbc2a68d1b22926e8a6a0043f458c7f1bc370b032058f"
    if got.hex() != want:
        raise AssertionError("KDF self-check failed: hashlib.blake2b disagrees "
                             "with the sodiumxt C KAT")

    # ed25519: the cross-project conformance vector bep44_golden_test.py pins,
    # and the zero-seed pubkey from sodium_smoke_test.c
    seed = bytes.fromhex(
        "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7")
    if ed25519_publickey(seed).hex() != (
            "672e8e0b259627f15c772ec0d61f15cd786ce2bc7244549255f9d6cfaac300b2"):
        raise AssertionError("ed25519 self-check failed (conformance seed)")
    if ed25519_publickey(b"\x00" * 32).hex() != (
            "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29"):
        raise AssertionError("ed25519 self-check failed (zero seed)")

    # BEP44 signbuf: the pinned buffer and signature from bep44_golden_test.py
    if bep44_signbuf(b"rp-prekeys", 1, b"2:hi") != (
            b"4:salt10:rp-prekeys3:seqi1e1:v2:hi"):
        raise AssertionError("BEP44 signbuf self-check failed")
    if ed25519_sign(b"4:salt10:rp-prekeys3:seqi1e1:v2:hi", seed).hex() != (
            "86c843ec4cc2495e025e949dd72658ef01556dbbfb1f5d9b474b5957dbcb26a2"
            "3497efe40f594387cc4f037075669efa4c42cb57c007eb0bddaa24934f3f740b"):
        raise AssertionError("ed25519 signature self-check failed")

    # v3 onion: a real published onion (torproject.org's, the onion-kat.py
    # vector) must survive decode -> re-derive.
    real = "2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion"
    if onion_from_pubkey(pubkey_from_onion(real)) != real:
        raise AssertionError("onion address self-check failed")

    # X25519 + crypto_kx: anchored against a REAL libsodium via
    # tools/emit-kx-anchor.py (libsodium.so.23.3.0 = 1.0.18, Linux x86_64,
    # 2026-08-14). These constants are that script's printed output; re-run
    # it against any libsodium to re-verify the anchor.
    if x25519_base(b"\x42" * 32).hex() != (
            "132c442be010fbd57e72603328aa76e71fccc1503aae219327d14d9c9993f472"):
        raise AssertionError("X25519 base-mult self-check failed")
    dm = kdf_derive(b"\x42" * 32, SUBKEY_DM, 32)
    conf = bytes.fromhex(
        "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7")
    gpk, gsk = kx_seed_keypair(dm)
    if gpk.hex() != ("d946190585386568c3123a6fa706f94f"
                     "5140fdfe647ab51fdf76e3f6e5799d3c"):
        raise AssertionError("crypto_kx seed keypair self-check failed (pk)")
    if gsk.hex() != ("f594dec79bb8d739bfe462cfd602a83e"
                     "dd48d17fecd6890bd71e1417edfae92b"):
        raise AssertionError("crypto_kx seed keypair self-check failed (sk)")
    cpk, csk = kx_seed_keypair(conf)
    if cpk.hex() != ("9cf14a375404bd5f3fc048647215af20"
                     "b506717fdab3f6e7df50c64e837f2059"):
        raise AssertionError("crypto_kx conf keypair self-check failed")
    rx, tx = kx_client_session_keys(gpk, gsk, cpk)
    if rx.hex() != ("0cf0c702142da300ac5d769dff39a1b4"
                    "aabe4842b617cdf4a624815290b4ba38"):
        raise AssertionError("crypto_kx client rx self-check failed")
    if tx.hex() != ("2f8bb162c5e2d4346eadcf2a47804458"
                    "428840336303e629d1ac20e8375dfe83"):
        raise AssertionError("crypto_kx client tx self-check failed")
    srx, stx = kx_server_session_keys(cpk, csk, gpk)
    if srx != tx or stx != rx:
        raise AssertionError("crypto_kx server keys do not cross-match")

    # LAN admission: a response built here must verify under the LAN public
    # derived from the same master, and a one-byte tamper must break it.
    m = b"\x42" * 32
    nonce = bytes.fromhex("5a" * 32)
    ch = lan_build_challenge("laptop", nonce)
    resp = lan_build_response(ch, "phone", m)
    lp, _ls = lan_keys(m)
    sig = resp[-64:]
    if not _verify_ed25519(sig, lan_sig_message(nonce, "phone"), lp):
        raise AssertionError("LAN admission self-check failed (valid sig)")
    if _verify_ed25519(sig, lan_sig_message(nonce, "laptop"), lp):
        raise AssertionError("LAN admission self-check failed (name binding)")

    # LAN sync records: the signature verifies under the sync domain, and
    # ONLY under the sync domain (an admission-domain read must fail - the
    # cross-record confusion the distinct tag exists to stop).
    dr = lan_build_draft("phone", 1, "d", m)
    if not _verify_ed25519(dr[-64:], LAN_SYNC_DOMAIN + dr[:-64], lp):
        raise AssertionError("LAN sync self-check failed (valid sig)")
    if _verify_ed25519(dr[-64:], LAN_DOMAIN + dr[:-64], lp):
        raise AssertionError("LAN sync self-check failed (domain "
                             "separation)")
    ho = lan_build_handoff("phone", 1, "ab" * 20, "f", 1, m)
    if not _verify_ed25519(ho[-64:], LAN_SYNC_DOMAIN + ho[:-64], lp):
        raise AssertionError("LAN handoff self-check failed (valid sig)")


_self_check()


# ---------------------------------------------------------------------------
# Vector printer: `python3 riptide_reference.py` prints the golden table the
# harness constants are copied from; `--check` runs the self-checks only.
# ---------------------------------------------------------------------------


def golden_vectors():
    """Every derived vector the harness and golden test pin, as a dict."""
    master = b"\x42" * 32
    id_seed = identity_seed(master)
    handle = handle_from_identity_seed(id_seed)
    onion = onion_from_pubkey(bytes.fromhex(handle))
    conf_seed = bytes.fromhex(
        "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7")
    conf_pub = ed25519_publickey(conf_seed).hex()
    prekey_t = "ab" * 20
    profile_t = "cd" * 20
    post1 = build_post(1754870400, ZERO_TARGET, "hello, riptide", [], id_seed)
    post1_target = immutable_target(post1)
    post2 = build_post(1754870460, post1_target, "second post",
                       ["ee" * 20], id_seed)
    post2_target = immutable_target(post2)
    head = build_head(7, "Riptide", post2_target, prekey_t, onion, profile_t)
    head_v = bencode_bytes(head)
    head_buf = bep44_signbuf(HEAD_SALT.encode("ascii"), 7, head_v)
    head_sig = ed25519_sign(head_buf, id_seed)
    # phase 4: the DM keys and wire records. The golden identity's handle
    # (5a54...) sorts below the conformance pubkey (672e...), so per the
    # role rule (lexically smaller handle is the kx CLIENT) the golden
    # side is the client and the conformance side the server.
    dm_kx_pk, dm_kx_sk = kx_seed_keypair(dm_seed(master))
    conf_kx_pk, conf_kx_sk = kx_seed_keypair(conf_seed)
    sess_rx, sess_tx = kx_client_session_keys(dm_kx_pk, dm_kx_sk, conf_kx_pk)
    prekey_rec = build_prekey(dm_kx_pk.hex(), id_seed)
    intro = build_intro(handle, dm_kx_pk.hex(), conf_pub, 1754870520, id_seed)
    intro_frame = build_dm_frame(b"I", intro)
    dm_msg = build_dm_message(b"T", 1754870580, "hello, dm")
    # phase 6: LAN admission. A fixed nonce makes the challenge and the
    # signed response deterministic (the app uses sxRandomBytes; the golden
    # pins a chosen nonce so the record and its signature are reproducible).
    lan_pub, _lan_seed = lan_keys(master)
    lan_nonce = bytes.fromhex("5a" * 32)
    lan_challenge = lan_build_challenge("laptop", lan_nonce)
    lan_response = lan_build_response(lan_challenge, "phone", master)
    lan_welcome = lan_build_welcome(lan_response, "laptop", master)
    # the phase-6 sync records (deterministic: chosen name/counters/text)
    lan_draft = lan_build_draft("phone", 5, "draft: hello mesh", master)
    lan_feed_state = lan_build_feed_state("phone", 9, handle,
                                          1754870700, master)
    lan_presence = lan_build_presence("phone", True, 3, master)
    # the channel-0 media handoff pointer (the chosen placeholder
    # info-hash is the same one the golden post-2 media list carries)
    lan_handoff = lan_build_handoff("phone", 7, "ee" * 20, "clip.mp4",
                                    1048576, master)
    # phase 7: the anon persona (subkey 100) and a sample BTXO stream
    anon0_handle = anon_handle(master, 0)
    anon0_onion = anon_onion(master, 0)
    btxo_hdr = btxo_header("secret.txt", 11, 0)
    btxo_frame = btxo_data_frame(b"hello world")
    # 8.3: the anon persona's sealed-DM prekey - the phase-4 RSK1/RSI1
    # machinery composed with the anon subkeys, nothing new on the wire
    anon0_dm_kx_pk, _adk_sk = kx_seed_keypair(anon_dm_seed(master, 0))
    anon0_prekey = build_prekey(anon0_dm_kx_pk.hex(), anon_seed(master, 0))
    anon0_intro = build_intro(handle, dm_kx_pk.hex(), anon0_handle,
                              1754870640, id_seed)
    # 8.2/8.3 serving: the feed page (title + the two golden post texts as
    # entries) and the /prekey body (== anon0_prekey, hex)
    anon0_page = anon_feed_page("Riptide", ["hello, riptide", "second post"])
    anon0_prekey_body = anon_prekey_body(master, 0)
    return {
        "master": master.hex(),
        "idSeed": id_seed.hex(),
        "dmSeed": dm_seed(master).hex(),
        "lanKey": lan_key(master).hex(),
        "anon0Seed": anon_seed(master, 0).hex(),
        "handle": handle,
        "onion": onion,
        "confSeed": conf_seed.hex(),
        "confPub": conf_pub,
        "inboxId": inbox_id(handle),
        "roomId": room_id(handle, conf_pub, b"golden-salt"),
        "post1": post1.hex(),
        "post1Target": post1_target,
        "post2": post2.hex(),
        "post2Target": post2_target,
        "head": head.hex(),
        "headValue": head_v.hex(),
        "headBuf": head_buf.hex(),
        "headSig": head_sig.hex(),
        "dmKxPub": dm_kx_pk.hex(),
        "confKxPub": conf_kx_pk.hex(),
        "confKxSec": conf_kx_sk.hex(),
        "sessionRx": sess_rx.hex(),
        "sessionTx": sess_tx.hex(),
        "prekeyRec": prekey_rec.hex(),
        "prekeyRecTarget": immutable_target(prekey_rec),
        "intro": intro.hex(),
        "introTarget": immutable_target(intro),
        "introFrame": intro_frame.hex(),
        "dmMsg": dm_msg.hex(),
        "lanPub": lan_pub.hex(),
        "lanNonce": lan_nonce.hex(),
        "lanChallenge": lan_challenge.hex(),
        "lanResponse": lan_response.hex(),
        "lanWelcome": lan_welcome.hex(),
        "lanDraft": lan_draft.hex(),
        "lanFeedState": lan_feed_state.hex(),
        "lanPresence": lan_presence.hex(),
        "lanHandoff": lan_handoff.hex(),
        "anon0Handle": anon0_handle,
        "anon0Onion": anon0_onion,
        "anon0DmSeed": anon_dm_seed(master, 0).hex(),
        "anon0DmKxPub": anon0_dm_kx_pk.hex(),
        "anon0Prekey": anon0_prekey.hex(),
        "anon0Intro": anon0_intro.hex(),
        "anon0Page": anon0_page.hex(),
        "anon0PrekeyBody": anon0_prekey_body,
        "btxoHeader": btxo_hdr.hex(),
        "btxoFrame": btxo_frame.hex(),
    }


def main(argv):
    if "--check" in argv:
        print("riptide_reference: self-checks OK")
        return 0
    v = golden_vectors()
    print("# riptide golden vectors (master seed 0x42 * 32)")
    for k in sorted(v):
        print("%-12s %s" % (k, v[k]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
