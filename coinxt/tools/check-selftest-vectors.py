#!/usr/bin/env python3
"""check-selftest-vectors.py - keep the OXT self-test's vectors honest.

tests/coin-selftest.livecodescript is the engine-side harness: a human pastes it
into OXT and it drives all 16 public cx* handlers against known answers. Its
expected values are LiteralS in a .livecodescript file, which means they are
hand-copied, which means they can drift - from tools/coin-kat.py, from the shim,
or from the published vectors themselves. A drifted expectation is worse than no
test: it turns a real regression into a green run, in a library that handles
money.

So this gate re-derives every constant in that harness and refuses to let it
disagree. It needs NO C compiler and no build, so it runs in the always-on gate
set on every push rather than only where a toolchain exists:

  * where Python ships an independent implementation of the primitive
    (hashlib, hmac), the constant is checked against THAT - which is the
    project rule, "cross-checked against an independent implementation before
    pinning", enforced continuously instead of once;
  * RIPEMD-160 is the known exception (OpenSSL 3 moved it to the legacy
    provider, so hashlib usually cannot supply it). There the constant is
    checked against the published vector table in tools/coin-kat.py, and the
    absence of a second opinion is REPORTED, never silently skipped;
  * the two structural claims the harness asserts but does not pin as a digest
    - that PBKDF2's short output prefixes its long one, and that Keccak-256 and
    SHA3-256 really do differ - are re-derived too.

The shim itself is coin-kat.py's job. This file's question is narrower and
different: does the harness we hand a human still SAY the right answers?

Usage:
  python3 tools/check-selftest-vectors.py          # per-vector detail
  python3 tools/check-selftest-vectors.py --check  # terse: one OK line or exit 1
"""

import hashlib
import hmac as pyhmac
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SELFTEST = os.path.normpath(os.path.join(HERE, "..", "tests",
                                         "coin-selftest.livecodescript"))
KAT = os.path.join(HERE, "coin-kat.py")


def load_constants(path):
    """Pull `constant kName = "value"` out of the harness, in file order."""
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    found = re.findall(r'^constant (k\w+) = "([^"]*)"', text, re.M)
    return dict(found)


def load_kat_table(name):
    """Read one vector table out of coin-kat.py without importing it.

    coin-kat.py builds a shared library at import time in some flows; parsing the
    literal table keeps this gate free of side effects and of a compiler.
    """
    with open(KAT, "r", encoding="utf-8") as handle:
        text = handle.read()
    block = re.search(name + r"\s*=\s*\{(.*?)\n\}", text, re.S)
    if not block:
        return {}
    out = {}
    for key, val in re.findall(r'b"([^"]*)":\s*\(?\s*"([0-9a-f"\s\n]*)"',
                               block.group(1)):
        out[key] = re.sub(r'[\s"]', "", val)
    return out


def load_kat_curve():
    """The secp256k1 constants coin-kat.py pins, read by IMPORTING it.

    The hash tables above are scraped with a regex because they are flat dicts
    of byte strings. The curve tables are lists of tuples, where a regex would
    be both uglier and easier to get quietly wrong, so this leg evaluates the
    file instead. That is safe here for the same reason the regex was chosen
    over it before: coin-kat.py does all of its work inside main(), which is
    guarded by __name__, so evaluating it builds nothing and needs no compiler.

    It reads the SOURCE and execs it rather than going through importlib, and
    that is not stylistic. importlib would consult __pycache__, and a cached
    .pyc is only invalidated when the source's mtime OR size changes - so a
    one-character edit made within the same second as the last run (exactly
    what editing a hex constant looks like) can leave this gate reading the
    PREVIOUS vectors and reporting OK. That was observed while mutation-testing
    this file, not theorised. A gate whose whole job is to catch drift must not
    have a stale-cache path, so it does not have one.
    """
    try:
        with open(KAT, "r", encoding="utf-8") as handle:
            source = handle.read()
        # __file__ has to be present: coin-kat.py derives its own paths from it
        # at module level, and __name__ has to be anything but "__main__" so its
        # entry point stays guarded.
        namespace = {"__name__": "coin_kat_vectors", "__file__": KAT}
        exec(compile(source, KAT, "exec"), namespace)  # noqa: S102 - see above
        pub = {sk: (c, u) for sk, c, u in namespace["PUBKEYS"]}
        sig = {(sk, msg): s for sk, msg, s in namespace["RFC6979"]}
        return {
            "pub1_compressed": pub[1][0],
            "pub1_uncompressed": pub[1][1],
            "sig_satoshi": sig[(1, b"Satoshi Nakamoto")],
        }
    except (OSError, SyntaxError, NameError, AttributeError, KeyError, ValueError):
        return None


