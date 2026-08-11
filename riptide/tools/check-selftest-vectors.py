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
    out = {}
    rx = re.compile(r'^constant (k\w+) = "([^"]*)"\s*$')
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            m = rx.match(line)
            if m:
                out[m.group(1)] = m.group(2)
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

    # structural claims, not just digests: the records really chain, and the
    # head really names the newest post
    if post2[12:52] != post1_target.encode("ascii"):
        failures.append("post 2 does not chain to post 1's target")
    if head[20:60] != post2_target.encode("ascii"):
        failures.append("the head does not name post 2 as latest")
    if len(head) > 1000 or len(post1) > 1000 or len(post2) > 1000:
        failures.append("a golden record exceeds the BEP44 1000-byte cap")

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
