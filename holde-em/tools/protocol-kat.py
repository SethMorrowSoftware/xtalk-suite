#!/usr/bin/env python3
"""Protocol known-answer vectors: envelope bytes, hash chain, Level 0 deal,
the spec 7.3 Level 2 algebra, the 4d void-and-audit machine with its 12.4
cheater-bot scenarios, and the spec 7.4 Chaum-Pedersen DLEQ proofs.

This is the headless CI pin for everything in spec sections 6 and 7.1 that is
a plain algorithm: canonical envelope serialization, the transcript hash
chain, seed commitments, the keyed-stream Fisher-Yates shuffle, and the deal
assignment order. The xTalk implementation in ``src/holdem.livecodescript``
must reproduce every value below on-engine; the self-test harness carries the
same pinned constants (``--gen-xtalk`` regenerates its block).

Primitive equivalences this file leans on (each one is an assumption the OXT
pass must confirm once, then the KATs hold both sides together):

  * ``sxHash`` == libsodium ``crypto_generichash`` == BLAKE2b, 32-byte digest,
    unkeyed == Python ``hashlib.blake2b(digest_size=32)``. Confirmed against
    libsodium (PyNaCl) when this file was authored.
  * ``sxSignDetached`` / ``sxSignKeypairFromSeed`` == libsodium ed25519. The
    embedded pure-Python ed25519 below is validated on every run against
    vectors generated from libsodium itself (the ED25519_TV table), so a bug
    in the embedded code cannot silently re-pin the envelopes.

Canonical envelope (the code-wins refinement of spec section 6 -- a sender
cannot sign ``seq``/``prev`` it does not know under a relay that assigns
ordering, so signatures are layered):

  contentLine = v TAB tableHex TAB hand TAB fromHex TAB type TAB bodyHex
  senderSig   = ed25519 over utf8(contentLine), by the sender key
  envLine     = contentLine TAB senderSigHex TAB seq TAB prevHex
  hostSig     = ed25519 over utf8(envLine), by the host relay key
  wire        = envLine TAB hostSigHex
  chainHead   = H("HOLDEM-CHAIN-v1|" || utf8(wire));  genesis prev = 32 zero bytes

All binary fields travel as lowercase hex; bodies are hex of their UTF-8 text
(no tabs can ever leak into the frame). One wire line = one rp1 payload.

Shuffle (spec 7.1, pinned exactly):

  seedsXor  = XOR of every seated player's 32-byte seed
  streamKey = H("HOLDEM-SHUF-v1|" || table(32B) || "|" || decimal(hand) || "|" || seedsXor)
  block_j   = H(streamKey || uint32be(j))    j = 0,1,2,...  stream = block_0 || block_1 ...
  draw(n)   : take 4 stream bytes big-endian as w; reject while w >= floor(2^32/n)*n;
              value = (w mod n) + 1          (rejection sampling: no modulo bias)
  shuffle   : deck[1..52] = 1..52; for i = 52 down to 2: j = draw(i); swap deck[i], deck[j]
  deck[1] is the top of the deck, dealt first.

Deal order: one card per occupied seat starting left of the button, two
rounds, then burn, flop x3, burn, turn, burn, river.

Usage::

    python3 tools/protocol-kat.py                # verify against pinned values
    python3 tools/protocol-kat.py --print-pinned # regenerate the PINNED block
    python3 tools/protocol-kat.py --gen-xtalk    # print the harness constants

Exit status is non-zero on any failure (CI gate).
"""

import hashlib
import os
import re
import sys

# --------------------------------------------------------------------------
# BLAKE2b-256 (the sxHash equivalence)
# --------------------------------------------------------------------------

def H(data):
    return hashlib.blake2b(data, digest_size=32).digest()


# --------------------------------------------------------------------------
# Embedded ed25519 (reference-style, sign only). Validated against libsodium
# vectors below on every run -- slow is fine, wrong is not.
# --------------------------------------------------------------------------

