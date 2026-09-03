#!/usr/bin/env python3
"""check-wallet-vectors.py - run the SHIPPED examples/wallet-core.livecodescript
against an independent oracle, headlessly, through tools/lcs-interp.py.

WHY THIS EXISTS. examples/wallet-core.livecodescript is the whole wallet
engine: scripts, addresses, extended keys, amounts, sizes, fees, coin
selection, sighash dispatch, witness shapes, PSBT, signed messages, payment
URIs, output descriptors, transaction decoding, JSON and QR. None of it is
cryptography - CoinXT owns every hash and every curve operation - but all of
it is BYTE LAYOUT, and a transcription slip in byte layout does not throw. It
produces an address that encodes cleanly and belongs to nobody, a PSBT that
parses and pays a different output, a descriptor whose checksum closes over
the wrong string, a fee estimate that underpays and leaves a transaction in
nobody's mempool.

Without this file the only thing that had ever READ that script was
check-livecodescript.py, which validates balance, quoting and the token traps
and cannot tell whether a handler computes the right bytes. That is exactly
the gap the suite's own CLAUDE.md names as its most expensive class of bug,
and the gap CoinXT, NostrXT and Riptide each closed with their own copy of
this gate.

WHAT IT IS NOT. An approximation of the engine, not the engine. Nothing here
promotes a handler out of "verified statically; needs an OXT pass" - what it
settles is LOGIC, not parser behaviour. If this file and the engine disagree,
the engine is right. tools/lcs-interp.py's own header carries the modelled
subset and its named divergences.

THE ORACLE IS INDEPENDENT AND ANCHORED. tools/wallet_reference.py is written
from the specifications, extends tools/coin_reference.py (itself anchored to
BIP-32/39/173/350 and EIP-55 at import), and asserts the published answers at
import: the BIP-44/49/84/86 first receive addresses for the public test
mnemonic, BIP-49 and BIP-84's own account ypub and zpub, Bitcoin Core's two
published descriptor checksums, the classic 226 and 141 virtual sizes, the
546/540/330/294 dust thresholds derived from Core's own branch, the
empty-message magic hash, and two golden QR matrices produced by an
independent encoder. A drifted oracle is worse than no oracle - every gate
that leans on it goes green while testing the wrong answer - so importing it
fails if any of those move, and this gate fails with it.

THE CRYPTO IS REAL. The cx* handlers the script calls are supplied by the
ACTUAL native shim, built from native/coinxt.c by tools/check-script-vectors.py's
own builder (imported, not reimplemented, so a shim change is picked up here
too). So what executes is this file's own byte layout over genuine
secp256k1 - the signed transactions below are really signed.

WHAT IT ADDS TO THAT BUILDER. check-script-vectors.py wires only the shim
entry points the ENCODING layer calls. A wallet calls more: ECDSA signing and
verification, recoverable signing and public-key recovery, BIP-340 Schnorr,
the x-only public key and the BIP-341 secret-key tweak. Those are wired here,
with the same rule the borrowed ones follow: a non-zero shim status raises
the same throw the .lcb wrapper would, or the script's own refusal paths
would never execute.

THE HONEST SPLIT. Every `kCw*` constant in the shipped file is either
RE-DERIVED from the oracle or listed below as an input with a written reason,
and the run reports which. A gate that prints the number of constants it
PARSED as the number it CHECKED is the failure this tree has already paid
for once (coinxt's own check-selftest-vectors.py, 2026-08-13).

Usage:
  python3 tools/check-wallet-vectors.py            # per-check detail
  python3 tools/check-wallet-vectors.py --check    # terse (the gate set)
"""
import ctypes
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)

CORE = os.path.join(MEMBER, "examples", "wallet-core.livecodescript")
COIN = os.path.join(MEMBER, "src", "coinxt.livecodescript")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CSV = _load("check_script_vectors", os.path.join(HERE, "check-script-vectors.py"))
LCS = CSV.LCS
REF = _load("wallet_reference", os.path.join(HERE, "wallet_reference.py"))
CR = REF.cr

TEST_MNEMONIC = REF._TEST_MNEMONIC


def to_str(b):
    return "".join(chr(x) for x in b)


def to_bytes(s):
    return bytes(ord(ch) & 0xFF for ch in str(LCS._disp(s)))


# --------------------------------------------------------------- the shim
def wire_signing(lib):
    """The .lcb handlers a WALLET calls that the encoding layer never does."""
    B, S = ctypes.c_char_p, ctypes.c_size_t
    for fn, args in (
        ("cnx_ecdsa_sign", [B, S, B, S, B, S]),
        ("cnx_ecdsa_sign_recoverable", [B, S, B, S, B, S]),
        ("cnx_ecdsa_verify", [B, S, B, S, B, S]),
        ("cnx_ecdsa_recover", [B, S, B, S, B, S]),
        ("cnx_ecdh", [B, S, B, S, B, S]),
        ("cnx_schnorr_sign", [B, S, B, S, B, S, B, S]),
        ("cnx_schnorr_verify", [B, S, B, S, B, S]),
        ("cnx_xonly_pubkey_from_seckey", [B, S, B, S]),
        ("cnx_taproot_tweak_seckey", [B, S, B, S, B, S]),
    ):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = args

    def buf(n):
        return ctypes.create_string_buffer(n)

    def fixed(fn, nargs, outlen, name):
        """A shim call taking nargs byte buffers and filling one of outlen."""
        def go(args):
            raw = [to_bytes(a) for a in args[:nargs]]
            out = buf(outlen)
            flat = []
            for r in raw:
                flat.extend([r if r else None, len(r)])
            rc = getattr(lib, fn)(*(flat + [out, outlen]))
            if rc != 0:
                raise LCS.Thrown("CoinXT: %s: status %d" % (name, rc))
            return to_str(out.raw[:outlen])
        return go

    def boolean(fn, name):
        """THE .lcb's OWN MAP, and it matters which way round it is.
        src/coinxt.lcb's cxVerify and cxSchnorrVerify answer FALSE for -5
        (BADSIG - the ordinary "this signature does not check out") and THROW
        for everything else (a null pointer, a bad length, a malformed key, an
        internal error). This helper had the two halves swapped: it answered
        false where the engine throws and threw where the engine answers
        false, so the script's refusal paths were being exercised by the wrong
        inputs and its throw paths not at all."""
        def go(args):
            raw = [to_bytes(a) for a in args]
            flat = []
            for r in raw:
                flat.extend([r, len(r)])
            rc = getattr(lib, fn)(*flat)
            if rc == 0:
                return True
            if rc == -5:
                return False
            raise LCS.Thrown("CoinXT: %s: status %d" % (name, rc))
        return go

    LCS.HASHES.update({
        "cxsign": fixed("cnx_ecdsa_sign", 2, 64, "cxSign"),
        "cxsignrecoverable": fixed("cnx_ecdsa_sign_recoverable", 2, 65,
                                   "cxSignRecoverable"),
        "cxrecover": fixed("cnx_ecdsa_recover", 2, 65, "cxRecover"),
        # the RAW 65-byte point (0x04 || X || Y), as cnx_ecdh_len says; the
        # 32 this line carried until 2026-09-04 made every offline ECDH a
        # BADLEN refusal, which nothing noticed until BIP-352 used it
        "cxecdh": fixed("cnx_ecdh", 2, 65, "cxEcdh"),
        "cxschnorrsign": fixed("cnx_schnorr_sign", 3, 64, "cxSchnorrSign"),
        "cxxonlypubkey": fixed("cnx_xonly_pubkey_from_seckey", 1, 32,
                               "cxXOnlyPubkey"),
        "cxtaproottweakseckey": fixed("cnx_taproot_tweak_seckey", 2, 32,
                                      "cxTaprootTweakSeckey"),
        "cxverify": boolean("cnx_ecdsa_verify", "cxVerify"),
        "cxschnorrverify": boolean("cnx_schnorr_verify", "cxSchnorrVerify"),
        "cxsignaturelen": lambda a: 64,
        "cxrecoverablesignaturelen": lambda a: 65,
        "cxschnorrsignaturelen": lambda a: 64,
        "cxseckeylen": lambda a: 32,
        "cxpubkeylencompressed": lambda a: 33,
        "cxpubkeylenuncompressed": lambda a: 65,
    })


# ------------------------------------------------------------- the checker
class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.problems = []
        self.count = 0

    def note(self, text):
        if not self.terse:
            print(text)

    def ck(self, label, got, want):
        self.count += 1
        if got == want:
            if not self.terse:
                print("  ok    %s" % label)
            return True
        self.problems.append("%s\n      got:  %r\n      want: %r" % (label, got, want))
        if not self.terse:
            print("  FAIL  %s\n        got:  %r\n        want: %r" % (label, got, want))
        return False

    def true(self, label, got):
        return self.ck(label, got is True or got == "true", True)

    def refuses(self, label, fn):
        self.count += 1
        try:
            fn()
        except LCS.Thrown:
            if not self.terse:
                print("  ok    %s" % label)
            return True
        except Exception as exc:                       # noqa: BLE001
            self.problems.append("%s raised %r rather than a script throw"
                                 % (label, exc))
            return False
        self.problems.append("%s was ACCEPTED and should have been refused" % label)
        if not self.terse:
            print("  FAIL  %s was accepted" % label)
        return False


def lst(items):
    a = {"n": len(items)}
    for i, v in enumerate(items):
        a[str(i + 1)] = v
    return a


def unlst(a):
    n = int(a.get("n", 0) or 0)
    return [a.get(str(i), "") for i in range(1, n + 1)]


# ------------------------------------------------------------ tier 1: constants
#
# Constants that are INPUTS rather than derivable answers, each with the
# reason it cannot be re-derived from the oracle. An entry here is a standing
# admission, not a way to quiet the tool.
CONSTANT_INPUTS = {
    "kCwVersion": "this layer's own version string",
    "kCwHexDigits": "checked by coinxt's own vector gate, which owns hex",
    "kCwMsgMagic": "the message prefix; its effect is checked by the digest",
    "kCwSigBytes": "a worst-case budget, not a derivable constant; its effect "
                   "is checked by every vsize vector",
    "kCwPubkeyBytes": "same, and 33 is checked by every derived address",
    "kCwSchnorrSigBytes": "same; checked by the taproot vsize vector",
    "kCwDustSpendLegacy": "an input to Core's dust rule; the four thresholds "
                          "it produces are all re-derived",
    "kCwDustSpendWitness": "same",
    "kCwIncrementalRelayFee": "BIP-125's relay floor; checked by cwRbfMinFee",
    "kCwQrPrim": "the QR field polynomial; checked by every QR matrix vector",
    "kCwQrFormatGen": "checked by every QR matrix vector",
    "kCwQrFormatMask": "checked by every QR matrix vector",
    "kCwQrVersionGen": "checked by the version-7 and version-8 QR matrix "
                       "vectors, which are the only ones that carry a "
                       "version-information block at all",
    "kCwPsbtMagic": "checked by every PSBT vector",
}
CONSTANT_INPUTS.update({("kCwOp" + n): "a script opcode; checked by the "
                        "scriptPubKey vectors that emit it"
                        for n in ("Zero", "Dup", "Equal", "EqualVerify",
                                  "Hash160", "CheckSig", "CheckMultisig", "One")})
CONSTANT_INPUTS.update({
    "kCwOpIf": "a script opcode; the inscription envelope vectors emit it and "
               "the reader's byte-compared script carries it",
    "kCwOpEndIf": "a script opcode; same envelope vectors",
    "kCwOpDrop": "a script opcode; the CLTV leaf vectors emit it",
    "kCwOpCltv": "a script opcode; the CLTV leaf vectors emit it and the "
                 "timelocked spend's witness carries the leaf",
    "kCwBolt11MaxLen": "this reader's own cap on an invoice's length (BOLT11 "
                       "sets none); the longest specification example is 765 "
                       "characters and decodes under it",
})
# THE PSBT KEY TYPES, NAMED ONE AT A TIME. These carried a single blanket
# excuse - "a BIP-174 key type; checked by the PSBT round-trip vectors" - and
# it was not true of most of them: exactly one byte-exact comparison existed,
# over a PSBT whose metadata used three of the twenty-one, and four of the
# names were read by no code path at all. A blanket reason is the shape this
# member's own history calls a gate that answers the question nobody asks
# twice; the four dead names have been deleted from the script, and each
# survivor now says which vector puts it on the wire.
CONSTANT_INPUTS.update({
    "kCwPsbtGlobalUnsignedTx":
        "byte-compared in every psbt_create vector (it is the one entry a "
        "PSBT cannot omit)",
    "kCwPsbtInWitnessUtxo":
        "byte-compared in the create, output-metadata, signed and finalized "
        "vectors",
    "kCwPsbtInBip32": "byte-compared in the same four",
    "kCwPsbtInNonWitnessUtxo":
        "byte-compared in the legacy-input vector, which is the only shape "
        "that emits it",
    "kCwPsbtInSighashType": "byte-compared in that same legacy-input vector",
    "kCwPsbtInPartialSig":
        "byte-compared in the signed-PSBT vector, keyed by the pubkey and "
        "carrying the DER signature plus its sighash byte",
    "kCwPsbtInFinalScriptSig":
        "byte-compared in the finalized-PSBT vector (absent for a v0 witness "
        "input, which that vector also pins)",
    "kCwPsbtInFinalScriptWitness": "byte-compared in the same vector",
    "kCwPsbtInRedeemScript":
        "emitted by the p2sh-p2wpkh sign-and-finalize vector, whose finalized "
        "TRANSACTION is byte-compared; the entry itself is not, because the "
        "wrapper it feeds is",
    "kCwPsbtInWitnessScript":
        "emitted by the 2-of-3 cosigner vectors, whose combined finalized "
        "transaction is byte-compared; the entry itself is not",
    "kCwPsbtInTapInternalKey":
        "emitted by the taproot vector, whose finalized transaction is "
        "byte-compared; the entry itself is not",
    "kCwPsbtInTapKeySig":
        "written by cwPsbtSign and read back by cwPsbtFinalize on the taproot "
        "vector - the round trip is exercised, the bytes are not compared to "
        "an independent implementation",
    "kCwPsbtInTapBip32":
        "NOT EXERCISED. cwPsbtCreate emits it when a caller supplies "
        "tapbip32 metadata and no vector supplies any; the wallet does not "
        "either, so this is declared for a caller that does not yet exist",
    "kCwPsbtOutRedeemScript":
        "byte-compared in the output-metadata vector",
    "kCwPsbtOutWitnessScript": "byte-compared in the same vector",
    "kCwPsbtOutBip32": "byte-compared in the same vector",
    "kCwPsbtOutTapInternalKey":
        "NOT EXERCISED, for the same reason as kCwPsbtInTapBip32: no vector "
        "and no wallet path supplies taproot metadata on an OUTPUT",
})


