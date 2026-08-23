#!/usr/bin/env python3
"""
nostr_reference.py - the independent oracle for NostrXT's pure-compute paths.

NostrXT itself adds NO cryptography (CLAUDE.md rule 1): SHA-256, BIP-340 Schnorr,
x-only keys and ECDH are CoinXT calls (cx*), randomness and constant-time compare
are SodiumXT calls (sx*). This file is a *reference implementation used only by
gates*, never shipped to an engine. It exists so that every constant the member
harness pins (event ids, signatures, bech32 entities, NIP-44 keys) is DERIVED by
an implementation that is independent of the livecodescript being tested, and so
that a broken transcription fails loudly at import instead of pinning a wrong
vector (the coinxt tools/coin_reference.py pattern).

What it implements, and what anchors each piece to ground truth:

  1. secp256k1 affine group math + BIP-340 Schnorr (tagged hashes, lift_x,
     sign, verify). Anchored at import to the published BIP-340 test vectors
     (transcribed subset here; tools/nostr-kat.py sweeps the FULL csv).
     source: https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
  2. NIP-01 canonical event serialization ([0,pubkey,created_at,kind,tags,content]
     with the exact seven-character escape set) and the sha256 event id.
     source: https://github.com/nostr-protocol/nips/blob/master/01.md
  3. bech32 / bech32m (BIP-173 / BIP-350) with NO 90-character cap, because
     NIP-19 explicitly waives it for TLV entities; anchored to the BIP-173
     vectors and the published NIP-19 examples.
     source: https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
     source: https://github.com/nostr-protocol/nips/blob/master/19.md
  4. NIP-44 v2: secp256k1 ECDH x-coordinate, HKDF-SHA256 extract/expand,
     the padding scheme, ChaCha20 (RFC 8439, counter 0), HMAC-SHA256 with
     AAD = nonce||ciphertext, standard base64. Anchored at import to two of
     the official vectors; tools/nostr-kat.py sweeps the FULL published set.
     source: https://github.com/paulmillr/nip44/blob/main/nip44.vectors.json
  5. RFC 6455 client pieces: the Sec-WebSocket-Accept derivation (SHA-1 over
     key + GUID, base64) and frame masking. The RFC text hosts are not
     reachable from this environment's egress proxy, so the GUID is anchored
     to the python-websockets reference implementation and the accept value
     is DERIVED, never quoted from memory.
     source: https://github.com/python-websockets/websockets/blob/main/src/websockets/utils.py

Pure standard library only (hashlib, hmac, base64), so it runs anywhere CI runs.
Import it; a failed anchor raises at import time.
"""

import base64
import hashlib
import hmac as hmac_mod

# --------------------------------------------------------------------- hashes


def sha256(b):
    return hashlib.sha256(b).digest()


def hmac_sha256(key, message):
    return hmac_mod.new(key, message, hashlib.sha256).digest()


def hkdf_extract(salt, ikm):
    return hmac_sha256(salt, ikm)


def hkdf_expand(prk, info, length):
    okm = b""
    t = b""
    counter = 1
    while len(okm) < length:
        t = hmac_sha256(prk, t + info + bytes([counter]))
        okm += t
        counter += 1
    return okm[:length]


# ----------------------------------------------------- secp256k1 and BIP-340
# Affine math with modular inverse via Fermat; slow and clear, which is what an
# oracle wants. Points are (x, y) tuples or None for infinity.

P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
G = (GX, GY)


def point_add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2 and (y1 + y2) % P == 0:
        return None
    if p1 == p2:
        lam = (3 * x1 * x1) * pow(2 * y1, P - 2, P) % P
    else:
        lam = (y2 - y1) * pow(x2 - x1, P - 2, P) % P
    x3 = (lam * lam - x1 - x2) % P
    return (x3, (lam * (x1 - x3) - y1) % P)


def point_mul(point, scalar):
    result = None
    addend = point
    while scalar:
        if scalar & 1:
            result = point_add(result, addend)
        addend = point_add(addend, addend)
        scalar >>= 1
    return result


