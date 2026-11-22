#!/usr/bin/env python3
"""Independent reference check of artnetxt's wire-format vectors (tests/vectors/).

tests/vectors/artnet.json is the ONE source of truth for the Art-Net bytes
artnetxt builds (artnetBuildDmx, artnetBuildPoll) and reads (artnetParseDmx,
artnetParseReply). The same vectors are asserted by two implementations that
share no code:

  * this file -- a clean-room Art-Net 4 codec written from the specification
    (tools/sim/refcodec.py);
  * the LCB binding, running headlessly under lc-run -- tools/run-lcb-tests.py
    generates a test module from the same JSON (tools/gen_vectors.py).

So a vector that is wrong fails here, and a binding that drifts from a correct
vector fails in its own suite.

Run:  python3 tests/vectors_reference_test.py
"""

import json
import sys
from pathlib import Path

VEC = Path(__file__).resolve().parent / "vectors"

FAILS = []
PASSES = 0


def check(name, ok, detail=""):
    global PASSES
    if ok:
        PASSES += 1
    else:
        FAILS.append(name + (("  -- " + detail) if detail else ""))
        print("  [FAIL] " + name + (("  -- " + detail) if detail else ""))


sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools" / "sim"))
import refcodec as R   # noqa: E402 -- the clean-room codec

REPLY_FIELDS = ("ip", "port", "version", "net", "subuni", "shortName", "longName", "nodeReport",
                "outputUniverses", "inputUniverses", "style", "mac", "bindIndex")


def test_artnet(v):
    print("Art-Net")
    for vec in v["dmx"]:
        built = R.artnet_dmx(vec["universe"], bytes.fromhex(vec["channels"]),
                             vec.get("sequence", 0), vec.get("physical", 0)).hex()
        check("artnet dmx: " + vec["name"], built == vec["hex"], "got " + built[:80])
        d = R.artnet_dmx_decode(bytes.fromhex(vec["hex"]))
        check("artnet dmx decodes: " + vec["name"], d is not None)
        if d is None:
            continue
        check("artnet dmx universe: " + vec["name"], d["universe"] == vec["universe"])
        check("artnet dmx length: " + vec["name"], d["length"] == vec["length"])
        check("artnet dmx sequence/physical: " + vec["name"],
              (d["sequence"], d["physical"]) == (vec.get("sequence", 0), vec.get("physical", 0)))
        check("artnet dmx channels: " + vec["name"], d["channels"].hex() == vec["hex"][36:])
    for vec in v["poll"]:
        check("artnet poll: " + vec["name"], R.artnet_poll().hex() == vec["hex"])
    for vec in v["pollreply"]:
        r = R.artnet_pollreply_decode(bytes.fromhex(vec["hex"]))
        check("artnet pollreply decodes: " + vec["name"], r is not None)
        if r is None:
            continue
        for k in REPLY_FIELDS:
            check("artnet pollreply %s: %s" % (k, vec["name"]), r[k] == vec[k],
                  "codec %r, vector %r" % (r[k], vec[k]))
    # The original replies were built with only the five fields ShowControl
    # read: rebuilding them from those must give the same bytes.
    for vec in v["pollreply"]:
        if vec["outputUniverses"] or vec["inputUniverses"] or vec["nodeReport"] or vec["bindIndex"]:
            continue
        if vec["mac"] != "00:00:00:00:00:00" or vec["style"] or len(vec["hex"]) != 2 * R.POLLREPLY_LEN:
            continue
        built = R.artnet_pollreply(vec["ip"], vec["shortName"], vec["longName"], vec["net"], vec["subuni"]).hex()
        check("artnet pollreply rebuilds: " + vec["name"], built == vec["hex"], "got " + built[:80])
    for vec in v["reject"]:
        check("artnet reject is not an ArtDmx: " + vec["name"],
              R.artnet_dmx_decode(bytes.fromhex(vec["hex"])) is None)
    for vec in v["pollreply_reject"]:
        check("artnet reject is not an ArtPollReply: " + vec["name"],
              R.artnet_pollreply_decode(bytes.fromhex(vec["hex"])) is None)


def main():
    art = json.loads((VEC / "artnet.json").read_text(encoding="utf-8"))
    test_artnet(art)
    print("\nvectors reference: %d passed, %d failed" % (PASSES, len(FAILS)))
    # A floor: a refactor that silently stops reading most vectors cannot print OK.
    floor = 120
    if PASSES < floor:
        print("FAIL: only %d checks ran; the floor is %d" % (PASSES, floor))
        return 1
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
