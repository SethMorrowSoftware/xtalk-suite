#!/usr/bin/env python3
# check-selftest-vectors.py - proves every golden constant in
# tests/riptide-selftest.livecodescript against tools/riptide_reference.py.
#
# The harness constants are hand-copied literals, which is exactly the kind
# of thing that drifts: a transcription slip would make the on-engine harness
# fail (or worse, pass) for reasons that have nothing to do with the library.
# This gate re-derives every derived constant from the oracle and refuses on
# any difference.
#
# THE HONEST COUNT (the coinxt lesson, carried verbatim): the gate FAILS on
# any k* constant that is neither re-derived nor listed as an input with a
# written reason, and FAILS on an input entry whose constant no longer
# exists. A gate that overstates its own coverage is worse than none,
# because it answers the question nobody re-asks.
#
# The oracle is exec-loaded from source, never imported: importlib consults
# __pycache__, and a gate whose whole job is to catch drift must not have a
# stale-cache path.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.join(HERE, "..", "tests", "riptide-selftest.livecodescript")
ORACLE = os.path.join(HERE, "riptide_reference.py")


def load_constants(path):
    # Every golden lives in ONE spelling: a single-line, double-quoted
    # `constant kX = "..."` at column 0. The honest count below can only
    # cover what this parse SEES, so a k* constant in any other spelling
    # (indented, unquoted, a continuation line) would bypass the
    # uncovered-constants enforcement silently - the exact
    # parsed-vs-checked hole the header refuses. So any `constant k` line
    # the regex cannot decompose is a LOUD failure, never a skip.
    out = {}
    rx = re.compile(r'^constant (k\w+) = "([^"]*)"\s*$')
    undecomposable = []
    with open(path, "r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            m = rx.match(line)
            if m:
                out[m.group(1)] = m.group(2)
            elif line.strip().startswith("constant k"):
                undecomposable.append("%s:%d: %s"
                                      % (path, lineno, line.strip()))
    if undecomposable:
        print("check-selftest-vectors: %d k* constant line(s) this gate "
              "cannot decompose - only single-line double-quoted "
              "`constant kX = \"...\"` at column 0 is checkable; rewrite "
              "the constant to that spelling or extend the parse (a "
              "constant the gate cannot read is a constant it cannot "
              "cover):" % len(undecomposable))
        for entry in undecomposable:
            print("  " + entry)
        sys.exit(1)
    return out


def main(argv):
    terse = "--check" in argv
    k = load_constants(HARNESS)
    ref = {}
    with open(ORACLE, "r", encoding="utf-8") as f:
        exec(compile(f.read(), ORACLE, "exec"), ref)

    failures = []
    checked = set()

    def want(name, expected):
        checked.add(name)
        if name not in k:
            failures.append("%s: missing from the harness" % name)
            return
        if k[name] != expected:
            failures.append("%s:\n  harness %s\n  oracle  %s"
                            % (name, k[name], expected))

    # inputs: chosen values, not derivable - each with its reason
    inputs = {
        "kRsGoldMasterHex": "the chosen test master seed (0x42 * 32)",
        "kRsGoldConfSeedHex": "the cross-project conformance seed pinned by "
                              "torrentxt/tests/bep44_golden_test.py",
        "kRsGoldRoomSalt": "a chosen session salt for the roomId vector",
        "kRsGoldPost1Text": "chosen post text",
        "kRsGoldPost2Text": "chosen post text",
        "kRsGoldTs1": "chosen post timestamp",
        "kRsGoldTs2": "chosen post timestamp",
        "kRsGoldHeadSeq": "chosen head sequence number",
        "kRsGoldHeadName": "chosen display name",
        "kRsGoldPrekeyTarget": "a chosen 40-hex placeholder target",
        "kRsGoldProfileTarget": "a chosen 40-hex placeholder target",
        "kRsGoldMediaTarget": "a chosen 40-hex placeholder info-hash",
        "kRsGoldDmTs": "chosen intro timestamp",
        "kRsGoldMsgTs": "chosen DM message timestamp",
        "kRsGoldDmMsgText": "chosen DM message text",
        "kRsGoldLanNonce": "a chosen 32-byte LAN challenge nonce (0x5a * 32)",
        "kRsGoldLanHostName": "chosen LAN host device name",
        "kRsGoldLanJoinName": "chosen LAN joiner device name",
    }
    for name in inputs:
        if name in k:
            checked.add(name)

    # sanity on the inputs the derivations consume, so a mangled input cannot
    # silently re-anchor every downstream vector
    if k.get("kRsGoldMasterHex") != "42" * 32:
        failures.append("kRsGoldMasterHex is not the documented 0x42 * 32")
    for name in ("kRsGoldPrekeyTarget", "kRsGoldProfileTarget",
                 "kRsGoldMediaTarget"):
        v = k.get(name, "")
        if len(v) != 40 or any(c not in "0123456789abcdef" for c in v):
            failures.append("%s is not 40 lowercase hex chars" % name)

    master = bytes.fromhex(k["kRsGoldMasterHex"])
    id_seed = ref["identity_seed"](master)

    want("kRsGoldIdSeedHex", id_seed.hex())
    want("kRsGoldDmSeedHex", ref["dm_seed"](master).hex())
    want("kRsGoldLanKeyHex", ref["lan_key"](master).hex())
    want("kRsGoldAnon0Hex", ref["anon_seed"](master, 0).hex())

    handle = ref["handle_from_identity_seed"](id_seed)
    want("kRsGoldHandle", handle)
    want("kRsGoldZeroSeedPub", ref["ed25519_publickey"](b"\x00" * 32).hex())

    conf_seed = bytes.fromhex(k["kRsGoldConfSeedHex"])
    conf_pub = ref["ed25519_publickey"](conf_seed).hex()
    want("kRsGoldConfPub", conf_pub)

    want("kRsGoldOnion", ref["onion_from_pubkey"](bytes.fromhex(handle)))
    want("kRsGoldInboxId", ref["inbox_id"](handle))
    want("kRsGoldRoomId",
         ref["room_id"](handle, conf_pub,
                        k["kRsGoldRoomSalt"].encode("ascii")))

    post1 = ref["build_post"](int(k["kRsGoldTs1"]), ref["ZERO_TARGET"],
                              k["kRsGoldPost1Text"], [], id_seed)
    want("kRsGoldPost1Hex", post1.hex())
    post1_target = ref["immutable_target"](post1)
    want("kRsGoldPost1Target", post1_target)

    post2 = ref["build_post"](int(k["kRsGoldTs2"]), post1_target,
                              k["kRsGoldPost2Text"],
                              [k["kRsGoldMediaTarget"]], id_seed)
    want("kRsGoldPost2Hex", post2.hex())
    post2_target = ref["immutable_target"](post2)
    want("kRsGoldPost2Target", post2_target)

    head = ref["build_head"](int(k["kRsGoldHeadSeq"]),
                             k["kRsGoldHeadName"], post2_target,
                             k["kRsGoldPrekeyTarget"],
                             k["kRsGoldOnion"],
                             k["kRsGoldProfileTarget"])
    want("kRsGoldHeadHex", head.hex())

    # the phase-2 live layer: the canonical BEP44 buffer the head's put signs
    # (salt "riptide-head", the head's own seq, the bencoded head as v) and
    # the ed25519 signature over it under the identity seed
    head_buf = ref["bep44_signbuf"](ref["HEAD_SALT"].encode("ascii"),
                                    int(k["kRsGoldHeadSeq"]),
                                    ref["bencode_bytes"](head))
    want("kRsGoldHeadBufHex", head_buf.hex())
    want("kRsGoldHeadSigHex", ref["ed25519_sign"](head_buf, id_seed).hex())

    # the phase-4 DM layer: kx keys (anchored against real libsodium in the
    # oracle's self-check), the session pair from the golden (client) side,
    # and the RSK1 / RSI1 / message records
    dm_kx_pk, dm_kx_sk = ref["kx_seed_keypair"](ref["dm_seed"](master))
    conf_kx_pk, _conf_kx_sk = ref["kx_seed_keypair"](conf_seed)
    want("kRsGoldDmKxPub", dm_kx_pk.hex())
    want("kRsGoldConfKxPub", conf_kx_pk.hex())
    sess_rx, sess_tx = ref["kx_client_session_keys"](dm_kx_pk, dm_kx_sk,
                                                     conf_kx_pk)
    want("kRsGoldSessionRx", sess_rx.hex())
    want("kRsGoldSessionTx", sess_tx.hex())
    prekey_rec = ref["build_prekey"](dm_kx_pk.hex(), id_seed)
    want("kRsGoldPrekeyRecHex", prekey_rec.hex())
    want("kRsGoldPrekeyRecTarget", ref["immutable_target"](prekey_rec))
    intro = ref["build_intro"](handle, dm_kx_pk.hex(), conf_pub,
                               int(k["kRsGoldDmTs"]), id_seed)
    want("kRsGoldIntroHex", intro.hex())
    want("kRsGoldDmMsgHex", ref["build_dm_message"](
        b"T", int(k["kRsGoldMsgTs"]), k["kRsGoldDmMsgText"]).hex())

    # structural claims, not just digests: the records really chain, and the
    # head really names the newest post
    if post2[12:52] != post1_target.encode("ascii"):
        failures.append("post 2 does not chain to post 1's target")
    if head[20:60] != post2_target.encode("ascii"):
        failures.append("the head does not name post 2 as latest")
    if len(head) > 1000 or len(post1) > 1000 or len(post2) > 1000:
        failures.append("a golden record exceeds the BEP44 1000-byte cap")
    if intro[4:68] != handle.encode("ascii"):
        failures.append("the golden intro's sender is not the golden handle")
    if intro[132:196] != conf_pub.encode("ascii"):
        failures.append("the golden intro is not addressed to the "
                        "conformance identity")

    # the phase-6 LAN admission: the mesh public, and the challenge/response
    # made deterministic by a fixed nonce
    lan_pub, _lan_seed = ref["lan_keys"](master)
    want("kRsGoldLanPub", lan_pub.hex())
    lan_nonce = bytes.fromhex(k["kRsGoldLanNonce"])
    challenge = ref["lan_build_challenge"](k["kRsGoldLanHostName"], lan_nonce)
    want("kRsGoldLanChallengeHex", challenge.hex())
    response = ref["lan_build_response"](challenge, k["kRsGoldLanJoinName"],
                                         master)
    want("kRsGoldLanResponseHex", response.hex())
    want("kRsGoldLanWelcomeHex", ref["lan_build_welcome"](
        response, k["kRsGoldLanHostName"], master).hex())
    # the response really verifies under the mesh public (a structural
    # claim, not a digest): a golden that did not verify would be useless
    if not ref["_verify_ed25519"](
            response[-64:],
            ref["lan_sig_message"](lan_nonce, k["kRsGoldLanJoinName"]),
            lan_pub):
        failures.append("the golden LAN response does not verify under the "
                        "mesh public key")

    if k.get("kRsGoldLanNonce") != "5a" * 32:
        failures.append("kRsGoldLanNonce is not the documented 0x5a * 32")

    # the phase-7 anon persona + BTXO framing
    want("kRsGoldAnon0Handle", ref["anon_handle"](master, 0))
    want("kRsGoldAnon0Onion", ref["anon_onion"](master, 0))
    want("kRsGoldAnonDmKxPub", ref["kx_seed_keypair"](
        ref["anon_dm_seed"](master, 0))[0].hex())
    want("kRsGoldBtxoHeaderHex",
         ref["btxo_header"]("secret.txt", 11, 0).hex())
    want("kRsGoldBtxoFrameHex",
         ref["btxo_data_frame"](b"hello world").hex())
    # the anon onion inverts back to the anon handle (self-authenticating)
    if ref["pubkey_from_onion"](k["kRsGoldAnon0Onion"]).hex() != \
            ref["anon_handle"](master, 0):
        failures.append("the golden anon onion does not invert to the anon "
                        "handle")

    # the honest split
    uncovered = sorted(set(k) - checked)
    if uncovered:
        failures.append("constants neither re-derived nor listed as inputs "
                        "(add a derivation or an input reason): "
                        + ", ".join(uncovered))
    stale = sorted(set(inputs) - set(k))
    if stale:
        failures.append("input entries whose constant no longer exists: "
                        + ", ".join(stale))

    derived = len(checked) - len(set(inputs) & set(k))
    if failures:
        print("check-selftest-vectors: %d FAILURE(S)" % len(failures))
        for f in failures:
            print("  " + f)
        return 1
    print("check-selftest-vectors: OK (%d of %d harness constant(s) "
          "re-derived, %d are inputs)"
          % (derived, len(k), len(set(inputs) & set(k))))
    if not terse:
        for name in sorted(k):
            tag = "input  " if name in inputs else "derived"
            print("  %s %s" % (tag, name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
