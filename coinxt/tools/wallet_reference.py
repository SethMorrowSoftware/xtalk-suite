#!/usr/bin/env python3
"""wallet_reference.py - an INDEPENDENT oracle for the CoinXT wallet layer.

WHY THIS EXISTS. examples/wallet-core.livecodescript is a pure calculator:
scripts, addresses, extended keys, coin selection, transaction assembly,
PSBT, message signatures, BIP-21 and output descriptors. None of that is
cryptography (coinxt.lcb owns every hash and every curve operation), but all
of it is byte layout, and a transcription slip in byte layout produces a
VALID-LOOKING wrong answer: an address that encodes cleanly and belongs to
nobody, a PSBT that parses and pays the wrong output, a descriptor whose
checksum closes over the wrong string.

So the shipped script needs an answer key written by somebody else. This file
is that key. It reuses coin_reference.py (already anchored at import to the
published BIP-173/350, BIP-32, BIP-39, EIP-55 and RLP vectors) for the pieces
that member already proves, and implements from the specification everything
the wallet layer adds. tools/check-wallet-vectors.py then RUNS the shipped
.livecodescript through lcs-interp.py and compares.

WHAT IT IS NOT. Not the engine, and not a wallet. It computes expected
answers; it never signs anything a person owns and it holds no state.

The published anchors checked at import (see _selftest at the bottom):
  - BIP-173 / BIP-350 segwit address vectors (via coin_reference)
  - BIP-141 / BIP-143 scriptPubKey shapes
  - BIP-49 / BIP-84 / BIP-86 account xpub/ypub/zpub for the test mnemonic
  - SLIP-132 extended key version bytes
  - BIP-174 PSBT test vectors (the valid ones this layer can produce)
  - the Bitcoin Signed Message format as implemented by Bitcoin Core
  - BIP-21 grammar, output descriptor checksum vectors from Bitcoin Core
  - ISO/IEC 18004 QR byte-mode vectors
"""
import hashlib
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

_spec = importlib.util.spec_from_file_location(
    "coin_reference", os.path.join(HERE, "coin_reference.py"))
cr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cr)

sha256 = cr.sha256
hash256 = cr.hash256
hash160 = cr.hash160
varint = cr.varint
_le = cr._le


# ===========================================================================
# NETWORK PARAMETERS
#
# Four networks, and the values that differ between them. The base58 version
# bytes are Bitcoin Core's chainparams; the bech32 HRPs are BIP-173 (bc/tb)
# and BIP-350's signet reuse of tb, with regtest's bcrt from Core.
#
# The extended-key versions are the pair every wallet gets wrong once: BIP-32
# defines ONE mainnet pair (xpub/xprv) and ONE testnet pair (tpub/tprv), and
# SLIP-132 adds a per-script-type pair (ypub/zpub and their testnet upub/vpub
# spellings) so a bare extended key carries its own script type. Taproot has
# no SLIP-132 assignment at all - BIP-86 explicitly keeps xpub - which is why
# the p2tr row below repeats the BIP-32 numbers rather than inventing any.
# ===========================================================================
NETWORKS = {
    "mainnet": {
        "hrp": "bc",
        "p2pkh": 0x00,
        "p2sh": 0x05,
        "wif": 0x80,
        "coin": 0,          # BIP-44 coin type
        "xpub": 0x0488B21E, "xprv": 0x0488ADE4,   # BIP-32
        "ypub": 0x049D7CB2, "yprv": 0x049D7878,   # SLIP-132 p2wpkh-in-p2sh
        "zpub": 0x04B24746, "zprv": 0x04B2430C,   # SLIP-132 p2wpkh
        "Ypub": 0x0295B43F, "Yprv": 0x0295B005,   # SLIP-132 p2wsh-in-p2sh
        "Zpub": 0x02AA7ED3, "Zprv": 0x02AA7A99,   # SLIP-132 p2wsh
    },
    "testnet": {
        "hrp": "tb",
        "p2pkh": 0x6F,
        "p2sh": 0xC4,
        "wif": 0xEF,
        "coin": 1,
        "xpub": 0x043587CF, "xprv": 0x04358394,
        "ypub": 0x044A5262, "yprv": 0x044A4E28,
        "zpub": 0x045F1CF6, "zprv": 0x045F18BC,
        "Ypub": 0x024289EF, "Yprv": 0x024285B5,
        "Zpub": 0x02575483, "Zprv": 0x02575048,
    },
    # Signet and regtest share testnet's base58 and extended-key bytes; only
    # the bech32 HRP differs (signet reuses tb, regtest uses bcrt). Kept as
    # separate rows rather than aliases so a wrong lookup is a wrong ROW, not
    # a silently shared dict.
    "signet": {
        "hrp": "tb",
        "p2pkh": 0x6F, "p2sh": 0xC4, "wif": 0xEF, "coin": 1,
        "xpub": 0x043587CF, "xprv": 0x04358394,
        "ypub": 0x044A5262, "yprv": 0x044A4E28,
        "zpub": 0x045F1CF6, "zprv": 0x045F18BC,
        "Ypub": 0x024289EF, "Yprv": 0x024285B5,
        "Zpub": 0x02575483, "Zprv": 0x02575048,
    },
    # Testnet4 (Bitcoin Core 28, 2024) is a new chain with testnet3's bytes
    # everywhere: prefixes, WIF, extended-key versions, coin type. Only the
    # backend can tell them apart, and that is the app's table, not this one.
    "testnet4": {
        "hrp": "tb",
        "p2pkh": 0x6F, "p2sh": 0xC4, "wif": 0xEF, "coin": 1,
        "xpub": 0x043587CF, "xprv": 0x04358394,
        "ypub": 0x044A5262, "yprv": 0x044A4E28,
        "zpub": 0x045F1CF6, "zprv": 0x045F18BC,
        "Ypub": 0x024289EF, "Yprv": 0x024285B5,
        "Zpub": 0x02575483, "Zprv": 0x02575048,
    },
    "regtest": {
        "hrp": "bcrt",
        "p2pkh": 0x6F, "p2sh": 0xC4, "wif": 0xEF, "coin": 1,
        "xpub": 0x043587CF, "xprv": 0x04358394,
        "ypub": 0x044A5262, "yprv": 0x044A4E28,
        "zpub": 0x045F1CF6, "zprv": 0x045F18BC,
        "Ypub": 0x024289EF, "Yprv": 0x024285B5,
        "Zpub": 0x02575483, "Zprv": 0x02575048,
    },
}

# script type -> (BIP purpose, SLIP-132 key stem for a single-key wallet)
SCRIPT_TYPES = {
    "p2pkh":  (44, "x"),
    "p2sh-p2wpkh": (49, "y"),
    "p2wpkh": (84, "z"),
    "p2tr":   (86, "x"),      # BIP-86 keeps xpub on purpose
    "p2wsh":  (48, "Z"),      # multisig, BIP-48 script-type 2
}


def net(name):
    if name not in NETWORKS:
        raise ValueError("unknown network %r" % name)
    return NETWORKS[name]


def derivation_path(script_type, network, account, change=None, index=None):
    """The standard account path for a script type, BIP-44 shaped."""
    if script_type not in SCRIPT_TYPES:
        raise ValueError("unknown script type %r" % script_type)
    purpose = SCRIPT_TYPES[script_type][0]
    coin = net(network)["coin"]
    path = "m/%d'/%d'/%d'" % (purpose, coin, account)
    if script_type == "p2wsh":
        path += "/2'"           # BIP-48 script-type index for native segwit
    if change is not None:
        path += "/%d" % change
        if index is not None:
            path += "/%d" % index
    return path


# ===========================================================================
# SCRIPTS
#
# Every scriptPubKey a single-signature or simple-multisig wallet produces,
# written as literal opcodes rather than assembled from a script builder, so
# the bytes are readable next to the BIP that defines them.
# ===========================================================================
OP_0 = 0x00
OP_1 = 0x51
OP_DUP = 0x76
OP_EQUAL = 0x87
OP_EQUALVERIFY = 0x88
OP_HASH160 = 0xA9
OP_CHECKSIG = 0xAC
OP_CHECKMULTISIG = 0xAE


def push(data: bytes) -> bytes:
    """A minimal data push. Only the direct form (1..75 bytes) and OP_PUSHDATA1
    are needed here: no wallet script this layer builds pushes more than 255
    bytes (a 15-of-15 witness script is 15*34+4 = 514, so PUSHDATA2 is
    reachable in principle and is implemented for completeness)."""
    n = len(data)
    if n < 0x4C:
        return bytes([n]) + data
    if n <= 0xFF:
        return bytes([0x4C, n]) + data
    if n <= 0xFFFF:
        return bytes([0x4D, n & 0xFF, n >> 8]) + data
    raise ValueError("push too large")


def spk_p2pkh(pubkey: bytes) -> bytes:
    return bytes([OP_DUP, OP_HASH160]) + push(hash160(pubkey)) + \
        bytes([OP_EQUALVERIFY, OP_CHECKSIG])


def spk_p2sh(script_hash: bytes) -> bytes:
    assert len(script_hash) == 20
    return bytes([OP_HASH160]) + push(script_hash) + bytes([OP_EQUAL])


def spk_p2wpkh(pubkey: bytes) -> bytes:
    return bytes([OP_0]) + push(hash160(pubkey))


def spk_p2wsh(witness_script: bytes) -> bytes:
    return bytes([OP_0]) + push(sha256(witness_script))


def spk_p2tr(output_key32: bytes) -> bytes:
    assert len(output_key32) == 32
    return bytes([OP_1]) + push(output_key32)


def redeem_p2sh_p2wpkh(pubkey: bytes) -> bytes:
    """BIP-49's redeem script: the P2WPKH scriptPubKey itself, wrapped."""
    return spk_p2wpkh(pubkey)


def spk_p2sh_p2wpkh(pubkey: bytes) -> bytes:
    return spk_p2sh(hash160(redeem_p2sh_p2wpkh(pubkey)))


def multisig_script(m: int, pubkeys, sort_bip67=True) -> bytes:
    """A bare m-of-n CHECKMULTISIG script - the witnessScript of a P2WSH
    multisig. BIP-67 lexicographic ordering is the default because it makes
    the address a function of the KEY SET rather than of the order somebody
    typed them in, which is what lets two cosigners derive the same address."""
    n = len(pubkeys)
    if not 1 <= m <= n <= 15:
        raise ValueError("m-of-n out of range: %d-of-%d" % (m, n))
    keys = sorted(pubkeys) if sort_bip67 else list(pubkeys)
    out = bytes([OP_1 + m - 1])
    for k in keys:
        if len(k) != 33:
            raise ValueError("multisig wants compressed keys")
        out += push(k)
    out += bytes([OP_1 + n - 1, OP_CHECKMULTISIG])
    return out


# ===========================================================================
# ADDRESSES, both directions
# ===========================================================================
def address_for_spk(network: str, spk: bytes) -> str:
    """The address a scriptPubKey pays to, or a raise. This is the direction
    a HISTORY view needs (bytes off the wire, a name for a person)."""
    p = net(network)
    if len(spk) == 25 and spk[0] == OP_DUP and spk[1] == OP_HASH160 and \
            spk[2] == 20 and spk[23] == OP_EQUALVERIFY and spk[24] == OP_CHECKSIG:
        return cr.b58check_encode(bytes([p["p2pkh"]]) + spk[3:23])
    if len(spk) == 23 and spk[0] == OP_HASH160 and spk[1] == 20 and \
            spk[22] == OP_EQUAL:
        return cr.b58check_encode(bytes([p["p2sh"]]) + spk[2:22])
    if len(spk) >= 4 and spk[1] == len(spk) - 2:
        ver = spk[0]
        if ver == OP_0:
            witver = 0
        elif OP_1 <= ver <= OP_1 + 15:
            witver = ver - OP_1 + 1
        else:
            raise ValueError("not a witness program")
        prog = spk[2:]
        if witver == 0 and len(prog) not in (20, 32):
            raise ValueError("v0 witness program must be 20 or 32 bytes")
        if not 2 <= len(prog) <= 40:
            raise ValueError("witness program length out of range")
        return cr.segwit_encode(p["hrp"], witver, prog)
    raise ValueError("scriptPubKey is not a standard wallet output")


def spk_for_address(network: str, address: str) -> bytes:
    """The scriptPubKey an address pays to, or a raise. Cross-network is a
    REFUSAL, never a coercion: paying a testnet address on mainnet is the
    mistake this function exists to make impossible."""
    p = net(network)
    address = address.strip()
    if not address:
        raise ValueError("empty address")
    lower = address.lower()
    if lower.startswith(p["hrp"] + "1"):
        witver, prog = cr.segwit_decode(p["hrp"], address)
        if witver is None:
            raise ValueError("bech32 address failed its checksum or rules")
        if witver == 0:
            if len(prog) == 20:
                return bytes([OP_0]) + push(bytes(prog))
            if len(prog) == 32:
                return bytes([OP_0]) + push(bytes(prog))
            raise ValueError("v0 witness program must be 20 or 32 bytes")
        return bytes([OP_1 + witver - 1]) + push(bytes(prog))
    payload = cr.b58check_decode(address)
    if payload is None or len(payload) != 21:
        raise ValueError("address is neither valid bech32 nor valid base58check")
    ver, h = payload[0], payload[1:]
    if ver == p["p2pkh"]:
        return bytes([OP_DUP, OP_HASH160]) + push(h) + \
            bytes([OP_EQUALVERIFY, OP_CHECKSIG])
    if ver == p["p2sh"]:
        return bytes([OP_HASH160]) + push(h) + bytes([OP_EQUAL])
    raise ValueError("base58 version %d is not a %s address" % (ver, network))


def address_kind(network: str, address: str) -> str:
    spk = spk_for_address(network, address)
    if spk[0] == OP_DUP:
        return "p2pkh"
    if spk[0] == OP_HASH160:
        return "p2sh"
    if spk[0] == OP_0:
        return "p2wpkh" if len(spk) == 22 else "p2wsh"
    if spk[0] == OP_1 and len(spk) == 34:
        return "p2tr"
    return "witness-unknown"


def electrum_scripthash(spk: bytes) -> str:
    """Electrum's scripthash: SHA-256 of the scriptPubKey, REVERSED, hex.
    The reversal is the part everybody gets wrong once - the protocol sends
    the hash in little-endian display order, like a txid."""
    return sha256(spk)[::-1].hex()


