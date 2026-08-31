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
        "cxecdh": fixed("cnx_ecdh", 2, 32, "cxEcdh"),
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
    order = ["mainnet", "testnet", "signet", "regtest"]

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

    # THE HONEST SPLIT: everything parsed is either checked above or listed.
    derived = {
        "kCwNetworks", "kCwHrps", "kCwP2pkhVersions", "kCwP2shVersions",
        "kCwWifVersions", "kCwCoinTypes", "kCwScriptTypes", "kCwPurposes",
        "kCwStems", "kCwDescInputHead", "kCwDescCharset", "kCwQrDataCw",
        "kCwQrEccPer", "kCwQrG1Blocks", "kCwQrG1Cw", "kCwQrG2Blocks",
        "kCwQrG2Cw", "kCwQrRemainder", "kCwQrAlign", "kCwSeqRbf",
        "kCwSeqFinal", "kCwSeqNoRbf",
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
    final_meta = {"witness_utxo": (50000, bytes.fromhex(spk)),
                  "bip32": {node["pubkey"]: (bytes.fromhex(fp),
                                             "m/84'/0'/0'/0/0")},
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
    v7 = REF.uri_build(ADDRESSES["mainnet"][2], 123456, "Invoice 41",
                       "thank you for the coffee and the conversation")
    v8 = v7 + " and the second cup as well, which was also good"
    samples = ("a", "HELLO WORLD", ADDRESSES["mainnet"][2], v7, v8)
    seen = set()
    for text in samples:
        version = REF.qr_version_for(len(text))
        seen.add(version)
        got = unlst(call("cwQrMatrix", [text]))
        want = ["".join(str(x) for x in row) for row in REF.qr_matrix(text)]
        c.ck("the QR matrix for %r (version %d)"
             % (text[:20], version), got, want)
    c.ck("the QR vectors reach the version-information block (>= 7) and a "
         "second codeword group (>= 8)",
         (max(seen) >= 8, sorted(seen)), (True, sorted(seen)))
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
                check_json_and_qr(ck, interp)
                check_odds(ck, interp)

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
    # had not happened. A floor that no run can clear is not a floor.
    floor = 30 if cc is None else 400
    if c.count < floor:
        print("check-wallet-vectors: FAILED - only %d checks ran, expected at least "
              "%d. Something stopped the vector set early." % (c.count, floor))
        return 1
    print("check-wallet-vectors: OK (%d checks against an independent oracle)" % c.count)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