def lift_x(x):
    """The even-y point with this x coordinate, or None if x is not on the curve."""
    if x >= P:
        return None
    y_sq = (pow(x, 3, P) + 7) % P
    y = pow(y_sq, (P + 1) // 4, P)
    if pow(y, 2, P) != y_sq:
        return None
    return (x, y if y % 2 == 0 else P - y)


def tagged_hash(tag, msg):
    tag_hash = sha256(tag.encode())
    return sha256(tag_hash + tag_hash + msg)


def int_from(b):
    return int.from_bytes(b, "big")


def bytes_from(i):
    return i.to_bytes(32, "big")


def pubkey_xonly(seckey):
    """BIP-340 x-only public key (the Nostr pubkey) for a 32-byte secret key."""
    d0 = int_from(seckey)
    if not (1 <= d0 <= N - 1):
        raise ValueError("secret key out of range")
    point = point_mul(G, d0)
    return bytes_from(point[0])


def schnorr_sign(msg32, seckey, aux32):
    """BIP-340 reference signing. msg32 is the 32-byte digest, aux32 the 32-byte
    auxiliary randomness (all-zero is a legal, deterministic choice)."""
    d0 = int_from(seckey)
    if not (1 <= d0 <= N - 1):
        raise ValueError("secret key out of range")
    point = point_mul(G, d0)
    d = d0 if point[1] % 2 == 0 else N - d0
    t = d ^ int_from(tagged_hash("BIP0340/aux", aux32))
    k0 = int_from(tagged_hash("BIP0340/nonce",
                              bytes_from(t) + bytes_from(point[0]) + msg32)) % N
    if k0 == 0:
        raise ValueError("nonce is zero")
    r_point = point_mul(G, k0)
    k = k0 if r_point[1] % 2 == 0 else N - k0
    e = int_from(tagged_hash("BIP0340/challenge",
                             bytes_from(r_point[0]) + bytes_from(point[0]) + msg32)) % N
    sig = bytes_from(r_point[0]) + bytes_from((k + e * d) % N)
    if not schnorr_verify(msg32, bytes_from(point[0]), sig):
        raise ValueError("created signature does not verify")
    return sig


def schnorr_verify(msg, pubkey32, sig64):
    """BIP-340 verification; any message length (the vectors carry several)."""
    if len(pubkey32) != 32 or len(sig64) != 64:
        return False
    pub_point = lift_x(int_from(pubkey32))
    r = int_from(sig64[0:32])
    s = int_from(sig64[32:64])
    if pub_point is None or r >= P or s >= N:
        return False
    e = int_from(tagged_hash("BIP0340/challenge",
                             sig64[0:32] + pubkey32 + msg)) % N
    r_point = point_add(point_mul(G, s), point_mul(pub_point, N - e))
    if r_point is None or r_point[1] % 2 != 0 or r_point[0] != r:
        return False
    return True


def ecdh_xonly(seckey, pubkey_x):
    """NIP-44's ECDH: multiply the (even-y lifted) point of the 32-byte x-only
    public key by the scalar, return the UNHASHED 32-byte x coordinate."""
    point = lift_x(int_from(pubkey_x))
    if point is None:
        raise ValueError("public key is not on the curve")
    d = int_from(seckey)
    if not (1 <= d <= N - 1):
        raise ValueError("secret key out of range")
    shared = point_mul(point, d)
    if shared is None:
        raise ValueError("shared point at infinity")
    return bytes_from(shared[0])


# ------------------------------------------------- NIP-01 canonical serialization
# The exact escape set NIP-01 mandates, and NOTHING else: other control bytes are
# included verbatim (json.dumps would \u-escape them, which is why this is
# hand-rolled rather than borrowed).

_ESCAPES = {
    0x0A: "\\n", 0x22: "\\\"", 0x5C: "\\\\",
    0x0D: "\\r", 0x09: "\\t", 0x08: "\\b", 0x0C: "\\f",
}


def json_escape(text):
    out = []
    for byte in text.encode("utf-8"):
        esc = _ESCAPES.get(byte)
        if esc is not None:
            out.append(esc.encode())
        else:
            out.append(bytes([byte]))
    return b"".join(out).decode("utf-8")


def serialize_event(pubkey_hex, created_at, kind, tags, content):
    """The canonical [0,pubkey,created_at,kind,tags,content] JSON string."""
    parts = ["[0,\"", pubkey_hex, "\",", str(int(created_at)), ",",
             str(int(kind)), ",["]
    tag_strs = []
    for tag in tags:
        tag_strs.append("[" + ",".join("\"" + json_escape(t) + "\"" for t in tag) + "]")
    parts.append(",".join(tag_strs))
    parts.append("],\"")
    parts.append(json_escape(content))
    parts.append("\"]")
    return "".join(parts)


def event_id(pubkey_hex, created_at, kind, tags, content):
    ser = serialize_event(pubkey_hex, created_at, kind, tags, content)
    return sha256(ser.encode("utf-8")).hex()


def sign_event(seckey_hex, created_at, kind, tags, content, aux_hex="00" * 32):
    """Build, id and sign a full event dict, deterministically for a given aux."""
    seckey = bytes.fromhex(seckey_hex)
    pubkey_hex = pubkey_xonly(seckey).hex()
    eid = event_id(pubkey_hex, created_at, kind, tags, content)
    sig = schnorr_sign(bytes.fromhex(eid), seckey, bytes.fromhex(aux_hex))
    return {
        "id": eid, "pubkey": pubkey_hex, "created_at": created_at,
        "kind": kind, "tags": tags, "content": content, "sig": sig.hex(),
    }


def verify_event(ev):
    eid = event_id(ev["pubkey"], ev["created_at"], ev["kind"], ev["tags"], ev["content"])
    if eid != ev["id"]:
        return False
    return schnorr_verify(bytes.fromhex(eid), bytes.fromhex(ev["pubkey"]),
                          bytes.fromhex(ev["sig"]))


# ------------------------------------------------------------ bech32 (BIP-173)

BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
BECH32M_CONST = 0x2BC830A3


def bech32_polymod(values):
    gen = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for value in values:
        top = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ value
        for i in range(5):
            chk ^= gen[i] if ((top >> i) & 1) else 0
    return chk


def bech32_hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def bech32_create_checksum(hrp, data, spec):
    const = BECH32M_CONST if spec == "bech32m" else 1
    values = bech32_hrp_expand(hrp) + data
    polymod = bech32_polymod(values + [0, 0, 0, 0, 0, 0]) ^ const
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]


