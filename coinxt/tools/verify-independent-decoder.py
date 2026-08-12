#!/usr/bin/env python3
"""verify-independent-decoder.py - the phase-5 acceptance bar that no gate in
this repo can be: a transaction the SHIPPED script layer builds is handed to an
INDEPENDENT, mainstream Bitcoin implementation, which must deserialize it,
evaluate its scripts under consensus rules, and confirm every signature.

WHY THIS IS SEPARATE FROM check-script-vectors.py. That gate proves the script
agrees with tools/coin_reference.py, and the oracle is anchored to the BIP-143
published vector - a strong check, but a closed loop: our encoder, our model,
our vector. "Broadcastable" is a claim about the OUTSIDE world, and the only
honest way to test it is to have code we did not write accept a transaction we
did. python-bitcointx (the maintained fork of python-bitcoinlib, a full Python
consensus-shaped script interpreter) is that code here.

WHY IT IS NOT IN THE CI GATE SET. python-bitcointx and its libsecp256k1 backend
(coincurve) are third-party pip packages the suite does not vendor and CI does
not install, so this cannot run on every push the way the headless vector gate
does. It is an ACCEPTANCE run: executed deliberately, its result recorded in
IMPLEMENTATION-PLAN.md and the api-reference status block, exactly like a
testnet-node acceptance would be. Without the packages it SKIPS loudly (exit 0
by default; --require turns a skip into a failure for a machine that has them).

WHAT MAKES THE TRANSACTION MEANINGFUL. It is FRESH, not the BIP-143 fixture:
different private keys, different amounts, a P2WPKH input, so a bug that only
reproduces the one pinned example cannot pass. The bytes under test are the
SCRIPT's: the sighash, DER, varint, witness and transaction serialization all
come out of src/coinxt.livecodescript driven through tools/lcs-interp.py; the
oracle supplies only the RFC 6979 (r, s) the app's cxSign would (the script
does not sign), and python-bitcointx supplies the independent verdict.

    python3 tools/verify-independent-decoder.py            # detail
    python3 tools/verify-independent-decoder.py --require   # skip -> failure

Install the verifier (a venv keeps it out of the repo tooling's site-packages):
    python3 -m venv /tmp/btcvenv
    /tmp/btcvenv/bin/pip install python-bitcointx coincurve
    /tmp/btcvenv/bin/python tools/verify-independent-decoder.py
"""

import glob
import hashlib
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(ROOT, "src", "coinxt.livecodescript")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CSV = _load("check_script_vectors",
            os.path.join(HERE, "check-script-vectors.py"))
# Share the SAME module instances check-script-vectors loaded, so the hashes
# CSV.wire_hashes() registers land in the very LCS.HASHES dict the Interp
# reads. Loading our own second copy would give the interpreter an empty hash
# table and every cxSha256 call would fail as "unknown function".
REF = CSV.REF
LCS = CSV.LCS


def import_bitcointx():
    """python-bitcointx needs a libsecp256k1; this environment ships none, but
    coincurve bundles one that exports the full secp256k1_* surface. Point
    bitcointx at it BEFORE any other bitcointx submodule is imported (the fork
    resolves the library once, at first use). Returns the module, or None."""
    try:
        import bitcointx
    except ImportError:
        return None
    try:
        cands = []
        for base in sys.path:
            cands += glob.glob(os.path.join(
                base, "coincurve", "_libsecp256k1*.so"))
            cands += glob.glob(os.path.join(
                base, "coincurve", "*libsecp256k1*"))
        if cands:
            bitcointx.set_custom_secp256k1_path(cands[0])
        # force resolution now so a bad backend fails here, not mid-verify
        from bitcointx.core.key import CPubKey  # noqa: F401
        return bitcointx
    except Exception as exc:  # pragma: no cover - environment-specific
        print("verify-independent-decoder: bitcointx present but its "
              "libsecp256k1 backend would not load: %s" % exc)
        return None


def build_shim():
    """Compile the coinxt shim and wire its hashes into the interpreter, the
    same way the headless vector gate does, so the script's sighash path runs
    over the real double-SHA256. Returns the built Interp, or None if no C
    compiler is available."""
    cc = CSV.find_cc() if hasattr(CSV, "find_cc") else None
    if cc is None:
        # CSV names the finder differently across versions; fall back to a probe
        for cand in ("cc", "gcc", "clang"):
            try:
                subprocess.run([cand, "--version"], capture_output=True,
                               check=True)
                cc = cand
                break
            except (OSError, subprocess.CalledProcessError):
                continue
    if cc is None:
        return None
    tmp = tempfile.mkdtemp(prefix="coinxt-decoder-")
    lib = os.path.join(tmp, "coinxt.so")
    CSV.build(cc, lib)
    import ctypes
    handle = ctypes.CDLL(lib)
    CSV.wire_hashes(handle)
    ip = LCS.Interp(open(SCRIPT, encoding="utf-8").read())
    return ip