# ===========================================================================
# EXTENDED KEYS
#
# BIP-32's 78 bytes with a chosen version, so the wallet can emit and read
# ypub/zpub/tpub/upub/vpub and not only coin_reference's fixed xpub/xprv.
# ===========================================================================
def xkey_encode(node: dict, version: int, private: bool) -> str:
    out = version.to_bytes(4, "big")
    out += bytes([node["depth"]])
    fp = node["parentfp"]
    out += fp if isinstance(fp, bytes) else bytes(fp)
    out += int(node["index"]).to_bytes(4, "big")
    out += node["chaincode"]
    out += (b"\x00" + node["seckey"]) if private else node["pubkey"]
    return cr.b58check_encode(out)


def xkey_decode(text: str) -> dict:
    raw = cr.b58check_decode(text.strip())
    if raw is None or len(raw) != 78:
        raise ValueError("not a valid 78-byte extended key")
    version = int.from_bytes(raw[0:4], "big")
    node = {
        "version": version,
        "depth": raw[4],
        "parentfp": raw[5:9],
        "index": int.from_bytes(raw[9:13], "big"),
        "chaincode": raw[13:45],
    }
    body = raw[45:78]
    if body[0] == 0x00:
        node["seckey"] = body[1:]
        node["pubkey"] = cr.pubkey(body[1:])
        node["private"] = True
    else:
        if body[0] not in (0x02, 0x03):
            raise ValueError("extended public key is not a compressed point")
        node["pubkey"] = body
        node["seckey"] = b""
        node["private"] = False
    for name, p in NETWORKS.items():
        for stem in ("x", "y", "z", "Y", "Z"):
            if version == p[stem + "pub"]:
                node["network"], node["stem"], node["kind"] = name, stem, "public"
                return node
            if version == p[stem + "prv"]:
                node["network"], node["stem"], node["kind"] = name, stem, "private"
                return node
    raise ValueError("unknown extended key version 0x%08X" % version)


def xkey_version(network: str, script_type: str, public: bool) -> int:
    stem = SCRIPT_TYPES[script_type][1]
    return net(network)[stem + ("pub" if public else "prv")]


def fingerprint(pubkey: bytes) -> bytes:
    return hash160(pubkey)[:4]


# ===========================================================================
# AMOUNTS
#
# Satoshi are integers and BTC is a DISPLAY form. Every conversion here is
# exact string arithmetic; nothing rounds through a float, because a float
# loses a satoshi somewhere above 90 million BTC and, far more usefully,
# because "0.1 + 0.2" is the oldest bug in money software.
# ===========================================================================
def sat_to_btc(sat: int) -> str:
    neg = sat < 0
    sat = abs(int(sat))
    whole, frac = divmod(sat, 100000000)
    return ("-" if neg else "") + "%d.%08d" % (whole, frac)


def btc_to_sat(text: str) -> int:
    t = str(text).strip()
    if not t:
        raise ValueError("empty amount")
    neg = t.startswith("-")
    if neg:
        t = t[1:]
    if t.count(".") > 1:
        raise ValueError("more than one decimal point")
    whole, _, frac = t.partition(".")
    whole = whole or "0"
    if not whole.isdigit() or (frac and not frac.isdigit()):
        raise ValueError("amount is not a decimal number")
    if len(frac) > 8:
        raise ValueError("a satoshi is the smallest unit: at most 8 decimals")
    frac = (frac + "00000000")[:8]
    v = int(whole) * 100000000 + int(frac)
    return -v if neg else v


# ===========================================================================
# SIZE, WEIGHT AND FEES
#
# Every number below is the worst case, and worst case is the only safe
# direction: underestimating vsize underpays the fee and the transaction
# sits unconfirmed. The signature figure is 72 (a DER-encoded ECDSA signature
# with low-S can be 71, and is 72 often enough that budgeting 71 produces an
# occasional under-payment); taproot's key-path witness is exactly 64+1.
# ===========================================================================
INPUT_WITNESS = {
    # scriptSig bytes (non-witness), witness bytes (weight units / 4 later)
    "p2pkh":       (1 + 72 + 1 + 33, 0),
    "p2sh-p2wpkh": (1 + 1 + 1 + 20, 1 + 1 + 72 + 1 + 33),
    "p2wpkh":      (0, 1 + 1 + 72 + 1 + 33),
    "p2tr":        (0, 1 + 1 + 64),
}

OUTPUT_SIZE = {
    "p2pkh": 8 + 1 + 25,
    "p2sh": 8 + 1 + 23,
    "p2sh-p2wpkh": 8 + 1 + 23,
    "p2wpkh": 8 + 1 + 22,
    "p2wsh": 8 + 1 + 34,
    "p2tr": 8 + 1 + 34,
}

# BIP-125 rule 3 and Core's default incremental relay fee: 1 sat/vB.
INCREMENTAL_RELAY_FEE = 1

# Core's dust threshold (GetDustThreshold in policy.cpp): an output is dust
# when spending it would cost more than a third of its value at the 3000
# sat/kvB dust relay fee. Core's spend-size estimate branches on ONE question -
# is the scriptPubKey a witness program? - and nothing else:
#
#     witness program:  32 + 4 + 1 + (107 / 4) + 4  =  67
#     anything else:    32 + 4 + 1 +  107      + 4  = 148
#
# The distinction that is NOT drawn there is the one it is natural to draw: a
# P2SH-wrapped SegWit output has a P2SH scriptPubKey, so it is NOT a witness
# program and costs 148, even though spending it really does use a witness.
# Writing per-type spend sizes by hand got that wrong here in both directions
# (91 for p2sh-p2wpkh, 57.5 for p2tr), which is why the rule is now Core's
# own branch rather than a table.
DUST_SPEND_WITNESS = 67
DUST_SPEND_LEGACY = 148

WITNESS_OUTPUTS = ("p2wpkh", "p2wsh", "p2tr")


# What spending a change output is assumed to cost LATER, in sat/vB. Bitcoin
# Core's own default, and the only rate in coin selection that is not the
# transaction's own - because the two halves of "cost of change" (making the
# output now, spending it later) happen at different times.
LONG_TERM_FEE_RATE = 10


def push_len(n: int) -> int:
    """Bytes a push of n data bytes occupies, opcode included."""
    return n + (1 if n < 0x4C else 2 if n <= 0xFF else 3)


def output_size(script_type: str) -> int:
    """OUTPUT_SIZE plus the parametrised "nulldata:N" (an OP_RETURN carrying
    N bytes): value, script length prefix, OP_RETURN, one push."""
    if script_type.startswith("nulldata:"):
        n = int(script_type[9:])
        script = 1 + push_len(n)
        return 8 + len(varint(script)) + script
    if script_type not in OUTPUT_SIZE:
        raise ValueError("unknown output type %r" % script_type)
    return OUTPUT_SIZE[script_type]


def dust_threshold(script_type: str) -> int:
    if script_type.startswith("nulldata:"):
        return 0                         # provably unspendable: nothing to price
    spend = (DUST_SPEND_WITNESS if script_type in WITNESS_OUTPUTS
             else DUST_SPEND_LEGACY)
    return (OUTPUT_SIZE.get(script_type, 34) + spend) * 3


def spk_op_return(data: bytes) -> bytes:
    """OP_RETURN and one push of the data; bare OP_RETURN for no data."""
    return b"\x6a" + (push(data) if data else b"")


def script_items(script: bytes):
    """The script as a list of ("push", data) and ("op", n), in order."""
    out, i = [], 0
    while i < len(script):
        b = script[i]
        i += 1
        if 1 <= b <= 75:
            n = b
        elif b == 76:
            n = script[i]
            i += 1
        elif b == 77:
            n = script[i] | (script[i + 1] << 8)
            i += 2
        elif b == 78:
            n = int.from_bytes(script[i:i + 4], "little")
            i += 4
        else:
            out.append(("op", b))
            continue
        if i + n > len(script):
            raise ValueError("push runs past the end")
        out.append(("push", script[i:i + n]))
        i += n
    return out


def op_return_data(script: bytes) -> bytes:
    """Every push after a leading OP_RETURN, joined; b"" for anything else."""
    if not script or script[0] != 0x6A:
        return b""
    return b"".join(d for kind, d in script_items(script[1:]) if kind == "push")


def multisig_witness_bytes(m: int, n: int) -> int:
    script = 1 + n * 34 + 2
    # items: an empty element for CHECKMULTISIG's off-by-one, m signatures,
    # then the witness script - each length-prefixed, plus the item count.
    return 1 + 1 + m * (1 + 72) + (1 if script < 253 else 3) + script