def bech32_encode(hrp, data, spec="bech32"):
    """No 90-char cap: NIP-19 waives it for TLV entities (SHOULD stay under 5000)."""
    combined = data + bech32_create_checksum(hrp, data, spec)
    return hrp + "1" + "".join(BECH32_CHARSET[d] for d in combined)


def bech32_decode(text):
    """Returns (hrp, data, spec) or raises. Mixed case is refused per BIP-173."""
    if text.lower() != text and text.upper() != text:
        raise ValueError("mixed case")
    text = text.lower()
    pos = text.rfind("1")
    if pos < 1 or pos + 7 > len(text):
        raise ValueError("bad separator position")
    hrp = text[:pos]
    if any(not (33 <= ord(c) <= 126) for c in hrp):
        raise ValueError("bad hrp character")
    data = []
    for c in text[pos + 1:]:
        if c not in BECH32_CHARSET:
            raise ValueError("bad data character")
        data.append(BECH32_CHARSET.index(c))
    check = bech32_polymod(bech32_hrp_expand(hrp) + data)
    if check == 1:
        spec = "bech32"
    elif check == BECH32M_CONST:
        spec = "bech32m"
    else:
        raise ValueError("bad checksum")
    return hrp, data[:-6], spec


def convertbits(data, frombits, tobits, pad=True):
    acc = 0
    bits = 0
    ret = []
    maxv = (1 << tobits) - 1
    for value in data:
        if value < 0 or (value >> frombits):
            raise ValueError("value out of range")
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad:
        if bits:
            ret.append((acc << (tobits - bits)) & maxv)
    elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
        raise ValueError("bad padding")
    return ret


# --------------------------------------------------------------- NIP-19 layer


def nip19_encode(prefix, payload):
    return bech32_encode(prefix, convertbits(list(payload), 8, 5, True), "bech32")


def nip19_decode(text):
    hrp, data, spec = bech32_decode(text)
    if spec != "bech32":
        raise ValueError("NIP-19 entities are bech32, not bech32m")
    return hrp, bytes(convertbits(data, 5, 8, False))


def tlv_encode(items):
    """items: list of (type, value_bytes); every value must fit one length byte."""
    out = b""
    for t, v in items:
        if len(v) > 255:
            raise ValueError("TLV value too long")
        out += bytes([t, len(v)]) + v
    return out


def tlv_decode(payload):
    items = []
    i = 0
    while i < len(payload):
        if i + 2 > len(payload):
            raise ValueError("truncated TLV header")
        t = payload[i]
        length = payload[i + 1]
        if i + 2 + length > len(payload):
            raise ValueError("truncated TLV value")
        items.append((t, payload[i + 2:i + 2 + length]))
        i += 2 + length
    return items