def check_constants(c, text):
    """Every kCw* constant is re-derived from the oracle or listed as an input.

    A constant is the cheapest possible place for the most expensive possible
    bug: one transposed pair in a version-byte row produces a valid-looking
    address on the wrong network, and nothing downstream can tell.
    """
    c.note("\nconstants: re-derived from tools/wallet_reference.py")
    consts = dict(re.findall(r'^constant\s+(\w+)\s*=\s*"([^"]*)"', text, re.M))
    nums = dict(re.findall(r'^constant\s+(\w+)\s*=\s*(-?\d+)\s*$', text, re.M))
    order = ["mainnet", "testnet", "signet", "regtest", "testnet4"]

    def row(key):
        return ",".join(str(REF.NETWORKS[n][key]) for n in order)

    c.ck("the network list", consts.get("kCwNetworks"), ",".join(order))
    c.ck("the bech32 HRPs",
         consts.get("kCwHrps"), ",".join(REF.NETWORKS[n]["hrp"] for n in order))
    c.ck("the P2PKH version bytes", consts.get("kCwP2pkhVersions"), row("p2pkh"))
    c.ck("the P2SH version bytes", consts.get("kCwP2shVersions"), row("p2sh"))
    c.ck("the WIF version bytes", consts.get("kCwWifVersions"), row("wif"))
    c.ck("the BIP-44 coin types", consts.get("kCwCoinTypes"), row("coin"))
    # the pub/prv constant names are SPELLED OUT rather than derived from each
    # other. Deriving them ("Xpub".replace("Pub", "Prv")) silently produced the
    # PUBLIC name for the three lowercase stems, so the private rows were
    # compared against the public constants and reported a failure in the
    # script that was a failure in this gate.
    for stem, pub_name, prv_name in (("x", "kCwXpubVersions", "kCwXprvVersions"),
                                     ("y", "kCwYpubVersions", "kCwYprvVersions"),
                                     ("z", "kCwZpubVersions", "kCwZprvVersions"),
                                     ("Z", "kCwZshPubVersions", "kCwZshPrvVersions")):
        c.ck("the SLIP-132 %s public versions" % stem,
             consts.get(pub_name), row(stem + "pub"))
        c.ck("the SLIP-132 %s private versions" % stem,
             consts.get(prv_name), row(stem + "prv"))
    c.ck("the script types", consts.get("kCwScriptTypes"),
         ",".join(["p2pkh", "p2sh-p2wpkh", "p2wpkh", "p2tr", "p2wsh"]))
    c.ck("the BIP purposes", consts.get("kCwPurposes"),
         ",".join(str(REF.SCRIPT_TYPES[t][0])
                  for t in ("p2pkh", "p2sh-p2wpkh", "p2wpkh", "p2tr", "p2wsh")))
    c.ck("the SLIP-132 stems", consts.get("kCwStems"),
         ",".join(REF.SCRIPT_TYPES[t][1]
                  for t in ("p2pkh", "p2sh-p2wpkh", "p2wpkh", "p2tr", "p2wsh")))
    for i, gen in enumerate(REF._DESC_GEN):
        c.ck("descriptor generator %d" % i, int(nums.get("kCwDescGen%d" % i, -1)), gen)
    c.ck("the descriptor input alphabet head",
         consts.get("kCwDescInputHead"), REF._DESC_INPUT[:92])
    c.ck("the descriptor checksum charset",
         consts.get("kCwDescCharset"), REF._DESC_CHARSET)
    c.ck("the QR level-M data codewords", consts.get("kCwQrDataCw"),
         ",".join(str(REF.QR_M[v][0]) for v in range(1, 16)))
    c.ck("the QR error-correction codewords per block", consts.get("kCwQrEccPer"),
         ",".join(str(REF.QR_M[v][1]) for v in range(1, 16)))
    c.ck("the QR group-1 block counts", consts.get("kCwQrG1Blocks"),
         ",".join(str(REF.QR_M[v][2]) for v in range(1, 16)))
    c.ck("the QR group-1 data codewords", consts.get("kCwQrG1Cw"),
         ",".join(str(REF.QR_M[v][3]) for v in range(1, 16)))
    c.ck("the QR group-2 block counts", consts.get("kCwQrG2Blocks"),
         ",".join(str(REF.QR_M[v][4]) for v in range(1, 16)))
    c.ck("the QR group-2 data codewords", consts.get("kCwQrG2Cw"),
         ",".join(str(REF.QR_M[v][5]) for v in range(1, 16)))
    c.ck("the QR remainder bits", consts.get("kCwQrRemainder"),
         ",".join(str(REF.QR_REMAINDER[v]) for v in range(1, 16)))
    c.ck("the QR alignment centres", consts.get("kCwQrAlign"),
         ";".join(",".join(str(x) for x in REF.QR_ALIGN[v]) for v in range(1, 16)))
    c.ck("the RBF sequence number", int(nums.get("kCwSeqRbf", -1)), 0xFFFFFFFD)
    c.ck("the final sequence number", int(nums.get("kCwSeqFinal", -1)), 0xFFFFFFFF)
    c.ck("the non-RBF sequence number", int(nums.get("kCwSeqNoRbf", -1)), 0xFFFFFFFE)
    c.ck("the long-term fee rate is the one the oracle prices with",
         int(nums.get("kCwLongTermFeeRate", -1)), REF.LONG_TERM_FEE_RATE)
    # ---- 2026-09-04: BIP-322, BIP-352, Runes, inscriptions, BOLT11 ------
    # Each of these has an answer the oracle (or the mathematics) supplies,
    # so none is an input. The first CI run after they landed was the gate
    # refusing all 26 by name, which is the tier doing its job: the isolated
    # drivers that proved the vectors never ran this tier.
    import string as _string
    c.ck("the BIP-322 tag", consts.get("kCwBip322Tag"), REF.BIP322_TAG)
    c.ck("the BIP-322 null txid", consts.get("kCwBip322NullTxid"), "00" * 32)
    c.ck("the BIP-352 inputs tag", consts.get("kCwSpTagInputs"), REF.SP_TAG_INPUTS)
    c.ck("the BIP-352 shared-secret tag", consts.get("kCwSpTagSecret"), REF.SP_TAG_SECRET)
    c.ck("the BIP-352 address length waiver", int(nums.get("kCwSpMaxLen", -1)), REF.SP_MAX_LEN)
    c.ck("the BIP-352 per-group limit K_max", int(nums.get("kCwSpKMax", -1)), REF.SP_K_MAX)
    c.ck("the curve order n", consts.get("kCwCurveN"), "%064x" % CR._N)
    c.ck("half the curve order, the low-S bound", consts.get("kCwCurveHalfN"),
         "%064x" % (CR._N // 2))
    c.ck("the zero scalar", consts.get("kCwScalarZero"), "0" * 64)
    c.ck("the bech32m constant", int(nums.get("kCwBech32mConst", -1)), CR.BECH32M_CONST)
    c.ck("the 5-bit xor table", consts.get("kCwXor5"),
         "".join("%02d" % (a ^ b) for a in range(32) for b in range(32)))
    c.ck("the Runes u128 maximum", consts.get("kCwRuneU128Max"), str(REF.RUNE_U128_MAX))
    c.ck("the Runes name alphabet", consts.get("kCwRuneAlphabet"), _string.ascii_uppercase)
    c.ck("the Runes divisibility ceiling is one below u128's digit count",
         int(nums.get("kCwRuneMaxDivisibility", -1)), len(str(REF.RUNE_U128_MAX)) - 1)
    c.ck("the Runes symbol ceiling is the last Unicode scalar",
         int(nums.get("kCwRuneMaxSymbol", -1)), 0x10FFFF)
    c.ck("the Runes spacer ceiling is 27 set bits (one gap per letter of a 28-letter name)",
         int(nums.get("kCwRuneMaxSpacers", -1)), (1 << 27) - 1)
    c.ck("the tapscript leaf version", int(nums.get("kCwTapLeafVersion", -1)), REF.TAP_LEAF_VERSION)
    c.ck("the inscription push chunk is the script element limit",
         int(nums.get("kCwInscriptionChunk", -1)), REF.INSCRIPTION_CHUNK)
    gx, gy = CR._G
    c.ck("the NUMS point H is the hash of G's uncompressed encoding, as BIP-341 says",
         consts.get("kCwNumsH"),
         CR.sha256(b"\x04" + gx.to_bytes(32, "big") + gy.to_bytes(32, "big")).hex())
    c.ck("and it is the oracle's", consts.get("kCwNumsH"), REF.SP_NUMS_H.hex())
    c.ck("a BOLT11 signature spans 104 five-bit values (65 bytes)",
         int(nums.get("kCwBolt11SigValues", -1)), (65 * 8 + 4) // 5)
    c.ck("the BOLT11 feature bits this reader knows",
         consts.get("kCwBolt11KnownFeatures"),
         ",".join(str(b) for b in sorted(REF.BOLT11_KNOWN_FEATURES)))

    # THE HONEST SPLIT: everything parsed is either checked above or listed.
    derived = {
        "kCwNetworks", "kCwHrps", "kCwP2pkhVersions", "kCwP2shVersions",
        "kCwWifVersions", "kCwCoinTypes", "kCwScriptTypes", "kCwPurposes",
        "kCwStems", "kCwDescInputHead", "kCwDescCharset", "kCwQrDataCw",
        "kCwQrEccPer", "kCwQrG1Blocks", "kCwQrG1Cw", "kCwQrG2Blocks",
        "kCwQrG2Cw", "kCwQrRemainder", "kCwQrAlign", "kCwSeqRbf",
        "kCwSeqFinal", "kCwSeqNoRbf", "kCwLongTermFeeRate",
        "kCwBip322Tag", "kCwBip322NullTxid", "kCwSpTagInputs", "kCwSpTagSecret",
        "kCwSpMaxLen", "kCwSpKMax", "kCwCurveN", "kCwCurveHalfN", "kCwScalarZero",
        "kCwBech32mConst", "kCwXor5", "kCwRuneU128Max", "kCwRuneAlphabet",
        "kCwRuneMaxDivisibility", "kCwRuneMaxSymbol", "kCwRuneMaxSpacers",
        "kCwTapLeafVersion", "kCwInscriptionChunk", "kCwNumsH",
        "kCwBolt11SigValues", "kCwBolt11KnownFeatures",
    }
    for name in ("kCwXpubVersions", "kCwXprvVersions", "kCwYpubVersions",
                 "kCwYprvVersions", "kCwZpubVersions", "kCwZprvVersions",
                 "kCwZshPubVersions", "kCwZshPrvVersions"):
        derived.add(name)
    for i in range(5):
        derived.add("kCwDescGen%d" % i)
    parsed = set(consts) | set(nums)
    stale = sorted(k for k in CONSTANT_INPUTS if k not in parsed)
    unaccounted = sorted(parsed - derived - set(CONSTANT_INPUTS))
    if unaccounted:
        c.problems.append(
            "these constants are neither re-derived nor listed as inputs with a "
            "reason: %s" % ", ".join(unaccounted))
    if stale:
        c.problems.append(
            "CONSTANT_INPUTS names constants the file no longer declares "
            "(a stale excuse outlives the thing it excused): %s" % ", ".join(stale))
    # THE SPLIT MUST ADD UP, and it did not. Two names sat in both sets, so
    # the note printed 35 + 45 for 78 constants - a report of coverage that
    # was, by two, a report of something else. A constant is either checked
    # here or excused there; being both means one of the two is a lie about
    # which, and there is no way to tell from the outside which one.
    both = sorted((derived & parsed) & set(CONSTANT_INPUTS))
    if both:
        c.problems.append(
            "these constants are BOTH re-derived and listed as an input with "
            "a reason, so the honest split double-counts them and one of the "
            "two claims is wrong: %s" % ", ".join(both))
    nderived, ninput = len(derived & parsed), len(parsed & set(CONSTANT_INPUTS))
    if nderived + ninput != len(parsed):
        c.problems.append(
            "the split does not add up: %d re-derived + %d listed = %d, for "
            "%d constants" % (nderived, ninput, nderived + ninput, len(parsed)))
    c.note("  %d constant(s) parsed: %d re-derived, %d listed as inputs"
           % (len(parsed), nderived, ninput))


# ------------------------------------------------------- tier 2: the vectors
ADDRESSES = {
    "mainnet": ["1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA",
                "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf",
                "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
                "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",
                "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"],
    "testnet": ["mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn",
                "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx",
                "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7"],
}


def check_vectors(c, ip):
    call = ip.call
    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    seed = CR.bip39_seed(TEST_MNEMONIC, "")
    master = call("cxHdFromSeed", [to_str(seed)])
    fp = REF.fingerprint(master_py["pubkey"]).hex()

    def at(path):
        return CR.bip32_path(master_py, path)

    # ---- scripts -----------------------------------------------------------
    c.note("\nscripts and addresses")
    n84 = at("m/84'/0'/0'/0/0")
    pub = n84["pubkey"].hex()
    c.ck("P2PKH scriptPubKey", call("cwScriptP2pkh", [pub]),
         REF.spk_p2pkh(n84["pubkey"]).hex())
    c.ck("P2WPKH scriptPubKey", call("cwScriptP2wpkh", [pub]),
         REF.spk_p2wpkh(n84["pubkey"]).hex())
    c.ck("P2SH-P2WPKH scriptPubKey", call("cwScriptP2shP2wpkh", [pub]),
         REF.spk_p2sh_p2wpkh(n84["pubkey"]).hex())
    c.ck("the BIP-49 redeem script", call("cwRedeemP2shP2wpkh", [pub]),
         REF.redeem_p2sh_p2wpkh(n84["pubkey"]).hex())
    tr = at("m/86'/0'/0'/0/0")
    okey, _ = CR.taproot_tweak_pubkey(tr["pubkey"][1:], None)
    c.ck("P2TR scriptPubKey", call("cwScriptP2tr", [okey.hex()]),
         REF.spk_p2tr(okey).hex())
    cosigners = [at("m/48'/0'/%d'/2'/0/0" % i) for i in range(3)]
    keys = [k["pubkey"] for k in cosigners]
    ws = call("cwMultisigScript", [2, lst([k.hex() for k in keys]), True])
    c.ck("a 2-of-3 witness script, BIP-67 ordered", ws,
         REF.multisig_script(2, keys).hex())
    c.ck("the same keys UNsorted",
         call("cwMultisigScript", [2, lst([k.hex() for k in keys]), False]),
         REF.multisig_script(2, keys, sort_bip67=False).hex())
    c.ck("P2WSH scriptPubKey", call("cwScriptP2wsh", [ws]),
         REF.spk_p2wsh(bytes.fromhex(ws)).hex())
    c.refuses("an uncompressed cosigner key is refused",
              lambda: call("cwMultisigScript",
                           [2, lst([CR._decompress and "04" + "11" * 64,
                                    keys[1].hex(), keys[2].hex()]), True]))
    c.refuses("a 0-of-3 multisig is refused",
              lambda: call("cwMultisigScript", [0, lst([k.hex() for k in keys]), True]))

    # ---- addresses ---------------------------------------------------------
    for net, addrs in ADDRESSES.items():
        for a in addrs:
            spk = REF.spk_for_address(net, a).hex()
            c.ck("%s: %s -> scriptPubKey" % (net, a[:22]),
                 call("cwScriptForAddress", [net, a]), spk)
            c.ck("%s: %s <- scriptPubKey" % (net, a[:22]),
                 call("cwAddressForScript", [net, spk]), a)
            c.ck("%s: %s is %s" % (net, a[:22], REF.address_kind(net, a)),
                 call("cwAddressKind", [net, a]), REF.address_kind(net, a))
    c.ck("a testnet address is REFUSED on mainnet",
         call("cwAddressIsValid", ["mainnet", ADDRESSES["testnet"][1]]), False)
    c.ck("a mainnet address is REFUSED on testnet",
         call("cwAddressIsValid", ["testnet", ADDRESSES["mainnet"][2]]), False)
    c.ck("a corrupt base58 checksum is refused",
         call("cwAddressIsValid", ["mainnet", "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabB"]),
         False)
    c.ck("a corrupt bech32 checksum is refused",
         call("cwAddressIsValid", ["mainnet",
                                   "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5"]),
         False)
    c.ck("an empty address is refused",
         call("cwAddressIsValid", ["mainnet", "   "]), False)
    c.true("the refusal says WHY",
           "another network" in call("cwAddressProblem",
                                     ["mainnet", ADDRESSES["testnet"][0]])
           or "not a mainnet address" in call("cwAddressProblem",
                                              ["mainnet", ADDRESSES["testnet"][0]]))
    spk = REF.spk_for_address("mainnet", ADDRESSES["mainnet"][2])
    c.ck("Electrum's reversed scripthash",
         call("cwElectrumScripthash", [spk.hex()]), REF.electrum_scripthash(spk))
    c.refuses("an unknown network is refused, never defaulted",
              lambda: call("cwNetHrp", ["mainet"]))

    # ---- derivation --------------------------------------------------------
    c.note("\nderivation paths and extended keys")
    c.ck("a path parses to its child numbers",
         unlst(call("cwParsePath", ["m/84'/0'/0'/0/5"])),
         REF.parse_path("m/84'/0'/0'/0/5"))
    c.ck("h and H are hardened too",
         call("cwFormatPath", [call("cwParsePath", ["m/84h/0'/0H/1/9"])]),
         "m/84'/0'/0'/1/9")
    c.ck("the master path is empty", call("cwListCount",
                                          [call("cwParsePath", ["m"])]), 0)
    c.refuses("a trailing separator is refused",
              lambda: call("cwParsePath", ["m/84'/"]))
    c.refuses("a non-numeric level is refused",
              lambda: call("cwParsePath", ["m/eighty-four'"]))
    for t in ("p2pkh", "p2sh-p2wpkh", "p2wpkh", "p2tr", "p2wsh"):
        c.ck("the account path for %s" % t,
             call("cwAccountPath", [t, "mainnet", 0]),
             REF.derivation_path(t, "mainnet", 0))
        c.ck("the account path for %s on testnet" % t,
             call("cwAccountPath", [t, "testnet", 3]),
             REF.derivation_path(t, "testnet", 3))
    c.ck("the master fingerprint",
         call("cwFingerprint", [master_py["pubkey"].hex()]), fp)
    for net in ("mainnet", "testnet"):
        for t in ("p2pkh", "p2sh-p2wpkh", "p2wpkh", "p2tr", "p2wsh"):
            for pubflag in (True, False):
                c.ck("the %s %s extended-key version (%s)"
                     % (net, t, "public" if pubflag else "private"),
                     call("cwXKeyVersion", [net, t, pubflag]),
                     REF.xkey_version(net, t, pubflag))
    c.ck("BIP-84's own account zpub",
         call("cwAccountXKey", [master, "p2wpkh", "mainnet", 0, False]),
         REF.xkey_encode(at("m/84'/0'/0'"),
                         REF.xkey_version("mainnet", "p2wpkh", True), False))
    c.ck("BIP-49's own account ypub",
         call("cwAccountXKey", [master, "p2sh-p2wpkh", "mainnet", 0, False]),
         REF.xkey_encode(at("m/49'/0'/0'"),
                         REF.xkey_version("mainnet", "p2sh-p2wpkh", True), False))
    c.ck("the account zprv",
         call("cwAccountXKey", [master, "p2wpkh", "mainnet", 0, True]),
         REF.xkey_encode(at("m/84'/0'/0'"),
                         REF.xkey_version("mainnet", "p2wpkh", False), True))
    zpub = REF.xkey_encode(at("m/84'/0'/0'"),
                           REF.xkey_version("mainnet", "p2wpkh", True), False)
    dec = call("cwXKeyDecode", [zpub])
    c.ck("a zpub decodes to its network", dec["network"], "mainnet")
    c.ck("a zpub decodes to its script type", dec["scripttype"], "p2wpkh")
    c.ck("a zpub is public", dec["kind"], "public")
    c.ck("a zpub carries its depth", dec["depth"], 3)
    c.ck("a zpub re-spelled as an xpub",
         call("cwXKeyRespell", [zpub, "mainnet", "p2pkh", True]),
         REF.xkey_encode(at("m/84'/0'/0'"),
                         REF.xkey_version("mainnet", "p2pkh", True), False))
    c.refuses("an unknown extended-key version is refused",
              lambda: call("cwXKeyDecode",
                           [CR.b58check_encode(bytes.fromhex("00112233") + b"\x00" * 74)]))
    for t, path in (("p2pkh", "m/44'/0'/0'"), ("p2sh-p2wpkh", "m/49'/0'/0'"),
                    ("p2wpkh", "m/84'/0'/0'"), ("p2tr", "m/86'/0'/0'")):
        acct = call("cxHdDerivePath", [master, path])
        for change in (0, 1):
            for index in (0, 1, 7):
                rec = call("cwAddressAt", [acct, t, "mainnet", change, index])
                node = at("%s/%d/%d" % (path, change, index))
                if t == "p2tr":
                    k, _ = CR.taproot_tweak_pubkey(node["pubkey"][1:], None)
                    want_spk = REF.spk_p2tr(k)
                else:
                    fn = {"p2pkh": REF.spk_p2pkh,
                          "p2sh-p2wpkh": REF.spk_p2sh_p2wpkh,
                          "p2wpkh": REF.spk_p2wpkh}[t]
                    want_spk = fn(node["pubkey"])
                c.ck("%s m%s/%d/%d" % (t, path[1:], change, index),
                     rec["address"], REF.address_for_spk("mainnet", want_spk))
    accts = lst([call("cxHdDerivePath", [master, "m/48'/0'/%d'/2'" % i])
                 for i in range(3)])
    ms = call("cwMultisigAddressAt", [accts, 2, "mainnet", 0, 0, True])
    c.ck("a 2-of-3 P2WSH address", ms["address"],
         REF.address_for_spk("mainnet", REF.spk_p2wsh(REF.multisig_script(2, keys))))


def check_money(c, ip):
    call = ip.call
    c.note("\namounts, sizes and fees")
    for sat in (0, 1, 546, 100000000, 123456789, 2100000000000000, -5):
        c.ck("%d satoshi in BTC" % sat, call("cwSatToBtc", [sat]), REF.sat_to_btc(sat))
    for text in ("21000000", "0.00000001", "1.23456789", "0.1", ".5", "12."):
        c.ck("%s BTC in satoshi" % text, call("cwBtcToSat", [text]),
             REF.btc_to_sat(text))
    for bad in ("0.123456789", "abc", "1.2.3", "", "1 2"):
        c.refuses("%r is refused as an amount" % bad,
                  lambda b=bad: call("cwBtcToSat", [b]))
    c.ck("mBTC display", call("cwFormatAmount", [123456789, "mBTC"]),
         REF.sat_to_btc(123456789 * 1000) + " mBTC")
    c.ck("satoshi display", call("cwFormatAmount", [42, "sat"]), "42 sat")

    def ins(specs):
        return lst([{"type": t, "m": m, "cosigners": n} for (t, m, n) in specs])

    cases = [
        ([("p2wpkh", 0, 0)], ["p2wpkh", "p2wpkh"]),
        ([("p2pkh", 0, 0)], ["p2pkh", "p2pkh"]),
        ([("p2tr", 0, 0)], ["p2wpkh"]),
        ([("p2tr", 0, 0)], ["p2tr"]),
        ([("p2sh-p2wpkh", 0, 0)], ["p2wpkh"]),
        ([("p2wsh", 2, 3)], ["p2wpkh"]),
        ([("p2wsh", 3, 5)], ["p2wsh", "p2wpkh"]),
        ([("p2wpkh", 0, 0), ("p2pkh", 0, 0)], ["p2wpkh", "p2tr"]),
        ([("p2wpkh", 0, 0)] * 30, ["p2wpkh", "p2wpkh"]),
    ]
    for spec, outs in cases:
        want = REF.estimate_vsize(
            [(x[0] if x[0] != "p2wsh" else (x[0], x[1], x[2])) for x in spec], outs)
        c.ck("vsize of %d %s in, %s out" % (len(spec), spec[0][0], ",".join(outs)),
             call("cwEstimateVsize", [ins(spec), lst(outs)]), want)
    for t in ("p2pkh", "p2sh", "p2sh-p2wpkh", "p2wpkh", "p2wsh", "p2tr"):
        c.ck("the dust threshold for %s" % t,
             call("cwDustThreshold", [t]), REF.dust_threshold(t))

    # ---- OP_RETURN outputs (2026-09-04): the script, its size, its data ----
    # A data output is sized by a parametrised type, "nulldata:N", because
    # everything here sizes outputs by type and a data output's size is not
    # a property of its type. Every push form the encoder emits is covered:
    # direct (to 75), PUSHDATA1 (to 255), PUSHDATA2.
    for n in (0, 1, 75, 76, 80, 255, 256, 1000):
        data = bytes((i * 7 + 3) & 0xFF for i in range(n))
        c.ck("the OP_RETURN script for %d bytes" % n,
             call("cwOpReturnScript", [data.hex()]), REF.spk_op_return(data).hex())
        c.ck("its output size, nulldata:%d" % n,
             call("cwOutputBytes", ["nulldata:%d" % n]), REF.output_size("nulldata:%d" % n))
        c.ck("its dust threshold is 0", call("cwDustThreshold", ["nulldata:%d" % n]), 0)
        c.ck("and the data reads back", call("cwOpReturnData", [REF.spk_op_return(data).hex()]),
             data.hex())
        c.ck("and the kind is nulldata", call("cwScriptKind", [REF.spk_op_return(data).hex()]),
             "nulldata")
    c.ck("a vsize with a data output",
         call("cwEstimateVsize", [ins([("p2wpkh", 0, 0)]), lst(["p2wpkh", "nulldata:32", "p2wpkh"])]),
         REF.estimate_vsize(["p2wpkh"], ["p2wpkh", "nulldata:32", "p2wpkh"]))
    c.ck("a script that is not OP_RETURN has no data",
         call("cwOpReturnData", [REF.spk_p2wpkh(b"\x02" + b"\x11" * 32).hex()]), "")
    # the shared script reader, on the shapes the decoders meet
    ord_env = (b"\x00\x63" + REF.push(b"ord") + REF.push(b"\x01")
               + REF.push(b"text/plain;charset=utf-8") + b"\x00"
               + REF.push(b"Hello, chain") + b"\x68")
    for label, scr in (("a P2PKH script", REF.spk_p2pkh(b"\x02" + b"\x11" * 32)),
                       ("an OP_RETURN with two pushes", b"\x6a" + REF.push(b"ab") + REF.push(b"cd")),
                       ("an inscription envelope", ord_env),
                       ("a PUSHDATA2 script", b"\x6a" + REF.push(b"z" * 300))):
        want = "".join(("push " + d.hex() if d else "push") + "\n" if k == "push"
                       else "op %d\n" % d for k, d in REF.script_items(scr))
        c.ck("cwScriptItems reads %s" % label, call("cwScriptItems", [scr.hex()]), want)
    try:
        call("cwScriptItems", ["6a4c05aabb"])
        c.ck("a push running past the end is refused", "accepted", "refused")
    except Exception as exc:                            # noqa: BLE001
        c.ck("a push running past the end is refused",
             "refused" if "past the end" in str(getattr(exc, "msg", exc)) else str(exc)[:80],
             "refused")
    for vs, rate in ((110, 5), (141, 1), (226, 1.5), (99, 10.7), (1000, 0.5)):
        c.ck("the fee for %d vB at %s sat/vB" % (vs, rate),
             call("cwFeeFor", [vs, rate]), REF.fee_for(vs, rate))
    c.ck("BIP-125's replacement floor", call("cwRbfMinFee", [500, 141]),
         500 + 141 * REF.INCREMENTAL_RELAY_FEE)


COINS = [{"value": 100000, "txid": "a" * 64, "vout": 0, "confirmations": 10},
         {"value": 50000, "txid": "b" * 64, "vout": 1, "confirmations": 3},
         {"value": 250000, "txid": "c" * 64, "vout": 0, "confirmations": 99},
         {"value": 7000, "txid": "d" * 64, "vout": 2, "confirmations": 1}]


def check_selection(c, ip):
    call = ip.call
    c.note("\ncoin selection")
    for strat in ("bnb", "largest", "smallest", "oldest"):
        for target, rate in ((60000, 5), (150000, 2), (300000, 1)):
            got = call("cwSelectCoins", [lst(COINS), target, rate, "p2wpkh",
                                         lst(["p2wpkh"]), "p2wpkh", strat, 0, 0])
            want = REF.select_coins(COINS, target, rate, "p2wpkh", ["p2wpkh"],
                                    "p2wpkh", strategy=strat)
            label = "%s for %d sat at %s sat/vB" % (strat, target, rate)
            c.ck(label + ": ok", got["ok"] is True or got["ok"] == "true", want["ok"])
            if want["ok"]:
                c.ck(label + ": the coins",
                     [int(x["value"]) for x in unlst(got["selected"])],
                     [x["value"] for x in want["selected"]])
                c.ck(label + ": the fee", got["fee"], want["fee"])
                c.ck(label + ": the change", got["change"], want["change"])
                c.ck(label + ": the total in", got["totalin"], want["total_in"])
                # the arithmetic identity, kept as its own assertion: the line
                # above compares two implementations, this one states the
                # invariant. Written as one check it was neither - both
                # operands came out of the same cwSelectCoins call.
                c.ck(label + ": total in == target + fee + change",
                     got["totalin"], target + got["fee"] + got["change"])
    exact = [{"value": 100550, "txid": "a" * 64, "vout": 0, "confirmations": 9}]
    got = call("cwSelectCoins", [lst(exact), 100000, 5, "p2wpkh", lst(["p2wpkh"]),
                                 "p2wpkh", "bnb", 0, 0])
    c.ck("branch and bound finds the changeless match", got["change"], 0)
    c.true("and says so", "no change output" in got["why"])
    got = call("cwSelectCoins", [lst(COINS), 4000000, 5, "p2wpkh", lst(["p2wpkh"]),
                                 "p2wpkh", "largest", 0, 0])
    c.ck("insufficient funds is a clean refusal", got["ok"], False)
    c.ck("and says why", got["why"], "insufficient funds")
    frozen = [dict(x) for x in COINS]
    frozen[2]["frozen"] = True
    got = call("cwSelectCoins", [lst(frozen), 60000, 5, "p2wpkh", lst(["p2wpkh"]),
                                 "p2wpkh", "largest", 0, 0])
    c.true("a frozen coin is never spent",
           250000 not in [int(x["value"]) for x in unlst(got["selected"])])
    # FROZEN AND TICKED AT ONCE - the one combination the two implementations
    # answered differently and no vector had ever asked them about. Freezing
    # is the more deliberate signal and must win.
    both = [dict(x) for x in COINS]
    both[2]["selected"] = True
    both[2]["frozen"] = True
    both[0]["selected"] = True
    got = call("cwSelectCoins", [lst(both), 60000, 5, "p2wpkh", lst(["p2wpkh"]),
                                 "p2wpkh", "manual", 0, 0])
    want = REF.select_coins(both, 60000, 5, "p2wpkh", ["p2wpkh"], "p2wpkh",
                            strategy="manual")
    c.true("a coin that is both ticked and frozen is NOT spent",
           250000 not in [int(x["value"]) for x in unlst(got["selected"])])
    c.ck("and the oracle agrees about which coins those are",
         [int(x["value"]) for x in unlst(got["selected"])],
         [x["value"] for x in want["selected"]])

    # THE CHANGELESS WINDOW, which nine strategy vectors all miss because each
    # is settled by the change >= dust branch first. One 100,000-sat p2wpkh
    # coin at 1 sat/vB: a change output costs 31 vB, so for targets just under
    # 99,597 the change falls below the 294-sat dust threshold while the
    # changeless surplus is above it - the band where requiring both bounds
    # reported "insufficient funds" for an affordable spend.
    one = [{"value": 100000, "txid": "e" * 64, "vout": 0, "confirmations": 6}]
    for target in (99596, 99580, 99566):
        got = call("cwSelectCoins", [lst(one), target, 1, "p2wpkh",
                                     lst(["p2wpkh"]), "p2wpkh", "bnb", 0, 0])
        want = REF.select_coins(one, target, 1, "p2wpkh", ["p2wpkh"], "p2wpkh",
                                strategy="bnb")
        lbl = "the changeless window at target %d" % target
        c.ck(lbl + ": ok", got["ok"] is True or got["ok"] == "true", True)
        c.ck(lbl + ": no change output", got["change"], 0)
        c.ck(lbl + ": the whole remainder is the fee",
             got["fee"], 100000 - target)
        c.ck(lbl + ": and the oracle agrees", got["fee"], want["fee"])

    # THE TICKED SET IS THE ANSWER, not a prefix of it. Both the script and
    # this gate's oracle used to add ticked coins one at a time and stop at
    # the first prefix that paid - the same rule as the automatic strategies -
    # so ticking three coins to consolidate them spent one. Two
    # implementations agreeing is not the same as either being right, and the
    # existing manual vector could not see it because both its ticked coins
    # were needed to reach the target. This one ticks far more than it needs.
    surplus_ticked = [dict(x) for x in COINS[:3]]
    for coin in surplus_ticked:
        coin["selected"] = True
    got = call("cwSelectCoins", [lst(surplus_ticked), 10000, 5, "p2wpkh",
                                 lst(["p2wpkh"]), "p2wpkh", "manual", 0, 0])
    want = REF.select_coins(surplus_ticked, 10000, 5, "p2wpkh", ["p2wpkh"],
                            "p2wpkh", strategy="manual")
    c.ck("manual spends EVERY ticked coin, not the first that covers it",
         [int(x["value"]) for x in unlst(got["selected"])],
         [x["value"] for x in surplus_ticked])
    c.ck("and the oracle agrees about the fee", got["fee"], want["fee"])
    c.ck("and about the change", got["change"], want["change"])

    # THE BnB ACCEPTANCE WINDOW, at a coin that lands inside it only under the
    # long-term-rate reading. Cost of change is the change output priced NOW
    # plus its future spend priced at kCwLongTermFeeRate; pricing that second
    # half at the current rate instead moved the upper bound 345 satoshi at
    # 5 sat/vB, and every existing vector sat outside the band. This one does
    # not, so the two rules can no longer read as agreement.
    band = [{"value": 101100, "txid": "f" * 64, "vout": 0, "confirmations": 4}]
    got = call("cwSelectCoins", [lst(band), 100000, 5, "p2wpkh",
                                 lst(["p2wpkh"]), "p2wpkh", "bnb", 0, 0])
    want = REF.select_coins(band, 100000, 5, "p2wpkh", ["p2wpkh"], "p2wpkh",
                            strategy="bnb")
    c.ck("a coin inside the cost-of-change band is spent WITHOUT change",
         got["change"], 0)
    # THE BRANCH, NOT THE PROSE. These are two independent implementations
    # and their messages are deliberately not shared, so comparing the strings
    # compares the wording rather than the decision - which is how this check
    # first failed while both sides were taking exactly the same branch.
    c.ck("and both reach it through branch and bound",
         ("branch and bound" in got["why"], "branch and bound" in want["why"]),
         (True, True))
    c.ck("and computes the same fee", got["fee"], want["fee"])
    c.ck("and the oracle agrees there is no change", want["change"], 0)

    manual = [dict(x) for x in COINS]
    manual[1]["selected"] = True
    manual[3]["selected"] = True
    got = call("cwSelectCoins", [lst(manual), 60000, 5, "p2wpkh", lst(["p2wpkh"]),
                                 "p2wpkh", "manual", 0, 0])
    c.ck("manual selection uses exactly the ticked coins",
         sorted(int(x["value"]) for x in unlst(got["selected"])), [7000, 50000])
    got = call("cwSelectCoins", [lst(manual), 600000, 5, "p2wpkh", lst(["p2wpkh"]),
                                 "p2wpkh", "manual", 0, 0])
    c.ck("manual selection that cannot pay is refused", got["ok"], False)
    got = call("cwSelectCoins", [lst([]), 1000, 5, "p2wpkh", lst(["p2wpkh"]),
                                 "p2wpkh", "largest", 0, 0])
    c.ck("an empty wallet is a clean refusal", got["ok"], False)


def check_signing(c, ip):
    """Every spend path, end to end, compared byte for byte with the oracle.

    This is the section that matters most: what it proves is that the
    transaction this wallet would broadcast is the transaction an independent
    implementation of the same specifications builds from the same inputs -
    with real secp256k1 under both.
    """
    call = ip.call
    c.note("\nsigning: five spend paths, byte for byte")
    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    dest = REF.spk_for_address("mainnet", ADDRESSES["mainnet"][2]).hex()
    py_ins = [("aa" * 32, 0, 0xFFFFFFFD)]
    py_outs = [(45000, bytes.fromhex(dest))]
    ins = lst([call("cwTxInput", ["aa" * 32, 0, 0xFFFFFFFD])])
    outs = lst([call("cwTxOutput", [45000, dest])])

    for kind, path, version in (("p2pkh", "m/44'/0'/0'/0/0", 1),
                                ("p2wpkh", "m/84'/0'/0'/0/0", 2),
                                ("p2sh-p2wpkh", "m/49'/0'/0'/0/0", 2)):
        node = CR.bip32_path(master_py, path)
        pub = node["pubkey"].hex()
        digest = call("cwSighash", [kind, version, ins, outs, 1, 0, pub, 50000,
                                    "", lst([]), lst([])])
        want = REF.sighash_for(kind, version, py_ins, py_outs, 0, 0,
                               pubkey=node["pubkey"], amount_sat=50000).hex()
        c.ck("%s sighash" % kind, digest, want)
        sig = call("cwSignInput", [kind, node["seckey"].hex(), digest, pub])
        pss, pwit = REF.sign_input(kind, node["seckey"], bytes.fromhex(want),
                                   node["pubkey"])
        raw = call("cwTxSerialize", [version, ins, outs, 0,
                                     lst([sig["scriptsig"]]), lst([sig["witness"]])])
        c.ck("%s signed transaction" % kind, raw,
             REF.tx_serialize(version, py_ins, py_outs, 0, [pss], [pwit]).hex())
        c.ck("%s txid" % kind,
             call("cwTxid", [version, ins, outs, 0, lst([sig["scriptsig"]])]),
             REF.tx_decode(bytes.fromhex(raw))["txid"])

    cosigners = [CR.bip32_path(master_py, "m/48'/0'/%d'/2'/0/0" % i)
                 for i in range(3)]
    ws = REF.multisig_script(2, [k["pubkey"] for k in cosigners]).hex()
    digest = call("cwSighash", ["p2wsh", 2, ins, outs, 1, 0, "", 50000, ws,
                                lst([]), lst([])])
    want = REF.sighash_for("p2wsh", 2, py_ins, py_outs, 0, 0, amount_sat=50000,
                           witness_script=bytes.fromhex(ws)).hex()
    c.ck("P2WSH multisig sighash", digest, want)
    sig = call("cwSignMultisig", [lst([cosigners[0]["seckey"].hex(),
                                       cosigners[2]["seckey"].hex()]), digest, ws])
    pss, pwit = REF.sign_multisig([cosigners[0]["seckey"], cosigners[2]["seckey"]],
                                  bytes.fromhex(want), bytes.fromhex(ws))
    c.ck("a 2-of-3 signed transaction",
         call("cwTxSerialize", [2, ins, outs, 0, lst([sig["scriptsig"]]),
                                lst([sig["witness"]])]),
         REF.tx_serialize(2, py_ins, py_outs, 0, [pss], [pwit]).hex())

    tr = CR.bip32_path(master_py, "m/86'/0'/0'/0/0")
    okey, _ = CR.taproot_tweak_pubkey(tr["pubkey"][1:], None)
    tspk = REF.spk_p2tr(okey).hex()
    digest = call("cwSighash", ["p2tr", 2, ins, outs, 1, 0, "", 0, "",
                                lst([tspk]), lst([50000])])
    want = REF.sighash_for("p2tr", 2, py_ins, py_outs, 0, 0,
                           prev_spks=[bytes.fromhex(tspk)],
                           prev_amounts=[50000]).hex()
    c.ck("BIP-341 key-path sighash", digest, want)
    sig = call("cwSignTaproot", [tr["seckey"].hex(), digest, ""])
    pss, pwit = REF.sign_taproot_keypath(tr["seckey"], bytes.fromhex(want))
    c.ck("a taproot key-path signed transaction",
         call("cwTxSerialize", [2, ins, outs, 0, lst([sig["scriptsig"]]),
                                lst([sig["witness"]])]),
         REF.tx_serialize(2, py_ins, py_outs, 0, [pss], [pwit]).hex())
    c.refuses("cwSignInput refuses taproot, which needs the key tweaked first",
              lambda: call("cwSignInput", ["p2tr", tr["seckey"].hex(), digest, ""]))


def check_decode(c, ip):
    call = ip.call
    c.note("\ntransaction decoding")
    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    node = CR.bip32_path(master_py, "m/84'/0'/0'/0/0")
    legacy = CR.bip32_path(master_py, "m/44'/0'/0'/0/0")
    dest = REF.spk_for_address("mainnet", ADDRESSES["mainnet"][2])
    py_ins = [("aa" * 32, 0, 0xFFFFFFFD), ("bb" * 32, 3, 0xFFFFFFFF)]
    py_outs = [(45000, dest), (1000, REF.spk_p2pkh(legacy["pubkey"]))]
    sigs, wits = [], []
    for i, amount in enumerate((50000, 9000)):
        d = REF.sighash_for("p2wpkh", 2, py_ins, py_outs, i, 0,
                            pubkey=node["pubkey"], amount_sat=amount)
        ss, w = REF.sign_input("p2wpkh", node["seckey"], d, node["pubkey"])
        sigs.append(ss)
        wits.append(w)
    raw = REF.tx_serialize(2, py_ins, py_outs, 0, sigs, wits).hex()
    got = call("cwTxDecode", [raw])
    want = REF.tx_decode(bytes.fromhex(raw))
    for field in ("txid", "wtxid", "vsize", "weight", "locktime", "version"):
        c.ck("a decoded transaction's %s" % field, got[field], want[field])
    c.ck("its replaceability", got["rbf"] is True or got["rbf"] == "true", want["rbf"])
    c.ck("its input count", call("cwListCount", [got["inputs"]]), 2)
    ins = unlst(got["inputs"])
    c.ck("input 1's txid (display order)", ins[0]["txid"], want["vin"][0]["txid"])
    c.ck("input 2's sequence", ins[1]["sequence"], want["vin"][1]["sequence"])
    c.ck("input 1's witness item count",
         call("cwListCount", [ins[0]["witness"]]), 2)
    outs = unlst(got["outputs"])
    c.ck("output 1's value", outs[0]["value"], want["vout"][0]["value"])
    c.ck("output 1's kind", outs[0]["kind"], "p2wpkh")
    c.ck("output 2's kind", outs[1]["kind"], "p2pkh")
    c.ck("the output total", got["outputtotal"], 46000)
    c.ck("a P2PKH script disassembles",
         call("cwScriptAsm", [outs[1]["script"]]),
         "OP_DUP OP_HASH160 PUSH(20) %s OP_EQUALVERIFY OP_CHECKSIG"
         % REF.hash160(legacy["pubkey"]).hex())
    d = REF.sighash_for("p2pkh", 1, py_ins[:1], py_outs[:1], 0, 0,
                        pubkey=legacy["pubkey"])
    ss, _ = REF.sign_input("p2pkh", legacy["seckey"], d, legacy["pubkey"])
    raw2 = REF.tx_serialize(1, py_ins[:1], py_outs[:1], 0, [ss], None).hex()
    got2 = call("cwTxDecode", [raw2])
    c.ck("a non-witness transaction's txid", got2["txid"],
         REF.tx_decode(bytes.fromhex(raw2))["txid"])
    c.ck("and it is not marked segwit",
         got2["segwit"] is True or got2["segwit"] == "true", False)
    c.refuses("trailing bytes are refused", lambda: call("cwTxDecode", [raw2 + "00"]))
    c.refuses("non-hex is refused", lambda: call("cwTxDecode", ["zzzz"]))


def check_psbt(c, ip):
    call = ip.call
    c.note("\nPSBT")
    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    fp = REF.fingerprint(master_py["pubkey"]).hex()
    dest = REF.spk_for_address("mainnet", ADDRESSES["mainnet"][2]).hex()
    py_ins = [("aa" * 32, 0, 0xFFFFFFFD)]
    py_outs = [(45000, bytes.fromhex(dest))]
    ins = lst([call("cwTxInput", ["aa" * 32, 0, 0xFFFFFFFD])])
    outs = lst([call("cwTxOutput", [45000, dest])])

    node = CR.bip32_path(master_py, "m/84'/0'/0'/0/0")
    spk = REF.spk_p2wpkh(node["pubkey"]).hex()
    meta = {"witnessutxoscript": spk, "witnessutxovalue": 50000,
            "bip32": lst([{"pubkey": node["pubkey"].hex(), "fingerprint": fp,
                           "path": "m/84'/0'/0'/0/0"}])}
    b64 = call("cwPsbtCreate", [2, ins, outs, 0, {"1": meta}, {}])
    want = REF.psbt_create(
        2, py_ins, py_outs, 0,
        in_meta={0: {"witness_utxo": (50000, bytes.fromhex(spk)),
                     "bip32": {node["pubkey"]: (REF.fingerprint(master_py["pubkey"]),
                                                "m/84'/0'/0'/0/0")}}})
    import base64 as _b64
    c.ck("a created PSBT is byte-identical to the oracle's",
         _b64.b64decode(b64).hex(), want.hex())
    c.ck("the unsigned transaction inside it",
         call("cwPsbtParse", [b64])["unsignedtx"],
         REF.unsigned_tx(2, py_ins, py_outs, 0).hex())
    parsed = call("cwPsbtParse", [b64])
    c.ck("its input map count", call("cwListCount", [parsed["inputs"]]), 1)
    c.ck("its output map count", call("cwListCount", [parsed["outputs"]]), 1)
    imap = unlst(parsed["inputs"])[0]
    c.ck("the input amount it carries", call("cwPsbtInputAmount", [imap]), 50000)
    c.ck("the input scriptPubKey it carries", call("cwPsbtInputScript", [imap]), spk)
    c.ck("the input type it implies", call("cwPsbtInputType", [imap]), "p2wpkh")
    c.ck("a path round-trips through PSBT's little-endian levels",
         call("cwPathFromBytes", [call("cwPathBytes", ["m/84'/0'/0'/0/5"])]),
         "m/84'/0'/0'/0/5")
    c.refuses("a truncated PSBT is refused",
              lambda: call("cwPsbtParse", [b64[:40]]))
    c.refuses("something that is not a PSBT is refused",
              lambda: call("cwPsbtParse", ["bm90IGEgcHNidA=="]))

    # ---- THE KEY TYPES, BYTE FOR BYTE -------------------------------------
    # The end-to-end vectors below prove the finalized TRANSACTION matches,
    # which is the thing that spends money - but a transaction can be right
    # while the PSBT carrying it is wrong, and a PSBT is what leaves this
    # wallet and reaches a cosigner. So the intermediate documents are
    # byte-compared too, and between them these three vectors put every
    # kCwPsbt* key type this file emits on the wire under an independent
    # implementation's version of the same bytes.
    ch = CR.bip32_path(master_py, "m/84'/0'/0'/1/0")
    ch_spk = REF.spk_p2wpkh(ch["pubkey"]).hex()
    nested = CR.bip32_path(master_py, "m/49'/0'/0'/1/0")
    redeem = REF.redeem_p2sh_p2wpkh(nested["pubkey"])
    ms = REF.multisig_script(
        2, [CR.bip32_path(master_py, "m/48'/0'/%d'/2'/1/0" % i)["pubkey"]
            for i in range(2)])
    out_meta = {"redeemscript": redeem.hex(), "witnessscript": ms.hex(),
                "bip32": lst([{"pubkey": ch["pubkey"].hex(),
                               "fingerprint": fp, "path": "m/84'/0'/0'/1/0"}])}
    py_outs2 = [(45000, bytes.fromhex(dest)), (4000, bytes.fromhex(ch_spk))]
    outs2 = lst([call("cwTxOutput", [45000, dest]),
                 call("cwTxOutput", [4000, ch_spk])])
    got = call("cwPsbtCreate", [2, ins, outs2, 0, {"1": meta}, {"2": out_meta}])
    want = REF.psbt_create(
        2, py_ins, py_outs2, 0,
        in_meta={0: {"witness_utxo": (50000, bytes.fromhex(spk)),
                     "bip32": {node["pubkey"]: (bytes.fromhex(fp),
                                                "m/84'/0'/0'/0/0")}}},
        out_meta={1: {"redeem_script": redeem, "witness_script": ms,
                      "bip32": {ch["pubkey"]: (bytes.fromhex(fp),
                                               "m/84'/0'/0'/1/0")}}})
    c.ck("a PSBT with OUTPUT metadata is byte-identical to the oracle's "
         "(the three kCwPsbtOut* key types)",
         _b64.b64decode(got).hex(), want.hex())

    # a LEGACY input carries the whole previous transaction, not a witness
    # utxo - the one branch that emits kCwPsbtInNonWitnessUtxo
    prev = REF.tx_serialize(2, [("dd" * 32, 0, 0xFFFFFFFF)],
                            [(50000, REF.spk_p2pkh(
                                CR.bip32_path(master_py,
                                              "m/44'/0'/0'/0/0")["pubkey"]))],
                            0, [b""])
    got = call("cwPsbtCreate", [2, ins, outs, 0,
                                {"1": {"nonwitnessutxo": prev.hex(),
                                       "sighash": 1}}, {}])
    want = REF.psbt_create(2, py_ins, py_outs, 0,
                           in_meta={0: {"non_witness_utxo": prev,
                                        "sighash": 1}})
    c.ck("a PSBT carrying a whole previous transaction and a sighash type "
         "is byte-identical (kCwPsbtInNonWitnessUtxo, kCwPsbtInSighashType)",
         _b64.b64decode(got).hex(), want.hex())

    # a SIGNED and a FINALIZED PSBT, compared as documents rather than as
    # the transaction they eventually produce
    b64s = call("cwPsbtCreate", [2, ins, outs, 0, {"1": meta}, {}])
    sig_res = call("cwPsbtSign", [b64s, lst([{"seckey": node["seckey"].hex()}]),
                                  "mainnet"])
    dgst = REF.sighash_for("p2wpkh", 2, py_ins, py_outs, 0, 0,
                           pubkey=node["pubkey"], amount_sat=50000)
    der = REF.der_sig(node["seckey"], dgst)
    want = REF.psbt_create(
        2, py_ins, py_outs, 0,
        in_meta={0: {"witness_utxo": (50000, bytes.fromhex(spk)),
                     "partial_sigs": {node["pubkey"]: der},
                     "bip32": {node["pubkey"]: (bytes.fromhex(fp),
                                                "m/84'/0'/0'/0/0")}}})
    c.ck("a SIGNED PSBT is byte-identical to the oracle's "
         "(kCwPsbtInPartialSig, keyed by the pubkey and carrying the "
         "sighash byte)", _b64.b64decode(sig_res["psbt"]).hex(), want.hex())
    fin = call("cwPsbtFinalize", [sig_res["psbt"]])
    _ss, _wit = REF.sign_input("p2wpkh", node["seckey"], dgst, node["pubkey"])
    # an EMPTY final scriptSig is not emitted at all (the script guards on
    # `is not ""`), which is what a v0 witness input should look like
    # BIP-174's Finalizer must CLEAR what the final fields supersede - the
    # partial signatures, the sighash type, the redeem and witness scripts
    # and the derivations - so the only entries left are the UTXO and the
    # final ones. This vector is what found that the layer kept them: a
    # forwarded PSBT was carrying a derivation path saying which wallet and
    # which chain position paid.
    final_meta = {"witness_utxo": (50000, bytes.fromhex(spk)),
                  "final_scriptwitness": REF.witness_bytes(_wit)}
    if _ss:
        final_meta["final_scriptsig"] = _ss
    want = REF.psbt_create(2, py_ins, py_outs, 0, in_meta={0: final_meta})
    c.ck("a FINALIZED PSBT is byte-identical to the oracle's "
         "(kCwPsbtInFinalScriptSig, kCwPsbtInFinalScriptWitness)",
         _b64.b64decode(fin["psbt"]).hex(), want.hex())

    for kind, path in (("p2wpkh", "m/84'/0'/0'/0/0"),
                       ("p2sh-p2wpkh", "m/49'/0'/0'/0/0"),
                       ("p2pkh", "m/44'/0'/0'/0/0")):
        node = CR.bip32_path(master_py, path)
        fn = {"p2pkh": REF.spk_p2pkh, "p2wpkh": REF.spk_p2wpkh,
              "p2sh-p2wpkh": REF.spk_p2sh_p2wpkh}[kind]
        spk = fn(node["pubkey"]).hex()
        meta = {"witnessutxoscript": spk, "witnessutxovalue": 50000,
                "bip32": lst([{"pubkey": node["pubkey"].hex(), "fingerprint": fp,
                               "path": path}])}
        if kind == "p2sh-p2wpkh":
            meta["redeemscript"] = call("cwRedeemP2shP2wpkh", [node["pubkey"].hex()])
        b64 = call("cwPsbtCreate", [2, ins, outs, 0, {"1": meta}, {}])
        signed = call("cwPsbtSign", [b64, lst([{"seckey": node["seckey"].hex()}]),
                                     "mainnet"])
        c.ck("%s: one input signed" % kind, signed["signed"], 1)
        final = call("cwPsbtFinalize", [signed["psbt"]])
        c.true("%s: finalized complete" % kind, final["complete"])
        d = REF.sighash_for(kind, 2, py_ins, py_outs, 0, 0,
                            pubkey=node["pubkey"], amount_sat=50000)
        pss, pwit = REF.sign_input(kind, node["seckey"], d, node["pubkey"])
        c.ck("%s: the finalized transaction" % kind, final["raw"],
             REF.tx_serialize(2, py_ins, py_outs, 0, [pss],
                              [pwit] if pwit else None).hex())
        nokey = call("cwPsbtSign", [b64, lst([]), "mainnet"])
        c.ck("%s: no key means no signature" % kind, nokey["signed"], 0)
        c.true("%s: and it says which input and why" % kind,
               "input 1" in nokey["why"])

    cosigners = [CR.bip32_path(master_py, "m/48'/0'/%d'/2'/0/0" % i)
                 for i in range(3)]
    ws = REF.multisig_script(2, [k["pubkey"] for k in cosigners]).hex()
    spk = REF.spk_p2wsh(bytes.fromhex(ws)).hex()
    meta = {"witnessutxoscript": spk, "witnessutxovalue": 50000,
            "witnessscript": ws}
    b64 = call("cwPsbtCreate", [2, ins, outs, 0, {"1": meta}, {}])
    first = call("cwPsbtSign", [b64, lst([{"seckey": cosigners[0]["seckey"].hex()}]),
                                "mainnet"])
    third = call("cwPsbtSign", [b64, lst([{"seckey": cosigners[2]["seckey"].hex()}]),
                                "mainnet"])
    partial = call("cwPsbtFinalize", [first["psbt"]])
    c.ck("one cosigner is not enough", partial["complete"] is True
         or partial["complete"] == "true", False)
    c.true("and it says how many of how many", "1 of 2" in partial["why"])
    combined = call("cwPsbtCombine", [first["psbt"], third["psbt"]])
    final = call("cwPsbtFinalize", [combined])
    c.true("two cosigners combined are enough", final["complete"])
    d = REF.sighash_for("p2wsh", 2, py_ins, py_outs, 0, 0, amount_sat=50000,
                        witness_script=bytes.fromhex(ws))
    pss, pwit = REF.sign_multisig([cosigners[0]["seckey"], cosigners[2]["seckey"]],
                                  d, bytes.fromhex(ws))
    c.ck("the combined 2-of-3 transaction", final["raw"],
         REF.tx_serialize(2, py_ins, py_outs, 0, [pss], [pwit]).hex())
    other = call("cwPsbtCreate", [2, ins, lst([call("cwTxOutput", [44000, dest])]),
                                  0, {"1": meta}, {}])
    c.refuses("combining two DIFFERENT transactions is refused",
              lambda: call("cwPsbtCombine", [b64, other]))

    tr = CR.bip32_path(master_py, "m/86'/0'/0'/0/0")
    okey, _ = CR.taproot_tweak_pubkey(tr["pubkey"][1:], None)
    tspk = REF.spk_p2tr(okey).hex()
    meta = {"witnessutxoscript": tspk, "witnessutxovalue": 50000,
            "tapinternalkey": tr["pubkey"][1:].hex()}
    b64 = call("cwPsbtCreate", [2, ins, outs, 0, {"1": meta}, {}])
    signed = call("cwPsbtSign", [b64, lst([{"seckey": tr["seckey"].hex()}]),
                                 "mainnet"])
    final = call("cwPsbtFinalize", [signed["psbt"]])
    c.true("a taproot input signs and finalizes", final["complete"])
    d = REF.sighash_for("p2tr", 2, py_ins, py_outs, 0, 0,
                        prev_spks=[bytes.fromhex(tspk)], prev_amounts=[50000])
    pss, pwit = REF.sign_taproot_keypath(tr["seckey"], d)
    c.ck("the taproot transaction", final["raw"],
         REF.tx_serialize(2, py_ins, py_outs, 0, [pss], [pwit]).hex())
    summary = call("cwPsbtSummary", [b64, "mainnet"])
    c.true("the summary names the destination", ADDRESSES["mainnet"][2] in summary)
    c.true("the summary states the fee", "fee: 0.00005000" in summary)
    noamount = call("cwPsbtCreate", [2, ins, outs, 0, {}, {}])
    r = call("cwPsbtSign", [noamount, lst([{"seckey": tr["seckey"].hex()}]),
                            "mainnet"])
    c.ck("an input with no witness UTXO is NOT signed", r["signed"], 0)
    c.true("and the refusal says the amount is unknown",
           "amount" in r["why"] and "guess" in r["why"])


def check_audit_2026_09_01(c, ip):
    """The wallet-core half of the 2026-09-01 audit: three fail-open paths.

    Each is checked in BOTH directions - the hostile shape is refused AND the
    legitimate one still works - because an over-refusing guard is the same
    defect with the sign flipped, and this member has shipped one of those
    before.
    """
    call = ip.call
    c.note("\nthe 2026-09-01 audit: three fail-open paths in the engine")

    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    node = CR.bip32_path(master_py, "m/84'/0'/0'/0/0")
    ourpub = node["pubkey"].hex()
    seckey = node["seckey"].hex()

    # (1) cwPsbtSign must bind the witness script to the output it claims to
    # spend. Our cosigner pubkeys are public - they are in any descriptor or
    # account xpub this wallet has ever exported - so without this an attacker
    # builds a 1-of-1 witness script around one, names any 32-byte P2WSH
    # program as the witness UTXO, and gets a signature over a BIP-143
    # preimage of their own choosing, reported as "SIGNED 1 input(s)".
    hostile_ws = call("cwMultisigScript", [1, lst([ourpub])])
    real_spk = call("cwScriptP2wsh", [hostile_ws])
    fake_spk = "0020" + "cd" * 32
    ins = lst([call("cwTxInput", ["aa" * 32, 0, 0xFFFFFFFD])])
    dest = REF.spk_for_address("mainnet", ADDRESSES["mainnet"][2]).hex()
    outs = lst([call("cwTxOutput", [45000, dest])])

    def psbt_with(spk):
        meta = {"witnessutxoscript": spk, "witnessutxovalue": 50000,
                "witnessscript": hostile_ws}
        return call("cwPsbtCreate", [2, ins, outs, 0, {"1": meta}, {}])

    keys = lst([{"seckey": seckey}])
    got = call("cwPsbtSign", [psbt_with(fake_spk), keys, "mainnet"])
    c.ck("a P2WSH input whose witness script does not hash to its own "
         "scriptPubKey is NOT signed", int(LCS._n(got["signed"])), 0)
    # c.true, NOT c.ck: this gate's ck is (label, got, want) and the boot
    # gate's beside it is (label, ok, detail). Written in the other file's
    # shape, this compared a Python bool against a description string - the
    # exact mistake this member recorded finding eleven times in one file.
    c.true("and it says why", "does not hash to the output" in str(got["why"]))
    got = call("cwPsbtSign", [psbt_with(real_spk), keys, "mainnet"])
    c.ck("but the same script over its OWN scriptPubKey still signs",
         int(LCS._n(got["signed"])), 1)

    # (2) cwTxDecode must not take a count from the bytes and use it as a loop
    # bound. OXT runs script on the UI thread, so an unbounded loop here is a
    # frozen engine with no error anybody can read.
    c.refuses("cwTxDecode refuses an input count the bytes cannot satisfy",
              lambda: call("cwTxDecode", ["01000000feffffff0f"]))
    c.refuses("cwTxDecode refuses an 0xff input count",
              lambda: call("cwTxDecode", ["01000000ffffffffffffffffff"]))
    c.refuses("cwTxDecode refuses an output count the bytes cannot satisfy",
              lambda: call("cwTxDecode",
                           ["0100000001" + "aa" * 32 + "00000000" + "00"
                            + "ffffffff" + "fdffff"]))
    # AND A REAL TRANSACTION STILL DECODES, so the bound is a refusal of the
    # impossible and not a wall. Without this the guard could be arbitrarily
    # strict and every refusal check above would still pass.
    good = call("cwTxSerialize", [2, ins, outs, 0, lst([""]), lst([lst([])])])
    dec = call("cwTxDecode", [good])
    c.ck("a real transaction still decodes past the bound",
         int(LCS._n(call("cwListCount", [dec["inputs"]]))), 1)
    c.ck("and reports its one output",
         int(LCS._n(call("cwListCount", [dec["outputs"]]))), 1)
    c.ck("and its txid", len(str(dec["txid"])), 64)

    # (3) cwSignInput's type set is closed. Everything that fell through got a
    # [signature, pubkey] witness with an empty scriptSig, which is P2WPKH's
    # shape - and "p2wsh" reaches it through the file's own documented
    # pairing with cwSighash, so the wallet produced a signed-looking
    # transaction no node will accept.
    digest = "11" * 32
    c.refuses("cwSignInput refuses p2wsh, which cwSignMultisig owns",
              lambda: call("cwSignInput", ["p2wsh", seckey, digest, ourpub]))
    c.refuses("cwSignInput refuses a type it does not know",
              lambda: call("cwSignInput", ["p2sh", seckey, digest, ourpub]))
    for kind in ("p2pkh", "p2wpkh", "p2sh-p2wpkh"):
        sig = call("cwSignInput", [kind, seckey, digest, ourpub])
        c.true("cwSignInput still signs %s" % kind,
               str(sig["scriptsig"]) != "" or
               int(LCS._n(call("cwListCount", [sig["witness"]]))) > 0)


def check_script_framing(c, ip):
    """cwScriptCheck, in both directions and at every push encoding.

    The renderer beside it (cwScriptAsm) cannot ask this question, because a
    LiveCodeScript chunk expression that runs past the end of a string answers
    with what is there instead of refusing: a push claiming forty bytes with
    ten left renders as a ten-byte push and reads exactly like a correct
    decode of a different script. That is why the Tools screen's script
    decoder frames the bytes BEFORE it renders them, and why every one of
    these is checked both ways round - a checker that says "not framed" to
    everything passes half of this on its own.
    """
    call = ip.call
    c.note("\nbare-script framing (cwScriptCheck)")

    good = [
        ("P2WPKH", "0014" + "75" * 20),
        ("P2PKH", "76a914" + "75" * 20 + "88ac"),
        ("P2SH", "a914" + "75" * 20 + "87"),
        ("P2WSH", "0020" + "ab" * 32),
        ("P2TR", "5120" + "ab" * 32),
        ("OP_RETURN with a 4-byte push", "6a04deadbeef"),
        ("bare OP_1", "51"),
        # OP_PUSHDATA1 of exactly 76 bytes, the first length that needs it
        ("PUSHDATA1", "4c4c" + "11" * 76),
        # OP_PUSHDATA2 of 256 bytes, LITTLE-endian length
        ("PUSHDATA2", "4d0001" + "22" * 256),
    ]
    for label, hexs in good:
        c.ck("%s frames" % label, call("cwScriptCheck", [hexs]), "")

    bad = [
        ("a 20-byte push with 2 bytes left", "0014dead"),
        ("a 32-byte push with nothing left", "0020"),
        ("PUSHDATA1 with no length byte", "4c"),
        ("PUSHDATA1 claiming 76 with 4 given", "4c4cdeadbeef"),
        ("PUSHDATA2 with a truncated length", "4d00"),
        ("PUSHDATA2 claiming 256 with 4 given", "4d0001deadbeef"),
        ("PUSHDATA4 with a truncated length", "4e000000"),
        ("PUSHDATA4 claiming 1 with nothing given", "4e01000000"),
    ]
    for label, hexs in bad:
        c.true("%s is refused" % label, str(call("cwScriptCheck", [hexs])) != "")

    # ...and the two shapes that are not scripts at all.
    c.true("empty is refused", "empty" in str(call("cwScriptCheck", [""])))
    c.true("non-hex is refused", "hex" in str(call("cwScriptCheck", ["zz01"])))
    # An ODD number of hex characters is half a byte, and the walker reads two
    # at a time - so without the cleanliness gate it would read the last one
    # against nothing and answer for a script that does not exist.
    c.true("an odd-length string is refused",
           str(call("cwScriptCheck", ["001"])) != "")

    # THE RENDERER STILL AGREES WITH THE FRAMER on everything the framer
    # accepts. Two walks over the same bytes is the arrangement this file's
    # own comment defends, and the cost of it is that they can disagree.
    for label, hexs in good:
        asm = str(call("cwScriptAsm", [hexs]))
        c.true("%s still disassembles to something" % label, asm != "")


def check_messages(c, ip):
    call = ip.call
    c.note("\nsigned messages, URIs and descriptors")
    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    c.ck("the empty-message magic hash", call("cwMsgDigest", [""]),
         REF.message_digest("").hex())
    c.ck("a magic hash with content", call("cwMsgDigest", ["test"]),
         REF.message_digest("test").hex())
    for kind, path in (("p2pkh", "m/44'/0'/0'/0/0"), ("p2wpkh", "m/84'/0'/0'/0/0"),
                       ("p2sh-p2wpkh", "m/49'/0'/0'/0/0")):
        node = CR.bip32_path(master_py, path)
        fn = {"p2pkh": REF.spk_p2pkh, "p2wpkh": REF.spk_p2wpkh,
              "p2sh-p2wpkh": REF.spk_p2sh_p2wpkh}[kind]
        addr = REF.address_for_spk("mainnet", fn(node["pubkey"]))
        sig = call("cwMsgSign", [node["seckey"].hex(), "hello wallet", kind, True])
        c.ck("a %s message signature" % kind, sig,
             REF.message_sign(node["seckey"], "hello wallet", kind, True))
        v = call("cwMsgVerify", ["mainnet", addr, "hello wallet", sig])
        c.true("%s: it verifies" % kind, v["ok"])
        c.ck("%s: against the right form" % kind, v["kind"], kind)
        bad = call("cwMsgVerify", ["mainnet", addr, "hello wallEt", sig])
        c.ck("%s: a tampered message does not" % kind,
             bad["ok"] is True or bad["ok"] == "true", False)
    # ---- BIP-322 (2026-09-04): the hash, the virtual spend, both shapes ----
    # The BIP's published values for the message hash and the to_spend txid
    # come first, then the signatures against the oracle byte for byte (both
    # sides sign deterministically), then the verifier on each, on a
    # tampered message, on the wrong address, and on the BIP's own
    # signatures for its test key.
    for msg, want in (("", "c90c269c4f8fcbe6880f72a721ddfbf1914268a794cbb21cfafee13770ae19f1"),
                      ("Hello World", "f0eb03b1a75ac6d9847f55c624a99169b5dccba2a31f5b23bea77ba270de0a7a")):
        c.ck("BIP-322's message hash for %r, as published" % msg,
             call("cwBip322Hash", [msg]), want)
        c.ck("and it is the oracle's", REF.bip322_hash(msg).hex(), want)
    bip_sk, bip_comp, bip_net = CR.wif_decode("L3VFeEujGtevx9w18HD1fhRbCH67Az2dpCymeRE1SoPK6XQtaN2k")[:3]
    bip_pub = CR.pubkey(bip_sk)
    bip_spk = REF.spk_p2wpkh(bip_pub)
    bip_addr = REF.address_for_spk("mainnet", bip_spk)
    c.ck("the BIP's test key gives the BIP's address", bip_addr,
         "bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l")
    for msg, want in (("", "c5680aa69bb8d860bf82d4e9cd3504b55dde018de765a91bb566283c545a99a7"),
                      ("Hello World", "b79d196740ad5217771c1098fc4a4b51e0535c32236c71f1ea4d61a2d603352b")):
        c.ck("to_spend's txid for %r, as published" % msg,
             call("cwBip322ToSpendTxid", [msg, bip_spk.hex()]), want)
        c.ck("and the oracle's", REF.bip322_to_spend_txid(msg, bip_spk), want)
    for msg in ("", "Hello World", "hello wallet"):
        sig = call("cwBip322Sign", [bip_sk.hex(), msg, "p2wpkh", bip_spk.hex(), bip_pub.hex()])
        c.ck("a P2WPKH BIP-322 signature for %r matches the oracle" % msg, sig,
             REF.bip322_sign(bip_sk, msg, "p2wpkh", bip_spk, bip_pub))
        v = call("cwBip322Verify", ["mainnet", bip_addr, msg, sig])
        c.true("p2wpkh: it verifies (%r)" % msg, v["ok"])
        c.ck("p2wpkh: and says which shape", v["kind"], "bip322-p2wpkh")
        bad = call("cwBip322Verify", ["mainnet", bip_addr, msg + "!", sig])
        c.ck("p2wpkh: a tampered message does not verify",
             bad["ok"] is True or bad["ok"] == "true", False)
    # bip-0322/basic-test-vectors.json (the BIP's own file, "simple" cases
    # for its test key; the file prefixes each with "smp"): two signatures
    # per message, one low-R and one not, and both must verify
    for msg, published in (
            ("", "AkcwRAIgM2gBAQqvZX15ZiysmKmQpDrG83avLIT492QBzLnQIxYCIBaTpOaD20qRlEylyxFSeEA2ba9YOixpX8z46TSDtS40ASECx/EgAxlkQpQ9hYjgGu6EBCPMVPwVIVJqO4XCsMvViHI="),
            ("", "AkgwRQIhAPkJ1Q4oYS0htvyuSFHLxRQpFAY56b70UvE7Dxazen0ZAiAtZfFz1S6T6I23MWI2lK/pcNTWncuyL8UL+oMdydVgzAEhAsfxIAMZZEKUPYWI4BruhAQjzFT8FSFSajuFwrDL1Yhy"),
            ("Hello World", "AkcwRAIgZRfIY3p7/DoVTty6YZbWS71bc5Vct9p9Fia83eRmw2QCICK/ENGfwLtptFluMGs2KsqoNSk89pO7F29zJLUx9a/sASECx/EgAxlkQpQ9hYjgGu6EBCPMVPwVIVJqO4XCsMvViHI="),
            ("Hello World", "AkgwRQIhAOzyynlqt93lOKJr+wmmxIens//zPzl9tqIOua93wO6MAiBi5n5EyAcPScOjf1lAqIUIQtr3zKNeavYabHyR8eGhowEhAsfxIAMZZEKUPYWI4BruhAQjzFT8FSFSajuFwrDL1Yhy")):
        v = call("cwBip322Verify", ["mainnet", bip_addr, msg, published])
        c.true("the BIP's published signature for %r verifies" % msg, v["ok"])
    tr = CR.bip32_path(master_py, "m/86'/0'/0'/0/0")
    okey, _ = CR.taproot_tweak_pubkey(tr["pubkey"][1:], None)
    tr_spk = REF.spk_p2tr(okey)
    tr_addr = REF.address_for_spk("mainnet", tr_spk)
    sig = call("cwBip322Sign", [tr["seckey"].hex(), "hello taproot", "p2tr", tr_spk.hex(), ""])
    c.ck("a P2TR BIP-322 signature matches the oracle", sig,
         REF.bip322_sign(tr["seckey"], "hello taproot", "p2tr", tr_spk))
    v = call("cwBip322Verify", ["mainnet", tr_addr, "hello taproot", sig])
    c.true("p2tr: it verifies", v["ok"])
    c.ck("p2tr: and says which shape", v["kind"], "bip322-p2tr")
    bad = call("cwBip322Verify", ["mainnet", tr_addr, "hello Taproot", sig])
    c.ck("p2tr: a tampered message does not verify",
         bad["ok"] is True or bad["ok"] == "true", False)
    wrong = call("cwBip322Verify", ["mainnet", bip_addr, "hello taproot", sig])
    c.ck("a taproot signature against a P2WPKH address is refused, with the reason",
         "two items" in str(wrong["why"]), True)
    for junk in ("not base64!!", "", "AAAA", "AQ=="):
        r = call("cwBip322Verify", ["mainnet", bip_addr, "x", junk])
        c.ck("BIP-322: %r is refused without throwing" % junk,
             r["ok"] is True or r["ok"] == "true", False)
    legacy_addr = REF.address_for_spk("mainnet", REF.spk_p2pkh(bip_pub))
    r = call("cwBip322Verify", ["mainnet", legacy_addr, "x", sig])
    c.ck("a legacy address is sent to the 2011 format", "2011" in str(r["why"]), True)
    stack = call("cwWitnessStackEncode", [lst(["aa", "", "bb" * 300])])
    back = call("cwWitnessStackDecode", [stack])
    c.ck("a witness stack with an empty item and a long one round-trips",
         unlst(back), ["aa", "", "bb" * 300])
    r_der = call("cwDerToCompact", [CR.der_encode(1, 2 ** 255 + 7).hex()])
    c.ck("DER to compact pads and strips as the encoding requires", r_der,
         (1).to_bytes(32, "big").hex() + (2 ** 255 + 7).to_bytes(32, "big").hex())

    node = CR.bip32_path(master_py, "m/84'/0'/0'/0/0")
    addr = REF.address_for_spk("mainnet", REF.spk_p2wpkh(node["pubkey"]))
    legacy_header = call("cwMsgSign", [node["seckey"].hex(), "x", "p2pkh", True])
    v = call("cwMsgVerify", ["mainnet", addr, "x", legacy_header])
    c.true("a legacy header over a bech32 address still verifies", v["ok"])
    c.true("and the disagreement is reported, not swallowed", "header claims" in v["why"])
    for junk in ("not base64!!", "", "AAAA"):
        r = call("cwMsgVerify", ["mainnet", addr, "x", junk])
        c.ck("%r is refused without throwing" % junk,
             r["ok"] is True or r["ok"] == "true", False)
    other = REF.address_for_spk("mainnet",
                                REF.spk_p2wpkh(CR.bip32_path(master_py,
                                                             "m/84'/0'/0'/0/1")["pubkey"]))
    r = call("cwMsgVerify", ["mainnet", other, "x", legacy_header])
    c.ck("a signature from another key is refused",
         r["ok"] is True or r["ok"] == "true", False)
    c.true("and the refusal is specific", "DIFFERENT address" in r["why"])

    u = call("cwUriParse", ["bitcoin:%s?amount=0.001&label=Luke-Jr"
                            % ADDRESSES["mainnet"][2]])
    c.ck("a BIP-21 address", u["address"], ADDRESSES["mainnet"][2])
    c.ck("a BIP-21 amount is BTC, not satoshi", u["amountsat"], 100000)
    c.ck("a BIP-21 label", u["label"], "Luke-Jr")
    c.ck("a URI with no scheme still parses",
         call("cwUriParse", [ADDRESSES["mainnet"][2]])["address"],
         ADDRESSES["mainnet"][2])
    c.ck("a req- parameter is surfaced",
         unlst(call("cwUriParse", ["bitcoin:1A1?req-unknown=50"])["required"]),
         ["req-unknown"])
    c.ck("a URI is built the way the oracle builds it",
         call("cwUriBuild", [ADDRESSES["mainnet"][2], 100000, "Luke-Jr",
                             "Donation for project xyz"]),
         REF.uri_build(ADDRESSES["mainnet"][2], 100000, "Luke-Jr",
                       "Donation for project xyz"))
    u = call("cwUriParse", ["bitcoin:%s?amount=0.001&lightning=LNBC10U1P3PJ257PP5"
                            % ADDRESSES["mainnet"][2]])
    c.ck("a unified URI keeps its lightning invoice beside the address",
         (u["address"], u["amountsat"], u["lightning"]),
         (ADDRESSES["mainnet"][2], 100000, "LNBC10U1P3PJ257PP5"))
    c.ck("and one with no address still parses",
         call("cwUriParse", ["bitcoin:?lightning=lnbc1abc"])["lightning"], "lnbc1abc")
    c.ck("percent-encoding round-trips",
         call("cwPercentDecode", [call("cwPercentEncode", ["a b/c?d=e&f"])]),
         "a b/c?d=e&f")

    # THE THREE TAIL POSITIONS OF CORE'S ALPHABET - a double quote, a
    # backslash and a space - are hand-coded returns in cwDescCharPos because
    # they cannot go inside an ASCII constant, and nothing reached any of
    # them. The oracle handles all 95 positions, so it is the answer key.
    for tail, name in (('raw(de"adbeef)', "a double quote"),
                       ("raw(de\\adbeef)", "a backslash"),
                       ("raw(de adbeef)", "a space")):
        c.ck("the descriptor checksum over %s" % name,
             call("cwDescriptorChecksum", [tail]), REF.descriptor_checksum(tail))
    for desc, want in (("raw(deadbeef)", "89f8spxm"),
                       ("wpkh([d34db33f/84h/0h/0h]xpub6DJ2dNUysrn5Vt36jH2KLBT2i1a"
                        "uw1tTSSomg8PhqNiUtx8QX2SvC9nrHu81fT41fvDUnhMjEzQgXnQjKEu"
                        "3oaqMSzhSrHMxyyoEAmUHQbY/0/*)", "cjjspncu")):
        c.ck("Bitcoin Core's descriptor checksum for %s" % desc[:20],
             call("cwDescriptorChecksum", [desc]), want)
    fp = REF.fingerprint(master_py["pubkey"]).hex()
    acct = CR.bip32_path(master_py, "m/84'/0'/0'")
    xpub = REF.xkey_encode(acct, REF.xkey_version("mainnet", "p2pkh", True), False)
    for t in ("p2pkh", "p2sh-p2wpkh", "p2wpkh", "p2tr"):
        c.ck("a %s descriptor" % t,
             call("cwDescriptor", [t, xpub, fp, "m/84'/0'/0'", 0]),
             REF.descriptor(t, xpub, fp, "m/84'/0'/0'", 0))
    keys = [REF.xkey_encode(CR.bip32_path(master_py, "m/48'/0'/%d'/2'" % i),
                            REF.xkey_version("mainnet", "p2pkh", True), False)
            for i in range(3)]
    c.ck("a sortedmulti descriptor",
         call("cwDescriptorMultisig", [2, lst(keys), 0, True]),
         REF.descriptor_multisig(2, keys, 0))
    c.refuses("a character that cannot appear in a descriptor is refused",
              lambda: call("cwDescriptorChecksum", ["pkh(" + chr(200) + ")"]))


JSON_SAMPLES = [
    '{"address":"bc1q","chain_stats":{"funded_txo_sum":123456,"tx_count":3}}',
    '[{"txid":"aa","vout":0,"value":50000,"status":{"confirmed":true}},'
    '{"txid":"bb","vout":1,"value":250,"status":{"confirmed":false}}]',
    '{"jsonrpc":"2.0","result":["one","two"],"id":1}',
    '[]', '{}', '"just a string"', '42', 'true', 'null',
]


SP_VECTORS = os.path.join(MEMBER, "tests", "bip352-sending-vectors.json")


def check_silent_payments(c, ip):
    """BIP-352, the sending side: the long bech32m codec, the hex scalars,
    and every stage of the derivation against the BIP's own sending vectors
    (tests/bip352-sending-vectors.json, the published file's sending half).
    The receiver-side input extraction that decides which inputs take part
    is the oracle's, and the vectors' input_pub_keys hold IT to the BIP."""
    import json as _json
    call = ip.call
    c.note("\nBIP-352 silent payments, the sending side")
    # ---- the codec, with the BIP's own waiver on BIP-173's length --------
    v0 = _json.load(open(SP_VECTORS, encoding="utf-8"))["vectors"]
    r0 = v0[0]["given"]["recipients"][0]
    scan0, spend0 = bytes.fromhex(r0["scan_pub_key"]), bytes.fromhex(r0["spend_pub_key"])
    c.ck("a 116-character silent payment address decodes past BIP-173's 90",
         len(r0["address"]) > 90, True)
    d = call("cwSpDecode", ["mainnet", r0["address"]])
    c.ck("its scan key", d["scan"], r0["scan_pub_key"])
    c.ck("its spend key", d["spend"], r0["spend_pub_key"])
    c.ck("its version", LCS._n(d["version"]), 0)
    c.ck("and it re-encodes to the same address",
         call("cwSpEncode", ["mainnet", r0["scan_pub_key"], r0["spend_pub_key"]]),
         r0["address"])
    c.ck("the oracle encodes it the same way",
         REF.sp_encode("mainnet", scan0, spend0), r0["address"])
    up = r0["address"].upper()
    c.ck("an all-uppercase address decodes",
         call("cwSpDecode", ["mainnet", up])["scan"], r0["scan_pub_key"])
    for net, hrp in (("testnet", "tsp"), ("signet", "tsp"), ("testnet4", "tsp"),
                     ("regtest", "sprt"), ("mainnet", "sp")):
        c.ck("%s's prefix is %s" % (net, hrp), call("cwSpHrp", [net]), hrp)
        a = REF.sp_encode(net, scan0, spend0)
        c.ck("a %s address round-trips" % net,
             call("cwSpDecode", [net, a])["spend"], r0["spend_pub_key"])
        c.true("and is recognised by shape", call("cwSpIsAddress", [a]))
    c.ck("an ordinary bech32 address is not one",
         call("cwSpIsAddress", ["bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l"]),
         False)
    tsp = REF.sp_encode("testnet", scan0, spend0)
    for label, net, text, want in (
            ("a testnet address is refused on mainnet, naming both",
             "mainnet", tsp, "test network"),
            ("a mainnet address is refused on signet",
             "signet", r0["address"], "mainnet"),
            ("a corrupt checksum is refused",
             "mainnet", r0["address"][:-1] + ("q" if r0["address"][-1] != "q" else "p"),
             "checksum"),
            ("mixed case is refused",
             "mainnet", r0["address"][:20].upper() + r0["address"][20:], "mixes"),
            ("version 31 is refused as reserved",
             "mainnet", REF.sp_encode("mainnet", scan0, spend0, 31), "reserved"),
            ("a version 0 address with 65 bytes is refused",
             "mainnet", REF.bech32_encode_long(
                 "sp", [0] + REF._convertbits(scan0 + spend0[:32], 8, 5, True), "bech32m"),
             "exactly 66"),
            ("a bech32 (not m) checksum is refused",
             "mainnet", REF.bech32_encode_long(
                 "sp", [0] + REF._convertbits(scan0 + spend0, 8, 5, True), "bech32"),
             "bech32m"),
            ("a scan key that is not a point is refused",
             "mainnet", REF.bech32_encode_long(
                 "sp", [0] + REF._convertbits(b"\x02" + b"\xff" * 32 + spend0, 8, 5, True),
                 "bech32m"), "")):
        try:
            call("cwSpDecode", [net, text])
            c.ck(label, "accepted", "refused")
        except LCS.Thrown as exc:
            c.ck(label, True if want in str(exc.msg) else str(exc.msg)[:120], True)
        except RuntimeError as exc:
            # the not-a-point case: the decompressor refuses natively, which
            # the engine surfaces as a script throw and this offline wiring
            # as a RuntimeError (check-script-vectors.py's decompress)
            c.ck(label, True if want == "" else str(exc)[:120], True)
    v1 = REF.bech32_encode_long(
        "sp", [1] + REF._convertbits(scan0 + spend0 + b"\x00" * 4, 8, 5, True), "bech32m")
    d1 = call("cwSpDecode", ["mainnet", v1])
    c.ck("a version 1 address with more bytes decodes to its first 66",
         (d1["scan"], d1["spend"], LCS._n(d1["version"])),
         (r0["scan_pub_key"], r0["spend_pub_key"], 1))
    c.refuses("a version 1 address with fewer than 66 bytes",
              lambda: call("cwSpDecode", ["mainnet", REF.bech32_encode_long(
                  "sp", [1] + REF._convertbits(scan0 + spend0[:20], 8, 5, True),
                  "bech32m")]))
    c.refuses("a 1024-character string", lambda: call(
        "cwBech32DecodeLong", ["sp1" + "q" * 1021, 1023]))
    # ---- scalars mod n, in hex ---------------------------------------------
    n_hex = "%064x" % CR._N
    one = "%064x" % 1
    c.ck("n - 1 plus 2 wraps to 1",
         call("cwScalarAdd", ["%064x" % (CR._N - 1), "%064x" % 2]), one)
    c.ck("1 plus 1", call("cwScalarAdd", [one, one]), "%064x" % 2)
    c.ck("negating 1 gives n - 1", call("cwScalarNegate", [one]), "%064x" % (CR._N - 1))
    c.ck("negating 0 stays 0", call("cwScalarNegate", ["0" * 64]), "0" * 64)
    for i in range(4):
        a = CR.sha256(b"scalar a %d" % i)
        b = CR.sha256(b"scalar b %d" % i)
        c.ck("a random add matches the oracle (%d)" % i,
             call("cwScalarAdd", [a.hex(), b.hex()]), REF.scalar_add(a, b).hex())
        c.ck("a random negation matches the oracle (%d)" % i,
             call("cwScalarNegate", [a.hex()]), REF.scalar_negate(a).hex())
        c.ck("a value plus its negation is 0 (%d)" % i,
             call("cwScalarAdd", [a.hex(), REF.scalar_negate(a).hex()]), "0" * 64)
    c.refuses("a scalar at n is refused", lambda: call("cwScalarAdd", [n_hex, one]))
    c.refuses("a 31-byte scalar is refused", lambda: call("cwScalarNegate", ["11" * 31]))
    for kind, pub, want in (("p2tr", "", True), ("p2wpkh", "", True),
                            ("p2sh-p2wpkh", "", True), ("p2pkh", "02" + "11" * 32, True),
                            ("p2pkh", "04" + "11" * 64, False), ("p2wsh", "", False),
                            ("nulldata:4", "", False)):
        c.ck("eligibility: %s%s" % (kind, " (uncompressed)" if pub.startswith("04") else ""),
             call("cwSpEligible", [kind, pub]), want)
    # ---- the published sending vectors, stage by stage ---------------------
    decoded = {}
    for vec in v0:
        name = vec["comment"]
        given, expected = vec["given"], vec["expected"]
        pubs, inputs, outpoints = [], [], []
        for vin in given["vin"]:
            pk = REF.sp_input_pubkey(vin)
            outpoints.append({"txid": vin["txid"], "vout": vin["vout"]})
            if pk is None:
                continue
            pubs.append(pk.hex())
            inputs.append({"seckey": vin["private_key"],
                           "xonly": REF._spk_kind(bytes.fromhex(vin["prevout"])) == "p2tr"})
        c.ck("%s: the inputs that take part are the BIP's" % name,
             pubs, expected["input_pub_keys"])
        recipients = []
        for r in given["recipients"]:
            if r["address"] not in decoded:
                d = call("cwSpDecode", ["mainnet", r["address"]])
                decoded[r["address"]] = d
                c.ck("%s: the address decodes to its published keys" % name,
                     (d["scan"], d["spend"]), (r["scan_pub_key"], r["spend_pub_key"]))
            d = decoded[r["address"]]
            recipients += [{"scan": d["scan"], "spend": d["spend"]}] * int(r.get("count", 1))
        if not inputs:
            c.refuses("%s: no eligible inputs is a refusal" % name,
                      lambda: call("cwSpInputSum", [lst(inputs)]))
            c.ck("%s: and the BIP expects no outputs" % name, expected["outputs"], [[]])
            continue
        if "input_private_key_sum" not in expected:
            c.refuses("%s: a zero key sum is a refusal" % name,
                      lambda: call("cwSpInputSum", [lst(inputs)]))
            c.ck("%s: and the BIP expects no outputs" % name, expected["outputs"], [[]])
            continue
        a = call("cwSpInputSum", [lst(inputs)])
        c.ck("%s: the input key sum" % name, a, expected["input_private_key_sum"])
        a_py = bytes.fromhex(expected["input_private_key_sum"])
        pub = CR.pubkey(a_py).hex()
        ih = call("cwSpInputHash", [lst(outpoints), pub])
        c.ck("%s: the input hash over the smallest outpoint" % name, ih,
             REF.sp_input_hash([(o["txid"], o["vout"]) for o in outpoints], CR.pubkey(a_py)).hex())
        if expected["shared_secrets"][0]:
            c.ck("%s: the shared secret" % name,
                 call("cwSpSharedSecret", [a, ih, recipients[0]["scan"]]),
                 expected["shared_secrets"][0])
        if expected["outputs"] == [[]]:
            c.refuses("%s: refused" % name,
                      lambda: call("cwSpOutputs", [a, ih, lst(recipients)]))
            continue
        outs = unlst(call("cwSpOutputs", [a, ih, lst(recipients)]))
        hit = any(sorted(outs) == sorted(alt) for alt in expected["outputs"])
        c.ck("%s: %d output(s), one of the BIP's accepted sets" % (name, len(outs)),
             True if hit else (outs, expected["outputs"][0]), True)
        c.ck("%s: the oracle agrees" % name,
             sorted(o.hex() for o in REF.sp_outputs(
                 a_py, bytes.fromhex(ih),
                 [(bytes.fromhex(r["scan"]), bytes.fromhex(r["spend"])) for r in recipients])),
             sorted(outs))
    # the one-call form the wallet uses, on the first vector
    given = v0[0]["given"]
    whole = unlst(call("cwSpSend", [
        lst([{"seckey": vin["private_key"], "xonly": False} for vin in given["vin"]]),
        lst([{"txid": vin["txid"], "vout": vin["vout"]} for vin in given["vin"]]),
        lst([{"scan": r0["scan_pub_key"], "spend": r0["spend_pub_key"]}])]))
    c.ck("cwSpSend does the whole derivation in one call", whole, v0[0]["expected"]["outputs"][0])
    c.ck("and the output script is a taproot output",
         call("cwScriptKind", [call("cwScriptP2tr", [whole[0]])]), "p2tr")


def check_runes(c, ip):
    """The runestone reader against the reference's own test cases (ord's
    crates/ordinals/src/{rune,runestone}.rs, 2026-09-04): names, spacers,
    amounts, LEB128 at the 128-bit edge, the tag table, delta-encoded
    edicts, and every cenotaph rule the specification lists."""
    call = ip.call
    c.note("\nRunes, read only")
    M = REF.RUNE_U128_MAX
    for n, want in ((0, "A"), (25, "Z"), (26, "AA"), (27, "AB"), (51, "AZ"),
                    (52, "BA"), (M - 2, "BCGDENLQRQWDSLRUGSNLBTMFIJAT"),
                    (M, "BCGDENLQRQWDSLRUGSNLBTMFIJAV")):
        c.ck("rune %s is %s" % (str(n)[:12], want), call("cwRuneName", [str(n)]), want)
    c.refuses("a rune past 2^128 - 1", lambda: call("cwRuneName", [str(M + 1)]))
    for bits, want in ((1, "A.AAA"), (3, "A.A.AA"), (2, "AA.AA"), (7, "A.A.A.A"), (8, "AAAA")):
        c.ck("spacers %d on AAAA" % bits, call("cwRuneSpaced", ["AAAA", str(bits)]), want)
    for div, want in ((0, "1234"), (1, "123.4"), (2, "12.34"), (3, "1.234"), (5, "0.01234")):
        c.ck("1234 at divisibility %d" % div, call("cwRuneAmountText", ["1234", div]), want)
    c.ck("a whole amount drops its zero fraction", call("cwRuneAmountText", ["1000", 3]), "1")
    c.ck("and a fraction drops its trailing zeros", call("cwRuneAmountText", ["1500", 3]), "1.5")
    # decimal strings
    c.ck("decimal multiply-add", call("cwDecMulAdd", ["99999999999999999999", 128, 127]),
         str(99999999999999999999 * 128 + 127))
    d = call("cwDecDivMod", [str(M), 26])
    c.ck("decimal divmod", (d["q"], LCS._n(d["r"])), (str(M // 26), M % 26))
    c.ck("decimal add", call("cwDecAdd", [str(M), "1"]), str(M + 1))
    c.ck("decimal subtract one", call("cwDecSub1", ["1000000000000000000000"]),
         "999999999999999999999")
    c.ck("decimal compare", [LCS._n(call("cwDecCompare", [a, b]))
                              for a, b in (("9", "10"), ("10", "9"), ("0010", "10"))], [-1, 1, 0])
    # LEB128
    for n in (0, 1, 127, 128, 300, 2 ** 64, M):
        enc = REF.leb128_encode(n).hex()
        c.ck("LEB128 encodes %s" % str(n)[:12], call("cwLeb128Encode", [str(n)]), enc)
        d = call("cwLeb128Decode", [enc, 1])
        c.ck("and decodes back", (d["value"], d["flaw"]), (str(n), ""))
    c.ck("2^128 - 1 is 19 bytes", len(REF.leb128_encode(M)), 19)
    c.ck("a truncated varint is flagged", call("cwLeb128Decode", ["80", 1])["flaw"], "truncated")
    c.ck("a 20-byte varint is overlong", call("cwLeb128Decode", ["80" * 19 + "01", 1])["flaw"],
         "overlong")
    c.ck("2^128 is an overflow",
         call("cwLeb128Decode", [REF.leb128_encode(M + 1).hex(), 1])["flaw"], "overflow")
    # the tag table, on the reference's all-tags etching
    T = REF.RUNE_TAGS
    ints = [T["flags"], 0b111, T["rune"], 4, T["divisibility"], 1, T["spacers"], 5,
            T["symbol"], ord("a"), T["offsetend"], 2, T["amount"], 3, T["premine"], 8,
            T["cap"], 9, T["pointer"], 0, T["mint"], 1, T["mint"], 1, T["body"], 1, 1, 2, 0]
    spk = REF.runestone_script(ints).hex()
    r = call("cwRunestoneDecode", [spk, 2])
    o = REF.runestone_decode(bytes.fromhex(spk), 2)
    e = r["etching"]
    c.true("an etching with every tag is a runestone", r["runestone"])
    c.ck("and not a cenotaph", r["cenotaph"] is True or r["cenotaph"] == "true", False)
    c.ck("its rune", (e["rune"], e["name"]), ("4", "E"))
    c.ck("divisibility, spacers, symbol", [LCS._n(e[k]) for k in ("divisibility", "spacers", "symbol")],
         [1, 5, ord("a")])
    c.ck("premine and turbo", (e["premine"], e["turbo"] is True or e["turbo"] == "true"), ("8", True))
    c.ck("terms", [e["terms"][k] for k in ("amount", "cap", "offsetend", "heightstart")],
         ["3", "9", "2", ""])
    c.ck("mint and pointer", (r["mint"], LCS._n(r["pointer"])), ("1:1", 0))
    ed = unlst(r["edicts"])
    c.ck("one edict", [(x["block"], x["tx"], x["amount"], LCS._n(x["output"])) for x in ed],
         [("1", "1", "2", 0)])
    c.ck("the oracle reads the same", [(x["block"], x["tx"], x["amount"], x["output"])
                                       for x in o["edicts"]], [("1", "1", "2", 0)])
    # delta-encoded edicts, the specification's worked example
    ints = [T["body"], 10, 5, 5, 1, 0, 0, 10, 3, 0, 2, 1, 8, 40, 1, 25, 4]
    r = call("cwRunestoneDecode", [REF.runestone_script(ints).hex(), 9])
    got = [(x["block"], x["tx"], x["amount"], LCS._n(x["output"])) for x in unlst(r["edicts"])]
    c.ck("delta-encoded edicts decode to the specification's table", got,
         [("10", "5", "5", 1), ("10", "5", "10", 3), ("10", "7", "1", 8), ("50", "1", "25", 4)])
    c.ck("and no etching, mint or pointer", (r["etching"], r["mint"], r["pointer"]), ("", "", ""))
    # the reference's multiple-edicts case
    r = call("cwRunestoneDecode", [REF.runestone_script([T["body"], 1, 1, 2, 0, 0, 3, 5, 0]).hex(), 1])
    c.ck("two edicts, the second by tx delta",
         [(x["block"], x["tx"], x["amount"]) for x in unlst(r["edicts"])],
         [("1", "1", "2"), ("1", "4", "5")])
    # min and max runes are not cenotaphs
    for n in (0, M):
        r = call("cwRunestoneDecode", [REF.runestone_script([T["flags"], 1, T["rune"], n]).hex(), 1])
        c.ck("rune %s etches cleanly" % str(n)[:8],
             (r["etching"]["name"], r["cenotaph"] is True or r["cenotaph"] == "true"),
             (REF.rune_name(n), False))
    # an empty runestone, and a payload split across pushes
    r = call("cwRunestoneDecode", ["6a5d", 1])
    c.ck("an empty runestone is one, with nothing in it",
         (r["runestone"] is True or r["runestone"] == "true", unlst(r["edicts"]), r["etching"]),
         (True, [], ""))
    payload = b"".join(REF.leb128_encode(i) for i in [T["flags"], 1, T["rune"], 26])
    r = call("cwRunestoneDecode", [REF.runestone_script(None, [payload[:1], payload[1:]]).hex(), 1])
    c.ck("pushes are concatenated into one payload", r["etching"]["name"], "AA")
    # odd tags are ignored, even ones are not
    r = call("cwRunestoneDecode", [REF.runestone_script([T["nop"], 100, 129, 5, T["flags"], 1]).hex(), 1])
    c.ck("unrecognized odd tags are ignored", r["cenotaph"] is True or r["cenotaph"] == "true", False)
    r = call("cwRunestoneDecode", [REF.runestone_script([T["divisibility"], 1, T["divisibility"], 2,
                                                          T["flags"], 1]).hex(), 1])
    c.ck("a duplicate odd tag keeps its first value", LCS._n(r["etching"]["divisibility"]), 1)
    # the cenotaph rules, each by name
    for label, spk, want in (
            ("an unrecognized even tag", REF.runestone_script([T["cenotaph"], 0]), "unrecognized even tag"),
            ("an unrecognized flag", REF.runestone_script([T["flags"], 1 << 127 | 1]), "unrecognized flag"),
            ("a tag with no value", REF.runestone_script([T["flags"]]), "truncated field"),
            ("trailing integers after the edicts", REF.runestone_script([T["body"], 1, 1, 2, 0, 5]),
             "trailing integers"),
            ("an edict output past the outputs", REF.runestone_script([T["body"], 1, 1, 2, 3]), "edict output"),
            ("a rune id with block zero and nonzero tx", REF.runestone_script([T["body"], 0, 1, 2, 0]),
             "edict rune id"),
            ("an overflowing edict id", REF.runestone_script([T["body"], M, 1, 2, 0, 1, 1, 1, 0]),
             "edict rune id"),
            ("a pointer past the outputs", REF.runestone_script([T["pointer"], 2]), "pointer"),
            ("a mint id with block zero", REF.runestone_script([T["mint"], 0, T["mint"], 1]), "mint rune id"),
            ("a truncated varint", b"\x6a\x5d" + REF.push(b"\x80"), "varint"),
            ("a non-push opcode after the magic", b"\x6a\x5d\x51", "opcode"),
            ("an etching field without the flag", REF.runestone_script([T["rune"], 4]),
             "unrecognized even tag"),
            ("a terms field without the flag", REF.runestone_script([T["flags"], 1, T["cap"], 4]),
             "unrecognized even tag")):
        r = call("cwRunestoneDecode", [spk.hex(), 2])
        c.ck("%s is a cenotaph" % label,
             (r["cenotaph"] is True or r["cenotaph"] == "true", unlst(r["flaws"])[:1]), (True, [want]))
        c.ck("and the oracle agrees", REF.runestone_decode(spk, 2)["flaws"][:1], [want])
    r = call("cwRunestoneDecode", [REF.runestone_script([T["flags"], 1, T["divisibility"], 39,
                                                          T["symbol"], 0x110000, T["spacers"], 1 << 27]).hex(), 1])
    c.ck("out-of-range divisibility, symbol and spacers are ignored, not cenotaphs",
         (r["cenotaph"] is True or r["cenotaph"] == "true",
          r["etching"]["divisibility"], r["etching"]["symbol"], r["etching"]["spacers"]),
         (False, "", "", ""))
    c.ck("an ordinary OP_RETURN is not a runestone",
         call("cwRunestoneDecode", [REF.spk_op_return(b"hi").hex(), 1])["runestone"] in (True, "true"),
         False)
    c.ck("an edict naming the output count means all outputs",
         call("cwRunestoneDecode", [REF.runestone_script([T["body"], 1, 1, 2, 2]).hex(), 2])["cenotaph"]
         in (True, "true"), False)


def check_tapscript(c, ip):
    """One-leaf tapscript for inscriptions (2026-09-04): the leaf hash with a
    real compact size, the ord envelope, the commit (tweak, control block,
    script), the script-path sighash against the oracle, and a reveal whose
    witness the wallet's own inscription reader parses back."""
    call = ip.call
    c.note("\nTapscript, one leaf: inscriptions by commit and reveal")
    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    node = CR.bip32_path(master_py, "m/86'/0'/0'/0/0")
    xonly = node["pubkey"][1:]
    c.ck("a short leaf hashes as coinxt's own leaf hash",
         call("cwTapLeafHash", ["51"]), CR.tap_leaf_hash(0xC0, b"\x51").hex())
    long_script = b"\x51" * 600
    c.ck("a 600-byte leaf hashes with a three-byte compact size",
         call("cwTapLeafHash", [long_script.hex()]), REF.tap_leaf_hash_long(long_script).hex())
    body = b"Hello, ordinals"
    env = call("cwInscriptionScript", [xonly.hex(), "text/plain;charset=utf-8", body.hex()])
    c.ck("the envelope is ord's", env, REF.inscription_script(xonly, "text/plain;charset=utf-8", body).hex())
    big = bytes(range(256)) * 5
    env_big = call("cwInscriptionScript", [xonly.hex(), "application/octet-stream", big.hex()])
    c.ck("a 1280-byte body goes in three pushes of at most 520",
         env_big, REF.inscription_script(xonly, "application/octet-stream", big).hex())
    items = call("cwScriptItems", [env_big]).split("\n")
    c.ck("and the script reader sees those pushes",
         [(len(x) - 5) // 2 for x in items if x.startswith("push ") and len(x) > 200], [520, 520, 240])
    c.refuses("an empty body is refused", lambda: call("cwInscriptionScript", [xonly.hex(), "text/plain", ""]))
    c.refuses("a missing content type is refused", lambda: call("cwInscriptionScript", [xonly.hex(), "", "00"]))
    commit = call("cwTapCommit", [xonly.hex(), env])
    o = REF.tap_commit(xonly, bytes.fromhex(env))
    c.ck("the commit's leaf hash", commit["leafhash"], o["leafhash"].hex())
    c.ck("its output key and parity", (commit["outputkey"], LCS._n(commit["parity"])),
         (o["outputkey"].hex(), o["parity"]))
    c.ck("its scriptPubKey", commit["script"], o["script"].hex())
    c.ck("its control block: version|parity then the internal key, no path",
         commit["controlblock"], o["controlblock"].hex())
    c.ck("the commit address is a taproot address",
         call("cwAddressKind", ["mainnet", call("cwAddressForScript", ["mainnet", commit["script"]])]), "p2tr")
    # a reveal: one input through the leaf, one output
    txid = "ab" * 32
    ins = lst([call("cwTxInput", [txid, 0, 0xFFFFFFFD])])
    out_spk = REF.spk_p2tr(CR.taproot_tweak_pubkey(CR.bip32_path(master_py, "m/86'/0'/0'/0/1")["pubkey"][1:], None)[0]).hex()
    outs = lst([call("cwTxOutput", [9000, out_spk])])
    digest = call("cwTapscriptSighash", [2, ins, outs, 1, 0, lst([commit["script"]]), lst([10000]), commit["leafhash"]])
    # the script counts inputs from 1, the oracle from 0
    want = REF.tapscript_sighash(2, [(txid, 0, 0xFFFFFFFD)], [(9000, bytes.fromhex(out_spk))], 0, 0,
                                 [o["script"]], [10000], o["leafhash"])
    c.ck("the script-path sighash matches the oracle", digest, want.hex())
    sig = call("cwSignTapscript", [node["seckey"].hex(), digest, env, commit["controlblock"]])
    wit = unlst(sig["witness"])
    c.ck("the witness is signature, script, control block",
         wit, [x.hex() for x in REF.sign_tapscript(node["seckey"], want, bytes.fromhex(env), o["controlblock"])])
    c.true("and the signature verifies against the leaf's key",
           CR.schnorr_verify(xonly, want, bytes.fromhex(wit[0])))
    c.ck("the reveal input's vsize", LCS._n(call("cwTapscriptInputVsize", [env])),
         REF.tapscript_input_vsize(bytes.fromhex(env)))
    raw = call("cwTxSerialize", [2, ins, outs, 0, lst([""]), lst([sig["witness"]])])
    dec = REF.tx_decode(bytes.fromhex(raw))
    c.ck("the serialized reveal decodes with that witness", dec["vin"][0].get("witness", dec["vin"][0].get("txinwitness")),
         wit)
    est = 11 + REF.tapscript_input_vsize(bytes.fromhex(env)) + 43
    c.ck("and its vsize is what the estimate said, within a byte",
         True if abs(int(dec["vsize"]) - est) <= 1 else (dec["vsize"], est), True)
    # ---- a timelock leaf under an unspendable key (2026-09-04) ----------
    for n, want in ((0, "00"), (1, "51"), (16, "60"), (17, "0111"), (127, "017f"),
                    (128, "028000"), (255, "02ff00"), (256, "020001"), (900000, "03a0bb0d"),
                    (499999999, "04ff64cd1d")):
        c.ck("script number %d" % n, call("cwScriptNum", [n]), want)
        c.ck("and the oracle's", REF.script_num(n).hex(), want)
    c.refuses("a negative script number", lambda: call("cwScriptNum", [-1]))
    lock = call("cwTimelockScript", [900000, xonly.hex()])
    c.ck("the timelock leaf: <height> CLTV DROP <key> CHECKSIG",
         lock, REF.timelock_script(900000, xonly).hex())
    c.ck("which the script reader decodes as those five items",
         call("cwScriptItems", [lock]).split("\n")[:5],
         ["push a0bb0d", "op 177", "op 117", "push " + xonly.hex(), "op 172"])
    c.refuses("a height of zero", lambda: call("cwTimelockScript", [0, xonly.hex()]))
    c.refuses("a height in the timestamp range", lambda: call("cwTimelockScript", [500000000, xonly.hex()]))
    nums = call("cwTapCommit", [REF.SP_NUMS_H.hex(), lock])
    o_nums = REF.tap_commit(REF.SP_NUMS_H, bytes.fromhex(lock))
    c.ck("under the NUMS point the commit is the oracle's",
         (nums["outputkey"], nums["controlblock"]), (o_nums["outputkey"].hex(), o_nums["controlblock"].hex()))
    c.ck("and its control block carries the NUMS point, not a wallet key",
         nums["controlblock"][2:], REF.SP_NUMS_H.hex())
    # the spend: a locktime at the height, signed by the leaf's key through the leaf
    ins_l = lst([call("cwTxInput", [txid, 1, 0xFFFFFFFD])])
    dig_l = call("cwTapscriptSighash", [2, ins_l, outs, 1, 900000, lst([nums["script"]]), lst([10000]), nums["leafhash"]])
    c.ck("the script-path sighash with the locktime set matches the oracle", dig_l,
         REF.tapscript_sighash(2, [(txid, 1, 0xFFFFFFFD)], [(9000, bytes.fromhex(out_spk))], 0, 900000,
                               [o_nums["script"]], [10000], o_nums["leafhash"]).hex())
    c.ck("and a different locktime is a different digest",
         call("cwTapscriptSighash", [2, ins_l, outs, 1, 899999, lst([nums["script"]]), lst([10000]), nums["leafhash"]]) == dig_l,
         False)
    sig_l = call("cwSignTapscript", [node["seckey"].hex(), dig_l, lock, nums["controlblock"]])
    c.true("the leaf's key signs it",
           CR.schnorr_verify(xonly, bytes.fromhex(dig_l), bytes.fromhex(unlst(sig_l["witness"])[0])))


BOLT11_VECTORS = os.path.join(MEMBER, "tests", "bolt11-vectors.json")


def check_bolt11(c, ip):
    """BOLT11 invoices against the specification's own examples
    (tests/bolt11-vectors.json): every field of every valid example, the
    recovered payee, and each invalid example refused for its stated
    reason. Read only; the wallet cannot pay one."""
    import json as _json
    call = ip.call
    c.note("\nBOLT11 Lightning invoices, decoded")
    v = _json.load(open(BOLT11_VECTORS, encoding="utf-8"))
    for amt, want in (("", ""), ("2500u", "250000000"), ("20m", "2000000000"), ("25m", "2500000000"),
                      ("10m", "1000000000"), ("9678785340p", "967878534"), ("1", "100000000000"),
                      ("2500n", "250000")):
        c.ck("amount %r is %s msat" % (amt, want or "any"), call("cwBolt11AmountMsat", [amt]), want)
    for amt in ("2500x", "2500000001p", "0500u", "abc", "m"):
        c.refuses("amount %r is refused" % amt, lambda a=amt: call("cwBolt11AmountMsat", [a]))
    c.ck("a Unix time renders as a UTC date", call("cwUnixDate", [1496314658]), "2017-06-01 10:57 UTC")
    c.ck("and the epoch does", call("cwUnixDate", [0]), "1970-01-01 00:00 UTC")
    c.ck("a leap day does", call("cwUnixDate", [951782400]), "2000-02-29 00:00 UTC")
    for vec in v["valid"]:
        title, want = vec["title"][:52], vec["expected"]
        got = call("cwBolt11Decode", [vec["invoice"]])
        c.ck("%s: network and amount" % title, (got["network"], got["amountmsat"]),
             (want["network"], "" if want["amount_msat"] is None else str(want["amount_msat"])))
        c.ck("%s: timestamp" % title, LCS._n(got["timestamp"]), want["timestamp"])
        c.ck("%s: payment hash and secret" % title, (got["paymenthash"], got["secret"]),
             (want["payment_hash"], want["secret"]))
        if "description" in want:
            c.ck("%s: description" % title, str(LCS._disp(got["description"])), want["description"])
        if "description_hash" in want:
            c.ck("%s: description hash" % title, got["descriptionhash"], want["description_hash"])
        c.ck("%s: expiry and final cltv" % title, (LCS._n(got["expiry"]), LCS._n(got["cltv"])),
             (want["expiry"], want["cltv"]))
        c.ck("%s: fallback address" % title, got["fallback"], want.get("fallback", ""))
        c.ck("%s: features" % title, [LCS._n(b) for b in unlst(got["features"])], want["features"])
        c.ck("%s: metadata" % title, got["metadata"], want.get("metadata", ""))
        routes = [[(h["pubkey"], h["channel"], LCS._n(h["feebase"]), LCS._n(h["feeppm"]), LCS._n(h["cltvdelta"]))
                   for h in unlst(r)] for r in unlst(got["routes"])]
        c.ck("%s: route hints" % title, routes,
             [[(h["pubkey"], h["channel"], h["fee_base_msat"], h["fee_ppm"], h["cltv_delta"]) for h in r]
              for r in want["routes"]])
        c.ck("%s: the payee recovered from the signature" % title, got["payee"], want["payee"])
        c.ck("%s: the oracle agrees" % title, REF.bolt11_decode(vec["invoice"])["payee"], want["payee"])
    for vec in v["invalid"]:
        title = vec["title"][:52]
        try:
            call("cwBolt11Decode", [vec["invoice"]])
            c.ck("%s: refused" % title, "accepted", "refused")
        except LCS.Thrown as exc:
            c.ck("%s: refused, naming the reason" % title,
                 True if vec["reason"] in str(exc.msg) else str(exc.msg)[:120], True)
        try:
            REF.bolt11_decode(vec["invoice"])
            c.ck("%s: the oracle refuses too" % title, "accepted", "refused")
        except ValueError:
            c.ck("%s: the oracle refuses too" % title, True, True)
    c.true("an invoice is recognised by shape", call("cwBolt11IsInvoice", [v["valid"][0]["invoice"]]))
    c.ck("an address is not", call("cwBolt11IsInvoice", ["bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l"]), False)


def check_json_and_qr(c, ip):
    call = ip.call
    c.note("\nJSON and QR")
    for text in JSON_SAMPLES:
        import json as _json
        want = _json.loads(text)
        node = call("cwJsonParse", [text])
        kind = {dict: "object", list: "array", str: "string", bool: "boolean",
                type(None): "null"}.get(type(want), "number")
        c.ck("%s parses as %s" % (text[:28], kind), call("cwJsonType", [node]), kind)
        if isinstance(want, (dict, list)):
            c.ck("%s counts %d" % (text[:28], len(want)),
                 call("cwJsonCount", [node]), len(want))
    node = call("cwJsonParse", [JSON_SAMPLES[0]])
    c.ck("a nested object path", call("cwJsonGet", [node, "chain_stats/funded_txo_sum"]),
         "123456")
    c.ck("a missing path answers empty", call("cwJsonGet", [node, "chain_stats/nope"]), "")
    c.ck("and reports itself as missing",
         call("cwJsonType", [call("cwJsonPath", [node, "nope/deeper"])]), "missing")
    node = call("cwJsonParse", [JSON_SAMPLES[1]])
    c.ck("an array element by 1-based index", call("cwJsonGet", [node, "1/txid"]), "aa")
    c.ck("a nested boolean", call("cwJsonGet", [node, "1/status/confirmed"]), "true")
    c.ck("the second element's value", call("cwJsonGet", [node, "2/value"]), "250")
    esc = call("cwJsonParse", ['{"d":"line\\nbreak \\"q\\" \\\\ back"}'])
    c.ck("escapes decode", call("cwJsonGet", [esc, "d"]), 'line\nbreak "q" \\ back')
    c.ck("a string escapes back out", call("cwJsonString2", ['a"b\\c\nd']),
         '"a\\"b\\\\c\\nd"')
    for bad in ('{"a":}', '[1,2', '{"a" 1}', '{,}', 'tru', '{"a":1}x'):
        c.refuses("%r is refused as JSON" % bad, lambda b=bad: call("cwJsonParse", [b]))

    # VERSIONS 1, 3, 7 AND 8 ARE ALL BUILT, and the last two are the point.
    # A symbol below version 7 carries no version-information block at all, so
    # kCwQrVersionGen and the whole cwQrVersionBits/cwQrPlaceVersion path were
    # excused as "checked by the version-7-and-up QR vectors" when the gate
    # built nothing above version 3. Version 8 additionally has a second
    # codeword group, which is the only thing that exercises the interleave's
    # short-block half. A BIP-21 URI carrying an address, an amount and a
    # message is the realistic payload at that size, which is what the wallet
    # actually puts in a QR.
    big = REF.uri_build(ADDRESSES["mainnet"][2], 123456, "Invoice 41",
                        "thank you for the coffee and the conversation")
    samples = ("a", "HELLO WORLD", ADDRESSES["mainnet"][2], big)
    seen = set()
    for text in samples:
        version = REF.qr_version_for(len(text))
        seen.add(version)
        got = unlst(call("cwQrMatrix", [text]))
        want = ["".join(str(x) for x in row) for row in REF.qr_matrix(text)]
        c.ck("the QR matrix for %r (version %d)"
             % (text[:20], version), got, want)
    # ASSERTED AS PROPERTIES, not as version numbers. What has to be reached
    # is the version-information block (any version >= 7) and a symbol with a
    # SECOND codeword group, and one large payload happens to give both - so
    # the check asks the capacity table which versions those are rather than
    # naming two that were true the day this was written.
    c.ck("the QR vectors reach the version-information block and a second "
         "codeword group (versions %s)" % ",".join(str(v) for v in sorted(seen)),
         (any(v >= 7 for v in seen), any(REF.QR_M[v][4] > 0 for v in seen)),
         (True, True))
    c.ck("a QR version is chosen by capacity", call("cwQrVersionFor", [412]), 15)
    c.refuses("a payload too big for version 15 is refused",
              lambda: call("cwQrVersionFor", [413]))
    # cwQrText is its OWN handler doing its own substitution, so it is
    # compared to the oracle's anchored rendering rather than line-counted.
    c.ck("the text rendering", call("cwQrText", ["a", "#", "."]),
         REF.qr_text("a", None, "#", "."))
    c.ck("with non-default on/off characters",
         call("cwQrText", ["a", "X", " "]), REF.qr_text("a", None, "X", " "))
    c.ck("the text rendering has one line per row",
         len(call("cwQrText", ["a", "#", "."]).split("\n")), 21)
    bmp = to_bytes(call("cwQrBmp", ["a", 4, 4]))
    c.ck("the BMP magic", bmp[:2], b"BM")
    c.ck("the BMP declares its own length",
         int.from_bytes(bmp[2:6], "little"), len(bmp))
    width = int.from_bytes(bmp[18:22], "little")
    c.ck("the BMP is square and quiet-zoned", width, (21 + 8) * 4)
    row_bytes = width * 3
    pad = (4 - row_bytes % 4) % 4
    c.ck("its rows are padded to a four-byte boundary",
         54 + (row_bytes + pad) * width, len(bmp))
    rows = unlst(call("cwQrMatrix", ["a"]))
    mismatch = 0
    for r, line in enumerate(rows):
        for col, ch in enumerate(line):
            px = ((4 + col) * 4 + 2) * 3
            py = width - 1 - ((4 + r) * 4 + 2)
            if (bmp[54 + py * (row_bytes + pad) + px] == 0) != (ch == "1"):
                mismatch += 1
    c.ck("every module lands on the right pixel", mismatch, 0)


def check_odds(c, ip):
    call = ip.call
    c.note("\nkeys, mnemonics and labels")
    master_py = CR.bip32_master(CR.bip39_seed(TEST_MNEMONIC, ""))
    node = CR.bip32_path(master_py, "m/44'/0'/0'/0/0")
    wif = CR.wif_encode(node["seckey"], "mainnet", True)
    info = call("cwWifInfo", [wif, "mainnet"])
    c.ck("a compressed WIF's P2PKH address", info["p2pkh"], ADDRESSES["mainnet"][0])
    c.ck("its P2WPKH address", info["p2wpkh"],
         REF.address_for_spk("mainnet", REF.spk_p2wpkh(node["pubkey"])))
    c.ck("no warning for a matching network", info["warning"], "")
    uncompressed = call("cwWifInfo", [CR.wif_encode(node["seckey"], "mainnet", False),
                                      "mainnet"])
    c.ck("an uncompressed key has NO segwit address", uncompressed["p2wpkh"], "")
    cross = call("cwWifInfo", [CR.wif_encode(node["seckey"], "testnet", True),
                               "mainnet"])
    c.true("a cross-network key is flagged", "TESTNET" in cross["warning"])
    c.ck("a 12-word mnemonic is 128 bits",
         call("cwMnemonicStrength", [TEST_MNEMONIC]), 128)
    c.ck("its word count", call("cwMnemonicWordCount", [TEST_MNEMONIC]), 12)
    c.ck("an 11-word phrase has no BIP-39 strength",
         call("cwMnemonicStrength", [" ".join(TEST_MNEMONIC.split()[:11])]), 0)
    c.true("a 1 sat/vB rate is described as risky",
           "minimum relay" in call("cwFeeRateLabel", [1]))
    c.true("a 50 sat/vB rate is described as very high",
           "very high" in call("cwFeeRateLabel", [50]))
    c.true("the version string names the layer",
           call("cwVersion", []).startswith("CoinXT Wallet core"))


# ------------------------------------------------------------------- main
# --------------------------------------------------------- tier 3: case folding
#
# THE ENGINE FOLDS CASE AND THE INTERPRETER DOES NOT, so every check above runs
# under a comparison rule OXT does not use. `the caseSensitive` defaults to
# FALSE, which makes `is` and `offset()` case-INSENSITIVE; tools/lcs-interp.py
# models both case-SENSITIVELY and names the first of those as its one declared
# divergence. That gap is not academic. It hid two real defects in this layer at
# once - a descriptor checksum that came out wrong for every descriptor
# containing a letter, and a multisig account key serialized with the
# single-signature version - and it hid them behind 414 green checks, because
# every one of those checks ran under the wrong rule.
#
# So the whole vector set is RUN TWICE. The second pass folds `is` and
# `offset()` to the engine's default and requires the SAME answers. That turns
# "does this code depend on a comparison rule the engine does not have?" from a
# thing somebody has to remember to look for into a thing the build asks on
# every push. A check that passes sensitively and fails folded is a check whose
# subject reads a case-significant alphabet - Base58, WIF, a descriptor, an
# address - with the wrong tool.
#
# What it does NOT fold: `contains`, `begins with`, `ends with` and `sort`,
# which the engine also folds. Those live inside the interpreter's expression
# parser rather than behind a module-level function, so folding them would mean
# subclassing it here - and this layer uses none of them on case-significant
# data (measured: every use is over hex, a lowercase HRP, or a fixed keyword).
# When one lands on an address or a key, this comment is the reason it needs a
# fourth tier rather than a quiet extension of this one.

def _fold_case():
    """Replace the interpreter's `is` and `offset()` with the ENGINE's default,
    returning what to call to put them back. Both are module-level names looked
    up at call time, which is why this can be done without touching the file."""
    real_eq = LCS._eq
    real_builtin = LCS._builtin_or_handler

    def folded_eq(a, b):
        if real_eq(a, b):
            return True
        if isinstance(a, dict) or isinstance(b, dict):
            return False
        if isinstance(a, bool) or isinstance(b, bool):
            return False
        return str(LCS._disp(a)).lower() == str(LCS._disp(b)).lower()

    def folded_builtin(ip, name, args):
        if name.lower() == "offset":
            hay = str(LCS._disp(args[1])).lower()
            nee = str(LCS._disp(args[0])).lower()
            return hay.find(nee) + 1
        return real_builtin(ip, name, args)

    LCS._eq = folded_eq
    LCS._builtin_or_handler = folded_builtin

    def restore():
        LCS._eq = real_eq
        LCS._builtin_or_handler = real_builtin
    return restore


def check_case_folded(c, ip, run_all):
    """Re-run every vector with the engine's comparison rule. Failures are
    reported against THIS tier, so the message says which rule broke them."""
    inner = Checker(True)
    restore = _fold_case()
    try:
        run_all(inner, ip)
    except Exception as exc:                                    # noqa: BLE001
        restore()
        c.ck("the vector set runs under the engine's case rule", "threw: %s: %s"
             % (type(exc).__name__, exc), "ran")
        return
    finally:
        restore()
    # The failures are folded INTO the reported problem, not printed through
    # note(): the build runs this gate with --check, which is terse, and a
    # tier whose diagnostics are invisible in CI is a tier somebody has to
    # reproduce locally before they can even see what moved.
    detail = ""
    if inner.problems:
        detail = "\n      the vectors that moved:\n      " + \
            "\n      ".join(p.replace("\n", "\n  ") for p in inner.problems[:8])
        if len(inner.problems) > 8:
            detail += "\n      ... and %d more" % (len(inner.problems) - 8)
    c.ck("every vector gives the SAME answer with `is` and `offset()` folded "
         "to the engine's default (%d re-run)%s" % (inner.count, detail),
         "%d differing" % len(inner.problems), "0 differing")


def check_case_folding_fires(c, ip):
    """MUTATION: prove the tier above can still fail. A gate that has gone
    blind reports OK, and an OK that cannot be false is worth nothing - this
    file's own recorded lesson about a constant gate that reported what it had
    parsed as what it had checked."""
    restore = _fold_case()
    try:
        # Core's descriptor alphabet is the sharpest case-significant surface
        # this layer touches, and cwCharIndex is what keeps it right. Under a
        # FOLDED offset() the byte scan is unaffected, so the mutation has to
        # be the other direction: prove that a lookup written with offset()
        # WOULD move, using the alphabet itself rather than a fixture.
        head = str(ip.constants.get("kCwDescInputHead", ""))
        moved = [ch for ch in head
                 if head.lower().find(ch.lower()) != head.find(ch)]
        # The two the finding turned on, named rather than counted: "A" sits
        # at 82 and folds onto "a" at 18; "w" sits at 78 and folds onto "W"
        # at 46. A bare count would pass on an alphabet that had lost them.
        # Compared LIKE FOR LIKE. Written as a bool against a description
        # string this check could not pass for any input, which is the same
        # shape of defect as a gate that reports what it parsed as what it
        # checked - and this one is the gate that proves the tier below it
        # can still fail, so a permanently-red check here is as useless as a
        # permanently-green one. The two characters are NAMED rather than
        # counted: "A" sits at 82 and folds onto "a" at 18, "w" at 78 onto
        # "W" at 46. A bare count passes on an alphabet that lost them.
        c.ck("the folded model moves the characters that matter",
             ("A" in moved, "w" in moved, len(moved)),
             (True, True, 26))
        c.ck("and it actually changes `is` on a case-significant pair",
             LCS._eq("Z", "z"), True)
    finally:
        restore()
    c.ck("and the real model is restored afterwards", LCS._eq("Z", "z"), False)


def main(argv):
    terse = "--check" in argv[1:]
    c = Checker(terse)
    if not os.path.exists(CORE):
        print("check-wallet-vectors: examples/wallet-core.livecodescript is missing")
        return 1
    text = open(CORE, encoding="utf-8").read()
    check_constants(c, text)

    cc = CSV.find_cc()
    if cc is None:
        print("check-wallet-vectors: SKIP the vector run (no C compiler found, so "
              "the cx* handlers the script calls are unavailable). The constants "
              "above still ran.")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            lib_path = os.path.join(tmp, "libcoinxt_wallet.so")
            try:
                CSV.build(cc, lib_path)
            except subprocess.CalledProcessError as exc:
                print("check-wallet-vectors: BUILD FAILED (%s)" % exc)
                return 1
            lib = ctypes.CDLL(lib_path)
            CSV.wire_hashes(lib)
            wire_signing(lib)
            coin = open(COIN, encoding="utf-8").read()
            # the embed strips a provider's leading `script "..."` line, and so
            # does this: the assembled unit must carry exactly one, and here it
            # carries none because nothing is being opened as a stack
            body = "\n".join(ln for ln in text.split("\n")
                             if not ln.startswith('script "'))
            ip = LCS.Interp(coin + "\n" + body)
            c.note("running the shipped wallet-core (%d handlers, %d constants) "
                   "through tools/lcs-interp.py" % (len(ip.handlers), len(ip.constants)))
            def run_all(ck, interp):
                check_vectors(ck, interp)
                check_money(ck, interp)
                check_selection(ck, interp)
                check_signing(ck, interp)
                check_decode(ck, interp)
                check_psbt(ck, interp)
                check_messages(ck, interp)
                check_silent_payments(ck, interp)
                check_runes(ck, interp)
                check_tapscript(ck, interp)
                check_bolt11(ck, interp)
                check_json_and_qr(ck, interp)
                check_odds(ck, interp)
                check_audit_2026_09_01(ck, interp)
                check_script_framing(ck, interp)

            run_all(c, ip)
            c.note("re-running the whole set with `is` and `offset()` folded "
                   "to the engine's default")
            check_case_folding_fires(c, ip)
            check_case_folded(c, ip, run_all)

    if c.problems:
        print("check-wallet-vectors: FAILED")
        for p in c.problems:
            print("  - %s" % p)
        return 1
    # A FLOOR ON THE COUNT. "All the checks passed" and "hardly any checks ran"
    # look identical on the way out, and on a signing surface the second one is
    # indistinguishable from a green build. Raise it when the set grows; it is
    # here to catch collapse, not to track the exact number.
    # THE COMPILER-FREE FLOOR IS THE CONSTANTS TIER'S OWN SIZE. It read 60
    # for a larger tier that has since shrunk, so the no-compiler path could
    # not pass at all: it ran its 35 checks and then reported a collapse that
    # had not happened. A floor that no run can clear is not a floor - and a
    # floor the tier can clear with a third of itself missing is not one
    # either: it stayed at 30 while the tier grew to 58 (2026-09-04), so
    # the 22 checks added that day could all have stopped running under it.
    # Fifty catches that; the full run is over a thousand checks now and
    # 900 catches the loss of any of its blocks.
    floor = 50 if cc is None else 900
    if c.count < floor:
        print("check-wallet-vectors: FAILED - only %d checks ran, expected at least "
              "%d. Something stopped the vector set early." % (c.count, floor))
        return 1
    print("check-wallet-vectors: OK (%d checks against an independent oracle)" % c.count)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
