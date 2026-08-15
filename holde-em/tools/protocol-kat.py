#!/usr/bin/env python3
"""Protocol known-answer vectors: envelope bytes, hash chain, Level 0 deal.

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


def content_line(v, table, hand, from_pub, mtype, body_text):
    return "\t".join([str(v), table.hex(), str(hand), from_pub.hex(), mtype,
                      body_text.encode("utf-8").hex()])


def make_wire(v, table, hand, sender_seed, mtype, body_text, seq, prev, host_seed):
    content = content_line(v, table, hand, ed_publickey(sender_seed), mtype, body_text)
    sender_sig = ed_sign(content.encode("utf-8"), sender_seed).hex()
    env_line = content + "\t" + sender_sig + "\t" + str(seq) + "\t" + prev.hex()
    host_sig = ed_sign(env_line.encode("utf-8"), host_seed).hex()
    return env_line + "\t" + host_sig


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


def compute_all():
    check_ed25519()
    out = {}
    out["table"] = TABLE.hex()
    out["id_pubs"] = [ed_publickey(s).hex() for s in ID_SEEDS]
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
    # stakes from the signed cfg); heLobbyCfgBody mirrors this string exactly
    out["lobby_cfg_body"] = "v=1,level=0,sb=1,bb=2,ante=0,stack=400,seats=6,button=1"
    lw1 = make_wire(1, TABLE, 0, ID_SEEDS[0], "cfg", out["lobby_cfg_body"],
                    1, GENESIS, HOST_SEED)
    lh1 = chain_next(lw1)
    lw2 = make_wire(1, TABLE, 0, ID_SEEDS[0], "roster", out["roster_body"],
                    2, lh1, HOST_SEED)
    out["lobby_head2"] = chain_next(lw2).hex()

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
 "admit_sig": "17cf45eeecf27a3e9b63e1e0ff47ae1ea337430cb135fb499944a60681fcd1e949a7a88f532b2f888c0ea32364e93e9aa2f569419f27e8034b695a4ee94d5e0b",
 "burns": "Jd,9d,3d",
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
 "id_pubs": [
  "b6ef1a19d789c27bea3f6c127db635929541f34907750ee12d0b715c010c7566",
  "833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10",
  "ad1d6dbbd062cdacf356daf0834471b6246105b17e3b988dd5e7f0db45fb66a6"
 ],
 "lobby_cfg_body": "v=1,level=0,sb=1,bb=2,ante=0,stack=400,seats=6,button=1",
 "lobby_head2": "974bbb46cf5c62eabc9d3930446b7748f38139d10b0ed1c0cb37f155b4d1a3e9",
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

    print()
    if fails:
        print("FAILED -- %d protocol vector(s) wrong." % fails)
        return 1
    print("All protocol vectors passed (%d pinned values)." % len(PINNED))
    return 0


if __name__ == "__main__":
    sys.exit(main())