def nprofile_encode(pubkey_hex, relays):
    items = [(0, bytes.fromhex(pubkey_hex))]
    for r in relays:
        items.append((1, r.encode("ascii")))
    return nip19_encode("nprofile", tlv_encode(items))


def nevent_encode(id_hex, relays, author_hex="", kind=None):
    items = [(0, bytes.fromhex(id_hex))]
    for r in relays:
        items.append((1, r.encode("ascii")))
    if author_hex:
        items.append((2, bytes.fromhex(author_hex)))
    if kind is not None:
        items.append((3, int(kind).to_bytes(4, "big")))
    return nip19_encode("nevent", tlv_encode(items))


def naddr_encode(identifier, pubkey_hex, kind, relays):
    items = [(0, identifier.encode("utf-8"))]
    for r in relays:
        items.append((1, r.encode("ascii")))
    items.append((2, bytes.fromhex(pubkey_hex)))
    items.append((3, int(kind).to_bytes(4, "big")))
    return nip19_encode("naddr", tlv_encode(items))


# ---------------------------------------------------------------- NIP-44 v2


def nip44_conversation_key(seckey, pubkey_x):
    shared_x = ecdh_xonly(seckey, pubkey_x)
    return hkdf_extract(b"nip44-v2", shared_x)


def nip44_message_keys(conv_key, nonce):
    if len(conv_key) != 32 or len(nonce) != 32:
        raise ValueError("conversation key and nonce must be 32 bytes")
    okm = hkdf_expand(conv_key, nonce, 76)
    return okm[0:32], okm[32:44], okm[44:76]