def _load_reference():
    """The phase-3 reference implementation, loaded the same source-exec way as
    the KAT tables above and for the same reason: no bytecode cache path."""
    import importlib.util
    path = os.path.join(HERE, "coin_reference.py")
    spec = importlib.util.spec_from_file_location("coin_reference_v", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sha3_256(data):
    return hashlib.sha3_256(data).hexdigest()


def have_ripemd():
    try:
        hashlib.new("ripemd160")
        return True
    except (ValueError, TypeError):
        return False


def main(argv):
    terse = "--check" in argv[1:]
    problems = []
    notes = []

    if not os.path.exists(SELFTEST):
        print("check-selftest-vectors: tests/coin-selftest.livecodescript is missing")
        return 1

    k = load_constants(SELFTEST)
    if not k:
        print("check-selftest-vectors: no constants parsed - has the harness changed shape?")
        return 1

    checked = set()

    def want(name, expected, source):
        checked.add(name)
        got = k.get(name)
        if got is None:
            problems.append(f"{name} is missing from the harness")
        elif got != expected:
            problems.append(f"{name}\n      harness: {got}\n      {source}: {expected}")
        elif not terse:
            print(f"  OK  {name:16s} vs {source}")

    fox = k.get("kFox", "")
    mnemonic = k.get("kBip39Mnemonic", "").encode()
    salt = k.get("kBip39Salt", "").encode()

    # --- primitives Python can independently reproduce -----------------------
    want("kSha3Empty", sha3_256(b""), "hashlib")
    want("kSha3Abc", sha3_256(b"abc"), "hashlib")
    want("kSha3Fox", sha3_256(fox.encode()), "hashlib")

    want("kSha256Empty", hashlib.sha256(b"").hexdigest(), "hashlib")
    want("kSha256Abc", hashlib.sha256(b"abc").hexdigest(), "hashlib")
    want("kSha512Empty", hashlib.sha512(b"").hexdigest(), "hashlib")
    want("kSha512Abc", hashlib.sha512(b"abc").hexdigest(), "hashlib")

    key1 = b"\x0b" * 20
    want("kHmac1Sha256", pyhmac.new(key1, b"Hi There", hashlib.sha256).hexdigest(), "hmac")
    want("kHmac1Sha512", pyhmac.new(key1, b"Hi There", hashlib.sha512).hexdigest(), "hmac")
    msg2 = b"what do ya want for nothing?"
    want("kHmac2Sha256", pyhmac.new(b"Jefe", msg2, hashlib.sha256).hexdigest(), "hmac")
    want("kHmac2Sha512", pyhmac.new(b"Jefe", msg2, hashlib.sha512).hexdigest(), "hmac")

    want("kBip39Seed",
         hashlib.pbkdf2_hmac("sha512", mnemonic, salt, 2048, 64).hex(),
         "hashlib.pbkdf2")

    want("kHash256Abc",
         hashlib.sha256(hashlib.sha256(b"abc").digest()).hexdigest(),
         "hashlib")

    # --- Keccak-256: Python has no Keccak, so the KAT table is the reference --
    keccak = load_kat_table("KECCAK256")
    if keccak:
        want("kKeccakEmpty", keccak.get("", ""), "coin-kat")
        want("kKeccakAbc", keccak.get("abc", ""), "coin-kat")
    else:
        problems.append("could not read KECCAK256 out of tools/coin-kat.py")

    # --- RIPEMD-160: the one primitive with no second opinion ----------------
    ripe = load_kat_table("RIPEMD160")
    if have_ripemd():
        for name, msg in (("kRipeEmpty", b""), ("kRipeA", b"a"),
                          ("kRipeAbc", b"abc"), ("kRipeMsgDigest", b"message digest")):
            digest = hashlib.new("ripemd160", msg).hexdigest()
            want(name, digest, "hashlib")
    elif ripe:
        notes.append("RIPEMD-160: hashlib cannot supply it here (OpenSSL 3 legacy "
                     "provider), so the published table in coin-kat.py is the only "
                     "reference available - no independent second opinion.")
        for name, msg in (("kRipeEmpty", ""), ("kRipeA", "a"),
                          ("kRipeAbc", "abc"), ("kRipeMsgDigest", "message digest")):
            want(name, ripe.get(msg, ""), "coin-kat")
    else:
        problems.append("could not read RIPEMD160 out of tools/coin-kat.py")

    # --- secp256k1 (phase 2) -------------------------------------------------
    # Two tiers, the same shape this file already uses for RIPEMD-160.
    #
    # Tier 1 always runs: the harness constants must equal the ones coin-kat.py
    # pins. That is precisely the drift this gate exists to catch, because the
    # two files are meant to be the same claim at two layers, and only one of
    # them is driven by CI on every push.
    #
    # Tier 2 runs when the independent `ecdsa` package is installed, and then
    # RE-DERIVES the values rather than comparing two copies of them. When it is
    # absent the gate says so instead of quietly passing on tier 1 alone.
    curve = load_kat_curve()
    if curve is None:
        problems.append("could not read the secp256k1 tables out of tools/coin-kat.py")
    else:
        want("kPubOneCompressed", curve["pub1_compressed"], "coin-kat")
        want("kPubOneUncompressed", curve["pub1_uncompressed"], "coin-kat")
        want("kSigSatoshi", curve["sig_satoshi"], "coin-kat")

    try:
        from ecdsa import SECP256k1, SigningKey
        from ecdsa.util import sigencode_string
        order = SECP256k1.order
        key = SigningKey.from_secret_exponent(1, curve=SECP256k1)
        vk = key.get_verifying_key()
        want("kPubOneCompressed", vk.to_string("compressed").hex(), "ecdsa")
        want("kPubOneUncompressed", vk.to_string("uncompressed").hex(), "ecdsa")
        raw = key.sign_digest_deterministic(
            hashlib.sha256(b"Satoshi Nakamoto").digest(),
            hashfunc=hashlib.sha256, sigencode=sigencode_string)
        r = int.from_bytes(raw[:32], "big")
        s = int.from_bytes(raw[32:], "big")
        # Upstream always emits the low-s form; normalise before comparing so a
        # mismatch means a wrong signature and not a different convention.
        if s > order // 2:
            s = order - s
        want("kSigSatoshi", (r.to_bytes(32, "big") + s.to_bytes(32, "big")).hex(), "ecdsa")
    except ImportError:
        # Same split as coin-kat.py: a skip is fine for a contributor without an
        # optional package, and wrong for CI, where it is indistinguishable from
        # a pass. CI sets COINXT_REQUIRE_CROSSCHECK so the independent
        # re-derivation cannot quietly stop happening.
        if os.environ.get("COINXT_REQUIRE_CROSSCHECK"):
            problems.append("COINXT_REQUIRE_CROSSCHECK is set but the `ecdsa` package "
                            "is not installed, so the curve constants could not be "
                            "re-derived independently (pip install ecdsa)")
        else:
            notes.append("secp256k1: the `ecdsa` package is not installed here, so the "
                         "curve constants were checked against the table in coin-kat.py "
                         "rather than re-derived independently (pip install ecdsa).")

    # --- phase 3: encodings and addresses ------------------------------------
    # Re-derived from tools/coin_reference.py, which reproduces the published
    # vectors independently. Two of these are worth stating plainly because they
    # are what makes the harness self-evidently right rather than self-
    # consistent: the P2WPKH and P2TR addresses of the private key 1 ARE
    # BIP-173's and BIP-350's own example addresses, because hash160(G) is the
    # witness program in the first and x-only G is the program in the second.
    try:
        ref = _load_reference()
    except Exception as exc:                                  # pragma: no cover
        ref = None
        problems.append(f"could not load tools/coin_reference.py ({exc})")
    if ref is not None:
        g33 = bytes.fromhex(k.get("kPubOneCompressed", ""))
        g65 = bytes.fromhex(k.get("kPubOneUncompressed", ""))
        # 2G. The harness uses it to prove that tweaking the private key and
        # tweaking the public key land on the same point, so it has to be the
        # curve's real second point and not whatever CoinXT happens to emit.
        want("kPubTwoCompressed", ref.pubkey((2).to_bytes(32, "big")).hex(),
             "coin_reference")
        payload = bytes.fromhex(k.get("kBase58Payload", ""))
        want("kBase58Address", ref.b58check_encode(payload), "coin_reference")
        want("kP2pkhOfG", ref.p2pkh(g33), "coin_reference")
        want("kP2wpkhOfG", ref.p2wpkh(g33), "coin_reference")
        want("kP2trOfG", ref.p2tr(g65[1:33]), "coin_reference")
        want("kEthOfG", ref.eip55(ref.eth_address(g65)), "coin_reference")
        for name in ("kEip55A", "kEip55B"):
            got = k.get(name, "")
            want(name, ref.eip55(got.lower()), "coin_reference")
        ver, prog = ref.segwit_decode("tb", k.get("kSegwitTestnet", ""))
        want("kSegwitTestnetProgram",
             bytes(prog).hex() if prog is not None else "(did not decode)",
             "coin_reference")
        # The two NEGATIVE vectors have to stay negative, or the checks that use
        # them silently stop testing anything.
        try:
            ref.b58check_decode(k.get("kBase58Corrupt", ""))
            problems.append("kBase58Corrupt has a VALID checksum, so the harness "
                            "check that it is refused proves nothing")
        except ValueError:
            if not terse:
                print("  OK  kBase58Corrupt        is genuinely corrupt")
        if ref.segwit_decode("bc", k.get("kSegwitV0WithBech32m", "")) != (None, None):
            problems.append("kSegwitV0WithBech32m decodes successfully, so the "
                            "harness check that it is refused proves nothing")
        elif not terse:
            print("  OK  kSegwitV0WithBech32m  is genuinely invalid")

        # WIF. All three positive forms are re-derived from the input key; the
        # reference's own import self-check anchors the mainnet/uncompressed
        # derivation to the Bitcoin wiki's published string, so a drifted
        # constant here disagrees with a public artifact, not merely with us.
        try:
            wif_sk = bytes.fromhex(k.get("kWifSeckey", ""))
            want("kWifUncompressed", ref.wif_encode(wif_sk, "mainnet", False),
                 "coin_reference")
            want("kWifCompressed", ref.wif_encode(wif_sk, "mainnet", True),
                 "coin_reference")
            want("kWifTestnet", ref.wif_encode(wif_sk, "testnet", True),
                 "coin_reference")
        except ValueError:
            # A missing or mangled input key leaves the three positives
            # unchecked, and the completeness sweep below then names them.
            problems.append("kWifSeckey is not a valid 64-hex private key, so "
                            "the WIF constants could not be re-derived")
        # The negative vector must stay negative, the kBase58Corrupt rule.
        try:
            ref.wif_decode(k.get("kWifBadChecksum", ""))
            problems.append("kWifBadChecksum has a VALID checksum, so the harness "
                            "check that it is refused proves nothing")
        except ValueError:
            if not terse:
                print("  OK  kWifBadChecksum      is genuinely corrupt")
        if ref.bech32_decode(k.get("kBech32Valid", ""))[0] is None:
            problems.append("kBech32Valid does not actually decode")
        elif not terse:
            print("  OK  kBech32Valid          is genuinely valid")

        # The fail-open regression pair. kSegwitErrorProgram exists for ONE
        # reason: its first five bytes spell "ERROR", which is what the old
        # in-band sentinel mistook for a failure. Edit those bytes to anything
        # else and the harness still passes - against a program that no longer
        # reproduces the bug. That is the regression quietly retiring itself,
        # so the property is asserted rather than left to the literal.
        checked.add("kSegwitErrorProgram")
        errprog = bytes.fromhex(k.get("kSegwitErrorProgram", ""))
        if errprog[:5] != b"ERROR":
            problems.append("kSegwitErrorProgram no longer begins with the bytes "
                            "'ERROR', so the in-band-sentinel regression it exists "
                            "for is no longer being reproduced")
        elif not terse:
            print("  OK  kSegwitErrorProgram   still spells ERROR")
        want("kSegwitErrorAddress", ref.segwit_encode("bc", 1, errprog),
             "coin_reference")

        # The two EIP-55 negatives must differ from kEip55A only in CASE (so the
        # bytes are the same address) and must not themselves be correctly
        # checksummed - otherwise "one corrupted letter is caught" is checking a
        # different address, not a corrupted one.
        for name in ("kEip55Corrupt", "kEip55Flipped"):
            checked.add(name)
            got = k.get(name, "")
            if got.lower() != k.get("kEip55A", "").lower():
                problems.append(f"{name} is not a case-variant of kEip55A, so the "
                                f"harness is testing a different address rather "
                                f"than a corrupted checksum")
            elif got == ref.eip55(got.lower()):
                problems.append(f"{name} IS correctly checksummed, so the harness "
                                f"check that it is rejected proves nothing")
            elif not terse:
                print(f"  OK  {name:16s} is a genuinely bad checksum")

        # ---- phase 4 --------------------------------------------------------
        # Re-derived rather than trusted, for the reason the harness itself
        # states: this is the one surface where a wrong constant produces
        # something that still looks right, so a drifted literal here would turn
        # a real regression into a green run.
        ent12 = bytes.fromhex(k.get("kBip39Entropy12", ""))
        ent24 = bytes.fromhex(k.get("kBip39Entropy24", ""))
        want("kBip39Mnemonic", ref.bip39_mnemonic(ent12), "coin_reference")
        want("kBip39Mnemonic24", ref.bip39_mnemonic(ent24), "coin_reference")
        want("kBip39SeedNoPass", ref.bip39_seed(k.get("kBip39Mnemonic", "")).hex(),
             "coin_reference")
        master1 = ref.bip32_master(bytes.fromhex(k.get("kBip32Seed1", "")))
        want("kBip32V1Xprv", ref.bip32_serialize(master1, True), "coin_reference")
        want("kBip32V1Xpub", ref.bip32_serialize(master1, False), "coin_reference")
        h0 = ref.bip32_path(master1, "m/0'")
        want("kBip32V1H0Xprv", ref.bip32_serialize(h0, True), "coin_reference")
        want("kBip32V1H0Xpub", ref.bip32_serialize(h0, False), "coin_reference")
        want("kBip32V1DeepXprv",
             ref.bip32_serialize(ref.bip32_path(master1, k.get("kBip32V1DeepPath", "m")), True),
             "coin_reference")
        want("kBip32V3Xprv",
             ref.bip32_serialize(ref.bip32_master(bytes.fromhex(k.get("kBip32Seed3", ""))), True),
             "coin_reference")
        abandon = ref.bip32_master(bytes.fromhex(k.get("kBip39SeedNoPass", "")))
        want("kAbandonXprv", ref.bip32_serialize(abandon, True), "coin_reference")
        want("kAbandonP2pkh",
             ref.p2pkh(ref.bip32_path(abandon, k.get("kAbandonBip44", "m"))["pubkey"]),
             "coin_reference")
        want("kAbandonP2wpkh",
             ref.p2wpkh(ref.bip32_path(abandon, k.get("kAbandonBip84", "m"))["pubkey"]),
             "coin_reference")
        want("kAbandonBip84Xpub",
             ref.bip32_serialize(ref.bip32_path(abandon, k.get("kAbandonBip84Account", "m")), False),
             "coin_reference")
        eth_node = ref.bip32_path(abandon, k.get("kAbandonEthPath", "m"))
        want("kAbandonEth",
             ref.eip55(ref.eth_address(b"\x04" + b"".join(
                 x.to_bytes(32, "big") for x in ref._decompress(eth_node["pubkey"])))),
             "coin_reference")
        # And the NEGATIVE vector, same rule as kBase58Corrupt above.
        try:
            ref.bip39_entropy(k.get("kBip39Mnemonic12Bad", ""))
            problems.append("kBip39Mnemonic12Bad has a VALID checksum, so the "
                            "harness check that it is refused proves nothing")
        except ValueError:
            if not terse:
                print("  OK  kBip39Mnemonic12Bad  genuinely fails its checksum")
        # The harness asserts the passphrase reaches the KDF by pinning the same
        # mnemonic twice; if the two seeds were equal that claim would be empty.
        if k.get("kBip39Seed") == k.get("kBip39SeedNoPass"):
            problems.append("the harness pins the same mnemonic with and without a "
                            "passphrase, but its two seed constants are equal - the "
                            "passphrase would not be being tested at all")
        elif not terse:
            print("  OK  the passphrase genuinely changes the seed")

    # --- phase 5: transactions -----------------------------------------------
    if ref is not None:
        ver, lock = 1, 17
        ins = [(ref.btc_outpoint(bytes.fromhex(k.get("kTxid0", "")), 0), 0xffffffee),
               (ref.btc_outpoint(bytes.fromhex(k.get("kTxid1", "")), 1), 0xffffffff)]
        o0 = ref.btc_output(112340000, bytes.fromhex(k.get("kTxOutScript0", "")))
        o1 = ref.btc_output(223450000, bytes.fromhex(k.get("kTxOutScript1", "")))
        outs = [o0, o1]
        want("kTxOutpoint0", ins[0][0].hex(), "coin_reference")
        want("kTxOutpoint1", ins[1][0].hex(), "coin_reference")
        want("kTxOut0", o0.hex(), "coin_reference")
        want("kTxOut1", o1.hex(), "coin_reference")
        d0 = ref.btc_sighash_legacy(ver, ins, outs, 0,
                                    bytes.fromhex(k.get("kTxScriptCode0", "")), lock)
        d1 = ref.btc_sighash_segwit(ver, ins, outs, 1,
                                    bytes.fromhex(k.get("kTxScriptCode1", "")),
                                    600000000, lock)
        want("kTxLegacySighash", d0.hex(), "coin_reference")
        want("kTxSegwitSighash", d1.hex(), "coin_reference")
        r0, s0, _ = ref.ecdsa_sign_recoverable(bytes.fromhex(k.get("kTxSeckey0", "")), d0)
        der0 = ref.der_encode(r0, s0) + b"\x01"
        want("kTxScriptSig0", (bytes([len(der0)]) + der0).hex(), "coin_reference")
        r1, s1, _ = ref.ecdsa_sign_recoverable(bytes.fromhex(k.get("kTxSeckey1", "")), d1)
        der1 = ref.der_encode(r1, s1) + b"\x01"
        pub1 = bytes.fromhex(k.get("kTxPubkey1", ""))
        want("kTxWitness1",
             (b"\x02" + bytes([len(der1)]) + der1 + bytes([len(pub1)]) + pub1).hex(),
             "coin_reference")
        raw, txid = ref.btc_tx(ver, ins, outs, lock,
                               [bytes([len(der0)]) + der0, b""], [[], [der1, pub1]])
        want("kTxSignedRaw", raw.hex(), "coin_reference")
        want("kTxTxid", txid.hex(), "coin_reference")
        # cxPublicKey(kTxSeckey1) must be the BIP's published compressed key, so
        # the harness's pubkey cross-check is against a real value, not itself.
        if ref.pubkey(bytes.fromhex(k.get("kTxSeckey1", ""))).hex() != k.get("kTxPubkey1"):
            problems.append("kTxPubkey1 is not the compressed public key of "
                            "kTxSeckey1 - the harness's derive-and-compare is empty")
        elif not terse:
            print("  OK  kTxPubkey1 is genuinely the pubkey of kTxSeckey1")

        to = bytes.fromhex(k.get("kEthTo", ""))
        gp = bytes.fromhex(k.get("kEthGasPrice", ""))
        val = bytes.fromhex(k.get("kEthValue", ""))
        h155 = ref.eth_legacy_sighash(9, int.from_bytes(gp, "big"), 21000, to,
                                      int.from_bytes(val, "big"), b"", 1)
        want("kEthLegacySighash", h155.hex(), "coin_reference")
        raw155, txh155 = ref.eth_legacy_encode(9, int.from_bytes(gp, "big"), 21000,
                                               to, int.from_bytes(val, "big"), b"", 1,
                                               bytes.fromhex(k.get("kEthSeckey", "")))
        want("kEthLegacyRaw", raw155.hex(), "coin_reference")
        want("kEthLegacyTxhash", txh155.hex(), "coin_reference")

        mp = int.from_bytes(bytes.fromhex(k.get("kEth1559MaxPrio", "")), "big")
        mf = int.from_bytes(bytes.fromhex(k.get("kEth1559MaxFee", "")), "big")
        v1559 = int.from_bytes(bytes.fromhex(k.get("kEth1559Value", "")), "big")
        h1559 = ref.eth_1559_sighash(1, 0, mp, mf, 21000, to, v1559, b"")
        want("kEth1559Sighash", h1559.hex(), "coin_reference")
        raw1559, txh1559 = ref.eth_1559_encode(1, 0, mp, mf, 21000, to, v1559, b"",
                                               bytes.fromhex(k.get("kEthSeckey", "")))
        want("kEth1559Raw", raw1559.hex(), "coin_reference")
        want("kEth1559Txhash", txh1559.hex(), "coin_reference")

    # --- the structural claims the harness makes beyond the fixed digests ----
    short = hashlib.pbkdf2_hmac("sha512", mnemonic, salt, 2048, 20).hex()
    if short != k.get("kBip39Seed", "")[:40]:
        problems.append("the harness asserts PBKDF2's 20-byte output prefixes its "
                        "64-byte one, and it does not")
    elif not terse:
        print("  OK  PBKDF2 short output prefixes the long one")

    if k.get("kSha3Abc") == k.get("kKeccakAbc") or k.get("kSha3Empty") == k.get("kKeccakEmpty"):
        problems.append("the harness asserts SHA3-256 and Keccak-256 differ, but its "
                        "own constants are equal - the aliasing trap it exists to "
                        "catch would go undetected")
    elif not terse:
        print("  OK  SHA3-256 and Keccak-256 constants genuinely differ")

    # --- COMPLETENESS. Everything above is an explicit list, and an explicit
    # list silently stops covering the file the moment someone adds a constant
    # to it. That is not hypothetical: kHash256Abc and kPubTwoCompressed were
    # both added to the harness and both sailed through this gate, which then
    # printed "66 harness constants re-derived" - a number that was counting the
    # constants it had PARSED, not the ones it had checked. A gate that
    # overstates its own coverage is worse than one that has none, because it
    # answers the question nobody re-asks. So: every k* constant must be either
    # re-derived above or listed here with the reason it cannot be.
    inputs = {
        "kStTitle": "the harness scaffold's window title, not a vector "
                    "(tools/check-harness-scaffold-drift.py owns the block)",
        "kFox": "an input string",
        "kBip39Salt": "an input to PBKDF2",
        "kBip39Entropy12": "an input; the mnemonic derived from it is checked",
        "kBip39Entropy24": "an input; the mnemonic derived from it is checked",
        "kBip32Seed1": "an input; the nodes derived from it are checked",
        "kBip32Seed3": "an input; the xprv derived from it is checked",
        "kBase58Payload": "an input; the address encoded from it is checked",
        "kBip32V1DeepPath": "a derivation path, i.e. an input",
        "kAbandonBip44": "a derivation path, i.e. an input",
        "kAbandonBip84": "a derivation path, i.e. an input",
        "kAbandonBip84Account": "a derivation path, i.e. an input",
        "kAbandonEthPath": "a derivation path, i.e. an input",
        "kBip39Mnemonic12Bad": "a negative vector, checked below as genuinely bad",
        "kBase58Corrupt": "a negative vector, checked as genuinely corrupt",
        "kWifSeckey": "the Bitcoin wiki's WIF worked-example private key (a "
                      "published, burned test key); the three WIF strings "
                      "derived from it are checked",
        "kWifBadChecksum": "a negative vector, checked as genuinely corrupt",
        "kSegwitV0WithBech32m": "a negative vector, checked as genuinely invalid",
        "kBech32Valid": "a positive vector, checked as genuinely decodable",
        "kSegwitTestnet": "an input; the program decoded from it is checked",
        # phase 5 inputs (published fixtures the derived vectors are built from)
        "kTxSeckey0": "a published test private key (BIP-143 input 0)",
        "kTxSeckey1": "a published test private key (BIP-143 input 1)",
        "kTxPubkey1": "the BIP's published pubkey; checked to be kTxSeckey1's",
        "kTxid0": "a published outpoint txid (BIP-143 input 0)",
        "kTxid1": "a published outpoint txid (BIP-143 input 1)",
        "kTxScriptCode0": "the published P2PK scriptCode (BIP-143 input 0)",
        "kTxScriptCode1": "the published P2WPKH scriptCode (BIP-143 input 1)",
        "kTxOutScript0": "a published output scriptPubKey (BIP-143)",
        "kTxOutScript1": "a published output scriptPubKey (BIP-143)",
        "kEthSeckey": "the EIP-155 spec example private key (0x46 * 32)",
        "kEthTo": "the EIP-155 spec example recipient address",
        "kEthGasPrice": "the EIP-155 spec example gas price (hex)",
        "kEthValue": "the EIP-155 spec example value (hex)",
        "kEth1559MaxPrio": "a chosen EIP-1559 max priority fee (hex)",
        "kEth1559MaxFee": "a chosen EIP-1559 max fee (hex)",
        "kEth1559Value": "a chosen EIP-1559 value (hex)",
    }
    uncovered = sorted(set(k) - checked - set(inputs))
    if uncovered:
        problems.append(
            "these harness constants are neither re-derived nor listed as inputs, "
            "so nothing here would notice if one drifted:\n      "
            + "\n      ".join(uncovered)
            + "\n      Add a want(...) for each, or add it to `inputs` with the "
              "reason it cannot be derived.")
    stale = sorted(set(inputs) - set(k))
    if stale:
        problems.append("these names are listed as inputs but no longer exist in "
                        "the harness: " + ", ".join(stale))

    for note in notes:
        print(f"  note: {note}")

    if problems:
        print("check-selftest-vectors: FAILED")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"check-selftest-vectors: OK ({len(checked)} of {len(k)} harness "
          f"constant(s) re-derived, {len(inputs)} are inputs)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