Q = 2 ** 255 - 19
L = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, Q - 2, Q) % Q
I = pow(2, (Q - 1) // 4, Q)


def _xrecover(y):
    xx = (y * y - 1) * pow(D * y * y + 1, Q - 2, Q)
    x = pow(xx, (Q + 3) // 8, Q)
    if (x * x - xx) % Q != 0:
        x = x * I % Q
    if x % 2 != 0:
        x = Q - x
    return x


_BY = 4 * pow(5, Q - 2, Q) % Q
_B = (_xrecover(_BY), _BY)


def _edw_add(p, q):
    x1, y1 = p
    x2, y2 = q
    t = D * x1 * x2 * y1 * y2
    x3 = (x1 * y2 + x2 * y1) * pow(1 + t, Q - 2, Q)
    y3 = (y1 * y2 + x1 * x2) * pow(1 - t, Q - 2, Q)
    return (x3 % Q, y3 % Q)


def _scalarmult(p, e):
    q = (0, 1)
    while e:
        if e & 1:
            q = _edw_add(q, p)
        p = _edw_add(p, p)
        e >>= 1
    return q


def _encodepoint(p):
    x, y = p
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _clamp(h32):
    a = int.from_bytes(h32, "little")
    a &= (1 << 254) - 8
    a |= 1 << 254
    return a


def ed_publickey(seed):
    a = _clamp(hashlib.sha512(seed).digest()[:32])
    return _encodepoint(_scalarmult(_B, a))


def ed_sign(msg, seed):
    h = hashlib.sha512(seed).digest()
    a = _clamp(h[:32])
    pub = _encodepoint(_scalarmult(_B, a))
    r = int.from_bytes(hashlib.sha512(h[32:] + msg).digest(), "little") % L
    renc = _encodepoint(_scalarmult(_B, r))
    k = int.from_bytes(hashlib.sha512(renc + pub + msg).digest(), "little") % L
    s = (r + k * a) % L
    return renc + s.to_bytes(32, "little")


# Vectors generated directly from libsodium (PyNaCl 1.6 / libsodium 1.0.x):
# (seed hex, message bytes hex, expected pub hex, expected sig hex). If the
# embedded ed25519 drifts from libsodium, everything below is untrustworthy,
# so these are checked first and hard-fail.
ED25519_TV = [
    ("00" * 32, "",
     "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29",
     "8f895b3cafe2c9506039d0e2a66382568004674fe8d237785092e40d6aaf483e"
     "4fc60168705f31f101596138ce21aa357c0d32a064f423dc3ee4aa3abf53f803"),
    ("01" * 32, "686f6c64656d",
     "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
     "715c322967dc4e79752372ca6313ddc9e7d4e32102cf8a2214c53060c2014e85"
     "58e547ec06a535a846fa60c25027740a09e5d1b2f95ce43fba5bc87be72aef0e"),
    ("9d2f5a0b" + "ab" * 28, "484f4c44454d2d454e562d76317c7465737420766563746f72",
     "9621b01475933793f4c36a7c180df55dbb9ccd0d14451f954faa02043015b81d",
     "b4d6689994684ebbf0112e031853a33493518c79d2283eba390c6d634d2fa6bc"
     "d732c85d9e2c9d1e7f2f3159f544d8f413c5fe0901230d38f07f710e9c1af207"),
]


def check_ed25519():
    for seed_hex, msg_hex, pub_hex, sig_hex in ED25519_TV:
        seed = bytes.fromhex(seed_hex)
        msg = bytes.fromhex(msg_hex)
        if ed_publickey(seed).hex() != pub_hex:
            raise AssertionError("embedded ed25519 pubkey drifts from libsodium")
        if ed_sign(msg, seed).hex() != sig_hex:
            raise AssertionError("embedded ed25519 signature drifts from libsodium")


# --------------------------------------------------------------------------
# Cards (same contract as tools/evaluator-kat.py: index 1..52)
# --------------------------------------------------------------------------

RANKS = "23456789TJQKA"
SUITS = "cdhs"


def card_name(i):
    return RANKS[(i - 1) // 4] + SUITS[(i - 1) % 4]


# --------------------------------------------------------------------------
# Keyed-stream shuffle (spec 7.1)
# --------------------------------------------------------------------------

def seed_commit(seed):
    return H(b"HOLDEM-SEEDC-v1|" + seed)


def xor_seeds(seeds):
    out = bytearray(32)
    for s in seeds:
        for i in range(32):
            out[i] ^= s[i]
    return bytes(out)


def stream_key(table, hand, seeds_xor):
    return H(b"HOLDEM-SHUF-v1|" + table + b"|" + str(hand).encode() + b"|" + seeds_xor)


def stream_bytes(key, nblocks):
    return b"".join(H(key + j.to_bytes(4, "big")) for j in range(nblocks))


def draw_uniform(stream, offset, n):
    """Uniform in 1..n by 4-byte big-endian words with rejection sampling."""
    limit = (2 ** 32 // n) * n
    while True:
        if offset + 4 > len(stream):
            raise ValueError("stream exhausted")
        w = int.from_bytes(stream[offset:offset + 4], "big")
        offset += 4
        if w < limit:
            return (w % n) + 1, offset


def shuffle_from_stream(stream):
    """Fisher-Yates over deck[1..52] fed by the stream; deck[0] is the top."""
    deck = list(range(1, 53))
    offset = 0
    for i in range(52, 1, -1):
        j, offset = draw_uniform(stream, offset, i)
        deck[i - 1], deck[j - 1] = deck[j - 1], deck[i - 1]
    return deck


def deal_order(occupied, button):
    """Occupied seats clockwise starting left of the button."""
    idx = occupied.index(button)
    return occupied[idx + 1:] + occupied[:idx + 1]


def assign_deal(deck, occupied, button):
    """Two hole rounds, then burn/flop/burn/turn/burn/river, from the top."""
    order = deal_order(occupied, button)
    pos = 0
    holes = {s: [] for s in occupied}
    for _ in range(2):
        for s in order:
            holes[s].append(deck[pos])
            pos += 1
    burns = [deck[pos]]
    pos += 1
    flop = deck[pos:pos + 3]
    pos += 3
    burns.append(deck[pos])
    pos += 1
    turn = deck[pos]
    pos += 1
    burns.append(deck[pos])
    pos += 1
    river = deck[pos]
    return holes, flop, turn, river, burns


# Deal-order breadth: over the IDENTITY deck (1..52), the card->seat mapping is
# just the deal positions, so these signatures pin the wrap-around logic for
# button-not-first, non-contiguous seats, and heads-up -- configs the main deal
# KAT (occ 1,2,3 button 1) never exercises. The xTalk heDealAssign must
# reproduce each on-engine (heTestDealOrderRun).
IDENT_DECK = list(range(1, 53))
DEAL_ORDER_CFGS = ["1,2,3|3", "2,4,6|4", "1,2|1", "3,5|5", "1,2,3,4,5,6|4"]


def deal_signature(deck, occ_txt, button):
    occ = [int(x) for x in occ_txt.split(",")]
    holes, flop, turn, river, _ = assign_deal(deck, occ, int(button))
    sig = ";".join("%d=%d-%d" % (s, holes[s][0], holes[s][1]) for s in occ)
    return sig + " flop=%d-%d-%d turn=%d river=%d" % (flop[0], flop[1], flop[2], turn, river)


# --------------------------------------------------------------------------
# Canonical envelope + chain (spec 6, layered signatures)
# --------------------------------------------------------------------------

GENESIS = bytes(32)

# Every wire type make_wire builds during compute_all, recorded so the A6
# coverage assertion in main() can hold "each source vocabulary type has at
# least one pinned wire" against what actually ran, not against a hand-kept
# list (the coinxt constant-gate lesson: report what was CHECKED).
WIRE_TYPES_BUILT = set()


def content_line(v, table, hand, from_pub, mtype, body_text):
    return "\t".join([str(v), table.hex(), str(hand), from_pub.hex(), mtype,
                      body_text.encode("utf-8").hex()])


def make_wire(v, table, hand, sender_seed, mtype, body_text, seq, prev, host_seed):
    WIRE_TYPES_BUILT.add(mtype)
    content = content_line(v, table, hand, ed_publickey(sender_seed), mtype, body_text)
    sender_sig = ed_sign(content.encode("utf-8"), sender_seed).hex()
    env_line = content + "\t" + sender_sig + "\t" + str(seq) + "\t" + prev.hex()
    host_sig = ed_sign(env_line.encode("utf-8"), host_seed).hex()
    return env_line + "\t" + host_sig


def source_wire_vocabulary():
    """The online wire-type vocabulary, parsed OUT OF THE SOURCE (backlog
    A6's prescription): every quoted type that heNetApplyWire compares
    tTypeTxt against - the roster/cfg pair it folds itself plus the game
    vocabulary it routes to heNetFoldGameWire. Parsed from the dispatcher's
    CODE rather than kept as a list here, so a NEW type cannot arrive
    unpinned: the moment the dispatcher learns it, this list grows and
    main() fails unless a wire of that type was built (and therefore
    pinned) by compute_all. The floor guards the parse itself: a regex that
    stops matching must FAIL, not pass vacuously (the coinxt constant-gate
    lesson)."""
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "src", "holdem.livecodescript")
    text = open(src, encoding="utf-8").read()
    m = re.search(r'^command heNetApplyWire\b(.*?)^end heNetApplyWire\b',
                  text, re.S | re.M)
    if not m:
        raise AssertionError(
            "heNetApplyWire not found in src/holdem.livecodescript - the "
            "wire-vocabulary parse is measuring nothing")
    types = sorted(set(re.findall(r'tTypeTxt is "([A-Za-z0-9]+)"', m.group(1))))
    if len(types) < 22:
        raise AssertionError(
            "wire-vocabulary parse found only %d types (expected >= 22: the "
            "20-type game vocabulary plus roster and cfg) - the dispatcher's "
            "shape changed and this parse no longer sees it" % len(types))
    return types


def chain_next(wire):
    return H(b"HOLDEM-CHAIN-v1|" + wire.encode("utf-8"))


def settle_hash(deltas_csv, chain_head):
    return H(b"HOLDEM-SETL-v1|" + deltas_csv.encode("utf-8") + b"|" + chain_head)


# --------------------------------------------------------------------------
# Host-trust hardening (spec 6 checkpoints + 8.3 settlement receipts). A ckpt
# is a player's signature over the current chain head at a street boundary --
# if two players' ckpts reference different heads, the host forked (attributable
# equivocation). A settlement receipt is every seated player's signature over a
# receipt head that hash-chains hand to hand, so the ledger is multi-signed and
# no subset can rewrite it. Domains are separated and versioned (spec 16).
# --------------------------------------------------------------------------

GENESIS_RCPT = "00" * 32          # empty predecessor for the receipt chain


def ckpt_sig(chain_head_hex, id_seed):
    return ed_sign(("HOLDEM-CKPT-v1|" + chain_head_hex).encode("utf-8"), id_seed).hex()


def receipt_head(settle_hash_hex, prev_rcpt_hex):
    return H(b"HOLDEM-RCPT-v1|" + (settle_hash_hex + "|" + prev_rcpt_hex).encode("utf-8")).hex()


def receipt_sig(rcpt_head_hex, id_seed):
    return ed_sign(("HOLDEM-RSIG-v1|" + rcpt_head_hex).encode("utf-8"), id_seed).hex()


def admit_token(table_hex, id_seed, role="host"):
    """Signed table-admission claim (spec 5): sign over
    "HOLDEM-SESS-v1|<tableHex>|<pubHex>|<role>", framed as pubHex TAB role TAB
    sigHex. Sent in btRp1SetToken so peers can drop strangers at handshake
    before any game message, and so a joining player adopts only a
    self-declared host (role="host"). Returns (token_line, sig_hex)."""
    pub_hex = ed_publickey(id_seed).hex()
    msg = ("HOLDEM-SESS-v1|" + table_hex + "|" + pub_hex + "|" + role).encode("utf-8")
    sig_hex = ed_sign(msg, id_seed).hex()
    return pub_hex + "\t" + role + "\t" + sig_hex, sig_hex


def roster_body(members):
    """Canonical lobby-presence body (spec 9): each member rendered as
    "pubHex:role", sorted ascending, joined by comma. The host re-signs and
    broadcasts it whenever the peer set changes; every client sorts the same
    way so the signed bytes are identical everywhere. The body is hex-encoded
    into the envelope like any other, so its commas never reach the wire frame.
    members: list of (pub_hex, role)."""
    return ",".join(sorted(p + ":" + r for p, r in members))


# --------------------------------------------------------------------------
# Fixtures: everything derived deterministically from tagged strings, so the
# whole KAT is reproducible from this file alone.
# --------------------------------------------------------------------------

TABLE = H(b"HOLDEM-KAT-v1|table")
HAND = 1
OCCUPIED = [1, 2, 3]
BUTTON = 1
DEAL_SEEDS = [H(b"HOLDEM-KAT-v1|seed|" + bytes([i])) for i in (1, 2, 3)]
ID_SEEDS = [H(b"HOLDEM-KAT-v1|identity|" + bytes([i])) for i in (1, 2, 3)]
HOST_SEED = ID_SEEDS[0]

# A fixed synthetic stream so the draw + Fisher-Yates core is testable on
# engines with no SodiumXT installed (pure byte-feeding, no hash needed).
SYNTH_STREAM = stream_bytes(H(b"HOLDEM-KAT-v1|synthetic-stream"), 16)


# --------------------------------------------------------------------------
# ristretto255, independently: RFC 9496's formulas written out - field
# arithmetic mod 2^255-19, the sqrt-ratio helper, the Elligator one-way map,
# extended Edwards point arithmetic, canonical encode/decode. This is the
# Phase 4 group (SodiumXT's sxRistretto* surface, Workstream U) implemented a
# SECOND way, the same discipline logic-fuzz.py applies to the evaluator: the
# pinned vectors were generated from libsodium and this reference re-derives
# them, so neither implementation can silently mis-pin the other. One honest
# calibration, documented where it happens: the Elligator map's global sign
# convention (a single +/- in w0) was set by comparing against libsodium once
# - every OTHER property here (curve law, canonicity, scalar field) agreed
# with no calibration at all, and ~255 independent bits per point still
# check.
# --------------------------------------------------------------------------

R255_P = 2 ** 255 - 19
R255_L = 2 ** 252 + 27742317777372353535851937790883648493
R255_D = (-121665 * pow(121666, R255_P - 2, R255_P)) % R255_P
R255_SQRT_M1 = pow(2, (R255_P - 1) // 4, R255_P)


def _r255_abs(x):
    return (-x) % R255_P if x & 1 else x % R255_P


def _r255_sqrt_ratio(u, v):
    p = R255_P
    v3 = (v * v % p) * v % p
    v7 = (v3 * v3 % p) * v % p
    r = (u * v3 % p) * pow(u * v7 % p, (p - 5) // 8, p) % p
    check = v * r % p * r % p
    correct = check == u % p
    flipped = check == (-u) % p
    flipped_i = check == (-u) % p * R255_SQRT_M1 % p
    if flipped or flipped_i:
        r = r * R255_SQRT_M1 % p
    return (correct or flipped), _r255_abs(r)


R255_ONE_MINUS_D_SQ = (1 - R255_D * R255_D) % R255_P
R255_D_MINUS_ONE_SQ = ((R255_D - 1) * (R255_D - 1)) % R255_P
_r255_ok, R255_INVSQRT_A_MINUS_D = _r255_sqrt_ratio(1, (-1 - R255_D) % R255_P)
assert _r255_ok
_r255_ok, R255_SQRT_AD_MINUS_ONE = _r255_sqrt_ratio((-R255_D - 1) % R255_P, 1)
assert _r255_ok


def _r255_add(a, b):
    p = R255_P
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    aa = (y1 - x1) * (y2 - x2) % p
    bb = (y1 + x1) * (y2 + x2) % p
    cc = 2 * R255_D * t1 % p * t2 % p
    dd = 2 * z1 * z2 % p
    e, f, g, h = (bb - aa) % p, (dd - cc) % p, (dd + cc) % p, (bb + aa) % p
    return (e * f % p, g * h % p, f * g % p, e * h % p)


def _r255_mul(k, pt):
    acc = (0, 1, 1, 0)
    while k:
        if k & 1:
            acc = _r255_add(acc, pt)
        pt = _r255_add(pt, pt)
        k >>= 1
    return acc


def r255_decode(b):
    p = R255_P
    if len(b) != 32:
        return None
    s = int.from_bytes(b, "little")
    if s >= p or s & 1:
        return None
    ss = s * s % p
    u1 = (1 - ss) % p
    u2 = (1 + ss) % p
    u2s = u2 * u2 % p
    v = (-(R255_D * u1 % p * u1) - u2s) % p
    was_sq, invsqrt = _r255_sqrt_ratio(1, v * u2s % p)
    den_x = invsqrt * u2 % p
    den_y = invsqrt * den_x % p * v % p
    x = _r255_abs(2 * s % p * den_x % p)
    y = u1 * den_y % p
    t = x * y % p
    if (not was_sq) or (t & 1) or y == 0:
        return None
    return (x, y, 1, t)


def r255_encode(pt):
    p = R255_P
    x, y, z, t = pt
    u1 = (z + y) * (z - y) % p
    u2 = x * y % p
    _, invsqrt = _r255_sqrt_ratio(1, u1 * u2 % p * u2 % p)
    den1 = invsqrt * u1 % p
    den2 = invsqrt * u2 % p
    z_inv = den1 * den2 % p * t % p
    if (t * z_inv % p) & 1:
        x, y = y * R255_SQRT_M1 % p, x * R255_SQRT_M1 % p
        den_inv = den1 * R255_INVSQRT_A_MINUS_D % p
    else:
        den_inv = den2
    if (x * z_inv % p) & 1:
        y = (-y) % p
    return _r255_abs(den_inv * ((z - y) % p) % p).to_bytes(32, "little")


def _r255_map(t):
    p = R255_P
    r = R255_SQRT_M1 * t % p * t % p
    u = (r + 1) % p * R255_ONE_MINUS_D_SQ % p
    v = (-1 - r * R255_D) % p * ((r + R255_D) % p) % p
    was_sq, s = _r255_sqrt_ratio(u, v)
    if not was_sq:
        s = _r255_abs(s * t % p) * (-1) % p
        c = r
    else:
        c = (-1) % p
    n = (c * ((r - 1) % p) % p * R255_D_MINUS_ONE_SQ - v) % p
    w0 = (-2) * s % p * v % p  # the one calibrated sign (see the block comment)
    w1 = n * R255_SQRT_AD_MINUS_ONE % p
    w2 = (1 - s * s) % p
    w3 = (1 + s * s) % p
    return (w0 * w3 % p, w2 * w1 % p, w1 * w3 % p, w0 * w2 % p)


def r255_from_hash(h64):
    a = int.from_bytes(h64[:32], "little") & ((1 << 255) - 1)
    b = int.from_bytes(h64[32:], "little") & ((1 << 255) - 1)
    return _r255_add(_r255_map(a % R255_P), _r255_map(b % R255_P))


def r255_scalarmult(k_bytes, p_bytes):
    pt = r255_decode(p_bytes)
    if pt is None:
        return None
    k = int.from_bytes(k_bytes, "little") % R255_L
    if k == 0:
        return None
    return r255_encode(_r255_mul(k, pt))


# the RFC 9496 basepoint, re-derived (y = 4/5, x the non-negative root)
_r255_by = 4 * pow(5, R255_P - 2, R255_P) % R255_P
_r255_ok, _r255_bx = _r255_sqrt_ratio((_r255_by * _r255_by - 1) % R255_P,
                                      (1 + R255_D * _r255_by * _r255_by) % R255_P)
assert _r255_ok
R255_BASE = (_r255_bx, _r255_by, 1, _r255_bx * _r255_by % R255_P)


# -- the ABI 9 follow-on operations (SodiumXT's DLEQ/batch surface, shipped
# 2026-08-15): point add/sub, base-point multiplication, scalar arithmetic
# mod L - the same pure Edwards machinery as above, no new calibration.
# Negation on the extended coordinates is (-x, y, z, -t); everything else
# composes the existing group law and encode/decode.

def _r255_neg(pt):
    x, y, z, t = pt
    return ((-x) % R255_P, y, z, (-t) % R255_P)


def r255_point_add(p_bytes, q_bytes):
    pp = r255_decode(p_bytes)
    qq = r255_decode(q_bytes)
    if pp is None or qq is None:
        return None
    return r255_encode(_r255_add(pp, qq))


def r255_point_sub(p_bytes, q_bytes):
    pp = r255_decode(p_bytes)
    qq = r255_decode(q_bytes)
    if pp is None or qq is None:
        return None
    return r255_encode(_r255_add(pp, _r255_neg(qq)))


def r255_scalarmult_base(k_bytes):
    """n * B (B = the RFC 9496 basepoint above); None on a zero scalar, the
    same merged identity-result failure libsodium reports."""
    k = int.from_bytes(k_bytes, "little") % R255_L
    if k == 0:
        return None
    return r255_encode(_r255_mul(k, R255_BASE))


def r255_scalar_add(x_bytes, y_bytes):
    """x + y mod L, each input read as a little-endian 256-bit integer and the
    result fully reduced (libsodium's widen-and-reduce semantics)."""
    z = (int.from_bytes(x_bytes, "little") + int.from_bytes(y_bytes, "little")) % R255_L
    return z.to_bytes(32, "little")


def r255_scalar_mul(x_bytes, y_bytes):
    z = (int.from_bytes(x_bytes, "little") * int.from_bytes(y_bytes, "little")) % R255_L
    return z.to_bytes(32, "little")


# --------------------------------------------------------------------------
# Level 2 mental-poker deal algebra (spec 7.3, plan 4a-4c) -- the l2_*
# functions below are LINE-FOR-LINE mirrors of the heL2* handlers in
# src/holdem.livecodescript, driven by the independent RFC 9496 reference
# above, so the pinned values hold the xTalk COMPUTE layer and this file
# together the same way the deal/betting KATs do. The contracts are string
# contracts, mirrored exactly:
#
#   * every seam is lowercase hex text (H6 corollary: raw bytes never touch
#     the script chunk evaluator); comparisons lowercase both sides because
#     xTalk's `is` is case-insensitive.
#   * a deck is 52 comma-separated 64-hex points; a permutation is 52
#     comma-separated indices (out[j] = k * in[perm[j]]); an unmask chain is
#     a comma list whose item 1 is the masked table point and each later
#     item is one seat's broadcast step value, in chain order.
#   * failures return distinct "void:..." strings (never raise), so Phase
#     4d's attribution can name the condition: scalar-format / point-format
#     / invalid-point / identity-point (libsodium reports zero-scalar and
#     identity results as one failure; sxRistrettoScalarMultPoint's throw IS
#     this detection) / deck-size / perm-size / perm-format / duplicate-point
#     (spec 7.3's free integrity check) / chain-short / final-not-in-table /
#     hole-not-in-table / shuffle-mismatch / unmask-mismatch / scalar-zero.
#     Position-tagged voids carry 1-based positions after the last colon.
#   * sigma is deliberately NOT required to be distinct here: a repeated
#     index duplicates a point in the OUTPUT deck, which the public
#     duplicate check catches on every client (spec 7.3: prevented, not
#     just detected) -- only range/format is validated.
# --------------------------------------------------------------------------

L2_CARD_DOMAIN = "HOLDEM-L2-CARD-v1|"
L2_IDENTITY_HEX = "00" * 32


def _l2_hex_ok(txt):
    """heIsHex(txt, 64) twin: exactly 64 hex chars, either case."""
    if not isinstance(txt, str) or len(txt) != 64:
        return False
    return all(c in "0123456789abcdefABCDEF" for c in txt)


def l2_point_valid(p_hex):
    """sxRistrettoPointValid twin (canonical-encoding predicate)."""
    return r255_decode(bytes.fromhex(p_hex)) is not None


def l2_card_point(idx):
    """heL2CardPointHex twin: base point for card index 1..52 via the
    domain-separated hash-to-group map (spec 7.3 setup); the 64-byte hash
    is sxHash(label, 64) == BLAKE2b-512."""
    if idx < 1 or idx > 52:
        return "void:card-range"
    lbl = (L2_CARD_DOMAIN + card_name(idx)).encode("utf-8")
    h = hashlib.blake2b(lbl, digest_size=64).digest()
    return r255_encode(r255_from_hash(h)).hex()


def l2_base_deck():
    """heL2BaseDeckHex twin: the public 52-point card table."""
    return ",".join(l2_card_point(i) for i in range(1, 53))


def l2_scalar_invert(k_hex):
    """heL2ScalarInvertHex twin (sxRistrettoScalarInvert: k^-1 mod L)."""
    if not _l2_hex_ok(k_hex):
        return "void:scalar-format"
    k = int.from_bytes(bytes.fromhex(k_hex), "little") % R255_L
    if k == 0:
        return "void:scalar-zero"
    return pow(k, R255_L - 2, R255_L).to_bytes(32, "little").hex()


def l2_mask_point(k_hex, p_hex):
    """heL2MaskPointHex twin: q = k * P, hex in / hex out. The validity
    check runs FIRST so a scalar-mult failure after it can only be the
    identity result (zero scalar, or P itself the identity)."""
    if not _l2_hex_ok(k_hex):
        return "void:scalar-format"
    if not _l2_hex_ok(p_hex):
        return "void:point-format"
    if not l2_point_valid(p_hex.lower()):
        return "void:invalid-point"
    q = r255_scalarmult(bytes.fromhex(k_hex), bytes.fromhex(p_hex))
    if q is None or q == b"\x00" * 32:
        return "void:identity-point"
    return q.hex()


def l2_deck_check(deck_txt):
    """heL2DeckCheckHex twin: spec 7.3's free integrity check. One pass, in
    position order: format, then encoding validity, then the duplicate
    lookup -- the first offence names its position(s)."""
    items = deck_txt.split(",")
    if len(items) != 52:
        return "void:deck-size"
    seen = {}
    for pos, p in enumerate(items, 1):
        if not _l2_hex_ok(p):
            return "void:point-format:%d" % pos
        lp = p.lower()
        if not l2_point_valid(lp):
            return "void:invalid-point:%d" % pos
        if lp in seen:
            return "void:duplicate-point:%d,%d" % (seen[lp], pos)
        seen[lp] = pos
    return "ok"


def l2_mask_deck(deck_txt, k_hex, perm_txt):
    """heL2MaskDeckHex twin: one full shuffle-mask step (spec 7.3) --
    out[j] = k * in[perm[j]] for j = 1..52. A void from the point mask is
    propagated with the output position appended."""
    items = deck_txt.split(",")
    if len(items) != 52:
        return "void:deck-size"
    perm = perm_txt.split(",")
    if len(perm) != 52:
        return "void:perm-size"
    out = []
    for j, sj in enumerate(perm, 1):
        if not sj.isdigit() or int(sj) < 1 or int(sj) > 52:
            return "void:perm-format:%d" % j
        q = l2_mask_point(k_hex, items[int(sj) - 1])
        if q.startswith("void:"):
            return "%s:%d" % (q, j)
        out.append(q)
    return ",".join(out)


def l2_card_of_point(p_hex, base_txt):
    """heL2CardOfPointHex twin: card index 1..52 of a point in the base
    table, 0 when absent (pure text scan, no group math)."""
    lp = p_hex.lower()
    for i, b in enumerate(base_txt.split(","), 1):
        if b.lower() == lp:
            return i
    return 0


def l2_public_card(chain_txt, base_txt):
    """heL2PublicCardHex twin: verify a COMPLETED public unmask chain
    (spec 7.3 dealing): every value well-formed and a valid encoding, and
    the final value must hit the 52-point table -- outside it is the
    void-and-audit condition."""
    items = chain_txt.split(",")
    if len(items) < 2:
        return "void:chain-short"
    for pos, p in enumerate(items, 1):
        if not _l2_hex_ok(p):
            return "void:point-format:%d" % pos
        if not l2_point_valid(p.lower()):
            return "void:invalid-point:%d" % pos
    idx = l2_card_of_point(items[-1], base_txt)
    if idx == 0:
        return "void:final-not-in-table"
    return "card:%d" % idx


def l2_hole_card(chain_txt, kinv_hex, base_txt):
    """heL2HoleCardHex twin: the owner's last, PRIVATE step of a hole
    chain -- strip the own mask off the public penultimate value and
    resolve the card. Also what showdown uses to make A's holes fall out
    of V * k_A^-1 for the world (spec 7.3)."""
    items = chain_txt.split(",")
    if len(items) < 1 or items[0] == "":
        return "void:chain-short"
    for pos, p in enumerate(items, 1):
        if not _l2_hex_ok(p):
            return "void:point-format:%d" % pos
        if not l2_point_valid(p.lower()):
            return "void:invalid-point:%d" % pos
    q = l2_mask_point(kinv_hex, items[-1])
    if q.startswith("void:"):
        return q
    idx = l2_card_of_point(q, base_txt)
    if idx == 0:
        return "void:hole-not-in-table"
    return "card:%d" % idx


def l2_reveal_shuffle(in_txt, out_txt, k_hex, perm_txt):
    """heL2RevealShuffleHex twin (spec 7.3 showdown): recompute the
    revealer's whole shuffle-mask step from the revealed (k, sigma) and
    compare against what it broadcast; the first mismatching position is
    named for 4d attribution."""
    redone = l2_mask_deck(in_txt, k_hex, perm_txt)
    if redone.startswith("void:"):
        return redone
    outs = out_txt.split(",")
    if len(outs) != 52:
        return "void:deck-size"
    res = redone.split(",")
    for pos in range(1, 53):
        if res[pos - 1].lower() != outs[pos - 1].lower():
            return "void:shuffle-mismatch:%d" % pos
    return "ok"


def l2_reveal_unmask(in_hex, out_hex, k_hex):
    """heL2RevealUnmaskHex twin (spec 7.3 showdown): one broadcast unmask
    step re-verified from the revealed scalar -- out must equal
    k^-1 * in."""
    kinv = l2_scalar_invert(k_hex)
    if kinv.startswith("void:"):
        return kinv
    redone = l2_mask_point(kinv, in_hex)
    if redone.startswith("void:"):
        return redone
    if not _l2_hex_ok(out_hex):
        return "void:point-format"
    if redone.lower() == out_hex.lower():
        return "ok"
    return "void:unmask-mismatch"


# --------------------------------------------------------------------------
# Phase 4d void-and-audit + Phase 5 DLEQ (spec 7.3/7.4, plan 4d/4e/5): the
# l2_dleq_* / l2_void_* functions below are line-for-line mirrors of the
# heL2Dleq* / heL2Void* handlers in src/holdem.livecodescript, driven by the
# independent RFC 9496 reference above. Two contracts are PINNED here first
# and the xTalk side is written to match (the "reference before trust" rule):
#
#   * THE RECORD FORMATS (spec 6 body conventions -- the body is UTF-8 text,
#     hex-encoded into the envelope, so its commas never reach the frame;
#     multi-value fields join with "|" like seats=1|2|3 does):
#       shuffleStep  body = pos=<P>,ck=<64hex|empty>,deck=<52 x 64hex "|">
#       unmaskStep   body = pos=<P>,slot=<S>,val=<64hex>,proof=<192hex|empty>
#     P = contributor position in the shuffle order (seat order at Level 2);
#     ck = the DLEQ commitment key k_P * B (required when the signed table
#     config pins dleq=1; empty is legal below that); S = the deck position
#     1..52 being unmasked (consumed in the fixed public order); proof is
#     spec 7.4's reserved field, filled at Phase 5. Audit reveals travel as
#     one line per contributor: <pos> TAB <kHex> TAB <sigma comma-list>.
#
#   * THE DLEQ PROOF (Chaum-Pedersen over ristretto255, spec 7.4): the
#     statement is P2 = k * P1 for the k behind the commitment ck = k*B --
#     an unmask step proves (k, P1=stepOut, P2=stepIn), since
#     out = k^-1 * in <=> in = k * out. Derandomized nonce (the RFC 6979 /
#     EdDSA pattern, what makes the proof pinnable from fixed scalars):
#       w  = reduce(H32("HOLDEM-L2-DLEQW-v1|" || k || "|" || p1 || "|" || p2))
#       a1 = w*B ;  a2 = w*P1
#       c  = reduce(H32("HOLDEM-L2-DLEQ-v1|" || ck || "|" || p1 || "|" || p2
#                        || "|" || a1 || "|" || a2))
#       z  = w + c*k mod L
#       proof = a1 || a2 || z          (96 bytes = 192 hex, spec 7.4's size)
#     All hash inputs are the LOWERCASED hex texts joined with "|" (xTalk's
#     `is` compares case-blind, but hashes see bytes -- canonicalize first).
#     reduce() is ScalarAdd(x, 0) -- libsodium's widen-and-reduce -- applied
#     BEFORE any point multiplication, so libsodium's bit-255 masking in
#     scalarmult and this reference's full mod-L arithmetic can never see
#     different scalars. Verification checks z canonical (reduce(z) == z),
#     then  z*B == a1 + c*ck  and  z*P1 == a2 + c*P2 ; c*ck and c*P2 ride
#     ONE sxRistrettoScalarMultBatch crossing on the engine (one scalar, two
#     points -- exactly the batch call's shape; z*B and z*P1 have different
#     bases so they cannot join it).
#
# The void machine consumes the DEDUPED, host-sequenced record stream (spec
# 6 kills transport replay at the envelope layer); an identical re-post of
# the last applied record is tolerated as "dup", and any OTHER step for an
# already-filled position is signed equivocation, named directly. Every
# refusal is a distinct "void:..." string; attribution is DIRECT (named=pos)
# when the offending record is itself publicly refusable, and DEFERRED
# (named=0 -> the mandatory full-reveal audit) when only the reveals can
# say whose step lied (a completed chain landing outside the table).
# --------------------------------------------------------------------------

L2_DLEQ_DOMAIN = "HOLDEM-L2-DLEQ-v1|"
L2_DLEQW_DOMAIN = "HOLDEM-L2-DLEQW-v1|"


def _l2_scalar_reduce(b32):
    """The ScalarAdd-zero reduce both sides pin (sxRistrettoScalarAdd(x, 0)):
    read 32 bytes little-endian, fully reduce mod L."""
    return r255_scalar_add(b32, b"\x00" * 32)


def l2_commit_key(k_hex):
    """heL2CommitKeyHex twin: ck = k*B, the per-hand DLEQ commitment key a
    shuffleStep carries. The scalar is reduced first (see the block comment);
    k == 0 mod L is the merged identity failure."""
    if not _l2_hex_ok(k_hex):
        return "void:scalar-format"
    q = r255_scalarmult_base(_l2_scalar_reduce(bytes.fromhex(k_hex)))
    if q is None:
        return "void:scalar-zero"
    return q.hex()


def l2_point_ok(p_hex):
    """heL2PointOkHex twin: format + canonical-encoding validity as a
    verdict string ("ok" / "void:...")."""
    if not _l2_hex_ok(p_hex):
        return "void:point-format"
    if not l2_point_valid(p_hex.lower()):
        return "void:invalid-point"
    return "ok"


def l2_dleq_prove(k_hex, p1_hex, p2_hex):
    """heL2DleqProve twin: Chaum-Pedersen proof that P2 = k*P1 for the k
    behind ck = k*B, without revealing k. Deterministic (derandomized w),
    so the pinned vector below IS the whole prover contract."""
    if not _l2_hex_ok(k_hex):
        return "void:scalar-format"
    vd = l2_point_ok(p1_hex)
    if vd != "ok":
        return vd
    vd = l2_point_ok(p2_hex)
    if vd != "ok":
        return vd
    ck = l2_commit_key(k_hex)
    if ck.startswith("void:"):
        return ck
    w = _l2_scalar_reduce(hashlib.blake2b(
        (L2_DLEQW_DOMAIN + k_hex.lower() + "|" + p1_hex.lower() + "|" +
         p2_hex.lower()).encode("utf-8"), digest_size=32).digest())
    a1 = r255_scalarmult_base(w)
    if a1 is None:
        return "void:scalar-zero"
    a2 = r255_scalarmult(w, bytes.fromhex(p1_hex))
    if a2 is None or a2 == b"\x00" * 32:
        return "void:identity-point"
    c = _l2_scalar_reduce(hashlib.blake2b(
        (L2_DLEQ_DOMAIN + ck + "|" + p1_hex.lower() + "|" + p2_hex.lower() +
         "|" + a1.hex() + "|" + a2.hex()).encode("utf-8"),
        digest_size=32).digest())
    z = r255_scalar_add(w, r255_scalar_mul(c, bytes.fromhex(k_hex)))
    return a1.hex() + a2.hex() + z.hex()


def l2_dleq_verify(ck_hex, p1_hex, p2_hex, proof_hex):
    """heL2DleqVerify twin. The challenge is re-derived from the transcript,
    so a tampered (a1, a2) changes c and neither equation can close
    (Fiat-Shamir); the two equations are named distinctly (:1 binds the
    commitment key, :2 binds the step values)."""
    if not isinstance(proof_hex, str) or len(proof_hex) != 192 or \
            not all(ch in "0123456789abcdefABCDEF" for ch in proof_hex):
        return "void:proof-format"
    a1_hex = proof_hex[0:64]
    a2_hex = proof_hex[64:128]
    z_hex = proof_hex[128:192]
    for p in (ck_hex, p1_hex, p2_hex, a1_hex, a2_hex):
        vd = l2_point_ok(p)
        if vd != "ok":
            return vd
    # a non-canonical z is refused, never reduced-and-accepted: libsodium
    # masks bit 255 in scalarmult while the reference reduces mod L, so an
    # attacker-chosen representation must not reach either
    if _l2_scalar_reduce(bytes.fromhex(z_hex)).hex() != z_hex.lower():
        return "void:scalar-format"
    c = _l2_scalar_reduce(hashlib.blake2b(
        (L2_DLEQ_DOMAIN + ck_hex.lower() + "|" + p1_hex.lower() + "|" +
         p2_hex.lower() + "|" + a1_hex.lower() + "|" + a2_hex.lower())
        .encode("utf-8"), digest_size=32).digest())
    # engine side: c*ck and c*P2 in ONE sxRistrettoScalarMultBatch crossing;
    # mirrored per-element (the batch contract IS element-wise scalarmult)
    c_ck = r255_scalarmult(c, bytes.fromhex(ck_hex))
    c_p2 = r255_scalarmult(c, bytes.fromhex(p2_hex))
    if c_ck is None or c_ck == b"\x00" * 32 or c_p2 is None or c_p2 == b"\x00" * 32:
        return "void:identity-point"
    lhs1 = r255_point_add(bytes.fromhex(a1_hex), c_ck)
    rhs1 = r255_scalarmult_base(bytes.fromhex(z_hex))
    if lhs1 is None or rhs1 is None:
        return "void:dleq-mismatch:1"
    if lhs1.hex() != rhs1.hex():
        return "void:dleq-mismatch:1"
    lhs2 = r255_point_add(bytes.fromhex(a2_hex), c_p2)
    rhs2 = r255_scalarmult(bytes.fromhex(z_hex), bytes.fromhex(p1_hex))
    if lhs2 is None or rhs2 is None or rhs2 == b"\x00" * 32:
        return "void:dleq-mismatch:2"
    if lhs2.hex() != rhs2.hex():
        return "void:dleq-mismatch:2"
    return "ok"


def l2_shuffle_body(pos, ck_hex, deck_txt):
    """heL2ShuffleBodyOf twin -- the PINNED shuffleStep record format."""
    return "pos=%d,ck=%s,deck=%s" % (pos, ck_hex, deck_txt.replace(",", "|"))


def l2_unmask_body(pos, slot, val_hex, proof_hex):
    """heL2UnmaskBodyOf twin -- the PINNED unmaskStep record format (proof
    is spec 7.4's reserved field; empty below Phase 5 hardening)."""
    return "pos=%d,slot=%d,val=%s,proof=%s" % (pos, slot, val_hex, proof_hex)


def _l2_body_parse(body):
    """The split-by-comma-and-equals idiom the xTalk machine uses."""
    a = {}
    for it in body.split(","):
        if "=" in it:
            k, v = it.split("=", 1)
            a[k] = v
    return a


def l2_void_mark(st, named, why):
    """heL2VoidMark twin: latch the machine void. named=0 means attribution
    is DEFERRED to the mandatory full-reveal audit."""
    st["phase"] = "void"
    st["named"] = named
    st["why"] = why
    st["last"] = "void"
    return st


def l2_void_new(count, base_txt, dleq, owners_txt):
    """heL2VoidNew twin: one hand's deal machine. owners_txt is a comma list
    of <slot>:<ownerPos> pairs naming the hole slots (the deal layout is
    public, so the ORCHESTRATOR declares it -- a record cannot)."""
    st = {"count": count, "base": base_txt,
          "dleq": "true" if dleq else "false",
          "phase": "shuffle", "applied": 0, "named": 0, "why": "", "stall": 0,
          "last": "", "deckAt": {0: base_txt}, "ck": {}, "shufBody": {},
          "chain": {}, "chainN": {}, "lastBody": {}, "owner": {}, "card": {},
          "holeUp": {}}
    if not isinstance(count, int) or count < 2 or count > 9:
        return l2_void_mark(st, 0, "void:count-range")
    if len(base_txt.split(",")) != 52:
        return l2_void_mark(st, 0, "void:deck-size")
    if owners_txt != "":
        for pair in owners_txt.split(","):
            if ":" not in pair:
                return l2_void_mark(st, 0, "void:owner-format")
            sj, oj = pair.split(":", 1)
            if not sj.isdigit() or not oj.isdigit() or int(sj) < 1 or \
                    int(sj) > 52 or int(oj) < 1 or int(oj) > count:
                return l2_void_mark(st, 0, "void:owner-format")
            st["owner"][int(sj)] = int(oj)
    return st


def l2_void_shuffle(st, pos, body):
    """heL2VoidShuffle twin: apply one shuffleStep record. Order is strict
    (pos = applied + 1); an identical re-post of an applied step is "dup"
    (state unmoved), a DIFFERENT one is equivocation, named directly."""
    if st["phase"] == "void":
        return st
    stored = st["shufBody"].get(pos, "")
    if stored != "":
        if body.lower() == stored.lower():
            st["last"] = "dup"
            return st
        return l2_void_mark(st, pos, "void:step-equivocation:%d" % pos)
    if st["phase"] != "shuffle":
        return l2_void_mark(st, pos, "void:step-phase")
    if pos != st["applied"] + 1:
        return l2_void_mark(st, pos, "void:step-order:%d,%d" % (st["applied"] + 1, pos))
    a = _l2_body_parse(body)
    posf = a.get("pos", "")
    ckf = a.get("ck", "")
    deckf = a.get("deck", "")
    if not posf.isdigit() or deckf == "":
        return l2_void_mark(st, pos, "void:body-format")
    if int(posf) != pos:
        return l2_void_mark(st, pos, "void:body-pos")
    if st["dleq"] == "true" and ckf == "":
        return l2_void_mark(st, pos, "void:ck-missing")
    if ckf != "":
        vd = l2_point_ok(ckf)
        if vd != "ok":
            return l2_void_mark(st, pos, vd)
    deck = deckf.replace("|", ",")
    vd = l2_deck_check(deck)
    if vd != "ok":
        return l2_void_mark(st, pos, vd)
    st["deckAt"][pos] = deck
    st["ck"][pos] = ckf
    st["shufBody"][pos] = body
    st["applied"] = pos
    st["last"] = "applied"
    if pos == st["count"]:
        st["phase"] = "deal"
    return st


def l2_void_unmask(st, pos, body):
    """heL2VoidUnmask twin: apply one unmaskStep record to its slot's chain.
    Per-step refusals (format, validity, order, a bad or missing DLEQ proof)
    are named DIRECTLY; a completed public chain landing outside the card
    table voids with attribution deferred to the audit."""
    if st["phase"] == "void":
        return st
    a = _l2_body_parse(body)
    posf = a.get("pos", "")
    slotf = a.get("slot", "")
    valf = a.get("val", "")
    prooff = a.get("proof", "")
    if not posf.isdigit() or not slotf.isdigit() or valf == "":
        return l2_void_mark(st, pos, "void:body-format")
    if int(posf) != pos:
        return l2_void_mark(st, pos, "void:body-pos")
    slot = int(slotf)
    if slot < 1 or slot > 52:
        return l2_void_mark(st, pos, "void:slot-range")
    stored = st["lastBody"].get(slot, "")
    if stored != "" and body.lower() == stored.lower():
        st["last"] = "dup"
        return st
    if st["phase"] != "deal":
        return l2_void_mark(st, pos, "void:step-phase")
    chain_n = st["chainN"].get(slot, 0)
    owner = st["owner"].get(slot, 0)
    need = st["count"] if owner == 0 else st["count"] - 1
    if chain_n >= need:
        return l2_void_mark(st, pos, "void:chain-done:%d" % slot)
    order = [p for p in range(1, st["count"] + 1) if p != owner]
    step = chain_n + 1
    expect = order[step - 1]
    if pos != expect:
        return l2_void_mark(st, pos, "void:chain-order:%d:%d,%d" % (slot, expect, pos))
    vd = l2_point_ok(valf)
    if vd != "ok":
        return l2_void_mark(st, pos, vd)
    chain_txt = st["chain"].get(slot, "")
    if chain_txt == "":
        chain_txt = st["deckAt"][st["count"]].split(",")[slot - 1]
    prev_hex = chain_txt.split(",")[-1]
    if st["dleq"] == "true" and prooff == "":
        return l2_void_mark(st, pos, "void:proof-missing:%d" % slot)
    if prooff != "":
        ck_stored = st["ck"].get(pos, "")
        if ck_stored == "":
            return l2_void_mark(st, pos, "void:ck-missing:%d" % slot)
        vd = l2_dleq_verify(ck_stored, valf, prev_hex, prooff)
        if vd != "ok":
            return l2_void_mark(st, pos, "%s:%d" % (vd, slot))
    st["chain"][slot] = chain_txt + "," + valf
    st["chainN"][slot] = step
    st["lastBody"][slot] = body
    st["last"] = "applied"
    if step == need:
        if owner == 0:
            card = l2_public_card(st["chain"][slot], st["base"])
            if card.startswith("card:"):
                st["card"][slot] = card
            else:
                return l2_void_mark(st, 0, "%s:%d" % (card, slot))
        else:
            st["holeUp"][slot] = "true"
    return st


def l2_void_timeout(st, owed_pos):
    """heL2VoidTimeout twin: the deal-phase timer expired with owed_pos owing
    the next step (spec 9). Provisionally named; the mandatory audit keeps
    the name only if every signed step re-verifies (an EARLIER bad step
    outranks the stall -- the spec's "first bad one" rule)."""
    if st["phase"] == "void":
        return st
    st["stall"] = owed_pos
    return l2_void_mark(st, owed_pos, "void:deal-timeout:%d" % owed_pos)


def l2_void_outcome(st):
    """heL2VoidOutcome twin: the 4d verdict line. A void hand ALWAYS returns
    the bets and ALWAYS requires the full reveal (spec 7.3: the hand is
    void, so the reveal costs nothing); named=audit defers attribution to
    l2_void_audit."""
    if st["phase"] != "void":
        return st["phase"]
    if st["named"] > 0:
        return "void|%s|named=%d|bets-return|reveal-required" % (st["why"], st["named"])
    return "void|%s|named=audit|bets-return|reveal-required" % st["why"]


def l2_void_audit(st, reveals_txt):
    """heL2VoidAudit twin: the mandatory full-reveal audit, in the MANDATORY
    order -- shuffle steps in contributor order first (a missing reveal or a
    commitment-key lie names its owner outright), then every opened chain in
    slot order, each step in chain order. The FIRST bad signed step names
    the cheater; a recorded staller keeps the name only when everything
    signed re-verifies; a clean audit is the table agreeing to void."""
    rk = {}
    rs = {}
    for line in reveals_txt.split("\n"):
        if line == "":
            continue
        f = line.split("\t")
        rk[int(f[0])] = f[1]
        rs[int(f[0])] = f[2]
    for i in range(1, st["count"] + 1):
        if rk.get(i, "") == "":
            return "named=%d|void:audit-refused" % i
        ck_stored = st["ck"].get(i, "")
        if ck_stored != "":
            # engine side also gates on heL2HasDleq (a pre-ABI-9 SodiumXT
            # cannot compute k*B); the reference always has the algebra
            if l2_commit_key(rk[i]).lower() != ck_stored.lower():
                return "named=%d|void:audit-ck-mismatch" % i
        vd = l2_reveal_shuffle(st["deckAt"].get(i - 1, ""),
                               st["deckAt"].get(i, ""), rk[i], rs[i])
        if vd != "ok":
            return "named=%d|%s" % (i, vd)
    for slot in range(1, 53):
        chain_n = st["chainN"].get(slot, 0)
        if chain_n == 0:
            continue
        chain = st["chain"][slot].split(",")
        owner = st["owner"].get(slot, 0)
        order = [p for p in range(1, st["count"] + 1) if p != owner]
        for t in range(1, chain_n + 1):
            p = order[t - 1]
            vd = l2_reveal_unmask(chain[t - 1], chain[t], rk[p])
            if vd != "ok":
                return "named=%d|%s:%d:%d" % (p, vd, slot, t)
    if st["stall"] > 0:
        return "named=%d|%s" % (st["stall"], st["why"])
    return "named=0|audit-clean"


def l0_audit(table, hand, seeds_hex, commits_hex, count, holes, flop, turn,
             river, occ, button):
    """heAuditDeal twin (spec 7.1 step 5) -- what the 4e deck-stacker bot
    runs against: recompute the whole Level 0 deal from the revealed seeds
    and name the FIRST failing step."""
    for i in range(1, count + 1):
        if seed_commit(bytes.fromhex(seeds_hex[i - 1])).hex() != commits_hex[i - 1]:
            return "fail:commit-mismatch-position-%d" % i
    seeds = [bytes.fromhex(s) for s in seeds_hex]
    key = stream_key(table, hand, xor_seeds(seeds))
    deck = shuffle_from_stream(stream_bytes(key, 16))
    ch, cf, ct, cr, _ = assign_deal(deck, occ, button)
    for s in occ:
        if ch[s] != holes[s]:
            return "fail:hole-mismatch-seat-%d" % s
    if cf != flop:
        return "fail:flop-mismatch"
    if ct != turn:
        return "fail:turn-mismatch"
    if cr != river:
        return "fail:river-mismatch"
    return "pass"


def compute_all():
    check_ed25519()
    out = {}
    out["table"] = TABLE.hex()
    out["id_pubs"] = [ed_publickey(s).hex() for s in ID_SEEDS]
    # -- the two display/rendezvous truncations of the SAME digest (spec 5,
    # spec 10). Both are one-liners, which is exactly why they earn a pin: a
    # silent off-by-one in the infohash is not a wrong pixel, it is two
    # machines announcing to two different DHT keys and never finding each
    # other -- a whole multi-machine session lost to a chunk expression no
    # harness ever evaluated. Mirrors heTableInfohash (20 bytes = 40 hex of
    # H(tableId), the id BYTES not their hex text) and heFingerprintOf
    # (8 hex of H(pubkey)).
    out["table_infohash"] = H(TABLE).hex()[:40]
    out["id_fingerprint1"] = H(ed_publickey(ID_SEEDS[0])).hex()[:8]
    out["deal_seeds"] = [s.hex() for s in DEAL_SEEDS]
    out["commits"] = [seed_commit(s).hex() for s in DEAL_SEEDS]
    sx = xor_seeds(DEAL_SEEDS)
    out["seeds_xor"] = sx.hex()
    key = stream_key(TABLE, HAND, sx)
    out["stream_key"] = key.hex()
    out["stream_block0"] = H(key + (0).to_bytes(4, "big")).hex()
    deck = shuffle_from_stream(stream_bytes(key, 16))
    out["deck"] = ",".join(card_name(c) for c in deck)
    holes, flop, turn, river, burns = assign_deal(deck, OCCUPIED, BUTTON)
    out["holes"] = {str(s): ",".join(card_name(c) for c in holes[s]) for s in OCCUPIED}
    out["flop"] = ",".join(card_name(c) for c in flop)
    out["turn"] = card_name(turn)
    out["river"] = card_name(river)
    out["burns"] = ",".join(card_name(c) for c in burns)
    out["deal_orders"] = {cfg: deal_signature(IDENT_DECK, *cfg.split("|"))
                          for cfg in DEAL_ORDER_CFGS}

    out["synth_stream"] = SYNTH_STREAM.hex()
    out["synth_deck"] = ",".join(card_name(c) for c in shuffle_from_stream(SYNTH_STREAM))

    # A six-envelope transcript: cfg (hand 0), three seedCommits, the blinds.
    msgs = [
        (ID_SEEDS[0], 0, "cfg", "v=1,level=0,sb=1,bb=2,seats=3,button=1"),
        (ID_SEEDS[0], 1, "seedCommit", out["commits"][0]),
        (ID_SEEDS[1], 1, "seedCommit", out["commits"][1]),
        (ID_SEEDS[2], 1, "seedCommit", out["commits"][2]),
        (ID_SEEDS[1], 1, "bidSB", "amount=1"),
        (ID_SEEDS[2], 1, "bidBB", "amount=2"),
    ]
    prev = GENESIS
    heads = []
    wires = []
    for seq, (sender, hand, mtype, body) in enumerate(msgs, 1):
        wire = make_wire(1, TABLE, hand, sender, mtype, body, seq, prev, HOST_SEED)
        wires.append(wire)
        prev = chain_next(wire)
        heads.append(prev.hex())
    out["env0_content"] = content_line(1, TABLE, 0, ed_publickey(ID_SEEDS[0]),
                                       "cfg", msgs[0][3])
    out["env0_sender_sig"] = ed_sign(out["env0_content"].encode("utf-8"),
                                     ID_SEEDS[0]).hex()
    out["env0_wire"] = wires[0]
    out["chain_heads"] = heads
    out["settle_hash"] = settle_hash("1:-4,2:8,3:-4", prev).hex()
    _, out["admit_sig"] = admit_token(TABLE.hex(), ID_SEEDS[0])

    # Host-trust fixture: a ckpt over the transcript head, and a TWO-hand
    # settlement-receipt chain that all three players sign.
    out["ckpt_sig"] = ckpt_sig(heads[5], ID_SEEDS[1])   # player 2 checkpoints head 6
    settle_hash2 = settle_hash("1:2,2:-1,3:-1", GENESIS).hex()
    out["settle_hash2"] = settle_hash2
    rh1 = receipt_head(out["settle_hash"], GENESIS_RCPT)
    rh2 = receipt_head(settle_hash2, rh1)
    out["receipt_head1"] = rh1
    out["receipt_head2"] = rh2
    out["receipt_sigs"] = [receipt_sig(rh2, s) for s in ID_SEEDS]  # all three sign hand 2

    # Lobby presence + reconnect fixture (spec 9): the host (ID0) opens a table
    # and signs a cfg (seq 1, from genesis); once a player (ID1) has joined the
    # host signs a roster (seq 2). A late joiner replays both from genesis and
    # advances its chain to lobby_head2. This pins the exact code path the
    # online lobby uses -- envelope build, roster canonicalization, chain
    # advance -- so heTestLobbyRun can machine-check it with no network.
    lobby_members = [(out["id_pubs"][0], "host"), (out["id_pubs"][1], "player")]
    out["roster_body"] = roster_body(lobby_members)
    # ante + stack joined the body in v0.17.0 (the online game folds its full
    # stakes from the signed cfg); the 2e liveness TIMER LENGTHS joined in
    # v0.23.0 (spec 6 "timer lengths" in message zero: act= seconds, bank=
    # the one per-hand time-bank, miss= consecutive timeouts before
    # auto-sit-out) -- a documented consensus change (this pin and
    # lobby_head2 regenerated; kHeHarnessV bumped; a pre-liveness client
    # ignores keys it does not read, so the wire stays compatible).
    # heLobbyCfgBody mirrors this string exactly.
    out["lobby_cfg_body"] = ("v=1,level=0,sb=1,bb=2,ante=0,stack=400,"
                             "seats=6,button=1,act=30,bank=60,miss=2")
    lw1 = make_wire(1, TABLE, 0, ID_SEEDS[0], "cfg", out["lobby_cfg_body"],
                    1, GENESIS, HOST_SEED)
    lh1 = chain_next(lw1)
    lw2 = make_wire(1, TABLE, 0, ID_SEEDS[0], "roster", out["roster_body"],
                    2, lh1, HOST_SEED)
    out["lobby_head2"] = chain_next(lw2).hex()

    # -- 2e street checkpoints + show/muck (spec 6 as-built bodies, v0.21.0).
    # A ckpt WIRE packages the street name, the boundary head, and the
    # player's ckpt signature over that head ("street=..,head=..,sig=..");
    # show/muck are seat-scoped display-choice wires ("seat=N" from the
    # seat's own key). Pinned as an EXTENSION of the six-envelope transcript
    # (seq 7..9 chained from head 6), so every pre-existing chain-head pin
    # stands byte-for-byte -- additive, not a consensus break.
    out["ckpt_body"] = "street=flop,head=%s,sig=%s" % (heads[5], out["ckpt_sig"])
    w7 = make_wire(1, TABLE, 1, ID_SEEDS[1], "ckpt", out["ckpt_body"],
                   7, prev, HOST_SEED)
    h7 = chain_next(w7)
    out["ckpt_head7"] = h7.hex()
    out["show_body"] = "seat=2"
    out["muck_body"] = "seat=3"
    w8 = make_wire(1, TABLE, 1, ID_SEEDS[1], "show", out["show_body"],
                   8, h7, HOST_SEED)
    h8 = chain_next(w8)
    out["show_head8"] = h8.hex()
    w9 = make_wire(1, TABLE, 1, ID_SEEDS[2], "muck", out["muck_body"],
                   9, h8, HOST_SEED)
    h9 = chain_next(w9)
    out["muck_head9"] = h9.hex()

    # -- 2e liveness wires (spec 8.1/9 as-built bodies, v0.23.0), pinned as
    # the seq 10..13 extension of the same transcript (additive again: no
    # earlier chain-head pin moves). The TIMEOUT wires are the EXISTING
    # act/bid wires with seat=/timeout=1/bank= marks, authored by the HOST
    # (the relay key -- here HOST_SEED, which is also ID_SEEDS[0]): the
    # spec 9 expiry prescription (check-or-fold; the exact engine amount
    # for a forced post) folded as the NAMED seat's action, so the
    # transcript stays deterministic. bank=1 marks the seat's one per-hand
    # time-bank (spec 8.1) as spent BY this timeout -- bank state is
    # transcript-derived consensus, never a clock's guess. "stand" is a
    # seat's own signed sit-out; "sit" WITHOUT a pub= field is its return
    # (the host-assignment form keeps pub=, so the two forms never collide).
    out["timeout_act_body"] = "verb=fold,amount=0,seat=3,timeout=1,bank=1"
    w10 = make_wire(1, TABLE, 1, HOST_SEED, "act", out["timeout_act_body"],
                    10, h9, HOST_SEED)
    h10 = chain_next(w10)
    out["timeout_head10"] = h10.hex()
    out["stand_body"] = "seat=2"
    w11 = make_wire(1, TABLE, 1, ID_SEEDS[1], "stand", out["stand_body"],
                    11, h10, HOST_SEED)
    h11 = chain_next(w11)
    out["stand_head11"] = h11.hex()
    out["sitback_body"] = "seat=2"
    w12 = make_wire(1, TABLE, 1, ID_SEEDS[1], "sit", out["sitback_body"],
                    12, h11, HOST_SEED)
    h12 = chain_next(w12)
    out["sitback_head12"] = h12.hex()
    out["timeout_bid_body"] = "amount=2,seat=3,timeout=1,bank=1"
    w13 = make_wire(1, TABLE, 1, HOST_SEED, "bidBB", out["timeout_bid_body"],
                    13, h12, HOST_SEED)
    h13 = chain_next(w13)
    out["timeout_bid_head13"] = h13.hex()

    # -- the deal-delivery wires (backlog A6, 2026-08-23): the types in the
    # dispatcher's vocabulary that had ZERO pinned occurrences - the whole
    # deal-delivery half of the protocol could have changed format with
    # every pin green. Bodies HAND-CONSTRUCTED from the shipped builders'
    # documented formats (the heNetSendAction call sites in
    # src/holdem.livecodescript: join in heNetGameReact step 1, handStart /
    # dealLevel in heNetHandKick, seedSeal in react step 3, bidAnte in step
    # 5, holeDeliver in heNetDealerDeal, board in heNetDealerBoard,
    # seedReveal in step 8, settle in step 9 via heNetComputeSettleTxt's
    # "seat:delta|..." shape, receipt in step 10, audit in step 11) - not
    # copied out of a run. Pinned as the seq 14..24 extension of the same
    # transcript, chained from head 13: ADDITIVE, no earlier pin moves.
    # Senders follow the per-type authority the fold enforces: handStart /
    # dealLevel / settle host-authored; holeDeliver / board from this
    # hand's dealer (the button seat, seat 1 - ID_SEEDS[0], which is also
    # the host key in this fixture); everything seat-scoped from the key
    # that owns the seat.
    # TWO bodies carry an sxSeal blob in real play (seedSeal, holeDeliver).
    # sxSeal is RANDOMIZED, so a real seal cannot be pinned from fixed
    # inputs; what IS pinnable - and pinned - is the FRAME: field names,
    # the hex discipline, and the blob length (sealed = 48 bytes overhead
    # + plaintext). The stand-ins are deterministic tagged-hash blobs of
    # exactly the real lengths (64-char hex seed -> 112 bytes; a two-card
    # index pair like "48,33" -> 53 bytes).
    out["join_box_pub"] = H(b"HOLDEM-KAT-v1|boxpub|" + bytes([2])).hex()
    out["join_body"] = "box=" + out["join_box_pub"]
    w14 = make_wire(1, TABLE, 0, ID_SEEDS[1], "join", out["join_body"],
                    14, h13, HOST_SEED)
    h14 = chain_next(w14)
    out["handstart_body"] = "seats=1|2|3,button=1"
    w15 = make_wire(1, TABLE, 1, HOST_SEED, "handStart", out["handstart_body"],
                    15, h14, HOST_SEED)
    h15 = chain_next(w15)
    out["deallevel_body"] = "level=0,dealer=1,count=3"
    # the same builder's ORACLE branch (spec 7.2: level=1 IS the oracle
    # marker, dealer=0 = no seat) - a format pin beside the level-0 wire
    out["deallevel_body_oracle"] = "level=1,dealer=0,count=3"
    w16 = make_wire(1, TABLE, 1, HOST_SEED, "dealLevel", out["deallevel_body"],
                    16, h15, HOST_SEED)
    h16 = chain_next(w16)
    seal_seed = (H(b"HOLDEM-KAT-v1|seal-standin|seedSeal") * 4)[:48 + 64]
    out["seedseal_body"] = "pos=2,sealed=" + seal_seed.hex()
    w17 = make_wire(1, TABLE, 1, ID_SEEDS[1], "seedSeal", out["seedseal_body"],
                    17, h16, HOST_SEED)
    h17 = chain_next(w17)
    out["bidante_body"] = "amount=1"
    w18 = make_wire(1, TABLE, 1, ID_SEEDS[1], "bidAnte", out["bidante_body"],
                    18, h17, HOST_SEED)
    h18 = chain_next(w18)
    seal_hole = (H(b"HOLDEM-KAT-v1|seal-standin|holeDeliver") * 2)[:48 + 5]
    out["holedeliver_body"] = "seat=2,sealed=" + seal_hole.hex()
    w19 = make_wire(1, TABLE, 1, ID_SEEDS[0], "holeDeliver", out["holedeliver_body"],
                    19, h18, HOST_SEED)
    h19 = chain_next(w19)
    out["board_body"] = "street=flop,cards=" + out["flop"].replace(",", "|")
    w20 = make_wire(1, TABLE, 1, ID_SEEDS[0], "board", out["board_body"],
                    20, h19, HOST_SEED)
    h20 = chain_next(w20)
    out["seedreveal_body"] = "pos=2,seed=" + out["deal_seeds"][1]
    w21 = make_wire(1, TABLE, 1, ID_SEEDS[1], "seedReveal", out["seedreveal_body"],
                    21, h20, HOST_SEED)
    h21 = chain_next(w21)
    out["settle_body"] = "deltas=1:-4|2:8|3:-4"
    w22 = make_wire(1, TABLE, 1, HOST_SEED, "settle", out["settle_body"],
                    22, h21, HOST_SEED)
    h22 = chain_next(w22)
    out["receipt_body"] = "head=%s,sig=%s" % (rh1, receipt_sig(rh1, ID_SEEDS[1]))
    w23 = make_wire(1, TABLE, 1, ID_SEEDS[1], "receipt", out["receipt_body"],
                    23, h22, HOST_SEED)
    h23 = chain_next(w23)
    out["audit_body"] = "result=pass"
    w24 = make_wire(1, TABLE, 1, ID_SEEDS[1], "audit", out["audit_body"],
                    24, h23, HOST_SEED)
    out["deal_wires_head24"] = chain_next(w24).hex()
    # the vocabulary itself, pinned: a type added to (or renamed in) the
    # dispatcher moves this value LOUDLY, beside the coverage assertion in
    # main() that requires the new type's wire
    out["wire_vocabulary"] = ",".join(source_wire_vocabulary())
    # the onion hello's compatible extension (2e auto-redial): the admission
    # token frame with the sender's APPLIED SEQ as a trailing tab item (the
    # redial resync mark -- heAdmitTokenVerify reads items 1..3 only, so an
    # old host ignores it and replays in full; a 2e host trims its
    # reconnect replay to the tail past the mark)
    _tok, _ = admit_token(TABLE.hex(), ID_SEEDS[1], "player")
    out["hello_trim_frame"] = "h\t" + _tok + "\t42"

    # -- spec 9 host election (the 2e liveness slice Phase 3 leans on): the
    # successor is DETERMINISTIC -- the lowest pubkey among the live
    # candidates -- so every client names the same one with no round trips.
    # Mirrors heElectHostOf (a text sort over lowercase 64-hex lines).
    out["elected_host"] = min(out["id_pubs"])
    # ...and "live" means NOT SITTING OUT (spec 9: "lowest pubkey among live
    # SEATED players"). Mirrors heNetElectablePubs' sit-out filter, which is
    # the half heElectHostOf cannot see: with the lowest-pubkey seat sat out
    # the candidate set is the other two, so the successor moves to the next
    # key up. Safe to mirror here precisely because sitOutBy is derived from
    # the transcript alone (a signed stand, or counted timeout wires), so the
    # KAT can compute it from the same public facts every client folds.
    out["elected_host_sitout"] = min(p for p in out["id_pubs"]
                                     if p != out["elected_host"])

    # -- Phase 3 oracle: the deterministic onion-service seed, play vs
    # oracle. ONE derivation shape, TWO domain tags (spec 16: every hash
    # carries its purpose, versioned): an oracle table's address can never
    # collide with the same host's PLAYING table on the same table id.
    # Mirrors heOnionSeedHex(idSeedHex, tableHex[, mode]).
    _svc = (ID_SEEDS[0].hex() + "|" + TABLE.hex()).encode("utf-8")
    out["onion_service_seed"] = H(b"HOLDEM-ONION-v1|" + _svc).hex()
    out["oracle_service_seed"] = H(b"HOLDEM-ORACLE-v1|" + _svc).hex()
    # The oracle table's signed cfg: level=1 IS the oracle marker (spec 7.2
    # -- Level 1 is the non-playing-dealer rung of the deal ladder). Every
    # other byte matches the playing body, so a pre-oracle client refuses
    # the hand at its dealLevel gate ("unsupported deal level") instead of
    # mis-folding an oracle table as a playing one.
    out["lobby_cfg_body_oracle"] = ("v=1,level=1,sb=1,bb=2,ante=0,stack=400,"
                                    "seats=6,button=1,act=30,bank=60,miss=2")

    # -- ristretto255 (Workstream U shipped in SodiumXT at ABI 8, 2026-08-15).
    # These values are computed by the INDEPENDENT reference below and pinned
    # against vectors generated from the pinned libsodium build itself, so a
    # run of this gate IS the cross-check the plan's Workstream U exit
    # criterion asks for: two implementations, one answer. The same vectors
    # are pinned in sodiumxt's C smoke test and its member harness.
    out["ristretto_generator"] = r255_encode(R255_BASE).hex()
    for lbl, key in (("card-00", "ristretto_point_card00"),
                     ("card-01", "ristretto_point_card01"),
                     ("card-51", "ristretto_point_card51")):
        h = hashlib.blake2b(("HOLDEM-RISTRETTO-KAT-v1|" + lbl).encode(),
                            digest_size=64).digest()
        out[key] = r255_encode(r255_from_hash(h)).hex()
    k7 = (7).to_bytes(32, "little")
    out["ristretto_k7_card00"] = r255_scalarmult(
        k7, bytes.fromhex(out["ristretto_point_card00"])).hex()
    out["ristretto_k7_inv"] = pow(7, R255_L - 2, R255_L).to_bytes(32, "little").hex()
    out["ristretto_unmask_roundtrip"] = (
        r255_scalarmult(bytes.fromhex(out["ristretto_k7_inv"]),
                        bytes.fromhex(out["ristretto_k7_card00"])).hex()
        == out["ristretto_point_card00"])
    out["ristretto_ff_invalid"] = r255_decode(b"\xff" * 32) is None

    # -- ABI 9 follow-ons (the plan's recorded Phase 5 surface, shipped in
    # SodiumXT 2026-08-15): base-mult, point add/sub, the one-crossing batch,
    # scalar arithmetic mod L. Same two-implementation rule as above: every
    # pin was generated from the pinned libsodium build and is re-derived
    # here by the independent reference on every run. The base-mult of 7 is
    # additionally RFC 9496's own small-multiples table entry B[7] - a third
    # independent witness for that one.
    out["ristretto_base_mult7"] = r255_scalarmult_base(k7).hex()
    out["ristretto_add_c00_c01"] = r255_point_add(
        bytes.fromhex(out["ristretto_point_card00"]),
        bytes.fromhex(out["ristretto_point_card01"])).hex()
    out["ristretto_sub_roundtrip"] = (
        r255_point_sub(bytes.fromhex(out["ristretto_add_c00_c01"]),
                       bytes.fromhex(out["ristretto_point_card01"])).hex()
        == out["ristretto_point_card00"])
    # the batch call's contract is element-for-element the single scalarmult,
    # so its pin IS the concatenation of the three per-card products
    out["ristretto_batch_k7_cards"] = ",".join(
        r255_scalarmult(k7, bytes.fromhex(out[key])).hex()
        for key in ("ristretto_point_card00", "ristretto_point_card01",
                    "ristretto_point_card51"))
    out["ristretto_scalar_add_wrap"] = r255_scalar_add(
        k7, (R255_L - 2).to_bytes(32, "little")).hex()   # 7 + (L-2) = 5 mod L
    out["ristretto_scalar_mul_inv"] = r255_scalar_mul(
        k7, bytes.fromhex(out["ristretto_k7_inv"])).hex()  # 7 * 7^-1 = 1 mod L
    out["ristretto_dleq_identity"] = (
        r255_scalarmult(k7, bytes.fromhex(out["ristretto_add_c00_c01"])).hex()
        == r255_point_add(
            bytes.fromhex(out["ristretto_batch_k7_cards"].split(",")[0]),
            bytes.fromhex(out["ristretto_batch_k7_cards"].split(",")[1])).hex())

    # -- Level 2 mental poker (spec 7.3, plan 4a-4c): a COMPLETE hand from
    # fixed scalars, end to end -- the Phase 4 exit criterion's KAT. Three
    # seats mask-and-shuffle the 52-point base deck in order; one public
    # card and one hole card (owner = seat 2) run their unmask chains; the
    # showdown reveal of (k2, sigma2) re-verifies every step seat 2 made;
    # and the refusal cases pin the void-string vocabulary 4d will
    # attribute with. Scalars derive from tagged hashes reduced mod L;
    # permutations reuse the committed keyed-stream Fisher-Yates so the
    # whole fixture reproduces from this file alone.
    l2_ks = []
    for i in (1, 2, 3):
        raw = hashlib.blake2b(b"HOLDEM-L2-KAT-v1|scalar|" + bytes([i]),
                              digest_size=32).digest()
        l2_ks.append((int.from_bytes(raw, "little") % R255_L)
                     .to_bytes(32, "little").hex())
    out["l2_scalars"] = l2_ks
    l2_invs = [l2_scalar_invert(k) for k in l2_ks]
    out["l2_scalar_invs"] = l2_invs
    l2_perms = [",".join(str(c) for c in shuffle_from_stream(
        stream_bytes(H(b"HOLDEM-L2-KAT-v1|perm|" + bytes([i])), 16)))
        for i in (1, 2, 3)]
    out["l2_perms"] = l2_perms

    l2_base = l2_base_deck()
    out["l2_base_deck"] = l2_base
    out["l2_base_deck_check"] = l2_deck_check(l2_base)
    l2_d1 = l2_mask_deck(l2_base, l2_ks[0], l2_perms[0])
    l2_d2 = l2_mask_deck(l2_d1, l2_ks[1], l2_perms[1])
    l2_d3 = l2_mask_deck(l2_d2, l2_ks[2], l2_perms[2])
    out["l2_deck_p1"] = l2_d1
    out["l2_deck_p2"] = l2_d2
    out["l2_masked_deck"] = l2_d3
    out["l2_masked_deck_check"] = l2_deck_check(l2_d3)

    # public card at table position 1: chain in seat order, final value must
    # hit the table -- and it must be the composite-permutation preimage,
    # asserted here so a pin can never drift from the algebra it claims.
    l2_c0 = l2_d3.split(",")[0]
    l2_v1 = l2_mask_point(l2_invs[0], l2_c0)
    l2_v2 = l2_mask_point(l2_invs[1], l2_v1)
    l2_v3 = l2_mask_point(l2_invs[2], l2_v2)
    l2_pub_chain = ",".join([l2_c0, l2_v1, l2_v2, l2_v3])
    out["l2_public_chain"] = l2_pub_chain
    out["l2_public_card"] = l2_public_card(l2_pub_chain, l2_base)
    p1 = [int(x) for x in l2_perms[0].split(",")]
    p2 = [int(x) for x in l2_perms[1].split(",")]
    p3 = [int(x) for x in l2_perms[2].split(",")]
    if out["l2_public_card"] != "card:%d" % p1[p2[p3[0] - 1] - 1]:
        raise AssertionError("L2 public chain does not resolve to sigma1(sigma2(sigma3(1)))")

    # hole card owned by seat 2, table position 2: seats 1 and 3 step
    # publicly (owner last); the penultimate value hits NO card (CDH-hidden)
    # until the owner strips its own mask.
    l2_h0 = l2_d3.split(",")[1]
    l2_w1 = l2_mask_point(l2_invs[0], l2_h0)
    l2_w2 = l2_mask_point(l2_invs[2], l2_w1)
    l2_hole_chain = ",".join([l2_h0, l2_w1, l2_w2])
    out["l2_hole_chain"] = l2_hole_chain
    out["l2_hole_penultimate_card"] = l2_card_of_point(l2_w2, l2_base)
    out["l2_hole_card"] = l2_hole_card(l2_hole_chain, l2_invs[1], l2_base)
    if out["l2_hole_card"] != "card:%d" % p1[p2[p3[1] - 1] - 1]:
        raise AssertionError("L2 hole chain does not resolve to sigma1(sigma2(sigma3(2)))")

    # showdown: seat 2 reveals (k2, sigma2); every step it made re-verifies
    out["l2_reveal_shuffle_ok"] = l2_reveal_shuffle(l2_d1, l2_d2, l2_ks[1], l2_perms[1])
    l2_tam = l2_d2.split(",")
    l2_tam[6], l2_tam[7] = l2_tam[7], l2_tam[6]
    out["l2_reveal_shuffle_bad"] = l2_reveal_shuffle(l2_d1, ",".join(l2_tam),
                                                     l2_ks[1], l2_perms[1])
    out["l2_reveal_unmask_ok"] = l2_reveal_unmask(l2_v1, l2_v2, l2_ks[1])

    # refusal cases: the void vocabulary, each surfaced as its own string
    l2_dup = l2_d3.split(",")
    l2_dup[1] = l2_dup[0]
    out["l2_void_duplicate"] = l2_deck_check(",".join(l2_dup))
    out["l2_void_wrong_scalar"] = l2_reveal_unmask(l2_v1, l2_v2, l2_ks[2])
    out["l2_void_invalid"] = l2_public_card(
        ",".join([l2_c0, "ff" * 32, l2_v2, l2_v3]), l2_base)
    l2_b2 = l2_mask_point(l2_invs[2], l2_v1)   # seat 2 applies the WRONG inverse
    l2_b3 = l2_mask_point(l2_invs[2], l2_b2)   # seat 3 steps correctly after it
    out["l2_void_bad_final"] = l2_public_card(
        ",".join([l2_c0, l2_v1, l2_b2, l2_b3]), l2_base)
    out["l2_void_identity"] = l2_mask_point(l2_ks[0], L2_IDENTITY_HEX)
    out["l2_void_mask_invalid"] = l2_mask_point(l2_ks[0], "ff" * 32)
    l2_bad_perm = l2_perms[0].split(",")
    l2_bad_perm[0] = "0"
    out["l2_void_perm"] = l2_mask_deck(l2_base, l2_ks[0], ",".join(l2_bad_perm))

    # -- Phase 4d void-and-audit + Phase 4e bots + Phase 5 DLEQ (spec 7.3 /
    # 7.4 / 12.4). Every pin below is a whole SCENARIO: the machine (or the
    # DLEQ verifier) driven by a scripted attacker over the fixed-scalar
    # fixtures above, with the verdict string pinned -- so the attribution
    # contract ("this attack is detected AND names this signer") is held
    # headlessly, and heTestLevel2VoidRun re-checks the same verdicts
    # on-engine.
    l2_cks = [l2_commit_key(k) for k in l2_ks]
    out["l2_cks"] = l2_cks
    out["l2_shuffle_body_ok"] = (
        l2_shuffle_body(1, "", l2_d1) ==
        "pos=1,ck=,deck=" + l2_d1.replace(",", "|"))
    out["l2_unmask_body1"] = l2_unmask_body(1, 1, l2_v1, "")
    l2_reveals = "\n".join("%d\t%s\t%s" % (i + 1, l2_ks[i], l2_perms[i])
                           for i in range(3))

    # the honest table: three shuffle steps, the pinned public chain on slot
    # 1, the pinned hole chain (owner seat 2) on slot 2 -- and a clean audit
    st = l2_void_new(3, l2_base, False, "2:2")
    st = l2_void_shuffle(st, 1, l2_shuffle_body(1, "", l2_d1))
    st = l2_void_shuffle(st, 2, l2_shuffle_body(2, "", l2_d2))
    st = l2_void_shuffle(st, 3, l2_shuffle_body(3, "", l2_d3))
    st = l2_void_unmask(st, 1, l2_unmask_body(1, 1, l2_v1, ""))
    st = l2_void_unmask(st, 2, l2_unmask_body(2, 1, l2_v2, ""))
    st = l2_void_unmask(st, 3, l2_unmask_body(3, 1, l2_v3, ""))
    st = l2_void_unmask(st, 1, l2_unmask_body(1, 2, l2_w1, ""))
    st = l2_void_unmask(st, 3, l2_unmask_body(3, 2, l2_w2, ""))
    out["l2v_honest_outcome"] = l2_void_outcome(st)
    out["l2v_honest_card"] = st["card"][1]
    out["l2v_honest_hole"] = st["holeUp"][2]
    out["l2v_honest_audit"] = l2_void_audit(st, l2_reveals)

    # bot: duplicate-point shuffler -- refused at post time, named directly
    st = l2_void_new(3, l2_base, False, "")
    st = l2_void_shuffle(st, 1, l2_shuffle_body(1, "", l2_d1))
    dd = l2_d2.split(",")
    dd[1] = dd[0]
    st = l2_void_shuffle(st, 2, l2_shuffle_body(2, "", ",".join(dd)))
    out["l2v_dup_shuffler"] = l2_void_outcome(st)

    # bot: rollback replayer -- an identical re-post is a harmless dup (the
    # state does not move), a DIFFERENT re-post for the applied position is
    # signed equivocation, named directly
    st = l2_void_new(3, l2_base, False, "")
    sh1 = l2_shuffle_body(1, "", l2_d1)
    st = l2_void_shuffle(st, 1, sh1)
    st = l2_void_shuffle(st, 2, l2_shuffle_body(2, "", l2_d2))
    st = l2_void_shuffle(st, 1, sh1)
    out["l2v_rollback_dup"] = "%s,%d" % (st["last"], st["applied"])
    de = l2_d1.split(",")
    de[0], de[1] = de[1], de[0]
    st = l2_void_shuffle(st, 1, l2_shuffle_body(1, "", ",".join(de)))
    out["l2v_rollback_equiv"] = l2_void_outcome(st)

    # bot: wrong-scalar unmasker, no DLEQ -- every step is individually
    # well-formed, the chain completes OUTSIDE the table (deferred
    # attribution), and the mandatory reveal audit names seat 2's step
    st = l2_void_new(3, l2_base, False, "")
    st = l2_void_shuffle(st, 1, l2_shuffle_body(1, "", l2_d1))
    st = l2_void_shuffle(st, 2, l2_shuffle_body(2, "", l2_d2))
    st = l2_void_shuffle(st, 3, l2_shuffle_body(3, "", l2_d3))
    st = l2_void_unmask(st, 1, l2_unmask_body(1, 1, l2_v1, ""))
    st = l2_void_unmask(st, 2, l2_unmask_body(2, 1, l2_b2, ""))
    st = l2_void_unmask(st, 3, l2_unmask_body(3, 1, l2_b3, ""))
    out["l2v_wrong_scalar_outcome"] = l2_void_outcome(st)
    out["l2v_wrong_scalar_audit"] = l2_void_audit(st, l2_reveals)

    # bot: deal staller -- provisionally named on the timeout; the audit
    # re-verifies everything signed and keeps the staller's name
    st = l2_void_new(3, l2_base, False, "")
    st = l2_void_shuffle(st, 1, l2_shuffle_body(1, "", l2_d1))
    st = l2_void_shuffle(st, 2, l2_shuffle_body(2, "", l2_d2))
    st = l2_void_shuffle(st, 3, l2_shuffle_body(3, "", l2_d3))
    st = l2_void_unmask(st, 1, l2_unmask_body(1, 1, l2_v1, ""))
    st = l2_void_timeout(st, 2)
    out["l2v_staller_outcome"] = l2_void_outcome(st)
    out["l2v_staller_audit"] = l2_void_audit(st, l2_reveals)

    # bot: deck-stacker (against LEVEL 0, spec 12.4's own list): a dealer
    # who deals cards the committed stream never produced, and one who
    # re-chooses its seed after seeing the others -- the spec 7.1 step 5
    # audit names each
    stacked = dict(holes)
    stacked[1], stacked[2] = holes[2], holes[1]
    seeds_hex = [s.hex() for s in DEAL_SEEDS]
    out["l0_stacker_holes"] = l0_audit(TABLE, HAND, seeds_hex, out["commits"],
                                       3, stacked, flop, turn, river,
                                       OCCUPIED, BUTTON)
    bad_commits = list(out["commits"])
    bad_commits[0] = out["commits"][1]
    out["l0_stacker_commit"] = l0_audit(TABLE, HAND, seeds_hex, bad_commits,
                                        3, holes, flop, turn, river,
                                        OCCUPIED, BUTTON)

    # -- Phase 5 DLEQ: the pinned honest proof (over the pinned unmask step
    # v1 = k1^-1 * c0, i.e. statement c0 = k1 * v1), then soundness proved
    # NEGATIVELY: a wrong secret, swapped points, a tampered commitment, and
    # the honest procedure run over a FALSE statement all verify false --
    # the last one via equation 2, which is exactly the wrong-scalar
    # unmasker's only available forgery.
    l2_proof = l2_dleq_prove(l2_ks[0], l2_v1, l2_c0)
    out["l2_dleq_proof"] = l2_proof
    out["l2_dleq_verify_ok"] = l2_dleq_verify(l2_cks[0], l2_v1, l2_c0, l2_proof)
    out["l2_dleq_forge_wrongval"] = l2_dleq_verify(
        l2_cks[1], l2_b2, l2_v1, l2_dleq_prove(l2_ks[1], l2_b2, l2_v1))
    out["l2_dleq_forge_wrongk"] = l2_dleq_verify(
        l2_cks[1], l2_v2, l2_v1, l2_dleq_prove(l2_ks[2], l2_v2, l2_v1))
    out["l2_dleq_forge_swap"] = l2_dleq_verify(l2_cks[0], l2_c0, l2_v1, l2_proof)
    out["l2_dleq_forge_tamper"] = l2_dleq_verify(
        l2_cks[0], l2_v1, l2_c0, l2_v3 + l2_proof[64:])

    # the proof wired into the unmaskStep record (spec 7.4's reserved field):
    # on a dleq=1 table a proof-carrying honest step applies, the
    # wrong-scalar unmasker is refused INSTANTLY with direct attribution (no
    # audit round -- 7.4's "impossible rather than attributable"), a missing
    # proof is itself a named refusal, and a lying commitment key is caught
    # by the audit's binding check
    stb = l2_void_new(3, l2_base, True, "2:2")
    stb = l2_void_shuffle(stb, 1, l2_shuffle_body(1, l2_cks[0], l2_d1))
    stb = l2_void_shuffle(stb, 2, l2_shuffle_body(2, l2_cks[1], l2_d2))
    stb = l2_void_shuffle(stb, 3, l2_shuffle_body(3, l2_cks[2], l2_d3))
    stb = l2_void_unmask(stb, 1, l2_unmask_body(1, 1, l2_v1, l2_proof))
    out["l2v_dleq_applied"] = stb["last"]
    stb = l2_void_unmask(stb, 2, l2_unmask_body(
        2, 1, l2_b2, l2_dleq_prove(l2_ks[1], l2_b2, l2_v1)))
    out["l2v_dleq_outcome"] = l2_void_outcome(stb)
    stc = l2_void_new(3, l2_base, True, "")
    stc = l2_void_shuffle(stc, 1, l2_shuffle_body(1, l2_cks[0], l2_d1))
    stc = l2_void_shuffle(stc, 2, l2_shuffle_body(2, l2_cks[1], l2_d2))
    stc = l2_void_shuffle(stc, 3, l2_shuffle_body(3, l2_cks[2], l2_d3))
    stc = l2_void_unmask(stc, 1, l2_unmask_body(1, 1, l2_v1, ""))
    out["l2v_dleq_missing"] = l2_void_outcome(stc)
    std = l2_void_new(3, l2_base, True, "")
    std = l2_void_shuffle(std, 1, l2_shuffle_body(1, l2_cks[2], l2_d1))
    std = l2_void_shuffle(std, 2, l2_shuffle_body(2, l2_cks[1], l2_d2))
    std = l2_void_shuffle(std, 3, l2_shuffle_body(3, l2_cks[2], l2_d3))
    out["l2v_audit_ck"] = l2_void_audit(std, l2_reveals)
    return out


# --------------------------------------------------------------------------
# Pinned expectations. Regenerate with --print-pinned ONLY for a deliberate,
# documented protocol change (that is a consensus break: every client must
# update together, and kHeHarnessV bumps in the harness).
# --------------------------------------------------------------------------

PINNED = {
 # ristretto255: generated from the pinned libsodium (SodiumXT ABI 8) and
 # re-derived on every run by the independent reference above.
 "ristretto_generator": "e2f2ae0a6abc4e71a884a961c500515f58e30b6aa582dd8db6a65945e08d2d76",
 "ristretto_point_card00": "d4976d032129eb3cc15bb2e700e0f303c46bdb8a4874d009dc03405c3fdedd4d",
 "ristretto_point_card01": "48a187d5d40ac12e4b95efe4d1c50e099efd7d5b1c3f9d881c32a51a6df6e70d",
 "ristretto_point_card51": "ac60cf25f6b43db094e469884067af3ab35d8aab89d67d573ed1dc7d6da9a304",
 "ristretto_k7_card00": "e4efdd42fce9e2cc212ccf6aa307b6bba55ba8f9d2b33103721be7fead96964c",
 "ristretto_k7_inv": "22d5909fba32273143cdfe848dda1f4c92244992244992244992244992244902",
 "ristretto_unmask_roundtrip": True,
 "ristretto_ff_invalid": True,
 # ABI 9 follow-ons (SodiumXT's DLEQ/batch surface, 2026-08-15): generated
 # from the pinned libsodium, re-derived by the reference on every run; the
 # base-mult of 7 also equals RFC 9496's small-multiples entry B[7].
 "ristretto_base_mult7": "44f53520926ec81fbd5a387845beb7df85a96a24ece18738bdcfa6a7822a176d",
 "ristretto_add_c00_c01": "34722b333ab7982fe4d5e2be2913c316db8f8675de2394a5cfb704abab7c8b4c",
 "ristretto_sub_roundtrip": True,
 "ristretto_batch_k7_cards": "e4efdd42fce9e2cc212ccf6aa307b6bba55ba8f9d2b33103721be7fead96964c,c4aea78979e6929435b9bfcc4dee30d0dc714c714ae28f5e3c44cc124625a345,58907d49b012f75999ae4231e156cdec4432851939532b1e1278f900fbfaaa2d",
 "ristretto_scalar_add_wrap": "0500000000000000000000000000000000000000000000000000000000000000",
 "ristretto_scalar_mul_inv": "0100000000000000000000000000000000000000000000000000000000000000",
 "ristretto_dleq_identity": True,
 # Level 2 mental poker (spec 7.3, plan 4a-4c): one complete hand from
 # fixed scalars, plus the void-string refusal vocabulary -- computed by
 # the l2_* mirrors over the independent reference, re-checked on-engine
 # by heTestLevel2Run against the same constants (--gen-xtalk).
 "l2_base_deck": "f43e364e1c1a4da57953b755e62e4a21c6ca54dad6c8afdd4fe527d1fa0f1471,e2b5c63bf1cb966f79bb5dd8049eb0fca145588b5128a6f7322acd1012e45b7c,ca68072db08307f62268023fb580e8148aea78f8b87e7b1d2691a922b5245446,b6e6777a5bf7657fd842629a537b02f06bc9e9c202d51b27cdd550b61c8a8a18,d68850b61f37953e920659d48ee504a51addd0e26996f0719188dad7f37fa52b,0c4a3a1a25314e3144391e6133bc6c7b135fae6673fbe9a0889dd5ed477c171a,4acd93b546fc640606953a84123707ad9a1617357d00e5f763084daa6a0d3840,dcfd9215cf8a022e2198e87af9f4c08059504ffb309a6dd1ff97917b6012902f,a825c649a65028cfa090453b8f8d7c91b5761a4df3c3a099105f764d05bbfc79,a2751a23688be97fee506a367e917f2d1b0b8445d56679fb66af2aca3f1dbc04,e2fd88a0a2bf8ec954e1bd7c637e9c5e810195e3614a09ee400adf6d8cb8c856,78f3c83c94a84614c0589b3f58269687a539de6a4cae5c02449f95bf6a46a46b,a40fdc57edfa2dc321608b50e782cc6f0907f65eada0ad48a25a00f546d0987a,22830c692615fc4b2a8ef1e3f8fbedc51a720107e359f9d2c1af737699af733b,d8ee75f4266debe97bcb495971922583ebb97ad60b78f5e9c1d187972bb1ec1b,44744fa706cee62e39546bb3f60b86c8563625be486dd73ae41bab0fd1a7cb00,4cd2d796f2e9e21c10b4db346d08ec53bbc7af1338f605d1d7e9a5244500af74,4aad6f63cff471e83ab8abbfefc7c52c4ac7e38eec8bab874a98db796b69f710,6ab24c9cd511a4fed28e34f86a40198700626511d05fc986eb5c4e0ac0688245,1a815ccb611b5b5fdcece3e811bf479e6d866f5211c4222766008c7de0b3fd77,40ebc4540b298dec8b107d3465bae5b4298c0d9dd0b052b6ee35085a15967043,1e7bb71f06a5a72d4f6dc5f0e5131b3ed38f344ae8afe4ab6325bd71d97eb770,0e6ac715b89c1b7350d1216965122c5565009b7d9140e0090c4041932c8a5a35,72edfa2243b1b418c24d89f6c7cc3444367945ead40cc152c1a02ed74b894d73,1af2d8904604eb9de539209d048932660026be3e09f1591deed8475b466d9c1d,98afeba72c1aad9ef62bb78730b25e81fb8c0f0aa496f5f558d4a401fb08dc32,2436bc86ba0f7a7a065a61e572021e4ba2f58edba7cf529d0f2fd9c852938d6b,36ff7c85101d8f18a8a98e16d225b56904ae11e5d4b3d441b0213237d274ee1f,9e3d2f7ba70b89df9fbeb9be41281e3738937f124195772e032c3d1fdb78f855,1cd179e72cb1b79eec94f4a249cb7ca303be533cf60004d22d18847ea06b6f74,ee9bf366559e64e3120c89a71b3a3f5157e901b52035c77add57f1e77631c621,62bb8617c9d4a3868b2685d0b68251a7ed77a438835f3955a809cdf991da5144,64b530ce023f8108b30706674fb1d50bcaec450e24b2eebebde1d0039be87b3f,6a88be3b6e714f8c47eb879456ee5343a54ad0090b1f8efa2ee3c55654b7cc16,146f81383fd8305ceec4ca6d3d59cf1358ef3333c708b6e6bb4d5dbd7cebb335,ccdf0af1f4608a4186a2ebddd4729174fb696a72606c0205bc237a181be2e006,248e4956f6625bc4e38f1025413893827006ec904f1d9e48f5bd8b9e8cfe622e,569050be976d1b9f7c3bb79534202819d33b2f747a04b34b00f74e4533f3d534,e686afeda75fbafe47f550a9914e5872f867fd144be9727906844fd7a5efba76,46f0ee3869ccfbd02973504688e82360867cead0540237b88cca8dd64ab8653e,feaa1f3bbfcd9f3e3428dc887d61612bab06635b7991abdd34ec69e01cd21a09,7ac0547ac2ae5c08f7b7dd14e1f2fd46d4110cc464c54379ed738e877bcdb42d,0ad5483deee6ec96989b844a54a52d93fdf9d61aa1c8bad49de64001e0aa7e42,7228ec86b2507b1f73de6668f23b68b01af1cbd1a18bc74b56bb98e0d1044d32,d070da71ae4c8f56464e6a9f0c0a7265f062de5047bce758957a37c3c06b4272,18b94704378b8065af2d9603b0e7a350105628025c8093ad9d6991c8efcd747b,967b07c684c6865789f35f3d3aaa16fae3f7d16d82b13dfe9c06fe79cf6f8578,a4467ecf421b21ff1783d95a45790c51a5904d0da89edfccf0c142e07b558901,fce090799a09255f8066bc186f716f53b7df53a54c38e4d4f83ce7a9800cba6b,d0f0a3ca37ae84285a38836c0abba3536af53cfc32ca1681347baec559f47b7b,88ce578d9d4f057a76486e5f2e15fce75b1d07ea6d23efcb5d0ed421e1d35c37,50532c4ee88d1439e01a61f151c2f25f1ba2319c2d32f943ecfb1264d03ed72e",
 "l2_base_deck_check": "ok",
 "l2_deck_p1": "a8de3428db2d1cb591341ac375bbdb0581bd46f80d2804e94e71710a3b48541f,6208a4235f8ae00a67e3c8f0ebbbf2c97fbcded0363569d684a174c9f9c33472,d80f7d6653463748864517be750974916e0139fe3afcbd1a5e05481471d1e71e,0cb1f4e9cc67e1d58c88b5141f12c64caad25c5cbd5641ed6eb7433ffd9b236f,aca2977971dfa44ef40e9086ab5b58f635f25993d91d1c9eebec806b42e2084d,b42c199b8688e4fa95be56db11c0f269defd692ec3d56726055f4f2e3bf15c22,be8fd78c93e5096e7f156a4b6401874965065c9a39abdb57d2e278b5252cae03,b83bf82a7d4192df111443cde252d748245569be844c373078c97b3c5c21d042,380662f5a44beb9168bad94af183a145d6aa68330087e47c2413e1c02255ce7b,880321e01b402cab8e58739e24b8650502e87a1e53a728f4c7120f85cd79ec31,c4a33acbf3a9748e75320863de31088d2c156358797f55c1992e11ea95a5e768,a610eeaa66e3a4f799ab05ad0a5791ccf155fe9105815c8a5a27341cf00c3e20,ac94ae783e70f5b4db4e723283815cc2266fd5def3d0063ac58f50444e6e6620,ccf2a5e4813136eebc70cc00c8452d587701f378214aaedd1ed577a7f1c1020f,2ad863fc5aa197b4c35efccdb87379ebcc84a15a046bdf7fab33ffb9acd1f759,9ac91cad66318f80906c50bc9c2161ff4204fdd5e573a71c9409b5e92ecfc446,06c97bc904c39b8f2f13833ca41b376d0a70df99c3f48ce81c63e827c700b135,82c2bb912824f452cb8d62f5acad8b700324d13083016ade60dbebd0e24adf16,4cbdb1a1a87e1b2087df92f229a7e3d646f841a730275f3a355647b79d4c726f,202a2868ad6d3b99b4646a08f4f571e2373221ff58df7af32ce2801d1d725770,dc1d10c111206bc0e777e46a9fd5a56a2df56f37cec67f5261c26aa12a2aa937,9ef54cb33db9d77c664069f15bf54061ed01e075b5a5846bff366acb7f477d37,30dec7a12b6fd2f973683dfa053865fa8aa3f08ea5325a10e27aad97020bb729,6aae1939f32cc599e76e968455a30ce4d82280274ddaa3da099226aee642b57a,cac50035ec7bfe2a6f0091969ce08045b28b5fcaf6502d8aae107557e3c3e109,70337dc2f81c273be97d83f42e8f36ea03acec7451c0f6472155ffc4ac0f3518,02bbda5b5f1987ec365739fb37c2a599d2b725bedc0c204deb31fea49b5a9c4b,b4eb5d98403b1e5276994305fca33f4aa508978ed4edd923f18616783458b118,90f8bce01a01e5b30373962182b648c731452a2ccbfec2dba91de8fb022c193a,12cf3f7c4cd5cbc9b1fac833454ef6dbbd7ddd139bfa3812ee19b2bc3a34753f,24fc8edd6bcccf04c49b2b4b337131f6d4fd4d36d1b1c4ba6ed1a24ebeaf581b,98063c80c1bfa451e791f19fbb52723a302c94d16dd01f52425b6a496413785f,6e161fd50766cbd972d31ea5fc0b90807a4a103bf79b9766427cdd7fc4e3521b,8a835b4edd4375f1e2e908f14f1a47ba48e2cd499dc90a64040333d9c9344a74,94deccd57786903f49e7783e30b373781ffd162eab5f095ebdf99f088a048e4c,f0e6fd4c43e8647095384db6e110202c691408d6c9be53f00b4b13023a24d217,b61e937b2825e50de783985a69279b1e07cf45b2113c4ada5a78b8951f57ae0d,2239b5510058e2962e0bd9cf17f54fde38cb3d76f0503ce5ec4e132887c9a571,10135c31a39b36a2af83c0a0ff759facde77bce17b6350579c706f656486a10f,acdee51d73bdf6ee8613c73739d7c897d97a52fb9c6c4a0104395ea4806f2047,6ad5cc0f70a07befcbfbd6abcdb0279a579968e51555c36af6bc6b2bb0f6a010,aa66031a9585d3487f62170ad6bc236d81dbdeff4e0287dcce6e971afcfd4150,205f6e66b3d54d4e23e7be0512194444a13e76ef53bc032773e3eb1ba615015f,1cad41fa4896a2192cb96763568fd7b0b1a17a641235c571d6b9f735f970d800,fa91391acee3da6ce5beb220842c6d3a89b127d898915d78569becf98e42c405,92fd398554c27e6d525f6ab451a60bd34773fb627f5ac5e335ba26ba01d30c39,c202fb60a22eebdf70b871f93f0c871b97a602f2c46e77c9bf6517e5eac87677,2ef2dc398f3c20aa0d472c7be964b1450c8aea652cbc950a0684559328771371,e6ac5b83882b4f694775463dcfa35b30e269be84200826242615191af8072b7a,d4e11d4f0dba15abe5ec94e448871bd11e00e7c5f8c301a5573fbccd3ea2cc04,e4e0dfcd6cf502920991dd5789504d3b4764db3ca8b5a7356d6e1fdd70ffc274,d69d1e07c98931eea27cdd197eee2dd78d2d787adfc8c21dfef0968b9aed5d07",
 "l2_deck_p2": "e00af99f3beffe9abefbd2f231aea944d2fccf129b8f455b6e67cb58f2c3096a,ae24f004bdddd625f0a643e1d33fc1674e9c3bac75eb6e353408cf6dd3e28f47,0e9979a00df7e9e4eedc7070d41b9a1246a3c43bd8bf4e43fc121755c2d2b86b,e6b15193619e11214d7ee7ecfe60bc9ad1f8384cb2963f85da1d3da00a47d72e,06e16d4dcabf7268a4d7ca91778f561f74ab76e756cfacdb6870fba17f3b894a,faea0cee68bc0c5072fa39ae3b4ac6c597702d060bd87ede907449be0b64b157,b8824ddcb814e807c60a9297e746be6528f2c8a33d6d7425b390be0df7c22a48,bce6e67c2e4ee8c80e8181af31288b4cadf0c5867e30ad9bfb2adaa66448f37a,c6d0359251b9d4faf957a2d0b656ad27ab9b5246a1f18f6e41b2f0b1f7f9c556,deb78cffc7d25564d07cdf504a71c60ed0b54219a769aeed282dffb8914adb5a,36586151ff4e63bc47824eeb63b1e0fd4bc67462ccf89c9899851bb401c5e70d,8615ce23a2b4509a1800d748325b11c20c2a2ef10e77c5303ab275d9c7505e73,a47a577fb3d554c5e49e8187bc30ef6018578faa6e6e112d5af2ec931315a65c,9490f37338790e72385d8d7f76bb954fe659e929cd2485f2910a3010d9ac115d,1826c8ee89f904ca2577326e80b1654a7e662acfd07406463490f4ca48c27f17,5c10e877642c1955d8385850c7eabea26df26b03463226929fcbb3c18ab66c76,3a03c642c57ead3aa269873b1195890461298f7b8022ef625958628cab9d5c09,18be0cf02a5fe520fe4047543a80fbf85506e7674530efb7e5f4ed9602a6770f,7c2cef9b4689c5e8c96a30346fbb4f5a9531361b7f227591e2834f230c1db419,30885fa1e9bb9066a31702c897b89377084fff6ed01bf3c9cb7ecef01ac3f20a,6a15e627d1e1c1fb927bd330f89503686bb4305741048a10382d6ad984ea861c,c2d28176098eb290daff9de21c01636586918164a070b666a729779e0e6dc46d,5c58344b00419d09fb750a7eef9a3a688aaeaf8e29bf3079e88e345aae18ca70,da6597739f21dfb7ef8cd2a402ac1e770d1018c08abfe96219368a85e2ac2903,3e8050fb3b185b865ca987ee08be52494a035a230b89e8ce852bc283d4c20a06,460e303935ca04266f9626ace031b5f1e928d8cffca26b49ad4f486fc3a92e34,f45000fb031a8647485e4911402dd5ae913bc675899915814a6f720ccc629c33,8a0a106db441695d3933ea3f0b4fef9a75434df805039ecbd845c056d6c07418,b2f4cfd105dd5ca3ef6c7bf57ce4ce9ee3907e47b927368e15aef1b89af0ea20,be362873b7d4e5c521903c9f96b28a2bac0e13cd07dad037da5863622d413970,1c31ac9c7e3812c51ea92daf24b50e4f1678e1227c5ebf031917b97686c75c3e,a6f76fd16b8c42eeb6e8aad371597b99d518e8ed903b2ed124aef1eee635e741,d8f24dc6c0890853646a0957cedecdccc97a7022f6ea1a85b6b249bc8a8a0c34,54dedffafd1cb60436c3fee9ed0dc3d1d0a987ad155993b7672ae07ebdc61d39,9ebf56f94521dfd25213ece8a86e3bee77139257654ae89c915267e0746e2d7b,7a0727ff61fd28537c96efb5c81710a267829215a2683f937cfb4b686bb8b539,9c2a0b5428a1c49aebe500995bebbe6f6b91c9ca122da94ba24fcf385e10fe7e,d671de58d85464abf5362086fee4817aac2a7e92f22174e84c44257c67749f5a,2411b826041538f996111d9e0ab256aced1bf88981ef0f0f243d4bb5260a5744,a0e8b09473778a59871c1e9c3637a522add088a56bc74a497241c5714f0f9b15,8af16ee8aa5e55fa7ec2c6f0c8353306736d0e1da5ace2e7033e6e31538c7f08,ae28e51d1124c27c3acd494064b3045bc39711889e7be95ca8c9279c2e455c14,54f4077595a2126c8204af53bce0959ba4863094d880be4888bdef1407eb650d,949d731f469556c556340857a735caea5b030453accd0155295de1b987f9874e,a4cc6aa1a0e9295d2f1e99dbf18ff406ecc8df97c9859dfa5ba644383be97b36,ea87bbdb383740c640f64d3225a76c9d8ec9741c7a6a89da602bd18d35ce022c,94083645cdadff3632b0f84b23332270d2a8fc952f883e56db53cbcf28a15631,6070052819345375bd2f4c3e64bc87f84b378367e72dafc340d9dc32ed95cf3c,78a9f206be2a991fe9969ffd0fb90e2286c347f55498a1862117159df4ed6876,46e83cc0f3acdac9cb1ef535927f0b8b390982b8e8ca1edd7e9e4414b6a4f72b,b698b194d9e75a6f7c91438a0308548005cc9f5503aa925ec51c957ae0b80a31,1c32c97abd536960b335394e3f1a9896297cf6a5aa410ebb89c570eb2005b175",
 "l2_hole_card": "card:47",
 "l2_hole_chain": "62e9d101a14e45cbea8506f23a225d6da973a3edfede81a99b7e81c3b9957827,80b56b50f6eea1ab201aaa93c738dd6441f5842f256bb890a5ebc867e5807c70,3a18dfc38fbbce3503f1fa5b45ba7b88c547799f663ecbd38d7474aa2aadff5b",
 "l2_hole_penultimate_card": 0,
 "l2_masked_deck": "1c4a4cd95ab5df7e3fbb801b47c156e726bc8ffef83cb6892e979e12f2f40a18,62e9d101a14e45cbea8506f23a225d6da973a3edfede81a99b7e81c3b9957827,ccbd8b67ded62a4c617adaf2661b6a5f3b321f8ac82d4ed631e174f17e016872,9087ea23c9a04974739041651d08ffaa60c83fe30e93c37ead172ddaeecea577,520321aa5411f0102d9854d7c36d0d9c0d218634c44655b99a3a78256178e774,8c155652fd2bdc7f3b1bbb3e960d9eb5097366f62c924b1c92bed58e945f9f19,1ed3f96f1a7d03fe3da78c54c209ed98aa2f2260bc5ff290ab9cb8ce1391ac0c,b632f200ca5decad5e041fa1d2411ea3555cd46a4b64790ccfe0c70c4de34a0f,9a4602b46bde2c6c860f9e7b9562ce87b62053c75daefeda0ffa3d72e13c4a05,4476b7e54b72b9abda47c42c7a0b55676acb865a9949119d2814a028b381bd10,4a0bb09499996a33d379909b8b7f1c6b48f276c76d7213abc82e920b2155872d,1ce9352e0a5505d7a67c00e0139bcd32ba585c84e416310e92eaccd4ff10245d,dca2411b332e647eec34df62d5fb8162d850bb831a115d1e71d51dce55eed626,56ba017c3ad1ea1126093efca04c749d085112132a578ec755d23a777f982f23,6edb77fbda06a59d0afa90686f9945efa863434424f74a1739c3d5153015f357,fa8273b7c9a231dfeb3ef71bc77788e7d357f292731c79cd2c52ef76acf47a29,c0ba5d3b244be2b869252cf23988a8063908520ff3e34ceca71cda4bbbc84b04,a8c3d44a17fbe150dedf35fadb9f3d5a3fbcf400f20994b4f0e1620478301a15,5e3168d6f5106aca4fea6916765ad28931aeba746d4e5c438e7257a053ec255b,3e59ef03c2f78b1c0be06501b254cee66608e3570dd08c9f16a2256f0585e476,20c2fcd252741106fc6bac82a30dccb3d9bb05f4c65891ebdc81d20cf4c6831a,5a954722e48f2a0534a26271ee77809fe27111152e77c161091d5c78476f6819,b42ba308571bd4f27052bf38ec82b50755dd22d97832cc4eb784630264d99638,a871a574b10e19d6431ae82e6f3d67571e29225e137d44821e887e1efceef715,a2d8ab119c8a7c9f2746cff786f8514fee315631e54c1850a20389b2e2d57e0b,6cc6bbf761404aca110b92e36e637dd5a8bca799e5680077654b0d0f192fa554,7cb1aeacfd37b1d7809c7d269c15737c7f746507c4358a30291c40a0efcfc13f,603aa0b85684a71fe8be7edbaa26cab094c4633df389f818faa6d1dbe69a4a51,2af6de55fc37181ad678f8dcb141c365f875d9a571b8e9727f8c963066792e62,38b0fbfdf0cdb815094dae6ae1ebe102125d5fc5933d2bf42ce9bc2bddd4eb0b,38f162c482282626597a32d0eff26dcadc22ea38b1e107c1934b905397d8b973,9c5f3d94578d122f329b825a8563b03d12b2e5b96916e83f1ff00264df8e9c67,767ac5e92db1ea84be5cf73dd70a39c61a7024e3464e109e36ff2c62b14a7235,308cdbdc2f3334271ef4d25e7f7ecc8933b5918ddbe819bb3484d3fa02325c27,8e8544127ae68c2a8d18a9c8cb8d37a76758916286ebf17597b17b9283b5f909,c0ddddd1e00241611d3c045b85d45b0fbf3ac2ae0078fd928da2955579339920,48c8be8d6374e2763cf6ab51e9a84863ad9d322098006243c8e1eaa318479e78,b49934b95c8748348fe21a30f191d080c805aae4e3505555f324b6974379ab68,bc2c0a3edf2c8f9c761980bcf13d444455d846c2a137a582ca8679ead71ee604,b463da981cfef69817ab80245630bf70deb604820fc87265719410f72462de35,6c7dc076178538735f5e1a890a21f054a9d81039f72424b65be5b041b5c3fa4f,8015469fa91721b299a3b6f7522478398820085127429312e17d42e5a40a462a,9abd2266d21ee49b0a6fc227a6ae21a8a18e8f0019eaf35933518d61f71c4052,d4a31d2d53796a3ffa6f12de5ed0de6cc2131a5d811c6b55505a5e58317af20e,b4e06f3351546a873220664a0585c506524e605453d9ea7d0de46bae5c90ea24,f4383b63dcb04aa7d70595c1450cad7842552095c31328d1c2ff3a5b3469067b,4876092cf6739c17bab348b6ff2d05feb8d00ecdcc865c5c17154b80f157c301,f4bb4c89cacaf8727fd11878f03b9fa47cb1645f5db293a656d3ba3b2641bf3b,da8fba36a6c821b0125984a1b9432c0911849f7fe6183c98abd940dad8d41b41,7247827e28f0b6116ec614a4d713f49ac291b6112f4ad0dd5f3a4f92bc331c02,feef6df7bf025f0f0b77c2fd40da954c44be8b85ccf943301e888e783a312307,e625479c6e3b0e1f1bafbe6f7e7630bd8c7c8c583e802b9282255bfe27574136",
 "l2_masked_deck_check": "ok",
 "l2_perms": ["35,31,39,27,36,51,26,11,7,49,18,9,28,24,40,50,25,44,45,34,15,2,13,5,41,3,23,12,33,6,29,52,20,10,21,42,17,46,8,22,38,19,32,47,16,37,30,14,48,1,43,4", "30,35,31,18,7,33,4,50,38,19,15,2,29,44,49,16,22,51,47,9,5,10,25,12,6,21,52,24,14,39,8,3,20,37,43,36,46,34,40,26,23,48,28,11,41,42,27,32,1,45,13,17", "22,14,28,2,48,29,37,23,52,32,38,25,30,47,43,5,11,3,39,20,1,45,50,21,51,27,15,4,9,26,24,8,19,36,41,35,18,49,7,13,46,6,31,34,44,16,12,33,42,17,10,40"],
 "l2_public_card": "card:49",
 "l2_public_chain": "1c4a4cd95ab5df7e3fbb801b47c156e726bc8ffef83cb6892e979e12f2f40a18,dccce0c6d9e263337316e3487d17796b76d3057c9473c40b95be7b4b78a10069,54a040c81ab1aca13bf76c725416660af35c171209001e3abfb7aa6f56e2ce24,fce090799a09255f8066bc186f716f53b7df53a54c38e4d4f83ce7a9800cba6b",
 "l2_reveal_shuffle_bad": "void:shuffle-mismatch:7",
 "l2_reveal_shuffle_ok": "ok",
 "l2_reveal_unmask_ok": "ok",
 "l2_scalar_invs": ["05e469c6d0880a9b8e27c9cfc6b887171837d1c5b5e01a9bc0320fe70a64bc0f", "5211b8e991092be89603c8b33eb590833774d63832f1294b7f3dc2b312112b0a", "8cf1653acb11f8ea598fe0918c83210d1282a4218f4cf9546a5907f3401c6403"],
 "l2_scalars": ["38f967b55df92422303a885e0bdd8400e52e6ca53623f2c816bc08ce6b7d480a", "04db114cfbf9228a88b8533a2fd8f7b3d023db8adb22abf3ce804a33d105e804", "380b4308d6301ffd7c124b79b15ae31343e221dfc77d6bb4c1ea48de8f34810a"],
 "l2_void_bad_final": "void:final-not-in-table",
 "l2_void_duplicate": "void:duplicate-point:1,2",
 "l2_void_identity": "void:identity-point",
 "l2_void_invalid": "void:invalid-point:2",
 "l2_void_mask_invalid": "void:invalid-point",
 "l2_void_perm": "void:perm-format:1",
 "l2_void_wrong_scalar": "void:unmask-mismatch",
 # Phase 4d/4e (spec 7.3/12.4): the pinned record formats, the void machine
 # driven by each scripted cheater bot, and the audit's attribution verdict
 # per attack -- re-checked on-engine by heTestLevel2VoidRun.
 "l2_cks": ["f8aaee2dfe3f251d8726037421fd646a85446b00f132dc37d0792a7e48a08a03", "94d02c9027dffcedbc3fca0569b23d13fc966462b5208b5a25668ddefaa4ea65", "9ce4b6a7337e94a6c60535fccf71ee83a69745b46359fa9bd0a1846864ad1458"],
 "l2_shuffle_body_ok": True,
 "l2_unmask_body1": "pos=1,slot=1,val=dccce0c6d9e263337316e3487d17796b76d3057c9473c40b95be7b4b78a10069,proof=",
 "l2v_honest_outcome": "deal",
 "l2v_honest_card": "card:49",
 "l2v_honest_hole": "true",
 "l2v_honest_audit": "named=0|audit-clean",
 "l2v_dup_shuffler": "void|void:duplicate-point:1,2|named=2|bets-return|reveal-required",
 "l2v_rollback_dup": "dup,2",
 "l2v_rollback_equiv": "void|void:step-equivocation:1|named=1|bets-return|reveal-required",
 "l2v_wrong_scalar_outcome": "void|void:final-not-in-table:1|named=audit|bets-return|reveal-required",
 "l2v_wrong_scalar_audit": "named=2|void:unmask-mismatch:1:2",
 "l2v_staller_outcome": "void|void:deal-timeout:2|named=2|bets-return|reveal-required",
 "l2v_staller_audit": "named=2|void:deal-timeout:2",
 "l0_stacker_holes": "fail:hole-mismatch-seat-1",
 "l0_stacker_commit": "fail:commit-mismatch-position-1",
 # Phase 5 DLEQ (spec 7.4): the derandomized proof from fixed scalars, its
 # soundness proved negatively, and the proof wired into the unmaskStep
 # record's reserved field on a dleq=1 machine. Provenance: at authoring
 # (2026-08-16) the commit keys and the proof below were ALSO recomposed
 # byte-for-byte against libsodium itself (ctypes over the system library:
 # scalar_add-reduce, base-mult, point-mult, point-add -- both verify
 # equations close, and the wrong-scalar forgery passes eq1 / fails eq2
 # there too), so reference, libsodium, and these pins agree; the xTalk
 # side composes the same libsodium through SodiumXT, leaving only the sx*
 # call shapes to its OXT pass.
 "l2_dleq_proof": "d84b045c40a2d08257ef6907556d4a096a26f0777b2a8c213db9736e403150048634476eb775e61807679da17345da913e9ae89959a0dd3a5ed121483a4de064c838dc1234a84786a24f5c120cf28dc410b59d28213e74c4befbc1992fbb2e04",
 "l2_dleq_verify_ok": "ok",
 "l2_dleq_forge_wrongval": "void:dleq-mismatch:2",
 "l2_dleq_forge_wrongk": "void:dleq-mismatch:1",
 "l2_dleq_forge_swap": "void:dleq-mismatch:1",
 "l2_dleq_forge_tamper": "void:dleq-mismatch:1",
 "l2v_dleq_applied": "applied",
 "l2v_dleq_outcome": "void|void:dleq-mismatch:2:1|named=2|bets-return|reveal-required",
 "l2v_dleq_missing": "void|void:proof-missing:1|named=1|bets-return|reveal-required",
 "l2v_audit_ck": "named=1|void:audit-ck-mismatch",
 "admit_sig": "17cf45eeecf27a3e9b63e1e0ff47ae1ea337430cb135fb499944a60681fcd1e949a7a88f532b2f888c0ea32364e93e9aa2f569419f27e8034b695a4ee94d5e0b",
 "burns": "Jd,9d,3d",
 # 2e street ckpt + show/muck wires (spec 6 as-built bodies), pinned as the
 # seq 7..9 extension of the six-envelope transcript -- additive, so no
 # earlier chain-head pin moved.
 "ckpt_body": "street=flop,head=62fcd52b3757f590c33bede7330620853074c1e5c153549244a8dac7287e3778,sig=08c7f29409998d642657b9a084802b7ca3a136d696e881b545ed4e5a750fdb6d14e4967f401977aca416f03c0d4f03f98b3acc53e61266f3d8cee9912639e20f",
 "ckpt_head7": "296cfef0944557351fa4899e8da5722743b4cfd212206dcf9a2b89fc30331497",
 "show_body": "seat=2",
 "show_head8": "969def7cb20b499f2ae3fa259234f09ac79cd4608e65b2d25b2027217a82a45c",
 "muck_body": "seat=3",
 "muck_head9": "5fbfd0aeef7d918249601a92233de273809dc1b4791e991e22758ba85af6df71",
 # 2e liveness wires (spec 8.1/9 as-built, v0.23.0), the seq 10..13
 # extension: host-authored timeout act/bid (seat=/timeout=1/bank= on the
 # EXISTING wires, never a new kind), a seat's own stand (sit-out) and
 # pub-less sit (return), and the onion hello's compatible trailing-seq
 # trim mark for the auto-redial resync.
 "timeout_act_body": "verb=fold,amount=0,seat=3,timeout=1,bank=1",
 "timeout_head10": "bb5c70e38815d017dbcd3be3654fd8691fd2513bd816a5ab33659e1103fed694",
 "stand_body": "seat=2",
 "stand_head11": "fc854db9ed13c5dcaf7ae7455678c87b4a0e1a6286e88ad98dd61dbf173e8ef6",
 "sitback_body": "seat=2",
 "sitback_head12": "f69afd084f98085581135c43346641dea04f2937952becc641e9922709ea6cdc",
 "timeout_bid_body": "amount=2,seat=3,timeout=1,bank=1",
 "timeout_bid_head13": "6324a6371f62ec9819d0a53acace305c3faefd274efe5db87bf869e1b4a57fcd",
 # the deal-delivery wires (backlog A6, 2026-08-23): bodies hand-built from
 # the shipped builders' documented formats, pinned as the seq 14..24
 # extension of the same transcript (additive; the sealed blobs are
 # deterministic stand-ins at the real sxSeal lengths, because a randomized
 # seal cannot be pinned - the FRAME is the pin). wire_vocabulary is parsed
 # out of heNetApplyWire on every run, so a new or renamed type moves it.
 "join_box_pub": "25e78030eed382878e1b7f67aac76a8fdf398a3932ab8b76d313cf09d2be899f",
 "join_body": "box=25e78030eed382878e1b7f67aac76a8fdf398a3932ab8b76d313cf09d2be899f",
 "handstart_body": "seats=1|2|3,button=1",
 "deallevel_body": "level=0,dealer=1,count=3",
 "deallevel_body_oracle": "level=1,dealer=0,count=3",
 "seedseal_body": "pos=2,sealed=f9f1b39c105158ea01a32b8f52450b2e1a9426941842cbe7e046e3a8478e32d8f9f1b39c105158ea01a32b8f52450b2e1a9426941842cbe7e046e3a8478e32d8f9f1b39c105158ea01a32b8f52450b2e1a9426941842cbe7e046e3a8478e32d8f9f1b39c105158ea01a32b8f52450b2e",
 "bidante_body": "amount=1",
 "holedeliver_body": "seat=2,sealed=3658667e2ead6b9185d65e584fa2373acb0921211b1174c52e6fe3653c475b1f3658667e2ead6b9185d65e584fa2373acb0921211b",
 "board_body": "street=flop,cards=4h|2c|6d",
 "seedreveal_body": "pos=2,seed=f7badd5dc86a8a5dce0984ef43bcb7ec228398e08a854a8a8c455ff895dc8a49",
 "settle_body": "deltas=1:-4|2:8|3:-4",
 "receipt_body": "head=53ed9ccc64863dc05c1b76cd7953e19bba73895b8dd22ea00e6c9ff40f423cef,sig=6c2ae423fd05768c28b164893f566f910e79b9e9953b6efba941e6fc5d9c167cc0abe02aa39cc73d7b6b4e541e965e659dac1aae698d8e3c18dd9f1019a06008",
 "audit_body": "result=pass",
 "deal_wires_head24": "2ac5e70a472bd5e18903b062c8e742900a1589bce12701ecfa18dba188a71d42",
 "wire_vocabulary": "act,audit,bidAnte,bidBB,bidSB,board,cfg,ckpt,dealLevel,handStart,holeDeliver,join,muck,receipt,roster,seedCommit,seedReveal,seedSeal,settle,show,sit,stand",
 "hello_trim_frame": "h\t833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10\tplayer\td02b1e826f4351264cd3a77a1580921495f9c7df5f0f29a370ebb5fdd69b9a1c5c1c9226ae2865919622a266df124ac755b57141a6d8a77e0eb8b6f7d89de208\t42",
 # spec 9 host election: the deterministic successor (lowest live pubkey)
 "elected_host": "833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10",
 # ...and the same election with that lowest key SITTING OUT: a sat-out seat
 # is not a live seat, so it is not electable (heNetElectablePubs' filter)
 "elected_host_sitout": "ad1d6dbbd062cdacf356daf0834471b6246105b17e3b988dd5e7f0db45fb66a6",
 # Phase 3 oracle: service-seed domain separation (play vs oracle) + the
 # oracle table's signed cfg (level=1 IS the oracle marker, spec 7.2)
 "onion_service_seed": "77061b1432063cb55aff898386cfe8948a1655627114891d10e6a5cb5af729e2",
 "oracle_service_seed": "6e027a075cd69ea09e20004167c54c12491c5538f105c138a0bafe49d956e5d0",
 "lobby_cfg_body_oracle": "v=1,level=1,sb=1,bb=2,ante=0,stack=400,seats=6,button=1,act=30,bank=60,miss=2",
 "chain_heads": [
  "a60914c4c335f520aaef3b3a5dace3f9dafc1ab4a26f7e65dde2e880d51ead02",
  "d742f834712a24c4da268dcbc44182e511113370c87302132694faa02cdb3c0e",
  "6082ffb793ad1e5c07fec8d4722f2a5aa730f50b8535c1f4aaaa8d7577e386da",
  "31621b0b88fce5589ad1adfd891fcffa5f8f91454affadcf6e8b7daf91e3d997",
  "91cfb880c55c546f559867c01427856b7e9f3efb5ef2b03d8f5bd4eb9cfb8f22",
  "62fcd52b3757f590c33bede7330620853074c1e5c153549244a8dac7287e3778"
 ],
 "ckpt_sig": "08c7f29409998d642657b9a084802b7ca3a136d696e881b545ed4e5a750fdb6d14e4967f401977aca416f03c0d4f03f98b3acc53e61266f3d8cee9912639e20f",
 "commits": [
  "7623721b5a6372fa974ed62f558fce9992259eb2a834ece7bcea66bce970c0e3",
  "83726c97707155ba2e81f0e5f673dd9e10dfde06e1c8f643bdd8539403aace51",
  "5f043c34bfb7a626581eb8653c88503a5a8524c9b47bdc2e09e37780005e0308"
 ],
 "deal_orders": {
  "1,2,3,4,5,6|4": "1=3-9;2=4-10;3=5-11;4=6-12;5=1-7;6=2-8 flop=14-15-16 turn=18 river=20",
  "1,2,3|3": "1=1-4;2=2-5;3=3-6 flop=8-9-10 turn=12 river=14",
  "1,2|1": "1=2-4;2=1-3 flop=6-7-8 turn=10 river=12",
  "2,4,6|4": "2=2-5;4=3-6;6=1-4 flop=8-9-10 turn=12 river=14",
  "3,5|5": "3=1-3;5=2-4 flop=6-7-8 turn=10 river=12"
 },
 "deal_seeds": [
  "6c10d2dcff41a1a7e8bd9c7530052c7eb91b91808ee5d935e5f56098539eea3c",
  "f7badd5dc86a8a5dce0984ef43bcb7ec228398e08a854a8a8c455ff895dc8a49",
  "e848bf12b0bf2708b52c20053ef674e603e7f3a3c7092533dc92e1b0828960cd"
 ],
 "deck": "Ks,4d,3c,Tc,9h,8c,Jd,4h,2c,6d,9d,Th,3d,9s,5s,3h,Qc,2h,9c,8h,7c,Js,7s,2d,6s,Ac,8s,As,Kh,2s,Ah,5h,Jh,Jc,4c,7h,6c,8d,Ad,Kd,Qs,Kc,6h,Qd,7d,5d,Qh,Ts,5c,3s,4s,Td",
 "env0_content": "1\te52675650d7ad48c7129185efdaec1e2b89cc410d8e4c8e085bcd652187b27d3\t0\tb6ef1a19d789c27bea3f6c127db635929541f34907750ee12d0b715c010c7566\tcfg\t763d312c6c6576656c3d302c73623d312c62623d322c73656174733d332c627574746f6e3d31",
 "env0_sender_sig": "c1d5f49bcc0fb8418830f63cc8be9c6bf7e5fd11a77807af38e672aa7284bba9c9cd58d73976888055851d034d440ab504cd0c9ab984f7df368a5f94225b310b",
 "env0_wire": "1\te52675650d7ad48c7129185efdaec1e2b89cc410d8e4c8e085bcd652187b27d3\t0\tb6ef1a19d789c27bea3f6c127db635929541f34907750ee12d0b715c010c7566\tcfg\t763d312c6c6576656c3d302c73623d312c62623d322c73656174733d332c627574746f6e3d31\tc1d5f49bcc0fb8418830f63cc8be9c6bf7e5fd11a77807af38e672aa7284bba9c9cd58d73976888055851d034d440ab504cd0c9ab984f7df368a5f94225b310b\t1\t0000000000000000000000000000000000000000000000000000000000000000\tef00bf818725cc9fbc867a1ba620ea89ba674d66029cf005bf7911b9e26ea111c7cd2129a7be1f25326d1f831ac98dc43e50dc31fbb9ea9c81e338fa95bd270c",
 "flop": "4h,2c,6d",
 "holes": {
  "1": "3c,8c",
  "2": "Ks,Tc",
  "3": "4d,9h"
 },
 # spec 10 DHT rendezvous id + spec 5 display fingerprint: the 40-hex and
 # 8-hex truncations of H(tableId) and H(pubkey)
 "table_infohash": "891e5f5c70b88414190980f34a02cb06784cd6da",
 "id_fingerprint1": "77d2c2dc",
 "id_pubs": [
  "b6ef1a19d789c27bea3f6c127db635929541f34907750ee12d0b715c010c7566",
  "833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10",
  "ad1d6dbbd062cdacf356daf0834471b6246105b17e3b988dd5e7f0db45fb66a6"
 ],
 # v0.23.0: the 2e timer lengths joined the cfg body (act/bank/miss), a
 # documented consensus change -- this pin and lobby_head2 regenerated.
 "lobby_cfg_body": "v=1,level=0,sb=1,bb=2,ante=0,stack=400,seats=6,button=1,act=30,bank=60,miss=2",
 "lobby_head2": "57c56971affa1ac3d723d600937df12046a7def0c059444054f763e94a65b7fa",
 "receipt_head1": "53ed9ccc64863dc05c1b76cd7953e19bba73895b8dd22ea00e6c9ff40f423cef",
 "receipt_head2": "0284af24c750eaaaa5a521b87d8f1ab6ce00b0b2be074ce03d24884e004fc910",
 "receipt_sigs": [
  "222929a8ce05e0d45cab6658d9e67d882d6cfa1f91c35cda8e07a58763c4b1fb6c733e23d116f04ed91960c0ad386541139fed43e1632df341175021d70b1700",
  "20a21d334da7d32b00bf3a17920350ebaad0773121fc3f2d9feba041360d9548fb527c555cab8039985439bed3af73d17656b939942a6bc3a793630275070706",
  "429a37ee32d74fd2d09b1b3a86fccc383c7e773ef52670ed07e4ede7e2e10f9ab4b791d630d0b44bdb6c405ed5238cc0bbab9d40129d3673c2c39f1d5d1a9c09"
 ],
 "river": "9s",
 "roster_body": "833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10:player,b6ef1a19d789c27bea3f6c127db635929541f34907750ee12d0b715c010c7566:host",
 "seeds_xor": "73e2b09387940cf29398389f4d4fef74987ffac3c369b68cb522ded044cb00b8",
 "settle_hash": "68095dcf5a74fac1e1340a1073a466dcf117024257f5c265de21698257b34b6f",
 "settle_hash2": "5e716ce9022f4c47d99e081b52be3a8bb5f9f1f56d3def18577c2f7ac9de8df5",
 "stream_block0": "22a256dd9846bb3d40d24d3d5441cdf5415e9fb3532ba99f4f4812630941108d",
 "stream_key": "e4d91a49ee23982afb804fd386cbd3d2df6370ae0a743b0f461325b94818e40f",
 "synth_deck": "Ac,Kc,3d,5h,Kh,5d,Qc,3h,2h,5c,8c,4h,4d,Tc,7h,Qs,6c,Ts,6h,7d,Th,6s,Kd,3c,Jc,9s,4c,Ah,5s,2d,8s,As,2s,Ad,9d,Qh,8d,Jh,Qd,Jd,2c,6d,7s,Ks,7c,Js,8h,3s,4s,9h,9c,Td",
 "synth_stream": "8eaba859db2f1a2a3bce5e381fc1afa1339dc9b7a8a1bbc550277e756dabdffcf7390d23167268d1523ac24f71f476cd47cd1fcd31cfa7ec51ef45c7853978859f7a10230ff86f287f1ead8ec6ac797f6f3d3a1eb75bcb435b5f491b81077775b47c0dcf3cc1d1c8f329c4e1cdae9c6e21f3825454f5c04a21fde75572ef04e25e36672b9e4ce78b4333da7090746ff00b8e32e7ad161f033523cb6f5ba2b10af1a1ebf6c815e54e4fe5efed623198c302732bf6e40ed8856a89e15d78f564614531b8f684aa727e51ea968727a22eb6e14bd588d502b2637bd73d59a8518eaf7a2311d555dd86147e83af7f1e9ef7c9baf253b851bbb48abecdea0b27f90761a67fb810022c6eae480866f19839deb884a4ec819be41bcb605df7dd1ee2efcdaab49eef76d4a98b6be858d3324ac616f2b1f58fc9a1749a6164e2a0e276d62d1815d6a042c78b82f3b0d1ff78852cf8778ba3e127411f0121775056de9e5f8e4253f98b54e627e74cf8c2a38c83edd7d6272de4eb6bd645ebcae1f1701bda866beadc5968e757a8f902e2be46933346dcb794676fd609e14f67d20432796eb492a0c86910f10e51c5c02e5a9fa95f407283b3d0abfb8357cc5f94fe4416b5984eb07e046975e1c15edece5c9e80fd6de3d43d6831a310fe9d74e0c5bb9e438da44bffd728a284795046da833ffb8fdd16128b7fdee7ef76e434e035c7471d52",
 "table": "e52675650d7ad48c7129185efdaec1e2b89cc410d8e4c8e085bcd652187b27d3",
 "turn": "Th"
}


def main():
    if "--print-pinned" in sys.argv:
        import json
        print("PINNED = " + json.dumps(compute_all(), indent=1, sort_keys=True))
        return 0

    if "--gen-xtalk" in sys.argv:
        got = compute_all()
        print("-- generated by tools/protocol-kat.py --gen-xtalk; do not hand-edit")
        print('constant kKatTableHex = "%s"' % got["table"])
        print('constant kKatSeed1 = "%s"' % got["deal_seeds"][0])
        print('constant kKatSeed2 = "%s"' % got["deal_seeds"][1])
        print('constant kKatSeed3 = "%s"' % got["deal_seeds"][2])
        print('constant kKatCommit1 = "%s"' % got["commits"][0])
        print('constant kKatCommit2 = "%s"' % got["commits"][1])
        print('constant kKatCommit3 = "%s"' % got["commits"][2])
        print('constant kKatSeedsXor = "%s"' % got["seeds_xor"])
        print('constant kKatStreamKey = "%s"' % got["stream_key"])
        print('constant kKatDeck = "%s"' % got["deck"])
        print('constant kKatHole1 = "%s"' % got["holes"]["1"])
        print('constant kKatHole2 = "%s"' % got["holes"]["2"])
        print('constant kKatHole3 = "%s"' % got["holes"]["3"])
        print('constant kKatFlop = "%s"' % got["flop"])
        print('constant kKatTurn = "%s"' % got["turn"])
        print('constant kKatRiver = "%s"' % got["river"])
        print('constant kKatSynthStream = "%s"' % got["synth_stream"])
        print('constant kKatSynthDeck = "%s"' % got["synth_deck"])
        print('constant kKatIdSeed1 = "%s"' % ID_SEEDS[0].hex())
        print('constant kKatIdSeed2 = "%s"' % ID_SEEDS[1].hex())
        print('constant kKatIdSeed3 = "%s"' % ID_SEEDS[2].hex())
        print('constant kKatIdPub1 = "%s"' % got["id_pubs"][0])
        # xTalk string literals have no escapes, so the tab-framed content
        # line travels as hex of its UTF-8 bytes
        print('constant kKatEnv0ContentHex = "%s"' % got["env0_content"].encode("utf-8").hex())
        print('constant kKatEnv0SenderSig = "%s"' % got["env0_sender_sig"])
        print('constant kKatChainHead6 = "%s"' % got["chain_heads"][5])
        print('constant kKatSettleHash = "%s"' % got["settle_hash"])
        print('constant kKatAdmitSig = "%s"' % got["admit_sig"])
        print('constant kKatIdPub2 = "%s"' % got["id_pubs"][1])
        print('constant kKatLobbyCfgBody = "%s"' % got["lobby_cfg_body"])
        print('constant kKatRosterBody = "%s"' % got["roster_body"])
        print('constant kKatLobbyHead2 = "%s"' % got["lobby_head2"])
        print('constant kKatCkptSig = "%s"' % got["ckpt_sig"])
        print('constant kKatSettleHash2 = "%s"' % got["settle_hash2"])
        print('constant kKatRcptHead1 = "%s"' % got["receipt_head1"])
        print('constant kKatRcptHead2 = "%s"' % got["receipt_head2"])
        print('constant kKatRcptSig1 = "%s"' % got["receipt_sigs"][0])
        print('constant kKatRcptSig2 = "%s"' % got["receipt_sigs"][1])
        print('constant kKatRcptSig3 = "%s"' % got["receipt_sigs"][2])
        print('constant kKatCkptBody = "%s"' % got["ckpt_body"])
        print('constant kKatCkptHead7 = "%s"' % got["ckpt_head7"])
        print('constant kKatShowHead8 = "%s"' % got["show_head8"])
        print('constant kKatMuckHead9 = "%s"' % got["muck_head9"])
        print('constant kKatTimeoutBody = "%s"' % got["timeout_act_body"])
        print('constant kKatTimeoutHead10 = "%s"' % got["timeout_head10"])
        print('constant kKatStandHead11 = "%s"' % got["stand_head11"])
        print('constant kKatSitBackHead12 = "%s"' % got["sitback_head12"])
        print('constant kKatTimeoutBidBody = "%s"' % got["timeout_bid_body"])
        print('constant kKatTimeoutBidHead13 = "%s"' % got["timeout_bid_head13"])
        # the hello frame carries tabs, so it travels as hex of its UTF-8
        # bytes (the kKatEnv0ContentHex convention)
        print('constant kKatHelloTrimHex = "%s"' % got["hello_trim_frame"].encode("utf-8").hex())
        print('constant kKatIdPub3 = "%s"' % got["id_pubs"][2])
        print('constant kKatTableInfohash = "%s"' % got["table_infohash"])
        print('constant kKatIdFingerprint1 = "%s"' % got["id_fingerprint1"])
        print('constant kKatElectedHost = "%s"' % got["elected_host"])
        print('constant kKatElectedHostSitOut = "%s"' % got["elected_host_sitout"])
        print('constant kKatOnionSeed = "%s"' % got["onion_service_seed"])
        print('constant kKatOracleSeed = "%s"' % got["oracle_service_seed"])
        print('constant kKatLobbyCfgBodyOracle = "%s"' % got["lobby_cfg_body_oracle"])
        print('constant kKatL2Scalar1 = "%s"' % got["l2_scalars"][0])
        print('constant kKatL2Scalar2 = "%s"' % got["l2_scalars"][1])
        print('constant kKatL2Scalar3 = "%s"' % got["l2_scalars"][2])
        print('constant kKatL2Inv1 = "%s"' % got["l2_scalar_invs"][0])
        print('constant kKatL2Inv2 = "%s"' % got["l2_scalar_invs"][1])
        print('constant kKatL2Inv3 = "%s"' % got["l2_scalar_invs"][2])
        print('constant kKatL2Perm1 = "%s"' % got["l2_perms"][0])
        print('constant kKatL2Perm2 = "%s"' % got["l2_perms"][1])
        print('constant kKatL2Perm3 = "%s"' % got["l2_perms"][2])
        print('constant kKatL2BaseDeck = "%s"' % got["l2_base_deck"])
        print('constant kKatL2Deck1 = "%s"' % got["l2_deck_p1"])
        print('constant kKatL2MaskedDeck = "%s"' % got["l2_masked_deck"])
        print('constant kKatL2PublicChain = "%s"' % got["l2_public_chain"])
        print('constant kKatL2PublicCard = "%s"' % got["l2_public_card"])
        print('constant kKatL2HoleChain = "%s"' % got["l2_hole_chain"])
        print('constant kKatL2HoleCard = "%s"' % got["l2_hole_card"])
        print('constant kKatL2Ck1 = "%s"' % got["l2_cks"][0])
        print('constant kKatL2Ck2 = "%s"' % got["l2_cks"][1])
        print('constant kKatL2Ck3 = "%s"' % got["l2_cks"][2])
        print('constant kKatL2DleqProof = "%s"' % got["l2_dleq_proof"])
        return 0

    got = compute_all()
    if not PINNED:
        print("FAIL  no pinned values embedded yet -- run --print-pinned and paste")
        return 1
    fails = 0
    for k in sorted(PINNED):
        if got.get(k) == PINNED[k]:
            print("PASS  %s" % k)
        else:
            print("FAIL  %s\n  observed=%r\n  expected=%r" % (k, got.get(k), PINNED[k]))
            fails += 1
    extra = sorted(set(got) - set(PINNED))
    if extra:
        print("FAIL  computed keys missing from PINNED: %s" % ", ".join(extra))
        fails += 1

    # backlog A6's coverage assertion: every type the SOURCE dispatcher
    # names must have at least one wire built (and therefore pinned) by
    # compute_all - so a NEW wire type cannot arrive unpinned. Checked
    # against WIRE_TYPES_BUILT, the set make_wire actually recorded on this
    # run, never against a hand-kept list.
    vocab = source_wire_vocabulary()
    unpinned = sorted(t for t in vocab if t not in WIRE_TYPES_BUILT)
    if unpinned:
        print("FAIL  wire types in heNetApplyWire's vocabulary with no pinned "
              "wire: %s" % ", ".join(unpinned))
        fails += 1
    else:
        print("PASS  wire-type coverage: all %d source vocabulary types have "
              "a pinned wire" % len(vocab))

    print()
    if fails:
        print("FAILED -- %d protocol vector(s) wrong." % fails)
        return 1
    print("All protocol vectors passed (%d pinned values)." % len(PINNED))
    return 0


if __name__ == "__main__":
    sys.exit(main())
