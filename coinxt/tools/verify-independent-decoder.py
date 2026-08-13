#!/usr/bin/env python3
"""verify-independent-decoder.py - the phase-5 acceptance bar that no gate in
this repo can be: transactions the SHIPPED script layer builds are handed to
INDEPENDENT, mainstream implementations, which must deserialize them, evaluate
them under their own rules, and confirm every signature. All four shipped
transaction families are covered: Bitcoin native P2WPKH (BIP-143) and legacy
P2PKH against python-bitcointx, and Ethereum EIP-155 and EIP-1559 against
eth-account (the signing/recovery library web3.py itself uses) plus an
independent RLP decode of every field.

WHY THIS IS SEPARATE FROM check-script-vectors.py. That gate proves the script
agrees with tools/coin_reference.py, and the oracle is anchored to the BIP-143
published vector - a strong check, but a closed loop: our encoder, our model,
our vector. "Broadcastable" is a claim about the OUTSIDE world, and the only
honest way to test it is to have code we did not write accept a transaction we
did. python-bitcointx (the maintained fork of python-bitcoinlib, a full Python
consensus-shaped script interpreter) and eth-account are that code here.

WHY IT IS NOT IN THE CI GATE SET. python-bitcointx, its libsecp256k1 backend
(coincurve), and eth-account are third-party pip packages the suite does not
vendor and CI does not install, so this cannot run on every push the way the
headless vector gate does. It is an ACCEPTANCE run: executed deliberately, its
result recorded in IMPLEMENTATION-PLAN.md and the api-reference status block,
exactly like a testnet-node acceptance would be. Without the packages it SKIPS
loudly, per half (exit 0 by default; --require turns any skip into a failure
for a machine that has them).

WHAT MAKES THE TRANSACTIONS MEANINGFUL. Every one is FRESH, not a pinned
fixture: different private keys, amounts, recipients, a chain id the repo has
never used, an Ethereum value above 2^53 so the big-int hex path is genuinely
exercised - so a bug that only reproduces the published examples cannot pass.
The bytes under test are the SCRIPT's: the sighashes, DER, varint, witness,
RLP and transaction serialization all come out of src/coinxt.livecodescript
driven through tools/lcs-interp.py; the oracle supplies only the RFC 6979
(r, s) the app's cxSign / cxSignRecoverable would (the script does not sign),
and the external libraries supply the independent verdicts.

    python3 tools/verify-independent-decoder.py            # detail
    python3 tools/verify-independent-decoder.py --require   # skip -> failure

Install the verifiers (a venv keeps them out of the repo tooling's
site-packages):
    python3 -m venv /tmp/btcvenv
    /tmp/btcvenv/bin/pip install python-bitcointx coincurve eth-account
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


def import_ethverify():
    """eth-account plus rlp plus keccak are the Ethereum counterpart of
    python-bitcointx: code we did not write that must accept the script's
    bytes. Returns (Account, rlp, keccak), or None - the Ethereum half then
    SKIPS loudly, same contract as the Bitcoin half."""
    try:
        from eth_account import Account
        import rlp
        from eth_utils import keccak
        return Account, rlp, keccak
    except ImportError:
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


def fresh_legacy_scenario():
    """A brand-new single-input legacy P2PKH spend, the pre-segwit sibling of
    fresh_scenario(): SIGHASH_ALL over the original preimage, a scriptSig
    instead of a witness, no amount committed in the digest. Nothing here is
    the BIP-143 fixture or the segwit scenario above."""
    sk = bytes.fromhex("badc0de5" * 8)
    pub = REF.pubkey(sk)                       # 33-byte compressed
    # legacy P2PKH: scriptCode IS the prevout's scriptPubKey
    spk = b"\x76\xa9\x14" + REF.hash160(pub) + b"\x88\xac"
    ver, lock = 1, 0
    prev_txid = bytes.fromhex("22" * 32)
    vout = 1
    seq = 0xffffffff
    op = REF.btc_outpoint(prev_txid, vout)
    dest_sk = bytes.fromhex("00" * 31 + "09")
    dest_spk = b"\x76\xa9\x14" + REF.hash160(REF.pubkey(dest_sk)) + b"\x88\xac"
    out_amount = 59_900_000                    # 0.6 BTC in, 0.001 BTC fee
    out = REF.btc_output(out_amount, dest_spk)
    ins, outs = [(op, seq)], [out]
    digest = REF.btc_sighash_legacy(ver, ins, outs, 0, spk, lock)
    r, s, _ = REF.ecdsa_sign_recoverable(sk, digest)
    return {
        "sk": sk, "pub": pub, "spk": spk, "ver": ver, "lock": lock,
        "seq": seq, "op": op, "out": out, "out_hex": out.hex(),
        "digest": digest, "rs": (r, s),
    }


def fresh_eth_scenarios():
    """Fresh EIP-155 and EIP-1559 transactions: keys, recipients, nonces and a
    chain id (137) the repo has never pinned, wei values above 2^53 so the
    big-int hex path is genuinely exercised, and (for the 1559 case) a
    non-empty data payload. The oracle signs (RFC 6979 recoverable, the
    app's cxSignRecoverable) and re-derives the raw tx for the closed-loop
    leg; eth-account and rlp supply the independent verdicts in main()."""
    chain = 137
    sk155 = bytes.fromhex("5eed" * 16)
    to155 = "4455445544554455445544554455445544554455"
    n155, gp, gas = 7, 31_000_000_000, 21000
    val155 = 1_500_000_000_000_000_000        # 1.5 ETH in wei, above 2^53
    h155 = REF.eth_legacy_sighash(n155, gp, gas, bytes.fromhex(to155),
                                  val155, b"", chain)
    r155, s155, rec155 = REF.ecdsa_sign_recoverable(sk155, h155)
    raw155, txh155 = REF.eth_legacy_encode(n155, gp, gas, bytes.fromhex(to155),
                                           val155, b"", chain, sk155)
    sk1559 = bytes.fromhex("7e57" * 16)
    to1559 = "6677667766776677667766776677667766776677"
    n1559, prio, fee = 3, 2_000_000_000, 42_000_000_000
    val1559 = 725_000_000_000_000_000
    data1559 = bytes.fromhex("c0ffee01")
    h1559 = REF.eth_1559_sighash(chain, n1559, prio, fee, gas,
                                 bytes.fromhex(to1559), val1559, data1559)
    r1559, s1559, rec1559 = REF.ecdsa_sign_recoverable(sk1559, h1559)
    raw1559, txh1559 = REF.eth_1559_encode(chain, n1559, prio, fee, gas,
                                           bytes.fromhex(to1559), val1559,
                                           data1559, sk1559)
    return {
        "chain": chain,
        "sk155": sk155, "to155": to155, "n155": n155, "gp": gp, "gas": gas,
        "val155": val155, "h155": h155, "rs155": (r155, s155),
        "rec155": rec155, "raw155": raw155, "txh155": txh155,
        "sk1559": sk1559, "to1559": to1559, "n1559": n1559, "prio": prio,
        "fee": fee, "val1559": val1559, "data1559": data1559, "h1559": h1559,
        "rs1559": (r1559, s1559), "rec1559": rec1559, "raw1559": raw1559,
        "txh1559": txh1559,
    }


def even_hex(n):
    """Minimal big-endian hex with an even length - the wire form the script's
    wei-scale fields cross as (an odd-length string is half a byte)."""
    h = "%x" % n
    if len(h) % 2:
        h = "0" + h
    return h


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
    print("  -- fresh native P2WPKH (BIP-143) --")

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

    # ===== fresh LEGACY P2PKH: the pre-segwit sighash and scriptSig path =====
    print()
    print("  -- fresh legacy P2PKH --")
    lg = fresh_legacy_scenario()
    lr, ls = lg["rs"]

    lg_digest = CSV.to_bytes(call(
        "cxBtcSighashLegacy", lg["ver"], lg["op"].hex(), str(lg["seq"]), 1,
        lg["spk"].hex(), lg["out_hex"], lg["lock"], 1))
    run.ok("the script's legacy sighash equals the oracle's",
           lg_digest == lg["digest"],
           "script %s\n       oracle %s" % (lg_digest.hex(),
                                            lg["digest"].hex()))

    # DER by the SCRIPT this time (the segwit leg above uses the oracle's,
    # so between the two legs both producers get an external verdict). The
    # P2PKH scriptSig is push(sig) push(pubkey); composing the two pushes is
    # the app's job in the shipped API, so composing them here is the same
    # trust boundary, not a shortcut.
    lg_compact = lr.to_bytes(32, "big") + ls.to_bytes(32, "big")
    lg_sig = CSV.to_bytes(call("cxDerEncode", lg_compact)) + b"\x01"
    lg_scriptsig = (bytes([len(lg_sig)]) + lg_sig
                    + bytes([len(lg["pub"])]) + lg["pub"])

    # witnesses cross as the EMPTY list: the encoder must emit the legacy
    # serialization, no segwit marker/flag - the byte-exact round-trip below
    # is what proves it did
    lg_tx_hex = CSV.to_bytes(call(
        "cxBtcTxEncode", lg["ver"], lg["op"].hex(), lg_scriptsig.hex(),
        str(lg["seq"]), "", lg["out_hex"], lg["lock"])).hex()
    lg_txid_hex = str(LCS._disp(call(
        "cxBtcTxid", lg["ver"], lg["op"].hex(), lg_scriptsig.hex(),
        str(lg["seq"]), lg["out_hex"], lg["lock"])))

    lg_tx = CTransaction.deserialize(x(lg_tx_hex))
    run.ok("python-bitcointx deserializes the legacy tx and it round-trips "
           "byte-exact (no witness marker)",
           lg_tx.serialize().hex() == lg_tx_hex)
    run.ok("its txid agrees with the script's cxBtcTxid",
           lg_tx.GetTxid()[::-1].hex() == lg_txid_hex,
           "bitcointx %s\n       script    %s"
           % (lg_tx.GetTxid()[::-1].hex(), lg_txid_hex))

    ok_eval = True
    detail = ""
    try:
        VerifyScript(lg_tx.vin[0].scriptSig, CScript(lg["spk"]), lg_tx, 0,
                     flags=(SCRIPT_VERIFY_P2SH,))
    except Exception as exc:
        ok_eval = False
        detail = str(exc)
    run.ok("VerifyScript accepts the P2PKH input under consensus rules",
           ok_eval, detail)

    lg_sighash_btx = SignatureHash(CScript(lg["spk"]), lg_tx, 0, SIGHASH_ALL)
    run.ok("python-bitcointx's independent legacy sighash matches too",
           lg_sighash_btx == lg["digest"])
    run.ok("the scriptSig signature verifies against that sighash (raw ECDSA)",
           CPubKey(lg["pub"]).verify(lg_sighash_btx, lg_sig[:-1]))

    bad = bytearray(x(lg_tx_hex))
    idx = lg_tx_hex.find(lg_sig.hex())
    assert idx >= 0 and idx % 2 == 0
    bad[idx // 2 + 5] ^= 0x01        # a byte inside the DER body
    bad_ok = True
    try:
        btx_bad = CTransaction.deserialize(bytes(bad))
        VerifyScript(btx_bad.vin[0].scriptSig, CScript(lg["spk"]), btx_bad, 0,
                     flags=(SCRIPT_VERIFY_P2SH,))
    except Exception:
        bad_ok = False
    run.ok("a single flipped signature byte is REJECTED", not bad_ok)

    # legacy sighash commits to the OUTPUTS (never to the spent amount, which
    # pre-BIP-143 verification cannot see): +1 satoshi on the output must fail
    bad2 = bytearray(x(lg_tx_hex))
    idx2 = lg_tx_hex.find(lg["out_hex"])
    assert idx2 >= 0 and idx2 % 2 == 0
    bad2[idx2 // 2] += 1             # low byte of the LE amount (96: no carry)
    bad2_ok = True
    try:
        btx_bad2 = CTransaction.deserialize(bytes(bad2))
        VerifyScript(btx_bad2.vin[0].scriptSig, CScript(lg["spk"]), btx_bad2,
                     0, flags=(SCRIPT_VERIFY_P2SH,))
    except Exception:
        bad2_ok = False
    run.ok("a +1-satoshi tampered OUTPUT is REJECTED (the legacy sighash "
           "commits to the outputs)", not bad2_ok)

    # ===== fresh Ethereum EIP-155 and EIP-1559 ===============================
    ethmods = import_ethverify()
    eth_skipped = ethmods is None
    eth = None
    if eth_skipped:
        print()
        print("verify-independent-decoder: SKIP the Ethereum half - "
              "eth-account not importable.\n"
              "    pip install eth-account   (rlp and keccak ride along)")
    else:
        Account, rlp, keccak = ethmods
        eth = fresh_eth_scenarios()

        def uint(b):
            return int.from_bytes(b, "big")

        def recovers_to(raw_bytes, sender):
            # a tampered tx may recover to a DIFFERENT valid key or raise;
            # either way it must not recover to the sender
            try:
                return Account.recover_transaction(raw_bytes) == sender
            except Exception:
                return False

        print()
        print("  -- fresh EIP-155 legacy --")
        r155, s155 = eth["rs155"]
        h = CSV.to_bytes(call(
            "cxEthLegacySighash", eth["n155"], even_hex(eth["gp"]),
            eth["gas"], eth["to155"], even_hex(eth["val155"]), "",
            eth["chain"]))
        run.ok("the script's EIP-155 sighash equals the oracle's",
               h == eth["h155"])
        res = call("cxEthLegacyEncode", eth["n155"], even_hex(eth["gp"]),
                   eth["gas"], eth["to155"], even_hex(eth["val155"]), "",
                   eth["chain"], eth["rec155"],
                   r155.to_bytes(32, "big").hex(),
                   s155.to_bytes(32, "big").hex())
        raw_hex, txh_hex = str(res["raw"]), str(res["txhash"])
        run.ok("the script's raw tx equals the oracle's, byte for byte",
               raw_hex == eth["raw155"].hex())
        raw = bytes.fromhex(raw_hex)
        run.ok("its txhash is keccak256 of the raw bytes (independent keccak)",
               keccak(raw).hex() == txh_hex)
        items = rlp.decode(raw)
        run.ok("an independent RLP decode returns the fields as sent",
               len(items) == 9 and uint(items[0]) == eth["n155"]
               and uint(items[1]) == eth["gp"]
               and uint(items[2]) == eth["gas"]
               and items[3].hex() == eth["to155"]
               and uint(items[4]) == eth["val155"] and items[5] == b"")
        run.ok("v encodes chain id 137 (chain*2 + 35 + recid)",
               uint(items[6]) == eth["chain"] * 2 + 35 + eth["rec155"])
        sender = Account.from_key(eth["sk155"]).address
        try:
            rec = Account.recover_transaction(raw)
        except Exception as exc:
            rec = "raised: %s" % exc
        run.ok("eth-account recovers the sender from the script-built tx",
               rec == sender,
               "recovered %s\n       expected  %s" % (rec, sender))
        rmin = r155.to_bytes(32, "big").lstrip(b"\x00")
        pos = raw.find(rmin)
        assert pos > 0
        bad = bytearray(raw)
        bad[pos + len(rmin) - 1] ^= 0x01
        run.ok("a flipped signature byte no longer recovers the sender",
               not recovers_to(bytes(bad), sender))
        vmin = eth["val155"].to_bytes(
            (eth["val155"].bit_length() + 7) // 8, "big")
        pos = raw.find(vmin)
        assert pos > 0
        bad2 = bytearray(raw)
        bad2[pos + 1] ^= 0x01
        run.ok("a tampered value no longer recovers the sender (the "
               "signature commits to the payload)",
               not recovers_to(bytes(bad2), sender))

        print()
        print("  -- fresh EIP-1559 typed --")
        r1559, s1559 = eth["rs1559"]
        h = CSV.to_bytes(call(
            "cxEth1559Sighash", eth["chain"], eth["n1559"],
            even_hex(eth["prio"]), even_hex(eth["fee"]), eth["gas"],
            eth["to1559"], even_hex(eth["val1559"]), eth["data1559"].hex()))
        run.ok("the script's EIP-1559 sighash equals the oracle's",
               h == eth["h1559"])
        res = call("cxEth1559Encode", eth["chain"], eth["n1559"],
                   even_hex(eth["prio"]), even_hex(eth["fee"]), eth["gas"],
                   eth["to1559"], even_hex(eth["val1559"]),
                   eth["data1559"].hex(), eth["rec1559"],
                   r1559.to_bytes(32, "big").hex(),
                   s1559.to_bytes(32, "big").hex())
        raw_hex, txh_hex = str(res["raw"]), str(res["txhash"])
        run.ok("the script's raw tx equals the oracle's, byte for byte",
               raw_hex == eth["raw1559"].hex())
        raw = bytes.fromhex(raw_hex)
        run.ok("its txhash is keccak256 of the raw bytes (independent keccak)",
               keccak(raw).hex() == txh_hex)
        run.ok("the envelope is typed 0x02", raw[0] == 2)
        p = rlp.decode(raw[1:])
        run.ok("an independent RLP decode returns the fields as sent "
               "(empty access list included)",
               len(p) == 12 and uint(p[0]) == eth["chain"]
               and uint(p[1]) == eth["n1559"] and uint(p[2]) == eth["prio"]
               and uint(p[3]) == eth["fee"] and uint(p[4]) == eth["gas"]
               and p[5].hex() == eth["to1559"]
               and uint(p[6]) == eth["val1559"]
               and p[7] == eth["data1559"] and p[8] == []
               and uint(p[9]) == eth["rec1559"])
        sender = Account.from_key(eth["sk1559"]).address
        try:
            rec = Account.recover_transaction(raw)
        except Exception as exc:
            rec = "raised: %s" % exc
        run.ok("eth-account recovers the sender from the script-built tx",
               rec == sender,
               "recovered %s\n       expected  %s" % (rec, sender))
        rmin = r1559.to_bytes(32, "big").lstrip(b"\x00")
        pos = raw.find(rmin)
        assert pos > 0
        bad = bytearray(raw)
        bad[pos + len(rmin) - 1] ^= 0x01
        run.ok("a flipped signature byte no longer recovers the sender",
               not recovers_to(bytes(bad), sender))

    print()
    if run.fail:
        print("verify-independent-decoder: %d of %d checks FAILED"
              % (run.fail, run.n))
        return 1
    families = ("Bitcoin native P2WPKH + legacy P2PKH accepted by "
                "python-bitcointx %s (consensus script eval + independent "
                "sighash + raw ECDSA)" % getattr(btx, "__version__", "?"))
    if not eth_skipped:
        families += ("; Ethereum EIP-155 + EIP-1559 accepted by eth-account "
                     "(sender recovery + independent RLP field decode + "
                     "independent keccak)")
    scope = ("all four transaction families" if not eth_skipped
             else "the two Bitcoin families (Ethereum SKIPPED, see above)")
    print("verify-independent-decoder: OK - fresh transactions built by "
          "src/coinxt.livecodescript were independently accepted in %s: %s; "
          "%d checks, negative controls firing in every family run"
          % (scope, families, run.n))
    print("  segwit tx:  %s" % tx_hex)
    print("  legacy tx:  %s" % lg_tx_hex)
    if not eth_skipped:
        print("  eip155 tx:  %s" % eth["raw155"].hex())
        print("  eip1559 tx: %s" % eth["raw1559"].hex())
    return 1 if (require and eth_skipped) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