def fresh_scenario():
    """A brand-new single-input native-P2WPKH spend the repo has never pinned.
    Distinct key, amount, prevout and destination from the BIP-143 fixture, so
    reproducing that one example is not enough to pass. Returns everything both
    the script and the independent verifier need."""
    sk = bytes.fromhex(
        "c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00")
    pub = REF.pubkey(sk)                       # 33-byte compressed
    pkh = REF.hash160(pub)                     # the witness program
    spk = b"\x00\x14" + pkh                    # scriptPubKey: OP_0 <20-byte>
    amount = 0x00000002_54_0b_e400 & 0xffffffffff  # ~10.13 BTC, fits u40 clean
    amount = 1_013_000_000                     # 10.13 BTC in satoshi
    ver, lock = 2, 0
    prev_txid = bytes.fromhex(
        "1111111111111111111111111111111111111111111111111111111111111111")
    vout = 3
    seq = 0xfffffffd                            # opt-in RBF, not the fixture's
    op = REF.btc_outpoint(prev_txid, vout)
    # pay 10.12 BTC to another P2WPKH, 0.01 BTC fee
    dest_sk = bytes.fromhex("00" * 31 + "07")
    dest_spk = b"\x00\x14" + REF.hash160(REF.pubkey(dest_sk))
    out = REF.btc_output(1_012_000_000, dest_spk)
    ins, outs = [(op, seq)], [out]
    # BIP-143 P2WPKH scriptCode = the corresponding P2PKH script
    script_code = (b"\x76\xa9\x14" + pkh + b"\x88\xac")
    digest = REF.btc_sighash_segwit(ver, ins, outs, 0, script_code, amount, lock)
    r, s, _ = REF.ecdsa_sign_recoverable(sk, digest)
    return {
        "sk": sk, "pub": pub, "spk": spk, "script_code": script_code,
        "amount": amount, "ver": ver, "lock": lock, "seq": seq,
        "op": op, "out": out, "digest": digest, "rs": (r, s),
    }


class Run:
    def __init__(self):
        self.fail = 0
        self.n = 0

    def ok(self, name, cond, detail=""):
        self.n += 1
        if cond:
            print("  ok   %s" % name)
        else:
            self.fail += 1
            print("  FAIL %s%s" % (name, ("\n       " + detail) if detail else ""))