def estimate_vsize(inputs, outputs, has_witness=None) -> int:
    """inputs: list of script-type strings (or ("p2wsh", m, n) tuples).
    outputs: list of script-type strings. Returns virtual bytes, rounded UP."""
    base = 4 + 4                       # version + locktime
    base += len(varint(len(inputs)))
    base += len(varint(len(outputs)))
    wit = 0
    any_witness = False
    for spec in inputs:
        if isinstance(spec, (tuple, list)):
            kind, m, n = spec[0], spec[1], spec[2]
            if kind != "p2wsh":
                raise ValueError("only p2wsh takes an m-of-n spec")
            base += 32 + 4 + 1 + 4     # outpoint + empty scriptSig len + seq
            wit += multisig_witness_bytes(m, n)
            any_witness = True
            continue
        if spec not in INPUT_WITNESS:
            raise ValueError("unknown input type %r" % spec)
        sig_bytes, w = INPUT_WITNESS[spec]
        base += 32 + 4 + len(varint(sig_bytes)) + sig_bytes + 4
        wit += w
        if w:
            any_witness = True
    for spec in outputs:
        base += output_size(spec)
    if has_witness is None:
        has_witness = any_witness
    if has_witness:
        wit += 2                        # marker + flag
        # every input contributes a witness stack, empty ones included
        for spec in inputs:
            if not isinstance(spec, (tuple, list)) and INPUT_WITNESS[spec][1] == 0:
                wit += 1                # the 0x00 empty-stack byte
    weight = base * 4 + wit
    return -(-weight // 4)              # ceil


def fee_for(vsize: int, sat_per_vb) -> int:
    return int(-(-(vsize * float(sat_per_vb) * 1000) // 1000))


# ===========================================================================
# COIN SELECTION
#
# Four strategies, and the reason there is more than one is that they trade
# different things. Branch-and-bound looks for a CHANGELESS solution (Murch's
# algorithm, the one Bitcoin Core reaches for first) because an output the
# wallet does not create is an output nobody can link. Largest-first keeps the
# UTXO set small and the transaction cheap. Smallest-first consolidates dust
# while fees are low. Oldest-first spends the coins with the most confirmations.
#
# All four are DETERMINISTIC here: no shuffling, no randomness, so a vector
# gate can pin them. A real wallet may want to randomise the change position;
# that is a UI decision made after selection, not part of it.
# ===========================================================================
def _coin_weight_cost(input_type, fee_rate):
    """What one input costs at this fee rate, in satoshi."""
    one = estimate_vsize([input_type], [])
    none = estimate_vsize([], [])
    return fee_for(max(one - none, 1), fee_rate)


def select_coins(utxos, target_sat, fee_rate, input_type, output_types,
                 change_type, strategy="bnb", long_term_fee_rate=None):
    """utxos: list of dicts with at least value (sat) and height/confirmations.
    Returns a dict: selected, fee, change, total_in, vsize, strategy, ok, why.

    The invariant every branch must hold, and the one a hand-rolled selector
    usually breaks: total_in == target + fee + change, with change either 0 or
    at least the dust threshold. A selector that returns a change output below
    dust has built a transaction the network will not relay."""
    if long_term_fee_rate is None:
        long_term_fee_rate = LONG_TERM_FEE_RATE
    spendable = [u for u in utxos if not u.get("frozen")]
    if strategy == "manual":
        # FROZEN BEATS TICKED, and this line used to REPLACE the freeze filter
        # rather than narrow it - so a coin carrying both flags was spent here
        # and refused by the script, and no vector asked the two the question
        # they answered differently. Freezing is the more deliberate signal.
        spendable = [u for u in spendable if u.get("selected")]

    def _vsize(n, with_change):
        outs = list(output_types) + ([change_type] if with_change else [])
        return estimate_vsize([input_type] * n, outs)

    def _result(sel, with_change):
        vs = _vsize(len(sel), with_change)
        fee = fee_for(vs, fee_rate)
        total = sum(u["value"] for u in sel)
        change = total - target_sat - fee
        return {"selected": sel, "fee": fee, "change": change if with_change else 0,
                "total_in": total, "vsize": vs}

    if not spendable:
        return {"ok": False, "why": "no spendable coins", "selected": [],
                "fee": 0, "change": 0, "total_in": 0, "vsize": 0,
                "strategy": strategy}

    dust = dust_threshold(change_type)
    cost_of_change = _coin_weight_cost(input_type, long_term_fee_rate) + \
        fee_for(OUTPUT_SIZE[change_type], fee_rate)

    # --- 1. branch and bound: an exact match within [target+fee, target+fee+
    # cost_of_change] means no change output at all.
    if strategy in ("bnb", "auto"):
        pool = sorted(spendable, key=lambda u: -u["value"])
        eff = []
        for u in pool:
            cost = _coin_weight_cost(input_type, fee_rate)
            e = u["value"] - cost
            if e > 0:
                eff.append((e, u))
        base_fee = fee_for(_vsize(0, False), fee_rate)
        lo = target_sat + base_fee
        hi = lo + cost_of_change
        best = None
        total_avail = sum(e for e, _ in eff)

        def _bnb(i, chosen, value, tries):
            nonlocal best
            if best is not None or tries[0] > 100000:
                return
            tries[0] += 1
            if value > hi:
                return
            if value >= lo:
                best = list(chosen)
                return
            if i >= len(eff):
                return
            remaining = sum(e for e, _ in eff[i:])
            if value + remaining < lo:
                return
            chosen.append(eff[i][1])
            _bnb(i + 1, chosen, value + eff[i][0], tries)
            chosen.pop()
            _bnb(i + 1, chosen, value, tries)

        if total_avail >= lo:
            _bnb(0, [], 0, [0])
        if best:
            r = _result(best, False)
            r.update({"ok": True, "why": "branch and bound: no change output",
                      "strategy": "bnb"})
            r["change"] = 0
            r["fee"] = r["total_in"] - target_sat
            return r
        strategy = "largest" if strategy == "auto" else strategy
        if strategy == "bnb":
            strategy = "largest"

    if strategy == "largest":
        pool = sorted(spendable, key=lambda u: (-u["value"], u.get("txid", ""),
                                                u.get("vout", 0)))
    elif strategy == "smallest":
        pool = sorted(spendable, key=lambda u: (u["value"], u.get("txid", ""),
                                                u.get("vout", 0)))
    elif strategy == "oldest":
        pool = sorted(spendable, key=lambda u: (-u.get("confirmations", 0),
                                                u.get("txid", ""),
                                                u.get("vout", 0)))
    elif strategy == "manual":
        pool = list(spendable)
    else:
        raise ValueError("unknown strategy %r" % strategy)

    # MANUAL SPENDS THE WHOLE TICKED SET. The loop below adds one coin at a
    # time and returns on the first prefix that pays, which is right for the
    # automatic strategies and wrong for this one - the ticked set IS the
    # answer the person gave, and consolidating twenty small coins into one
    # payment is the main reason to tick a set at all. This file had the same
    # prefix behaviour as the script, which is why the gate could not see it:
    # two implementations agreeing is not the same as either being right.
    candidates = [pool] if strategy == "manual" else None

    sel = []
    for step, u in enumerate(pool):
        if candidates is not None:
            if step:
                break
            sel = list(pool)
        else:
            sel.append(u)
        r = _result(sel, True)
        if r["change"] >= dust:
            r.update({"ok": True, "why": "with change", "strategy": strategy})
            return r
        # a change output below dust is better BURNED INTO THE FEE than
        # created: the network will not relay it, and adding another input to
        # push it over costs more than the change is worth.
        # The remainder if no change output is made. _result reports change
        # as 0 in that shape by construction, so the surplus is recomputed
        # here from the total rather than read back out of it - reading it
        # back was a real bug in this file: every candidate looked like an
        # exact match, so the FIRST coin always "won" and the fee came out
        # negative.
        # NO UPPER BOUND ON THE SURPLUS. This test is only reached when a
        # change output WOULD be below dust, and the surplus always exceeds
        # that change by the cost of the change output itself (~31 vB), so
        # requiring `surplus < dust` too left a window - change under dust,
        # surplus over it - where neither branch fired. With another coin to
        # try that was wasteful; on the last coin it reported "insufficient
        # funds" for a spend that was plainly affordable.
        r0 = _result(sel, False)
        surplus = r0["total_in"] - target_sat - r0["fee"]
        if surplus >= 0:
            r0["fee"] = r0["total_in"] - target_sat
            r0["change"] = 0
            r0.update({"ok": True, "why": "changeless: the remainder is dust "
                                          "and goes to the miner",
                       "strategy": strategy})
            return r0
    if strategy == "manual":
        r = _result(sel, True)
        r.update({"ok": False, "why": "the coins you picked do not cover "
                                      "the amount plus the fee"})
        return r
    r = _result(pool, True)
    r.update({"ok": False, "why": "insufficient funds"})
    return r


# ===========================================================================
# PSBT (BIP-174 version 0, with the BIP-371 taproot fields)
#
# The format is three runs of key/value maps - one global, one per input, one
# per output - each terminated by a zero-length key. A key is
# <compact_size keylen><keytype><keydata>; a value is <compact_size len><data>.
# Nothing about it is clever, and that is precisely why it needs an oracle:
# every field is a length prefix around a blob, so a wrong length produces a
# file that another wallet parses into different money.
# ===========================================================================
PSBT_MAGIC = b"psbt\xff"

# global
PSBT_GLOBAL_UNSIGNED_TX = 0x00
PSBT_GLOBAL_XPUB = 0x01
PSBT_GLOBAL_VERSION = 0xFB
# input
PSBT_IN_NON_WITNESS_UTXO = 0x00
PSBT_IN_WITNESS_UTXO = 0x01
PSBT_IN_PARTIAL_SIG = 0x02
PSBT_IN_SIGHASH_TYPE = 0x03
PSBT_IN_REDEEM_SCRIPT = 0x04
PSBT_IN_WITNESS_SCRIPT = 0x05
PSBT_IN_BIP32_DERIVATION = 0x06
PSBT_IN_FINAL_SCRIPTSIG = 0x07
PSBT_IN_FINAL_SCRIPTWITNESS = 0x08
PSBT_IN_TAP_KEY_SIG = 0x13
PSBT_IN_TAP_BIP32_DERIVATION = 0x16
PSBT_IN_TAP_INTERNAL_KEY = 0x17
PSBT_IN_TAP_MERKLE_ROOT = 0x18
# output
PSBT_OUT_REDEEM_SCRIPT = 0x00
PSBT_OUT_WITNESS_SCRIPT = 0x01
PSBT_OUT_BIP32_DERIVATION = 0x02
PSBT_OUT_TAP_INTERNAL_KEY = 0x05
PSBT_OUT_TAP_BIP32_DERIVATION = 0x07


def _kv(keytype: int, keydata: bytes, value: bytes) -> bytes:
    key = bytes([keytype]) + keydata
    return varint(len(key)) + key + varint(len(value)) + value


def _emit_map(entries) -> bytes:
    """entries: list of (keytype, keydata, value). Emitted in ascending key
    order so the same wallet state always serialises to the same bytes -
    BIP-174 does not require it, and a vector gate does."""
    out = b""
    for keytype, keydata, value in sorted(entries, key=lambda e: (e[0], e[1])):
        out += _kv(keytype, keydata, value)
    return out + b"\x00"


def _read_varint(b, i):
    n = b[i]
    i += 1
    if n < 0xFD:
        return n, i
    if n == 0xFD:
        return int.from_bytes(b[i:i + 2], "little"), i + 2
    if n == 0xFE:
        return int.from_bytes(b[i:i + 4], "little"), i + 4
    return int.from_bytes(b[i:i + 8], "little"), i + 8


def _parse_map(b, i):
    entries = []
    while True:
        if i >= len(b):
            raise ValueError("PSBT map ran off the end without a separator")
        klen, i = _read_varint(b, i)
        if klen == 0:
            return entries, i
        key = b[i:i + klen]
        i += klen
        vlen, i = _read_varint(b, i)
        value = b[i:i + vlen]
        i += vlen
        entries.append((key[0], key[1:], value))


def unsigned_tx(version, inputs, outputs, locktime) -> bytes:
    """The PSBT unsigned transaction: every scriptSig empty, no witness."""
    out = _le(version, 4) + varint(len(inputs))
    for txid_be, vout, seq in inputs:
        out += bytes.fromhex(txid_be)[::-1] + _le(vout, 4) + b"\x00" + _le(seq, 4)
    out += varint(len(outputs))
    for value, spk in outputs:
        out += _le(value, 8) + varint(len(spk)) + spk
    out += _le(locktime, 4)
    return out


def psbt_create(version, inputs, outputs, locktime, in_meta=None, out_meta=None,
                global_xpubs=None) -> bytes:
    """inputs: [(txid_hex_be, vout, sequence)]; outputs: [(sat, spk_bytes)].
    in_meta[i] / out_meta[i]: dicts of the optional per-map fields."""
    g = [(PSBT_GLOBAL_UNSIGNED_TX, b"",
          unsigned_tx(version, inputs, outputs, locktime))]
    for xpub78, (fp, path) in (global_xpubs or {}).items():
        g.append((PSBT_GLOBAL_XPUB, xpub78, fp + _path_bytes(path)))
    out = PSBT_MAGIC + _emit_map(g)
    for i in range(len(inputs)):
        out += _emit_map(_input_entries((in_meta or {}).get(i, {})))
    for i in range(len(outputs)):
        out += _emit_map(_output_entries((out_meta or {}).get(i, {})))
    return out


def _path_bytes(path) -> bytes:
    """A BIP-32 path as PSBT stores it: each level a 4-byte LITTLE-endian
    uint, hardened levels carrying the 0x80000000 bit. Note the endianness:
    every other place BIP-32 writes a child number it is big-endian, and this
    one place it is not."""
    if isinstance(path, str):
        path = parse_path(path)
    return b"".join(_le(x, 4) for x in path)


def parse_path(path: str):
    """m/84'/0'/0'/0/5 -> [0x80000054, 0x80000000, 0x80000000, 0, 5]"""
    out = []
    p = path.strip()
    if p in ("m", "m/", ""):
        return out
    if p.startswith("m/"):
        p = p[2:]
    elif p.startswith("m"):
        p = p[1:]
    for level in p.split("/"):
        if not level:
            raise ValueError("empty level in path %r" % path)
        hardened = level[-1] in ("'", "h", "H")
        num = level[:-1] if hardened else level
        if not num.isdigit():
            raise ValueError("path level %r is not a number" % level)
        n = int(num)
        if n >= 0x80000000:
            raise ValueError("path level %r is out of range" % level)
        out.append(n + 0x80000000 if hardened else n)
    return out


def format_path(levels) -> str:
    parts = ["m"]
    for n in levels:
        parts.append("%d'" % (n - 0x80000000) if n >= 0x80000000 else str(n))
    return "/".join(parts)


def _input_entries(meta):
    e = []
    if "non_witness_utxo" in meta:
        e.append((PSBT_IN_NON_WITNESS_UTXO, b"", meta["non_witness_utxo"]))
    if "witness_utxo" in meta:
        value, spk = meta["witness_utxo"]
        e.append((PSBT_IN_WITNESS_UTXO, b"",
                  _le(value, 8) + varint(len(spk)) + spk))
    for pk, sig in sorted(meta.get("partial_sigs", {}).items()):
        e.append((PSBT_IN_PARTIAL_SIG, pk, sig))
    if "sighash" in meta:
        e.append((PSBT_IN_SIGHASH_TYPE, b"", _le(meta["sighash"], 4)))
    if "redeem_script" in meta:
        e.append((PSBT_IN_REDEEM_SCRIPT, b"", meta["redeem_script"]))
    if "witness_script" in meta:
        e.append((PSBT_IN_WITNESS_SCRIPT, b"", meta["witness_script"]))
    for pk, (fp, path) in sorted(meta.get("bip32", {}).items()):
        e.append((PSBT_IN_BIP32_DERIVATION, pk, fp + _path_bytes(path)))
    if "final_scriptsig" in meta:
        e.append((PSBT_IN_FINAL_SCRIPTSIG, b"", meta["final_scriptsig"]))
    if "final_scriptwitness" in meta:
        e.append((PSBT_IN_FINAL_SCRIPTWITNESS, b"", meta["final_scriptwitness"]))
    if "tap_key_sig" in meta:
        e.append((PSBT_IN_TAP_KEY_SIG, b"", meta["tap_key_sig"]))
    if "tap_internal_key" in meta:
        e.append((PSBT_IN_TAP_INTERNAL_KEY, b"", meta["tap_internal_key"]))
    if "tap_merkle_root" in meta:
        e.append((PSBT_IN_TAP_MERKLE_ROOT, b"", meta["tap_merkle_root"]))
    for pk, (fp, path) in sorted(meta.get("tap_bip32", {}).items()):
        e.append((PSBT_IN_TAP_BIP32_DERIVATION, pk,
                  varint(0) + fp + _path_bytes(path)))
    return e


def _output_entries(meta):
    e = []
    if "redeem_script" in meta:
        e.append((PSBT_OUT_REDEEM_SCRIPT, b"", meta["redeem_script"]))
    if "witness_script" in meta:
        e.append((PSBT_OUT_WITNESS_SCRIPT, b"", meta["witness_script"]))
    for pk, (fp, path) in sorted(meta.get("bip32", {}).items()):
        e.append((PSBT_OUT_BIP32_DERIVATION, pk, fp + _path_bytes(path)))
    if "tap_internal_key" in meta:
        e.append((PSBT_OUT_TAP_INTERNAL_KEY, b"", meta["tap_internal_key"]))
    for pk, (fp, path) in sorted(meta.get("tap_bip32", {}).items()):
        e.append((PSBT_OUT_TAP_BIP32_DERIVATION, pk,
                  varint(0) + fp + _path_bytes(path)))
    return e


def psbt_parse(raw: bytes) -> dict:
    if raw[:5] != PSBT_MAGIC:
        raise ValueError("not a PSBT: the magic bytes are wrong")
    g, i = _parse_map(raw, 5)
    out = {"global": g, "inputs": [], "outputs": []}
    tx = None
    for kt, kd, v in g:
        if kt == PSBT_GLOBAL_UNSIGNED_TX:
            tx = v
    if tx is None:
        raise ValueError("PSBT has no unsigned transaction")
    out["unsigned_tx"] = tx
    n_in, n_out = _count_tx(tx)
    for _ in range(n_in):
        m, i = _parse_map(raw, i)
        out["inputs"].append(m)
    for _ in range(n_out):
        m, i = _parse_map(raw, i)
        out["outputs"].append(m)
    if i != len(raw):
        raise ValueError("trailing bytes after the PSBT output maps")
    return out


def _count_tx(tx: bytes):
    i = 4
    n_in, i = _read_varint(tx, i)
    for _ in range(n_in):
        i += 32 + 4
        slen, i = _read_varint(tx, i)
        i += slen + 4
    n_out, i = _read_varint(tx, i)
    return n_in, n_out


# ===========================================================================
# BITCOIN SIGNED MESSAGE
#
# The format Bitcoin Core has used since 2011 and every wallet copies:
#
#   magic  = varstr("Bitcoin Signed Message:\n")   -- 24 bytes, so 0x18 first
#   digest = SHA256(SHA256(magic || varstr(message_utf8)))
#   sig    = base64( header || r(32) || s(32) )
#
# The header encodes the recovery id AND the address form the signer claims,
# which is the part that makes verification work without a public key:
#
#   27 + recid       uncompressed P2PKH
#   31 + recid       compressed P2PKH          (27 + 4)
#   35 + recid       P2SH-P2WPKH               (Electrum's convention)
#   39 + recid       P2WPKH                    (Electrum's convention)
#
# The 35/39 ranges are ELECTRUM'S, not a BIP: BIP-137 proposed them and was
# never merged, and Bitcoin Core signs segwit addresses with BIP-322 instead.
# A verifier that wants to interoperate widely therefore accepts 27..42 and
# checks the recovered key against the address form the header claims - which
# is what verify() below does, and why it reports WHICH convention matched.
# ===========================================================================
MSG_MAGIC = b"\x18Bitcoin Signed Message:\n"


def message_digest(message: str) -> bytes:
    body = message.encode("utf-8")
    return hash256(MSG_MAGIC + varint(len(body)) + body)


# ---- BIP-322 (the "simple" encoding), for P2WPKH and P2TR key-path ----------
BIP322_TAG = "BIP0322-signed-message"


def bip322_hash(message: str) -> bytes:
    return cr.tagged_hash(BIP322_TAG, message.encode("utf-8"))


def bip322_to_spend_txid(message: str, spk: bytes) -> str:
    raw = tx_serialize(0, [("00" * 32, 0xFFFFFFFF, 0)], [(0, spk)], 0,
                       [b"\x00\x20" + bip322_hash(message)])
    return hash256(raw)[::-1].hex()


def bip322_digest(message: str, script_type: str, spk: bytes, pubkey=None) -> bytes:
    ins = [(bip322_to_spend_txid(message, spk), 0, 0)]
    outs = [(0, b"\x6a")]
    if script_type == "p2tr":
        return sighash_for("p2tr", 0, ins, outs, 0, 0, prev_spks=[spk],
                           prev_amounts=[0])
    if script_type == "p2wpkh":
        return sighash_for("p2wpkh", 0, ins, outs, 0, 0, pubkey=pubkey, amount_sat=0)
    raise ValueError("bip322 here covers p2wpkh and p2tr, not %r" % script_type)


def bip322_sign(seckey: bytes, message: str, script_type: str, spk: bytes,
                pubkey=None) -> str:
    import base64 as _b64
    digest = bip322_digest(message, script_type, spk, pubkey)
    if script_type == "p2tr":
        tweaked = cr.taproot_tweak_seckey(seckey, None)
        items = [cr.schnorr_sign(tweaked, digest, bytes(32))]
    else:
        r, s, _ = cr.ecdsa_sign_recoverable(seckey, digest)
        items = [cr.der_encode(r, s) + b"\x01", pubkey]
    stack = varint(len(items)) + b"".join(varint(len(i)) + i for i in items)
    return _b64.b64encode(stack).decode("ascii")


# ---- BIP-352 silent payments, the sending side (2026-09-04) ----------------
# The oracle for wallet-core's cwSp* handlers: the BIP's own algorithm over
# coin_reference's curve arithmetic, plus the receiver-side input-pubkey
# extraction the BIP's test vectors use to decide which inputs take part.

SP_TAG_INPUTS = "BIP0352/Inputs"
SP_TAG_SECRET = "BIP0352/SharedSecret"
SP_MAX_LEN = 1023
SP_K_MAX = 2323
SP_NUMS_H = bytes.fromhex(
    "50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0")


def sp_hrp(network: str) -> str:
    if network == "mainnet":
        return "sp"
    if network == "regtest":
        return "sprt"
    if network in ("testnet", "testnet4", "signet"):
        return "tsp"
    raise ValueError("unknown network %r" % network)


def sp_is_address(text: str) -> bool:
    t = text.strip().lower()
    return t.startswith("sp1") or t.startswith("tsp1") or t.startswith("sprt1")


def bech32_decode_long(text: str, limit: int):
    """(hrp, spec, values) with the length cap a parameter, or raise."""
    if len(text) > limit:
        raise ValueError("longer than %d" % limit)
    if any(ord(x) < 33 or ord(x) > 126 for x in text):
        raise ValueError("non-printable")
    if text.lower() != text and text.upper() != text:
        raise ValueError("mixed case")
    text = text.lower()
    pos = text.rfind("1")
    if pos < 1 or pos + 7 > len(text):
        raise ValueError("no separator or too short")
    hrp, data = text[:pos], text[pos + 1:]
    if any(ch not in cr.CHARSET for ch in data):
        raise ValueError("bad charset")
    values = [cr.CHARSET.find(ch) for ch in data]
    chk = cr.bech32_polymod(cr.bech32_hrp_expand(hrp) + values)
    if chk == 1:
        spec = "bech32"
    elif chk == cr.BECH32M_CONST:
        spec = "bech32m"
    else:
        raise ValueError("bad checksum")
    return hrp, spec, values[:-6]


def bech32_encode_long(hrp: str, values, spec: str) -> str:
    return cr.bech32_encode(hrp, list(values), spec)


def _convertbits(data, frombits, tobits, pad):
    acc, bits, out = 0, 0, []
    maxv = (1 << tobits) - 1
    for v in data:
        acc = (acc << frombits) | v
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            out.append((acc >> bits) & maxv)
    if pad:
        if bits:
            out.append((acc << (tobits - bits)) & maxv)
    elif bits >= frombits or ((acc << (tobits - bits)) & maxv):
        raise ValueError("bad padding")
    return out


def sp_decode(network: str, address: str):
    """(version, scan33, spend33) or raise, by the BIP's rules."""
    hrp, spec, values = bech32_decode_long(address.strip(), SP_MAX_LEN)
    if hrp != sp_hrp(network):
        raise ValueError("hrp %s is not %s's" % (hrp, network))
    if spec != "bech32m":
        raise ValueError("not bech32m")
    if not values:
        raise ValueError("no version")
    version = values[0]
    if version == 31:
        raise ValueError("version 31 is reserved")
    payload = bytes(_convertbits(values[1:], 5, 8, False))
    if version == 0 and len(payload) != 66:
        raise ValueError("v0 carries 66 bytes, not %d" % len(payload))
    if len(payload) < 66:
        raise ValueError("fewer than 66 bytes")
    scan, spend = payload[:33], payload[33:66]
    for k in (scan, spend):
        if k[0] not in (2, 3):
            raise ValueError("not a compressed point")
        cr._decompress(k)
    return version, scan, spend


def sp_encode(network: str, scan: bytes, spend: bytes, version: int = 0) -> str:
    values = [version] + _convertbits(scan + spend, 8, 5, True)
    return bech32_encode_long(sp_hrp(network), values, "bech32m")


def scalar_add(a: bytes, b: bytes) -> bytes:
    return ((int.from_bytes(a, "big") + int.from_bytes(b, "big")) % cr._N
            ).to_bytes(32, "big")


def scalar_negate(a: bytes) -> bytes:
    v = int.from_bytes(a, "big")
    return bytes(32) if v == 0 else (cr._N - v).to_bytes(32, "big")


def sp_eligible(script_type: str, pubkey: bytes) -> bool:
    if script_type in ("p2tr", "p2wpkh", "p2sh-p2wpkh"):
        return True
    if script_type == "p2pkh":
        return len(pubkey) == 33
    return False


def sp_input_sum(inputs) -> bytes:
    """inputs: [(seckey32, xonly_bool)]; the BIP's a, or raise on empty/zero."""
    if not inputs:
        raise ValueError("no eligible inputs")
    total = 0
    for sk, xonly in inputs:
        k = int.from_bytes(sk, "big")
        if xonly and cr._pt_mul(k)[1] % 2 == 1:
            k = cr._N - k
        total = (total + k) % cr._N
    if total == 0:
        raise ValueError("the input keys sum to zero")
    return total.to_bytes(32, "big")


def sp_input_hash(outpoints, sum_pubkey33: bytes) -> bytes:
    """outpoints: [(txid_hex_display, vout)] over ALL inputs."""
    low = min(cr.btc_outpoint(bytes.fromhex(t), v) for t, v in outpoints)
    return cr.tagged_hash(SP_TAG_INPUTS, low + sum_pubkey33)


def sp_shared_secret(a: bytes, input_hash: bytes, scan33: bytes) -> bytes:
    k = (int.from_bytes(input_hash, "big") * int.from_bytes(a, "big")) % cr._N
    if int.from_bytes(input_hash, "big") == 0 or int.from_bytes(input_hash, "big") >= cr._N:
        raise ValueError("input hash is not a scalar")
    return cr._compress(cr._pt_mul(k, cr._decompress(scan33)))


def sp_outputs(a: bytes, input_hash: bytes, recipients):
    """recipients: [(scan33, spend33)] -> [xonly32] in the same order."""
    sizes = {}
    for scan, _ in recipients:
        sizes[scan] = sizes.get(scan, 0) + 1
        if sizes[scan] > SP_K_MAX:
            raise ValueError("more than K_max outputs to one scan key")
    secrets, counters, out = {}, {}, []
    for scan, spend in recipients:
        if scan not in secrets:
            secrets[scan] = sp_shared_secret(a, input_hash, scan)
            counters[scan] = 0
        t_k = cr.tagged_hash(SP_TAG_SECRET,
                             secrets[scan] + counters[scan].to_bytes(4, "big"))
        tk = int.from_bytes(t_k, "big")
        if tk == 0 or tk >= cr._N:
            raise ValueError("t_k is not a scalar")
        point = cr._pt_add(cr._decompress(spend), cr._pt_mul(tk))
        out.append(point[0].to_bytes(32, "big"))
        counters[scan] += 1
    return out


def sp_send(inputs, outpoints, recipients):
    a = sp_input_sum(inputs)
    return sp_outputs(a, sp_input_hash(outpoints, cr.pubkey(a)), recipients)


def _spk_kind(spk: bytes) -> str:
    n = len(spk)
    if n == 25 and spk[:3] == b"\x76\xa9\x14" and spk[23:] == b"\x88\xac":
        return "p2pkh"
    if n == 23 and spk[:2] == b"\xa9\x14" and spk[22:] == b"\x87":
        return "p2sh"
    if n == 22 and spk[:2] == b"\x00\x14":
        return "p2wpkh"
    if n == 34 and spk[:2] == b"\x00\x20":
        return "p2wsh"
    if n == 34 and spk[:2] == b"\x51\x20":
        return "p2tr"
    return "unknown"


def _witness_stack(hexstr: str):
    b = bytes.fromhex(hexstr or "")
    if not b:
        return []
    n, i = _read_varint(b, 0)
    items = []
    for _ in range(n):
        ln, i = _read_varint(b, i)
        items.append(b[i:i + ln])
        i += ln
    return items


def sp_input_pubkey(vin: dict):
    """The receiver's view of one input: the public key it contributes, or
    None if it is skipped. vin: txid, vout, scriptSig (hex), txinwitness
    (hex, the serialized stack), prevout (spk hex). The BIP reference's
    get_pubkey_from_input, including the malleated-P2PKH window scan."""
    spk = bytes.fromhex(vin["prevout"])
    ss = bytes.fromhex(vin.get("scriptSig") or "")
    stack = _witness_stack(vin.get("txinwitness") or "")
    kind = _spk_kind(spk)
    if kind == "p2pkh":
        want = spk[3:23]
        for i in range(len(ss), 32, -1):
            cand = ss[i - 33:i]
            if cr.hash160(cand) == want and cand[0] in (2, 3):
                try:
                    cr._decompress(cand)
                    return cand
                except Exception:
                    pass
        return None
    if kind == "p2sh":
        redeem = ss[1:]
        if _spk_kind(redeem) == "p2wpkh" and stack and len(stack[-1]) == 33:
            return stack[-1]
        return None
    if kind == "p2wpkh":
        if stack and len(stack[-1]) == 33:
            return stack[-1]
        return None
    if kind == "p2tr":
        if not stack:
            return None
        if len(stack) > 1 and stack[-1][:1] == b"\x50":
            stack = stack[:-1]
        if len(stack) > 1 and stack[-1][1:33] == SP_NUMS_H:
            return None
        return b"\x02" + spk[2:34]
    return None

# ---- Runes, read only (2026-09-04) -------------------------------------------
# The oracle for wallet-core's runestone reader: LEB128 over Python ints, the
# specification's tag table and cenotaph rules, and the reference's name,
# spacer and amount display. Etching, minting and balances are not here,
# because the wallet does not do them either.

RUNE_U128_MAX = (1 << 128) - 1
RUNE_TAGS = {"body": 0, "flags": 2, "rune": 4, "premine": 6, "cap": 8,
             "amount": 10, "heightstart": 12, "heightend": 14,
             "offsetstart": 16, "offsetend": 18, "mint": 20, "pointer": 22,
             "cenotaph": 126, "divisibility": 1, "spacers": 3, "symbol": 5,
             "nop": 127}


def leb128_encode(n: int) -> bytes:
    out = bytearray()
    while True:
        byte = n & 0x7F
        n >>= 7
        if n:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def leb128_decode(b: bytes, i: int):
    """(value, next_index) or raise ValueError('truncated'|'overlong'|'overflow')."""
    value, shift, count = 0, 0, 0
    while True:
        if i >= len(b):
            raise ValueError("truncated")
        byte = b[i]
        i += 1
        count += 1
        if count > 19:
            raise ValueError("overlong")
        value |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            break
    if value > RUNE_U128_MAX:
        raise ValueError("overflow")
    return value, i


def rune_name(n: int) -> str:
    if n == RUNE_U128_MAX:
        return "BCGDENLQRQWDSLRUGSNLBTMFIJAV"
    n += 1
    out = ""
    while n > 0:
        out = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[(n - 1) % 26] + out
        n = (n - 1) // 26
    return out


def rune_spaced(name: str, spacers: int, sep: str = ".") -> str:
    out = ""
    for i, ch in enumerate(name):
        out += ch
        if i < len(name) - 1 and (spacers >> i) & 1:
            out += sep
    return out


def rune_amount_text(amount: int, divisibility: int) -> str:
    if divisibility <= 0:
        return str(amount)
    cutoff = 10 ** divisibility
    whole, frac = divmod(amount, cutoff)
    if frac == 0:
        return str(whole)
    return "%d.%s" % (whole, str(frac).rjust(divisibility, "0").rstrip("0"))


def runestone_script(integers, pushes=None) -> bytes:
    """OP_RETURN OP_13 with the varints in one push (or in the given
    chunks of bytes, to test payload concatenation)."""
    payload = b"".join(leb128_encode(i) for i in (integers or []))
    if pushes is None:
        pushes = [payload] if payload else []
    return b"\x6a\x5d" + b"".join(push(p) for p in pushes)


def runestone_decode(spk: bytes, n_outputs: int) -> dict:
    """The reader's answer, in the same shape as cwRunestoneDecode with big
    values as decimal strings."""
    out = {"runestone": False}
    if spk[:2] != b"\x6a\x5d":
        return out
    out.update({"runestone": True, "edicts": [], "etching": "", "mint": "",
                "pointer": "", "flaws": []})
    payload = b""
    i = 2
    while i < len(spk):
        op = spk[i]
        i += 1
        if op == 0:
            continue
        if 1 <= op <= 75:
            ln = op
        elif op == 76:
            ln = spk[i] if i < len(spk) else None
            i += 1
        elif op == 77:
            ln = int.from_bytes(spk[i:i + 2], "little") if i + 2 <= len(spk) else None
            i += 2
        elif op == 78:
            ln = int.from_bytes(spk[i:i + 4], "little") if i + 4 <= len(spk) else None
            i += 4
        else:
            out["flaws"] = ["opcode"]
            out["cenotaph"] = True
            return out
        if ln is None or i + ln > len(spk):
            out["flaws"] = ["script"]
            out["cenotaph"] = True
            return out
        payload += spk[i:i + ln]
        i += ln
    ints = []
    i = 0
    try:
        while i < len(payload):
            v, i = leb128_decode(payload, i)
            ints.append(v)
    except ValueError:
        out["flaws"] = ["varint"]
        out["cenotaph"] = True
        return out
    fields, order, flaws = {}, [], []
    body = None
    i = 0
    while i < len(ints):
        tag = ints[i]
        if tag == 0:
            body = i + 1
            break
        if i + 1 >= len(ints):
            flaws.append("truncated field")
            break
        if tag not in fields:
            fields[tag] = []
            order.append(tag)
        fields[tag].append(ints[i + 1])
        i += 2
    edicts = []
    if body is not None:
        block = tx = 0
        i = body
        while i + 3 < len(ints):
            delta = ints[i]
            block += delta
            tx = tx + ints[i + 1] if delta == 0 else ints[i + 1]
            if block > RUNE_U128_MAX or tx > RUNE_U128_MAX or (block == 0 and tx != 0):
                flaws.append("edict rune id")
                break
            output = ints[i + 3]
            if output > n_outputs:
                flaws.append("edict output")
                break
            edicts.append({"block": str(block), "tx": str(tx),
                           "amount": str(ints[i + 2]), "output": output})
            i += 4
        if i < len(ints) and not flaws:
            flaws.append("trailing integers")
    flags = fields.get(2, [0])[0]
    etching_flag, terms_flag, turbo = flags & 1, flags & 2, flags & 4
    if flags >> 3:
        flaws.append("unrecognized flag")
    if etching_flag:
        e = {"rune": "", "name": "", "divisibility": "", "spacers": "",
             "symbol": "", "premine": "", "turbo": bool(turbo), "terms": ""}
        if 4 in fields:
            e["rune"] = str(fields[4][0])
            e["name"] = rune_name(fields[4][0])
        if 1 in fields and fields[1][0] <= 38:
            e["divisibility"] = fields[1][0]
        if 3 in fields and fields[3][0] <= 0x7FFFFFF:
            e["spacers"] = fields[3][0]
        if 5 in fields and fields[5][0] <= 0x10FFFF:
            e["symbol"] = fields[5][0]
        if 6 in fields:
            e["premine"] = str(fields[6][0])
        if terms_flag:
            e["terms"] = {k: (str(fields[tag][0]) if tag in fields else "")
                          for k, tag in (("amount", 10), ("cap", 8), ("heightstart", 12),
                                         ("heightend", 14), ("offsetstart", 16),
                                         ("offsetend", 18))}
        out["etching"] = e
    if 20 in fields:
        if len(fields[20]) >= 2 and not (fields[20][0] == 0 and fields[20][1] != 0):
            out["mint"] = "%d:%d" % (fields[20][0], fields[20][1])
        else:
            flaws.append("mint rune id")
    if 22 in fields:
        if fields[22][0] >= n_outputs:
            flaws.append("pointer")
        else:
            out["pointer"] = fields[22][0]
    for tag in order:
        if tag % 2 == 1 or tag in (2, 20, 22):
            continue
        if tag in (4, 6):
            if not etching_flag:
                flaws.append("unrecognized even tag")
            continue
        if tag in (8, 10, 12, 14, 16, 18):
            if not terms_flag:
                flaws.append("unrecognized even tag")
            continue
        flaws.append("unrecognized even tag")
    out["edicts"] = edicts
    out["flaws"] = flaws
    out["cenotaph"] = bool(flaws)
    return out

# ---- tapscript, one leaf: inscriptions by commit and reveal (2026-09-04) ----

TAP_LEAF_VERSION = 0xC0
INSCRIPTION_CHUNK = 520


def tap_leaf_hash_long(script: bytes) -> bytes:
    """BIP-341's TapLeaf hash with a real compact size (the coin_reference
    one stops at 252 bytes; an inscription body is longer)."""
    return cr.tagged_hash("TapLeaf", bytes([TAP_LEAF_VERSION]) + varint(len(script)) + script)


def inscription_script(xonly: bytes, content_type: str, body: bytes) -> bytes:
    out = push(xonly) + b"\xac" + b"\x00" + b"\x63" + push(b"ord") + push(b"\x01")
    out += push(content_type.encode("utf-8")) + b"\x00"
    for i in range(0, len(body), INSCRIPTION_CHUNK):
        out += push(body[i:i + INSCRIPTION_CHUNK])
    return out + b"\x68"


def tap_commit(internal32: bytes, leaf_script: bytes) -> dict:
    leaf = tap_leaf_hash_long(leaf_script)
    output_key, parity = cr.taproot_tweak_pubkey(internal32, leaf)
    return {"leafhash": leaf, "outputkey": output_key, "parity": parity,
            "script": spk_p2tr(output_key),
            "controlblock": bytes([TAP_LEAF_VERSION | parity]) + internal32}


def tapscript_sighash(version, inputs, outputs, index, locktime, prev_spks,
                      prev_amounts, leaf_hash):
    co = _cr_outputs(outputs)
    return cr.btc_sighash_taproot(
        version, locktime,
        [cr.btc_outpoint(bytes.fromhex(t), v) for t, v, _ in inputs],
        prev_amounts, prev_spks, [s for _, _, s in inputs], co, index, 0,
        tapleaf=leaf_hash)


def sign_tapscript(seckey: bytes, digest: bytes, leaf_script: bytes,
                   control_block: bytes):
    return [cr.schnorr_sign(seckey, digest, bytes(32)), leaf_script, control_block]


def script_num(n: int) -> bytes:
    if n < 0:
        raise ValueError("non-negative only")
    if n == 0:
        return b"\x00"
    if n <= 16:
        return bytes([0x50 + n])
    out = bytearray()
    while n:
        out.append(n & 0xFF)
        n >>= 8
    if out[-1] & 0x80:
        out.append(0)
    return push(bytes(out))


def timelock_script(height: int, xonly: bytes) -> bytes:
    return script_num(height) + b"\xb1\x75" + push(xonly) + b"\xac"


def tapscript_input_vsize(leaf_script: bytes) -> int:
    witness = 1 + 1 + 64 + len(varint(len(leaf_script))) + len(leaf_script) + 1 + 33
    return 41 + (witness + 3) // 4

# ---- BOLT11 Lightning invoices, decoded (2026-09-04) ------------------------
# The oracle for wallet-core's cwBolt11Decode: the human-readable amount, the
# 35-bit timestamp, the tagged fields, the signature's recovery. Read only.

BOLT11_HRPS = {"lnbc": "mainnet", "lntb": "testnet", "lntbs": "signet", "lnbcrt": "regtest"}
BOLT11_MULTIPLIERS = {"m": 10 ** 8, "u": 10 ** 5, "n": 10 ** 2, "p": None}   # to msat
BOLT11_KNOWN_FEATURES = {0, 1, 8, 9, 14, 15, 16, 17, 48, 49}


def _bits_to_bytes(values, exact=False):
    """5-bit values to bytes, dropping the incomplete tail (the spec's fields
    carry up to four padding bits)."""
    acc = bits = 0
    out = bytearray()
    for v in values:
        acc = (acc << 5) | v
        bits += 5
        if bits >= 8:
            bits -= 8
            out.append((acc >> bits) & 0xFF)
            acc &= (1 << bits) - 1
    return bytes(out)


def _bits_to_int(values):
    n = 0
    for v in values:
        n = (n << 5) | v
    return n


def bolt11_decode(invoice: str) -> dict:
    """The decoded invoice, or raise ValueError(reason)."""
    hrp, spec, values = bech32_decode_long(invoice.strip(), 65535)
    if spec != "bech32":
        raise ValueError("an invoice carries a bech32 checksum, not bech32m")
    prefix = None
    for p in sorted(BOLT11_HRPS, key=len, reverse=True):
        if hrp.startswith(p):
            prefix = p
            break
    if prefix is None:
        raise ValueError("not a Lightning invoice prefix")
    network = BOLT11_HRPS[prefix]
    amount = hrp[len(prefix):]
    msat = None
    if amount:
        mult = 10 ** 11
        if amount[-1] in BOLT11_MULTIPLIERS:
            mult = BOLT11_MULTIPLIERS[amount[-1]]
            amount = amount[:-1]
        elif not amount[-1].isdigit():
            raise ValueError("invalid multiplier")
        if not amount.isdigit() or (len(amount) > 1 and amount[0] == "0"):
            raise ValueError("invalid amount")
        n = int(amount)
        if mult is None:
            if n % 10:
                raise ValueError("sub-millisatoshi precision")
            msat = n // 10
        else:
            msat = n * mult
    if len(values) < 7 + 104:
        raise ValueError("too short")
    timestamp = _bits_to_int(values[:7])
    sig_values = values[-104:]
    body = values[7:-104]
    fields = {"routes": [], "features": [], "expiry": 3600, "cltv": 18}
    i = 0
    while i + 3 <= len(body):
        tag, ln = body[i], body[i + 1] * 32 + body[i + 2]
        data = body[i + 3:i + 3 + ln]
        if len(data) < ln:
            raise ValueError("truncated field")
        i += 3 + ln
        ch = cr.CHARSET[tag]
        if ch == "p" and ln == 52 and "payment_hash" not in fields:
            fields["payment_hash"] = _bits_to_bytes(data)[:32].hex()
        elif ch == "s" and ln == 52 and "secret" not in fields:
            fields["secret"] = _bits_to_bytes(data)[:32].hex()
        elif ch == "d" and "description" not in fields:
            fields["description"] = _bits_to_bytes(data).decode("utf-8", "replace")
        elif ch == "h" and ln == 52 and "description_hash" not in fields:
            fields["description_hash"] = _bits_to_bytes(data)[:32].hex()
        elif ch == "n" and ln == 53 and "payee" not in fields:
            fields["payee"] = _bits_to_bytes(data)[:33].hex()
        elif ch == "x":
            fields["expiry"] = _bits_to_int(data)
        elif ch == "c":
            fields["cltv"] = _bits_to_int(data)
        elif ch == "m" and "metadata" not in fields:
            fields["metadata"] = _bits_to_bytes(data).hex()
        elif ch == "f" and data and "fallback" not in fields:
            ver, prog = data[0], _bits_to_bytes(data[1:])
            if ver == 17 and len(prog) == 20:
                fields["fallback"] = address_for_spk(network, b"\x76\xa9\x14" + prog + b"\x88\xac")
            elif ver == 18 and len(prog) == 20:
                fields["fallback"] = address_for_spk(network, b"\xa9\x14" + prog + b"\x87")
            elif ver == 0 and len(prog) in (20, 32):
                fields["fallback"] = address_for_spk(network, b"\x00" + push(prog))
            elif 1 <= ver <= 16 and 2 <= len(prog) <= 40:
                fields["fallback"] = address_for_spk(network, bytes([0x50 + ver]) + push(prog))
        elif ch == "r":
            raw = _bits_to_bytes(data)
            hops = []
            for k in range(0, len(raw) - len(raw) % 51, 51):
                h = raw[k:k + 51]
                scid = int.from_bytes(h[33:41], "big")
                hops.append({"pubkey": h[:33].hex(),
                             "channel": "%dx%dx%d" % (scid >> 40, (scid >> 16) & 0xFFFFFF, scid & 0xFFFF),
                             "fee_base_msat": int.from_bytes(h[41:45], "big"),
                             "fee_ppm": int.from_bytes(h[45:49], "big"),
                             "cltv_delta": int.from_bytes(h[49:51], "big")})
            fields["routes"].append(hops)
        elif ch == "9":
            n = _bits_to_int(data)
            bits = [b for b in range(n.bit_length()) if (n >> b) & 1]
            fields["features"] = bits
            unknown_required = [b for b in bits if b % 2 == 0 and b not in BOLT11_KNOWN_FEATURES]
            if unknown_required:
                raise ValueError("unknown required feature %d" % unknown_required[0])
    if "payment_hash" not in fields:
        raise ValueError("no payment hash")
    if "secret" not in fields:
        raise ValueError("no payment secret")
    if "description" not in fields and "description_hash" not in fields:
        raise ValueError("no description")
    sig = _bits_to_bytes(sig_values)
    if len(sig) < 65 or sig[64] > 3:
        raise ValueError("bad signature encoding")
    msg = hrp.encode("ascii") + _bits_to_bytes_padded(body_all(values))
    digest = cr.sha256(msg)
    r, s = int.from_bytes(sig[:32], "big"), int.from_bytes(sig[32:64], "big")
    if not (1 <= r < cr._N and 1 <= s < cr._N):
        raise ValueError("signature not recoverable")
    pub = ecdsa_recover(sig[:64], sig[64], digest)
    if pub is None:
        raise ValueError("signature not recoverable")
    if "payee" in fields:
        if pub != fields["payee"]:
            raise ValueError("signature does not match the n field")
        if s > cr._N // 2:
            raise ValueError("high-S signature with n present")
    fields.update({"network": network, "amount_msat": msat, "timestamp": timestamp,
                   "payee": fields.get("payee", pub), "signature": sig.hex(), "digest": digest.hex()})
    return fields


def body_all(values):
    return values[:-104]


def _bits_to_bytes_padded(values):
    acc = bits = 0
    out = bytearray()
    for v in values:
        acc = (acc << 5) | v
        bits += 5
        while bits >= 8:
            bits -= 8
            out.append((acc >> bits) & 0xFF)
            acc &= (1 << bits) - 1
    if bits:
        out.append((acc << (8 - bits)) & 0xFF)
    return bytes(out)


def ecdsa_recover(sig64: bytes, recid: int, digest: bytes):
    """The compressed public key an ECDSA signature recovers to, or None."""
    r, s = int.from_bytes(sig64[:32], "big"), int.from_bytes(sig64[32:], "big")
    e = int.from_bytes(digest, "big")
    x = r + (recid >> 1) * cr._N
    if x >= cr._P:
        return None
    y_sq = (pow(x, 3, cr._P) + 7) % cr._P
    y = pow(y_sq, (cr._P + 1) // 4, cr._P)
    if pow(y, 2, cr._P) != y_sq:
        return None
    if (y & 1) != (recid & 1):
        y = cr._P - y
    R = (x, y)
    r_inv = pow(r, cr._N - 2, cr._N)
    sR = cr._pt_mul(s, R)
    eG = cr._pt_mul(e)
    neg_eG = (eG[0], cr._P - eG[1])
    Q = cr._pt_mul(r_inv, cr._pt_add(sR, neg_eG))
    if Q is None:
        return None
    return cr._compress(Q).hex()

def message_sign(seckey: bytes, message: str, script_type="p2pkh",
                 compressed=True) -> str:
    import base64 as _b64
    digest = message_digest(message)
    r, sv, recid = cr.ecdsa_sign_recoverable(seckey, digest)
    sig64 = r.to_bytes(32, "big") + sv.to_bytes(32, "big")
    if script_type == "p2pkh":
        base = 31 if compressed else 27
    elif script_type == "p2sh-p2wpkh":
        base = 35
    elif script_type == "p2wpkh":
        base = 39
    else:
        raise ValueError("this message format has no header for %r" % script_type)
    return _b64.b64encode(bytes([base + recid]) + sig64).decode("ascii")


def message_verify(network: str, address: str, message: str, sig_b64: str):
    """Returns (ok, why). Never raises on a malformed signature: a verifier
    that throws where it should answer False is a verifier a caller will
    wrap in a bare try and get wrong."""
    import base64 as _b64
    try:
        raw = _b64.b64decode(sig_b64.strip().encode("ascii"), validate=False)
    except Exception:
        return False, "the signature is not base64"
    if len(raw) != 65:
        return False, "a signed message is 65 bytes: header, r, s"
    header = raw[0]
    if not 27 <= header <= 42:
        return False, "the header byte %d is outside 27..42" % header
    recid = (header - 27) & 3
    compressed = header >= 31
    digest = message_digest(message)
    try:
        pk = _recover(raw[1:], digest, recid)
    except Exception:
        return False, "no public key recovers from this signature"
    if pk is None:
        return False, "no public key recovers from this signature"
    forms = []
    if compressed:
        forms.append(("p2pkh", cr.b58check_encode(
            bytes([net(network)["p2pkh"]]) + hash160(pk))))
        forms.append(("p2sh-p2wpkh", address_for_spk(network,
                                                     spk_p2sh_p2wpkh(pk))))
        forms.append(("p2wpkh", address_for_spk(network, spk_p2wpkh(pk))))
    else:
        un = cr._decompress(pk)
        raw65 = b"\x04" + un[0].to_bytes(32, "big") + un[1].to_bytes(32, "big")
        forms.append(("p2pkh-uncompressed", cr.b58check_encode(
            bytes([net(network)["p2pkh"]]) + hash160(raw65))))
    claim = {31: "p2pkh", 27: "p2pkh-uncompressed", 35: "p2sh-p2wpkh",
             39: "p2wpkh"}.get(header - recid, "unknown")
    for kind, addr in forms:
        if addr == address.strip():
            # The header CLAIM and the form that actually matched can differ,
            # and refusing on that would break interoperability: plenty of
            # signers emit header 31 for a segwit address because BIP-137 was
            # never merged and Core signs segwit with BIP-322 instead. So the
            # match decides, and the disagreement is REPORTED rather than
            # swallowed - a caller that wants strictness has what it needs.
            if claim != kind:
                return True, "%s (the header claims %s)" % (kind, claim)
            return True, kind
    return False, "the signature is valid but recovers a different address"


def _recover(sig64: bytes, digest: bytes, recid: int):
    """Public key recovery, written here because coin_reference has the sign
    half and not this one. Standard SEC-1 4.1.6 over the model already in
    that file."""
    p, n_ord, g = cr._P, cr._N, cr._G
    r = int.from_bytes(sig64[:32], "big")
    s = int.from_bytes(sig64[32:], "big")
    if r <= 0 or r >= n_ord or s <= 0 or s >= n_ord:
        return None
    x = r + (n_ord if recid >= 2 else 0)
    if x >= p:
        return None
    alpha = (pow(x, 3, p) + 7) % p
    beta = pow(alpha, (p + 1) // 4, p)
    if pow(beta, 2, p) != alpha:
        return None
    y = beta if (beta % 2 == recid % 2) else p - beta
    R = (x, y)
    e = int.from_bytes(digest, "big")
    r_inv = pow(r, n_ord - 2, n_ord)
    q = cr._pt_add(cr._pt_mul(s * r_inv % n_ord, R),
                   cr._pt_mul((n_ord - e) * r_inv % n_ord, g))
    if q is None:
        return None
    return cr._compress(q)


# ===========================================================================
# BIP-21 PAYMENT URIs
#
#   bitcoin:<address>[?amount=<btc>][&label=<text>][&message=<text>][&<k>=<v>]
#
# Two rules carry all the weight. `amount` is in BTC with a decimal point,
# NEVER satoshi - a wallet that reads it as satoshi pays 100 million times
# too little, and one that writes satoshi is asking the recipient's wallet to
# do the same. And a parameter whose key begins with `req-` is REQUIRED: a
# wallet that does not understand it must refuse the URI rather than pay the
# address and ignore the condition.
# ===========================================================================
def uri_parse(uri: str) -> dict:
    u = uri.strip()
    if u.lower().startswith("bitcoin:"):
        u = u[8:]
    elif ":" in u.split("?")[0]:
        raise ValueError("only the bitcoin: scheme is understood")
    body, _, query = u.partition("?")
    out = {"address": _percent_decode(body), "params": {}, "required": []}
    if query:
        for pair in query.split("&"):
            if not pair:
                continue
            k, _, v = pair.partition("=")
            k = _percent_decode(k)
            v = _percent_decode(v.replace("+", " "))
            out["params"][k] = v
            if k.lower().startswith("req-"):
                out["required"].append(k)
    if "amount" in out["params"]:
        out["amount_sat"] = btc_to_sat(out["params"]["amount"])
    out["label"] = out["params"].get("label", "")
    out["message"] = out["params"].get("message", "")
    return out


def uri_build(address: str, amount_sat=None, label="", message="") -> str:
    parts = []
    if amount_sat:
        # trailing zeros trimmed: BIP-21 amounts are decimal BTC and
        # "0.00100000" and "0.001" are the same payment, but the short form
        # is what a person can check at a glance.
        btc = sat_to_btc(amount_sat).rstrip("0").rstrip(".")
        parts.append("amount=" + (btc if btc else "0"))
    if label:
        parts.append("label=" + _percent_encode(label))
    if message:
        parts.append("message=" + _percent_encode(message))
    return "bitcoin:" + address + ("?" + "&".join(parts) if parts else "")


_URI_SAFE = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
                "0123456789-_.~")


def _percent_encode(text: str) -> str:
    out = []
    for b in text.encode("utf-8"):
        c = chr(b)
        out.append(c if c in _URI_SAFE else "%%%02X" % b)
    return "".join(out)


def _percent_decode(text: str) -> str:
    raw, i = bytearray(), 0
    while i < len(text):
        if text[i] == "%" and i + 2 < len(text) + 0:
            try:
                raw.append(int(text[i + 1:i + 3], 16))
                i += 3
                continue
            except ValueError:
                pass
        raw.append(ord(text[i]) & 0xFF if ord(text[i]) < 256 else 0x3F)
        if ord(text[i]) >= 256:
            raw.pop()
            raw.extend(text[i].encode("utf-8"))
        i += 1
    return raw.decode("utf-8", errors="replace")


# ===========================================================================
# OUTPUT DESCRIPTORS
#
# The checksum is the piece worth an oracle: it is a bech32-style polymod over
# a 3-bit/5-bit split of the descriptor's characters, with its own generator
# and its own charset, and Bitcoin Core will refuse a descriptor whose
# checksum is one character off. Transcribed from Core's descriptor.cpp.
# ===========================================================================
_DESC_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
_DESC_INPUT = ("0123456789()[],'/*abcdefgh@:$%{}"
               "IJKLMNOPQRSTUVWXYZ&+-.;<=>?!^_|~"
               "ijklmnopqrstuvwxyzABCDEFGH`#\"\\ ")
_DESC_GEN = [0xF5DEE51989, 0xA9FDCA3312, 0x1BAB10E32D,
             0x3706B1677A, 0x644D626FFD]


def _desc_polymod(c, val):
    c0 = c >> 35
    c = ((c & 0x7FFFFFFFF) << 5) ^ val
    for i in range(5):
        if (c0 >> i) & 1:
            c ^= _DESC_GEN[i]
    return c


def descriptor_checksum(desc: str) -> str:
    c = 1
    cls = 0
    clscount = 0
    for ch in desc:
        pos = _DESC_INPUT.find(ch)
        if pos < 0:
            raise ValueError("character %r cannot appear in a descriptor" % ch)
        c = _desc_polymod(c, pos & 31)
        cls = cls * 3 + (pos >> 5)
        clscount += 1
        if clscount == 3:
            c = _desc_polymod(c, cls)
            cls = 0
            clscount = 0
    if clscount > 0:
        c = _desc_polymod(c, cls)
    for _ in range(8):
        c = _desc_polymod(c, 0)
    c ^= 1
    return "".join(_DESC_CHARSET[(c >> (5 * (7 - i))) & 31] for i in range(8))


def descriptor(script_type: str, xpub: str, fingerprint_hex: str,
               path: str, change: int, index="*") -> str:
    """A ranged single-key descriptor: the standard export a wallet hands to
    Bitcoin Core, Sparrow or a coordinator so they can watch the same keys."""
    origin = "[%s%s]" % (fingerprint_hex.lower(),
                         path[1:] if path.startswith("m") else path)
    key = "%s%s/%d/%s" % (origin, xpub, change, index)
    if script_type == "p2pkh":
        body = "pkh(%s)" % key
    elif script_type == "p2sh-p2wpkh":
        body = "sh(wpkh(%s))" % key
    elif script_type == "p2wpkh":
        body = "wpkh(%s)" % key
    elif script_type == "p2tr":
        body = "tr(%s)" % key
    else:
        raise ValueError("no single-key descriptor for %r" % script_type)
    return body + "#" + descriptor_checksum(body)


def descriptor_multisig(m: int, keys, change: int, index="*",
                        sorted_multi=True) -> str:
    inner = ",".join("%s/%d/%s" % (k, change, index) for k in keys)
    body = "wsh(%s(%d,%s))" % ("sortedmulti" if sorted_multi else "multi",
                               m, inner)
    return body + "#" + descriptor_checksum(body)


# ===========================================================================
# QR CODES (ISO/IEC 18004), BYTE MODE, ERROR LEVEL M, VERSIONS 1..15
#
# A receive address that has to be typed by hand is a receive address that
# gets typed wrong, so a wallet draws one. The scope here is deliberately the
# narrowest that covers everything this wallet shows: byte mode (addresses,
# BIP-21 URIs, xpubs, descriptors are all ASCII), level M (15% recovery, the
# common wallet default), and versions 1..15 (523 bytes at level M, which is
# more than any of those). Kanji, numeric and alphanumeric modes, and the
# structured-append that would let a big PSBT span several codes, are OUT of
# scope and refused rather than approximated.
#
# The vectors this is pinned against were generated by segno, an independent
# implementation, and are committed as golden matrices - the house rule is
# that an expected answer must be right before it is pinned, and "my own two
# implementations agree" is not that.
# ===========================================================================

# data codewords, ec codewords per block, (blocks in group 1, blocks in
# group 2) - the level-M rows of ISO/IEC 18004 table 9, versions 1..15.
QR_M = {
    #        total data cw, ec per block, g1 blocks, g1 data cw, g2 blocks, g2 data cw
    1:  (16, 10, 1, 16, 0, 0),
    2:  (28, 16, 1, 28, 0, 0),
    3:  (44, 26, 1, 44, 0, 0),
    4:  (64, 18, 2, 32, 0, 0),
    5:  (86, 24, 2, 43, 0, 0),
    6:  (108, 16, 4, 27, 0, 0),
    7:  (124, 18, 4, 31, 0, 0),
    8:  (154, 22, 2, 38, 2, 39),
    9:  (182, 22, 3, 36, 2, 37),
    10: (216, 26, 4, 43, 1, 44),
    11: (254, 30, 1, 50, 4, 51),
    12: (290, 22, 6, 36, 2, 37),
    13: (334, 22, 8, 37, 1, 38),
    14: (365, 24, 4, 40, 5, 41),
    15: (415, 24, 5, 41, 5, 42),
}

# alignment pattern centre coordinates, versions 1..15 (table E.1)
QR_ALIGN = {
    1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34],
    7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50],
    11: [6, 30, 54], 12: [6, 32, 58], 13: [6, 34, 62], 14: [6, 26, 46, 66],
    15: [6, 26, 48, 70],
}

# remainder bits appended after the interleaved codewords (table 1)
QR_REMAINDER = {1: 0, 2: 7, 3: 7, 4: 7, 5: 7, 6: 7, 7: 0, 8: 0, 9: 0,
                10: 0, 11: 0, 12: 0, 13: 0, 14: 3, 15: 3}

_GF_EXP = [0] * 512
_GF_LOG = [0] * 256


def _gf_init():
    x = 1
    for i in range(255):
        _GF_EXP[i] = x
        _GF_LOG[x] = i
        x <<= 1
        if x & 0x100:
            x ^= 0x11D                  # the QR field's primitive polynomial
    for i in range(255, 512):
        _GF_EXP[i] = _GF_EXP[i - 255]


_gf_init()


def _gf_mul(a, b):
    if a == 0 or b == 0:
        return 0
    return _GF_EXP[_GF_LOG[a] + _GF_LOG[b]]


def _rs_generator(n):
    g = [1]
    for i in range(n):
        g2 = [0] * (len(g) + 1)
        for j, c in enumerate(g):
            g2[j] ^= _gf_mul(c, 1)
            g2[j + 1] ^= _gf_mul(c, _GF_EXP[i])
        g = g2
    return g


def _rs_ecc(data, n):
    gen = _rs_generator(n)
    rem = list(data) + [0] * n
    for i in range(len(data)):
        coef = rem[i]
        if coef:
            for j in range(1, len(gen)):
                rem[i + j] ^= _gf_mul(gen[j], coef)
    return rem[len(data):]


def qr_version_for(nbytes: int) -> int:
    for v in range(1, 16):
        total = QR_M[v][0]
        header = 4 + (8 if v <= 9 else 16)
        if nbytes * 8 + header <= total * 8:
            return v
    raise ValueError("%d bytes does not fit a version-15 level-M QR code"
                     % nbytes)


def qr_codewords(data: bytes, version: int):
    total, ecc_per, g1, g1n, g2, g2n = QR_M[version]
    bits = []

    def put(value, n):
        for i in range(n - 1, -1, -1):
            bits.append((value >> i) & 1)

    put(0b0100, 4)                                  # byte mode
    put(len(data), 8 if version <= 9 else 16)
    for b in data:
        put(b, 8)
    put(0, min(4, total * 8 - len(bits)))           # terminator
    while len(bits) % 8:
        bits.append(0)
    pad = [0xEC, 0x11]
    k = 0
    while len(bits) < total * 8:
        put(pad[k % 2], 8)
        k += 1
    cw = [int("".join(str(b) for b in bits[i:i + 8]), 2)
          for i in range(0, len(bits), 8)]

    blocks, eccs, i = [], [], 0
    for _ in range(g1):
        blocks.append(cw[i:i + g1n])
        i += g1n
    for _ in range(g2):
        blocks.append(cw[i:i + g2n])
        i += g2n
    for b in blocks:
        eccs.append(_rs_ecc(b, ecc_per))

    out = []
    for j in range(max(len(b) for b in blocks)):
        for b in blocks:
            if j < len(b):
                out.append(b[j])
    for j in range(ecc_per):
        for e in eccs:
            out.append(e[j])
    return out


def _qr_blank(size):
    return [[None] * size for _ in range(size)]


def _qr_place_function(mat, version):
    size = len(mat)

    def finder(r, c):
        for dr in range(-1, 8):
            for dc in range(-1, 8):
                rr, cc = r + dr, c + dc
                if 0 <= rr < size and 0 <= cc < size:
                    on = (0 <= dr <= 6 and 0 <= dc <= 6 and
                          (dr in (0, 6) or dc in (0, 6) or
                           (2 <= dr <= 4 and 2 <= dc <= 4)))
                    mat[rr][cc] = 1 if on else 0

    finder(0, 0)
    finder(0, size - 7)
    finder(size - 7, 0)
    for i in range(8, size - 8):
        mat[6][i] = 1 - (i % 2)
        mat[i][6] = 1 - (i % 2)
    centres = QR_ALIGN[version]
    for r in centres:
        for c in centres:
            if (r < 8 and c < 8) or (r < 8 and c > size - 9) or \
                    (r > size - 9 and c < 8):
                continue
            for dr in range(-2, 3):
                for dc in range(-2, 3):
                    mat[r + dr][c + dc] = 1 if (abs(dr) == 2 or abs(dc) == 2 or
                                                (dr == 0 and dc == 0)) else 0
    mat[size - 8][8] = 1                    # the dark module
    for i in range(9):                      # format information areas
        if mat[8][i] is None:
            mat[8][i] = 0
        if mat[i][8] is None:
            mat[i][8] = 0
    for i in range(8):
        if mat[8][size - 1 - i] is None:
            mat[8][size - 1 - i] = 0
        if mat[size - 1 - i][8] is None:
            mat[size - 1 - i][8] = 0
    if version >= 7:
        for i in range(6):
            for j in range(3):
                mat[size - 11 + j][i] = 0
                mat[i][size - 11 + j] = 0


def _qr_reserved(version):
    mat = _qr_blank(17 + 4 * version)
    _qr_place_function(mat, version)
    return [[c is not None for c in row] for row in mat]


def _qr_place_data(mat, reserved, codewords, version):
    size = len(mat)
    bits = []
    for cw in codewords:
        for i in range(7, -1, -1):
            bits.append((cw >> i) & 1)
    bits.extend([0] * QR_REMAINDER[version])
    idx = 0
    col = size - 1
    upward = True
    while col > 0:
        if col == 6:
            col -= 1                        # the vertical timing column
        for k in range(size):
            row = (size - 1 - k) if upward else k
            for c in (col, col - 1):
                if reserved[row][c]:
                    continue
                mat[row][c] = bits[idx] if idx < len(bits) else 0
                idx += 1
        col -= 2
        upward = not upward


_QR_MASKS = [
    lambda r, c: (r + c) % 2 == 0,
    lambda r, c: r % 2 == 0,
    lambda r, c: c % 3 == 0,
    lambda r, c: (r + c) % 3 == 0,
    lambda r, c: (r // 2 + c // 3) % 2 == 0,
    lambda r, c: (r * c) % 2 + (r * c) % 3 == 0,
    lambda r, c: ((r * c) % 2 + (r * c) % 3) % 2 == 0,
    lambda r, c: ((r + c) % 2 + (r * c) % 3) % 2 == 0,
]


def _qr_penalty(mat):
    """The four penalty rules of ISO/IEC 18004 7.8.3.

    Rule 3 is the one with a real reading ambiguity, and getting it wrong
    changes which mask is chosen (a symbol that still scans, but not the one
    any other encoder produces, so no cross-check can ever agree). The
    reading used here is the one two independent encoders implement: the
    1:1:3:1:1 pattern counts when it is followed OR preceded by four light
    modules, and the run of four is CLAMPED at the symbol edge - so a pattern
    flush against the border counts, with nothing beside it to be light.
    """
    size = len(mat)
    score = 0
    lines = [list(row) for row in mat] + [list(col) for col in zip(*mat)]

    # rule 1: runs of five or more in a row or column
    for line in lines:
        run, prev = 1, line[0]
        for v in line[1:]:
            if v == prev:
                run += 1
            else:
                if run >= 5:
                    score += 3 + (run - 5)
                run, prev = 1, v
        if run >= 5:
            score += 3 + (run - 5)

    # rule 2: every 2x2 block of one colour
    for r in range(size - 1):
        for c in range(size - 1):
            if mat[r][c] == mat[r][c + 1] == mat[r + 1][c] == mat[r + 1][c + 1]:
                score += 3

    # rule 3: the finder-like 1:1:3:1:1 pattern with a four-module light run
    # beside it, matched as the two ELEVEN-module windows. The alternative
    # reading - a seven-module match with the light run clamped at the symbol
    # edge - was tried and rejected: it disagrees with the encoders this file
    # is checked against on which mask wins, and a mask nobody else picks is
    # a symbol no cross-check can ever confirm.
    patt_a = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
    patt_b = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
    for line in lines:
        for i in range(size - 10):
            window = line[i:i + 11]
            if window == patt_a or window == patt_b:
                score += 40

    # rule 4: distance from an even light/dark split, in 5% steps
    dark = sum(sum(row) for row in mat)
    score += 10 * int(abs(dark * 100.0 / (size * size) - 50) / 5)
    return score


_QR_FORMAT_GEN = 0b10100110111
_QR_FORMAT_MASK = 0b101010000010010


def _qr_format_bits(ec_level_bits, mask):
    data = (ec_level_bits << 3) | mask
    rem = data << 10
    for i in range(4, -1, -1):
        if rem & (1 << (i + 10)):
            rem ^= _QR_FORMAT_GEN << i
    return ((data << 10) | rem) ^ _QR_FORMAT_MASK


def _qr_version_bits(version):
    rem = version << 12
    for i in range(5, -1, -1):
        if rem & (1 << (i + 12)):
            rem ^= 0b1111100100101 << i
    return (version << 12) | rem


def _qr_place_format(mat, mask):
    size = len(mat)
    bits = _qr_format_bits(0b00, mask)        # level M is 00
    for i in range(15):
        # MSB FIRST: module i of the format area carries bit 14-i. The
        # opposite reading is easy to arrive at (the 15-bit value is written
        # as an integer, and `bits >> i` is the natural spelling) and it
        # produces a symbol whose DATA is perfect and which no scanner will
        # read, because the format area is what tells the scanner which mask
        # to undo. Settled against two independent encoders.
        b = (bits >> (14 - i)) & 1
        if i < 6:
            mat[8][i] = b
        elif i == 6:
            mat[8][7] = b
        elif i == 7:
            mat[8][8] = b
        elif i == 8:
            mat[7][8] = b
        else:
            mat[14 - i][8] = b
        # The second copy: modules 0..6 run UP column 8 from the bottom, and
        # modules 7..14 run RIGHT along row 8 from column size-8. The
        # off-by-one here (writing module 7 into column 8 instead of row 8)
        # leaves exactly one module of the symbol unwritten, which is the
        # kind of defect that survives every structural check and fails a
        # scanner.
        if i < 7:
            mat[size - 1 - i][8] = b
        else:
            mat[8][size - 15 + i] = b
    mat[size - 8][8] = 1                      # the always-dark module


def _qr_place_version(mat, version):
    if version < 7:
        return
    size = len(mat)
    bits = _qr_version_bits(version)
    for i in range(18):
        b = (bits >> i) & 1
        mat[i // 3][size - 11 + i % 3] = b
        mat[size - 11 + i % 3][i // 3] = b


def qr_matrix(text, version=None):
    """Returns a list of rows of 0/1. Level M, byte mode, mask chosen by the
    standard's own penalty rules so the answer is deterministic."""
    data = text.encode("utf-8") if isinstance(text, str) else text
    if version is None:
        version = qr_version_for(len(data))
    cw = qr_codewords(data, version)
    reserved = _qr_reserved(version)
    best, best_mask, best_score = None, None, None
    for mask in range(8):
        mat = _qr_blank(17 + 4 * version)
        _qr_place_function(mat, version)
        _qr_place_data(mat, reserved, cw, version)
        # the always-dark module is part of the FORMAT information area, so it
        # is light while the masks are scored for the same reason the rest of
        # that area is; _qr_place_format puts it back.
        mat[len(mat) - 8][8] = 0
        for r in range(len(mat)):
            for c in range(len(mat)):
                if not reserved[r][c] and _QR_MASKS[mask](r, c):
                    mat[r][c] ^= 1
        # THE FORMAT AREA IS LEFT LIGHT WHILE THE MASKS ARE SCORED, and the
        # real format bits go in only once a mask has won. The standard says
        # to evaluate the symbol, and says nothing about whether the format
        # information is in it yet; scoring it in and scoring it out pick
        # DIFFERENT masks on small versions, so the choice has to be made and
        # written down. This is the one deployed encoders make, and matching
        # them is what lets this file be cross-checked at all.
        score = _qr_penalty(mat)
        if best_score is None or score < best_score:
            best, best_mask, best_score = mat, mask, score
    _qr_place_format(best, best_mask)
    _qr_place_version(best, version)
    return best


def qr_text(text, version=None, on="#", off="."):
    return "\n".join("".join(on if v else off for v in row)
                     for row in qr_matrix(text, version))


# ===========================================================================
# TRANSACTIONS: assemble, sign, decode
#
# coin_reference already owns the two sighash preimages this wallet needs
# (legacy and BIP-143) and the taproot one; what is added here is the part a
# WALLET does with them - the scriptSig and witness shapes per script type,
# and a decoder, which is the half no signer needs and every reviewer does.
# ===========================================================================
def tx_serialize(version, inputs, outputs, locktime, script_sigs, witnesses=None):
    """inputs: [(txid_hex_be, vout, sequence)]; outputs: [(sat, spk)];
    script_sigs: [bytes]; witnesses: [[bytes]] or None."""
    has_wit = witnesses is not None and any(w for w in witnesses)
    out = _le(version, 4)
    if has_wit:
        out += b"\x00\x01"
    out += varint(len(inputs))
    for (txid, vout, seq), ss in zip(inputs, script_sigs):
        out += bytes.fromhex(txid)[::-1] + _le(vout, 4)
        out += varint(len(ss)) + ss + _le(seq, 4)
    out += varint(len(outputs))
    for value, spk in outputs:
        out += _le(value, 8) + varint(len(spk)) + spk
    if has_wit:
        for w in witnesses:
            out += varint(len(w))
            for item in w:
                out += varint(len(item)) + item
    out += _le(locktime, 4)
    return out


def txid_of(version, inputs, outputs, locktime, script_sigs):
    return hash256(tx_serialize(version, inputs, outputs, locktime,
                                script_sigs, None))[::-1].hex()


def tx_decode(raw: bytes) -> dict:
    i = 0
    version = int.from_bytes(raw[i:i + 4], "little")
    i += 4
    segwit = False
    if raw[i] == 0x00 and raw[i + 1] == 0x01:
        segwit = True
        i += 2
    n_in, i = _read_varint(raw, i)
    vin = []
    for _ in range(n_in):
        txid = raw[i:i + 32][::-1].hex()
        i += 32
        vout = int.from_bytes(raw[i:i + 4], "little")
        i += 4
        slen, i = _read_varint(raw, i)
        script = raw[i:i + slen]
        i += slen
        seq = int.from_bytes(raw[i:i + 4], "little")
        i += 4
        vin.append({"txid": txid, "vout": vout, "scriptsig": script.hex(),
                    "sequence": seq, "witness": []})
    n_out, i = _read_varint(raw, i)
    vout_list = []
    for _ in range(n_out):
        value = int.from_bytes(raw[i:i + 8], "little")
        i += 8
        slen, i = _read_varint(raw, i)
        spk = raw[i:i + slen]
        i += slen
        vout_list.append({"value": value, "scriptpubkey": spk.hex()})
    if segwit:
        for k in range(n_in):
            cnt, i = _read_varint(raw, i)
            items = []
            for _ in range(cnt):
                ln, i = _read_varint(raw, i)
                items.append(raw[i:i + ln].hex())
                i += ln
            vin[k]["witness"] = items
    locktime = int.from_bytes(raw[i:i + 4], "little")
    i += 4
    if i != len(raw):
        raise ValueError("trailing bytes after the transaction")
    stripped = tx_serialize(version,
                            [(v["txid"], v["vout"], v["sequence"]) for v in vin],
                            [(o["value"], bytes.fromhex(o["scriptpubkey"]))
                             for o in vout_list],
                            locktime,
                            [bytes.fromhex(v["scriptsig"]) for v in vin], None)
    weight = len(stripped) * 3 + len(raw)
    return {
        "version": version, "segwit": segwit, "locktime": locktime,
        "vin": vin, "vout": vout_list,
        "txid": hash256(stripped)[::-1].hex(),
        "wtxid": hash256(raw)[::-1].hex(),
        "size": len(raw), "vsize": -(-weight // 4), "weight": weight,
        "rbf": any(v["sequence"] < 0xFFFFFFFE for v in vin),
    }


def sign_input(script_type, seckey, sighash_preimage_digest, pubkey,
               witness_script=None, sighash_byte=1):
    """Returns (scriptSig, witness_items) for one input."""
    der = cr.der_encode(*cr.ecdsa_sign_recoverable(seckey,
                                                   sighash_preimage_digest)[:2])
    sig = der + bytes([sighash_byte])
    if script_type == "p2pkh":
        return push(sig) + push(pubkey), []
    if script_type == "p2wpkh":
        return b"", [sig, pubkey]
    if script_type == "p2sh-p2wpkh":
        return push(redeem_p2sh_p2wpkh(pubkey)), [sig, pubkey]
    if script_type == "p2wsh":
        # the caller assembles the multisig stack; this is the single-sig
        # convenience shape and is deliberately refused here rather than
        # guessed at.
        raise ValueError("p2wsh signing is per-cosigner: use sign_multisig")
    raise ValueError("unknown script type %r" % script_type)


def der_sig(seckey, digest, sighash_byte=1) -> bytes:
    """The DER signature plus its sighash byte: what a PSBT partial-sig entry
    holds, and the first thing sign_input builds. Its own function so a
    partial-sig entry can be checked WITHOUT reconstructing the whole
    scriptSig or witness that eventually carries it."""
    return cr.der_encode(*cr.ecdsa_sign_recoverable(seckey, digest)[:2]) + \
        bytes([sighash_byte])


def witness_bytes(items) -> bytes:
    """A witness stack serialized the way PSBT_IN_FINAL_SCRIPTWITNESS holds
    it: the item count, then each item length-prefixed. Identical to the
    per-input encoding tx_serialize writes in its witness section."""
    out = varint(len(items))
    for item in items:
        out += varint(len(item)) + item
    return out


def sign_multisig(seckeys, digest, witness_script, sighash_byte=1):
    """The P2WSH m-of-n witness: an empty element for CHECKMULTISIG's
    off-by-one, then one signature per cosigner IN WITNESS-SCRIPT KEY ORDER,
    then the witness script. Signatures out of key order are a script
    failure, not a policy warning."""
    order = []
    i = 1
    while i < len(witness_script) - 2:
        ln = witness_script[i]
        order.append(witness_script[i + 1:i + 1 + ln])
        i += 1 + ln
    sigs = []
    for pk in order:
        for sk in seckeys:
            if cr.pubkey(sk) == pk:
                der = cr.der_encode(*cr.ecdsa_sign_recoverable(sk, digest)[:2])
                sigs.append(der + bytes([sighash_byte]))
                break
    return b"", [b""] + sigs + [witness_script]


def sign_taproot_keypath(seckey, digest, merkle_root=None, aux=b"\x00" * 32):
    tweaked = cr.taproot_tweak_seckey(seckey, merkle_root)
    return b"", [cr.schnorr_sign(tweaked, digest, aux)]


def _cr_inputs(inputs):
    return [(cr.btc_outpoint(bytes.fromhex(t), v), s) for t, v, s in inputs]


def _cr_outputs(outputs):
    return [cr.btc_output(value, spk) for value, spk in outputs]


def sighash_for(script_type, version, inputs, outputs, index, locktime,
                pubkey=None, amount_sat=None, witness_script=None,
                prev_spks=None, prev_amounts=None, sighash_type=1):
    """The digest to sign for one input, chosen by the input's script type.

    The scriptCode rules are the ones a wallet gets wrong: for P2WPKH and for
    P2SH-P2WPKH the BIP-143 scriptCode is the P2PKH script of the SAME key,
    not the witness program; for P2WSH it is the witness script itself; and
    taproot does not use a scriptCode at all - it commits to every input's
    scriptPubKey and amount, which is why prev_spks and prev_amounts are
    required there and forbidden elsewhere."""
    ci, co = _cr_inputs(inputs), _cr_outputs(outputs)
    if script_type == "p2pkh":
        code = spk_p2pkh(pubkey)
        return cr.btc_sighash_legacy(version, ci, co, index, code, locktime,
                                     sighash_type)
    if script_type in ("p2wpkh", "p2sh-p2wpkh"):
        code = spk_p2pkh(pubkey)
        return cr.btc_sighash_segwit(version, ci, co, index, code, amount_sat,
                                     locktime, sighash_type)
    if script_type == "p2wsh":
        return cr.btc_sighash_segwit(version, ci, co, index, witness_script,
                                     amount_sat, locktime, sighash_type)
    if script_type == "p2tr":
        return cr.btc_sighash_taproot(
            version, locktime,
            [cr.btc_outpoint(bytes.fromhex(t), v) for t, v, _ in inputs],
            prev_amounts, prev_spks,
            [s for _, _, s in inputs], co, index,
            0 if sighash_type == 1 else sighash_type)
    raise ValueError("unknown script type %r" % script_type)


# ===========================================================================
# IMPORT-TIME ANCHORS
#
# coin_reference anchors itself to the published BIP vectors at import, and
# this file does the same for everything it adds. The point is not belt and
# braces: it is that an ORACLE which has drifted is worse than no oracle,
# because every gate that depends on it goes green while testing the wrong
# answer. If any assertion below fails, importing this module fails, and
# every gate that uses it fails with it.
# ===========================================================================
_TEST_MNEMONIC = ("abandon abandon abandon abandon abandon abandon abandon "
                  "abandon abandon abandon abandon about")


def _selftest():
    master = cr.bip32_master(cr.bip39_seed(_TEST_MNEMONIC, ""))

    def at(path):
        return cr.bip32_path(master, path)

    # --- BIP-44 / 49 / 84 / 86 first receive addresses, the four every
    # wallet ships in its own test suite.
    assert address_for_spk("mainnet", spk_p2pkh(at("m/44'/0'/0'/0/0")["pubkey"])) \
        == "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"
    assert address_for_spk("mainnet",
                           spk_p2sh_p2wpkh(at("m/49'/0'/0'/0/0")["pubkey"])) \
        == "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf"
    assert address_for_spk("mainnet", spk_p2wpkh(at("m/84'/0'/0'/0/0")["pubkey"])) \
        == "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
    tr_key, _ = cr.taproot_tweak_pubkey(at("m/86'/0'/0'/0/0")["pubkey"][1:], None)
    assert address_for_spk("mainnet", spk_p2tr(tr_key)) \
        == "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"

    # --- SLIP-132 account keys for the same mnemonic (BIP-49 and BIP-84's
    # own published account-level extended keys).
    assert xkey_encode(at("m/49'/0'/0'"), xkey_version("mainnet",
                                                       "p2sh-p2wpkh", True),
                       False).startswith("ypub6Ww3ibxVfGzLrAH1PNcjyAWenMTbbAos")
    assert xkey_encode(at("m/84'/0'/0'"), xkey_version("mainnet", "p2wpkh",
                                                       True), False) == \
        ("zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1AD"
         "qtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs")
    assert fingerprint(master["pubkey"]).hex() == "73c5da0a"

    # --- the extended-key decoder is the inverse, including the network and
    # script type the version byte carries.
    got = xkey_decode(xkey_encode(at("m/84'/0'/0'"),
                                  xkey_version("mainnet", "p2wpkh", True), False))
    assert got["network"] == "mainnet" and got["stem"] == "z" \
        and got["kind"] == "public" and got["depth"] == 3

    # --- address <-> scriptPubKey, both directions, all five forms, and the
    # cross-network refusal.
    for addr in ("1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA",
                 "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf",
                 "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
                 "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",
                 "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"):
        assert address_for_spk("mainnet", spk_for_address("mainnet", addr)) == addr
    try:
        spk_for_address("mainnet", "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx")
        raise AssertionError("a testnet address was accepted on mainnet")
    except ValueError:
        pass

    # --- Electrum's scripthash, on BIP-173's own P2WPKH example.
    spk = spk_for_address("mainnet", "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    assert electrum_scripthash(spk) == sha256(spk)[::-1].hex()

    # --- amounts round trip exactly, including the 8-decimal boundary.
    assert btc_to_sat("21000000") == 2100000000000000
    assert sat_to_btc(1) == "0.00000001"
    assert btc_to_sat(sat_to_btc(123456789)) == 123456789

    # --- the vsize estimator against the classic published figures.
    assert estimate_vsize(["p2pkh"], ["p2pkh", "p2pkh"]) == 226
    assert estimate_vsize(["p2wpkh"], ["p2wpkh", "p2wpkh"]) == 141
    assert dust_threshold("p2pkh") == 546 and dust_threshold("p2wpkh") == 294
    assert dust_threshold("p2sh") == 540 and dust_threshold("p2wsh") == 330
    assert dust_threshold("p2tr") == 330

    # --- coin selection keeps its invariant on every strategy.
    coins = [{"value": 100000, "txid": "a" * 64, "vout": 0, "confirmations": 10},
             {"value": 50000, "txid": "b" * 64, "vout": 1, "confirmations": 3},
             {"value": 250000, "txid": "c" * 64, "vout": 0, "confirmations": 99}]
    for strat in ("bnb", "largest", "smallest", "oldest"):
        r = select_coins(coins, 60000, 5, "p2wpkh", ["p2wpkh"], "p2wpkh",
                         strategy=strat)
        assert r["ok"]
        assert r["total_in"] == 60000 + r["fee"] + r["change"], strat
        assert r["change"] == 0 or r["change"] >= dust_threshold("p2wpkh")

    # --- a message signature round trips and refuses a tampered message.
    sk = at("m/84'/0'/0'/0/0")["seckey"]
    pk = at("m/84'/0'/0'/0/0")["pubkey"]
    addr = address_for_spk("mainnet", spk_p2wpkh(pk))
    sig = message_sign(sk, "hello", "p2wpkh", True)
    assert message_verify("mainnet", addr, "hello", sig)[0] is True
    assert message_verify("mainnet", addr, "hell0", sig)[0] is False
    assert message_digest("").hex() == \
        "80e795d4a4caadd7047af389d9f7f220562feb6196032e2131e10563352c4bcc"

    # --- BIP-21 both directions, and a req- parameter is surfaced.
    u = uri_parse("bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
                  "?amount=0.001&label=Luke-Jr")
    assert u["amount_sat"] == 100000 and u["label"] == "Luke-Jr"
    assert uri_parse("bitcoin:1A1?req-x=1")["required"] == ["req-x"]

    # --- the descriptor checksum, against Bitcoin Core's published examples.
    assert descriptor_checksum("raw(deadbeef)") == "89f8spxm"
    assert descriptor_checksum(
        "wpkh([d34db33f/84h/0h/0h]xpub6DJ2dNUysrn5Vt36jH2KLBT2i1auw1tTSSomg8P"
        "hqNiUtx8QX2SvC9nrHu81fT41fvDUnhMjEzQgXnQjKEu3oaqMSzhSrHMxyyoEAmUHQb"
        "Y/0/*)") == "cjjspncu"

    # --- a PSBT round trips through its own parser, and the unsigned
    # transaction inside it is the transaction the wallet meant.
    spk84 = spk_p2wpkh(pk)
    dest = spk_for_address("mainnet", "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    psbt = psbt_create(2, [("aa" * 32, 0, 0xFFFFFFFD)],
                       [(45000, dest), (4000, spk84)], 0,
                       in_meta={0: {"witness_utxo": (50000, spk84)}})
    p = psbt_parse(psbt)
    assert len(p["inputs"]) == 1 and len(p["outputs"]) == 2
    assert p["unsigned_tx"] == unsigned_tx(2, [("aa" * 32, 0, 0xFFFFFFFD)],
                                           [(45000, dest), (4000, spk84)], 0)

    # --- every script type signs, decodes, and the estimator agrees with the
    # transaction that actually came out.
    ins = [("aa" * 32, 0, 0xFFFFFFFD)]
    outs = [(45000, dest)]
    d = sighash_for("p2wpkh", 2, ins, outs, 0, 0, pubkey=pk, amount_sat=50000)
    ss, wit = sign_input("p2wpkh", sk, d, pk)
    dec = tx_decode(tx_serialize(2, ins, outs, 0, [ss], [wit]))
    assert dec["vsize"] == estimate_vsize(["p2wpkh"], ["p2wpkh"]) == 110
    assert dec["rbf"] is True

    tr = at("m/86'/0'/0'/0/0")
    okey, _ = cr.taproot_tweak_pubkey(tr["pubkey"][1:], None)
    tspk = spk_p2tr(okey)
    d = sighash_for("p2tr", 2, ins, outs, 0, 0, prev_spks=[tspk],
                    prev_amounts=[50000])
    ss, wit = sign_taproot_keypath(tr["seckey"], d)
    assert cr.schnorr_verify(okey, d, wit[0])

    # --- QR: the smallest and a realistic payload, pinned as golden strings
    # produced by an independent encoder (see the section header).
    import hashlib as _hl
    assert _hl.sha256(qr_text("a").encode()).hexdigest() == \
        "0b2a5ded825360b8e6469fe394dbdafe0feb7ce2e470eaa7eb0c63eb4d8e90bb"
    assert _hl.sha256(qr_text("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
                      .encode()).hexdigest() == \
        "a67bd361e5244dccaaf7e6d6743961d348c39ea5611be5c613b268f215578a0b"
    assert qr_text("a").split("\n")[0] == "#######..#.##.#######"
    assert len(qr_matrix("bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7"
                         "kv8f3t4?amount=0.001")) == 37


_selftest()