def nip44_calc_padded_len(unpadded_len):
    if unpadded_len < 1:
        raise ValueError("invalid plaintext length")
    if unpadded_len <= 32:
        return 32
    next_power = 1 << ((unpadded_len - 1).bit_length())
    chunk = 32 if next_power <= 256 else next_power // 8
    return chunk * ((unpadded_len - 1) // chunk + 1)


def nip44_pad(plaintext):
    # The u16-prefix path only: the published vectors mark 65536+ as invalid
    # (the newer spec text sketches a 6-byte extended prefix, but no vector
    # set pins it yet), so NostrXT refuses rather than guessing - fail closed.
    unpadded = plaintext.encode("utf-8")
    ulen = len(unpadded)
    if ulen < 1 or ulen > 65535:
        raise ValueError("invalid plaintext length")
    prefix = ulen.to_bytes(2, "big")
    return prefix + unpadded + bytes(nip44_calc_padded_len(ulen) - ulen)


def nip44_unpad(padded):
    ulen = int.from_bytes(padded[0:2], "big")
    unpadded = padded[2:2 + ulen]
    if (ulen == 0 or len(unpadded) != ulen or
            len(padded) != 2 + nip44_calc_padded_len(ulen)):
        raise ValueError("invalid padding")
    return unpadded.decode("utf-8")


def _chacha_quarter(state, a, b, c, d):
    state[a] = (state[a] + state[b]) & 0xFFFFFFFF
    state[d] = state[d] ^ state[a]
    state[d] = ((state[d] << 16) | (state[d] >> 16)) & 0xFFFFFFFF
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF
    state[b] = state[b] ^ state[c]
    state[b] = ((state[b] << 12) | (state[b] >> 20)) & 0xFFFFFFFF
    state[a] = (state[a] + state[b]) & 0xFFFFFFFF
    state[d] = state[d] ^ state[a]
    state[d] = ((state[d] << 8) | (state[d] >> 24)) & 0xFFFFFFFF
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF
    state[b] = state[b] ^ state[c]
    state[b] = ((state[b] << 7) | (state[b] >> 25)) & 0xFFFFFFFF


def _chacha_block(key, counter, nonce):
    constants = (0x61707865, 0x3320646E, 0x79622D32, 0x6B206574)
    state = list(constants)
    state += [int.from_bytes(key[i:i + 4], "little") for i in range(0, 32, 4)]
    state.append(counter & 0xFFFFFFFF)
    state += [int.from_bytes(nonce[i:i + 4], "little") for i in range(0, 12, 4)]
    working = list(state)
    for _ in range(10):
        _chacha_quarter(working, 0, 4, 8, 12)
        _chacha_quarter(working, 1, 5, 9, 13)
        _chacha_quarter(working, 2, 6, 10, 14)
        _chacha_quarter(working, 3, 7, 11, 15)
        _chacha_quarter(working, 0, 5, 10, 15)
        _chacha_quarter(working, 1, 6, 11, 12)
        _chacha_quarter(working, 2, 7, 8, 13)
        _chacha_quarter(working, 3, 4, 9, 14)
    out = b""
    for i in range(16):
        out += ((working[i] + state[i]) & 0xFFFFFFFF).to_bytes(4, "little")
    return out


def chacha20(key, nonce, data):
    """RFC 8439 ChaCha20 stream, starting counter 0 (the NIP-44 configuration)."""
    out = bytearray()
    counter = 0
    for i in range(0, len(data), 64):
        keystream = _chacha_block(key, counter, nonce)
        chunk = data[i:i + 64]
        out += bytes(a ^ b for a, b in zip(chunk, keystream))
        counter += 1
    return bytes(out)


def nip44_encrypt_with_nonce(conv_key, nonce, plaintext):
    chacha_key, chacha_nonce, hmac_key = nip44_message_keys(conv_key, nonce)
    padded = nip44_pad(plaintext)
    ciphertext = chacha20(chacha_key, chacha_nonce, padded)
    mac = hmac_sha256(hmac_key, nonce + ciphertext)
    return base64.b64encode(b"\x02" + nonce + ciphertext + mac).decode("ascii")


def nip44_decrypt(conv_key, payload):
    if len(payload) == 0 or payload[0] == "#":
        raise ValueError("unknown encryption version")
    if len(payload) < 132:
        raise ValueError("invalid payload size")
    data = base64.b64decode(payload, validate=True)
    if len(data) < 99:
        raise ValueError("invalid data size")
    if data[0] != 2:
        raise ValueError("unknown encryption version")
    nonce = data[1:33]
    ciphertext = data[33:-32]
    mac = data[-32:]
    chacha_key, chacha_nonce, hmac_key = nip44_message_keys(conv_key, nonce)
    expected = hmac_sha256(hmac_key, nonce + ciphertext)
    if not hmac_mod.compare_digest(expected, mac):
        raise ValueError("invalid MAC")
    return nip44_unpad(chacha20(chacha_key, chacha_nonce, ciphertext))


# ----------------------------------------------------------- RFC 6455 pieces

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def ws_accept(key_b64):
    return base64.b64encode(hashlib.sha1((key_b64 + WS_GUID).encode()).digest()).decode()


def ws_mask(payload, mask4):
    return bytes(b ^ mask4[i % 4] for i, b in enumerate(payload))


def ws_frame_client(opcode, payload, mask4):
    """A client frame: FIN set, masked, no fragmentation (what NostrXT sends)."""
    head = bytes([0x80 | (opcode & 0x0F)])
    plen = len(payload)
    if plen < 126:
        head += bytes([0x80 | plen])
    elif plen < 65536:
        head += bytes([0x80 | 126]) + plen.to_bytes(2, "big")
    else:
        head += bytes([0x80 | 127]) + plen.to_bytes(8, "big")
    return head + mask4 + ws_mask(payload, mask4)


# -------------------------------------------------------- import-time anchors
# A compact set of published anchors; tools/nostr-kat.py runs the FULL sweeps.

# BIP-340 test-vectors.csv rows 0 and 5 (the first signing row and the first
# "public key not on the curve" refusal), transcribed verbatim.
# source: https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
_B340_SEC0 = "0000000000000000000000000000000000000000000000000000000000000003"
_B340_PUB0 = "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9"
_B340_AUX0 = "0000000000000000000000000000000000000000000000000000000000000000"
_B340_MSG0 = "0000000000000000000000000000000000000000000000000000000000000000"
_B340_SIG0 = ("E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA8215"
              "25F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0")
_B340_PUB5 = "EEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34"

# NIP-19 published examples.
# source: https://github.com/nostr-protocol/nips/blob/master/19.md
_N19_PUB_HEX = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
_N19_NPUB = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"
_N19_SEC_HEX = "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa"
_N19_NSEC = "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5"
_N19_NPROFILE = ("nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8g"
                 "pp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p")
_N19_RELAYS = ["wss://r.x.com", "wss://djbas.sadkb.com"]

# Two of the official NIP-44 v2 vectors (get_conversation_key sec1=0x01 row, and
# the first encrypt_decrypt row), transcribed verbatim.
# source: https://github.com/paulmillr/nip44/blob/main/nip44.vectors.json
_N44_SEC1 = "0000000000000000000000000000000000000000000000000000000000000001"
_N44_SEC2 = "0000000000000000000000000000000000000000000000000000000000000002"
_N44_CONV = "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d"
_N44_ED_NONCE = "0000000000000000000000000000000000000000000000000000000000000001"
_N44_ED_PLAINTEXT = "a"
_N44_ED_PAYLOAD = ("AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYE"
                   "AjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb")

# BIP-173 anchors: two valid strings and one invalid-checksum string.
# source: https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
_B173_VALID = ["A12UEL5L",
               "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs"]
_B173_INVALID = ["A1G7SGD8"]


def _self_check():
    failures = []
    # BIP-340: sign row 0 and refuse the off-curve key of row 5.
    sig = schnorr_sign(bytes.fromhex(_B340_MSG0), bytes.fromhex(_B340_SEC0),
                       bytes.fromhex(_B340_AUX0))
    if sig.hex().upper() != _B340_SIG0:
        failures.append("BIP-340 vector 0 signature mismatch")
    if pubkey_xonly(bytes.fromhex(_B340_SEC0)).hex().upper() != _B340_PUB0:
        failures.append("BIP-340 vector 0 pubkey mismatch")
    if schnorr_verify(bytes.fromhex(_B340_MSG0), bytes.fromhex(_B340_PUB5), sig):
        failures.append("BIP-340 off-curve pubkey accepted")
    # NIP-19 published examples round-trip.
    if nip19_encode("npub", bytes.fromhex(_N19_PUB_HEX)) != _N19_NPUB:
        failures.append("NIP-19 npub example mismatch")
    if nip19_encode("nsec", bytes.fromhex(_N19_SEC_HEX)) != _N19_NSEC:
        failures.append("NIP-19 nsec example mismatch")
    hrp, payload = nip19_decode(_N19_NPROFILE)
    tlv = tlv_decode(payload)
    if (hrp != "nprofile" or tlv[0][1].hex() != _N19_PUB_HEX or
            [v.decode() for t, v in tlv if t == 1] != _N19_RELAYS):
        failures.append("NIP-19 nprofile example mismatch")
    if nprofile_encode(_N19_PUB_HEX, _N19_RELAYS) != _N19_NPROFILE:
        failures.append("NIP-19 nprofile re-encode mismatch")
    # NIP-44 anchors: conversation key and one full encrypt/decrypt.
    conv = nip44_conversation_key(bytes.fromhex(_N44_SEC1),
                                  pubkey_xonly(bytes.fromhex(_N44_SEC2)))
    if conv.hex() != _N44_CONV:
        failures.append("NIP-44 conversation key anchor mismatch")
    payload = nip44_encrypt_with_nonce(bytes.fromhex(_N44_CONV),
                                       bytes.fromhex(_N44_ED_NONCE), _N44_ED_PLAINTEXT)
    if payload != _N44_ED_PAYLOAD:
        failures.append("NIP-44 encrypt anchor mismatch")
    if nip44_decrypt(bytes.fromhex(_N44_CONV), _N44_ED_PAYLOAD) != _N44_ED_PLAINTEXT:
        failures.append("NIP-44 decrypt anchor mismatch")
    # BIP-173 anchors.
    for text in _B173_VALID:
        try:
            bech32_decode(text)
        except ValueError:
            failures.append("BIP-173 valid string refused: " + text)
    for text in _B173_INVALID:
        try:
            bech32_decode(text)
            failures.append("BIP-173 invalid string accepted: " + text)
        except ValueError:
            pass
    # RFC 6455: accept derivation is internally consistent with sha1+base64 over
    # the GUID (anchored to the python-websockets reference; see header).
    if len(base64.b64decode(ws_accept("dGhlIHNhbXBsZSBub25jZQ=="))) != 20:
        failures.append("ws_accept does not produce a 20-byte SHA-1 digest")
    if ws_mask(ws_mask(b"Hello", b"\x37\xfa\x21\x3d"), b"\x37\xfa\x21\x3d") != b"Hello":
        failures.append("ws_mask is not an involution")
    return failures


_FAILURES = _self_check()
if _FAILURES:
    raise ImportError("nostr_reference self-check failed: " + "; ".join(_FAILURES))