def main(argv):
    require = "--require" in argv
    btx = import_bitcointx()
    if btx is None:
        msg = ("verify-independent-decoder: SKIP - python-bitcointx / coincurve "
               "not importable.\n  Install into a venv and re-run:\n"
               "    python3 -m venv /tmp/btcvenv\n"
               "    /tmp/btcvenv/bin/pip install python-bitcointx coincurve\n"
               "    /tmp/btcvenv/bin/python tools/verify-independent-decoder.py")
        print(msg)
        return 1 if require else 0

    ip = build_shim()
    if ip is None:
        print("verify-independent-decoder: SKIP - no C compiler to build the "
              "shim the script's sighash path calls.")
        return 1 if require else 0

    from bitcointx.core import CTransaction, x
    from bitcointx.core.script import (
        CScript, SignatureHash, SIGHASH_ALL, SIGVERSION_WITNESS_V0)
    from bitcointx.core.scripteval import (
        VerifyScript, SCRIPT_VERIFY_P2SH, SCRIPT_VERIFY_WITNESS)
    from bitcointx.core.key import CPubKey

    sc = fresh_scenario()
    r, s = sc["rs"]

    run = Run()

    # --- drive the SHIPPED script to produce the transaction ------------------
    def call(fn, *args):
        return ip.call(fn, [CSV.to_str(a) if isinstance(a, (bytes, bytearray))
                            else a for a in args])

    op_hex = sc["op"].hex()
    out_hex = sc["out"].hex()
    sig = REF.der_encode(r, s) + b"\x01"                 # DER + SIGHASH_ALL
    pub_hex = sc["pub"].hex()
    # The script's field arguments cross exactly as the vector gate feeds them:
    # outpoints/outputs/scriptCode as HEX strings, sequences as decimal, the
    # amount as an integer, input index 1-based, sighash type 1 (SIGHASH_ALL).
    sc_hex = sc["script_code"].hex()

    # the segwit sighash, computed BY THE SCRIPT over the real double-SHA256
    script_digest = CSV.to_bytes(call(
        "cxBtcSighashSegwit", sc["ver"], op_hex, str(sc["seq"]), 1,
        sc_hex, sc["amount"], out_hex, sc["lock"], 1))
    run.ok("the script's segwit sighash equals the oracle's",
           script_digest == sc["digest"],
           "script %s\n       oracle %s" % (script_digest.hex(),
                                            sc["digest"].hex()))

    # the witness stack, built BY THE SCRIPT
    wit = CSV.to_bytes(call("cxBtcWitness", sig.hex() + "," + pub_hex))

    # the whole transaction, serialized BY THE SCRIPT (one input: empty
    # scriptSig - the empty list is one empty item - and the witness above)
    tx_hex = CSV.to_bytes(call(
        "cxBtcTxEncode", sc["ver"], op_hex, "", str(sc["seq"]),
        wit.hex(), out_hex, sc["lock"])).hex()

    # the script's own txid (its non-witness serialization, reversed to display
    # order) - a display-order hex string
    script_txid_hex = str(LCS._disp(call(
        "cxBtcTxid", sc["ver"], op_hex, "", str(sc["seq"]), out_hex,
        sc["lock"])))

    # --- INDEPENDENT verdict: python-bitcointx must accept the script's bytes -
    tx = CTransaction.deserialize(x(tx_hex))
    run.ok("python-bitcointx deserializes the script-built tx and it "
           "round-trips byte-exact", tx.serialize().hex() == tx_hex)

    run.ok("its txid agrees with the script's cxBtcTxid",
           tx.GetTxid()[::-1].hex() == script_txid_hex,
           "bitcointx %s\n       script    %s"
           % (tx.GetTxid()[::-1].hex(), script_txid_hex))

    # full consensus-shaped script evaluation of the P2WPKH input
    ok_eval = True
    try:
        VerifyScript(tx.vin[0].scriptSig, CScript(sc["spk"]), tx, 0,
                     flags=(SCRIPT_VERIFY_P2SH, SCRIPT_VERIFY_WITNESS),
                     amount=sc["amount"],
                     witness=tx.wit.vtxinwit[0].scriptWitness)
    except Exception as exc:
        ok_eval = False
        detail = str(exc)
    run.ok("VerifyScript accepts the P2WPKH input under consensus rules "
           "(SCRIPT_VERIFY_WITNESS)", ok_eval,
           "" if ok_eval else detail)

    # the manual sighash + raw-ECDSA path, independently
    stack_sig, stack_pub = tx.wit.vtxinwit[0].scriptWitness.stack
    sighash_btx = SignatureHash(CScript(sc["script_code"]), tx, 0, SIGHASH_ALL,
                                amount=sc["amount"],
                                sigversion=SIGVERSION_WITNESS_V0)
    run.ok("python-bitcointx's independent segwit sighash matches too",
           sighash_btx == sc["digest"])
    run.ok("the witness signature verifies against that sighash (raw ECDSA)",
           CPubKey(stack_pub).verify(sighash_btx, bytes(stack_sig)[:-1]))

    # --- negative controls: the verifier is not vacuous -----------------------
    bad = bytearray(x(tx_hex))
    # find the signature's first DER byte inside the witness and flip it
    sig_marker = sig.hex()
    idx = tx_hex.find(sig_marker)
    assert idx >= 0 and idx % 2 == 0
    flip_at = idx // 2 + 5           # a byte inside the DER body, not the length
    bad[flip_at] ^= 0x01
    bad_ok = True
    try:
        btx_bad = CTransaction.deserialize(bytes(bad))
        VerifyScript(btx_bad.vin[0].scriptSig, CScript(sc["spk"]), btx_bad, 0,
                     flags=(SCRIPT_VERIFY_P2SH, SCRIPT_VERIFY_WITNESS),
                     amount=sc["amount"],
                     witness=btx_bad.wit.vtxinwit[0].scriptWitness)
    except Exception:
        bad_ok = False
    run.ok("a single flipped signature byte is REJECTED (verify is not vacuous)",
           not bad_ok)

    # BIP-143 commits to the amount: verifying at a wrong amount must fail
    wrong_amount_ok = True
    try:
        VerifyScript(tx.vin[0].scriptSig, CScript(sc["spk"]), tx, 0,
                     flags=(SCRIPT_VERIFY_P2SH, SCRIPT_VERIFY_WITNESS),
                     amount=sc["amount"] + 1,
                     witness=tx.wit.vtxinwit[0].scriptWitness)
    except Exception:
        wrong_amount_ok = False
    run.ok("verifying at a +1-satoshi wrong amount is REJECTED "
           "(the sighash commits to it)", not wrong_amount_ok)

    print()
    if run.fail:
        print("verify-independent-decoder: %d of %d checks FAILED" % (run.fail, run.n))
        return 1
    print("verify-independent-decoder: OK - a fresh P2WPKH transaction built by "
          "src/coinxt.livecodescript was accepted by python-bitcointx %s "
          "(consensus script eval + independent sighash + raw ECDSA; %d checks, "
          "negative controls firing)" % (getattr(btx, "__version__", "?"), run.n))
    print("  tx: %s" % tx_hex)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
