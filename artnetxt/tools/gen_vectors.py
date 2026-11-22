#!/usr/bin/env python3
"""Generate test code from artnetxt's wire-format vectors, tests/vectors/artnet.json.

The JSON file is the single source of truth (see tests/vectors_reference_test.py,
which proves every vector against a clean-room Art-Net 4 codec). This tool
projects it into the LCB test suite: a test module
(org.openxtalk.showcontrol.tests.vectors), generated into the build dir at test
time by tools/run-lcb-tests.py, never committed, so it can never be stale. It
builds every `dmx` and `poll` vector with the binding and compares the bytes,
reads every `dmx` and `pollreply` vector back field by field, and checks that
every `reject` and `pollreply_reject` vector is refused with a reason.

(oscxt's copy of this tool also writes a committed C header; Art-Net has no C
code, so here `--check` only proves the vectors project cleanly.)

Usage:
    python3 tools/gen_vectors.py --check     # exit 1 if the vectors cannot be projected
    python3 tools/gen_vectors.py --lcb OUT   # write the LCB vectors module to OUT
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VEC = ROOT / "tests" / "vectors"

# Every key a pollreply vector must carry: a vector that forgets one would
# silently assert less than the reader of the JSON assumes.
REPLY_KEYS = ("ip", "shortName", "longName", "net", "subuni", "port", "version", "nodeReport",
              "outputUniverses", "inputUniverses", "style", "mac", "bindIndex", "hex")


def load():
    return {k: json.loads((VEC / (k + ".json")).read_text(encoding="utf-8"))
            for k in ("artnet",)}


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _ascii_check(s, what):
    if any(ord(c) > 126 or ord(c) < 32 for c in s):
        raise SystemExit("gen_vectors: %s must be printable ASCII (got %r)" % (what, s))
    return s


def lcb_str(s):
    """An LCB string literal. Vectors are printable ASCII without double quotes
    (LCB literals have no portable escape on the 9.6.3 floor)."""
    _ascii_check(s, "an LCB string literal")
    if '"' in s:
        raise SystemExit("gen_vectors: a double quote cannot appear in an LCB literal: %r" % s)
    return '"' + s + '"'


def tap_desc(s):
    """A test description safe for TAP: no '#' (directive), no double quote."""
    return lcb_str(_ascii_check(s, "a vector name").replace("#", "no.").replace('"', "'"))


def lcb_list_test(var, key, want, desc):
    """Element-by-element assertions for a List field (an LCB list `is` compare
    would hide WHICH element differs)."""
    L = ["   test %s when the number of elements in %s[%s] is %d" % (
        tap_desc(desc + " count"), var, lcb_str(key), len(want))]
    for i, x in enumerate(want):
        L.append("   test %s when element %d of %s[%s] is %d" % (
            tap_desc("%s %d" % (desc, i + 1)), i + 1, var, lcb_str(key), x))
    return L


# ---------------------------------------------------------------------------
# LCB module
# ---------------------------------------------------------------------------

def lcb_artnet(v, L):
    L.append("public handler TestArtnetDmxVectors()")
    L.append("   variable tData as Data")
    L.append("   variable tP as Array")
    for d in v["dmx"]:
        nm = d["name"]
        if "sequence" not in d:     # artnetBuildDmx always sends sequence/physical 0
            L.append("   put artnetBuildDmx(%d, HexToData(%s)) into tData" % (d["universe"], lcb_str(d["channels"])))
            L.append("   test %s when DataToHex(tData) is %s" % (tap_desc("artnet dmx bytes: " + nm), lcb_str(d["hex"])))
        L.append("   put artnetParseDmx(HexToData(%s)) into tP" % lcb_str(d["hex"]))
        L.append("   test %s when tP[\"opcode\"] is \"ArtDmx\"" % tap_desc("artnet parse opcode: " + nm))
        L.append("   test %s when tP[\"universe\"] is %d" % (tap_desc("artnet parse universe: " + nm), d["universe"]))
        L.append("   test %s when tP[\"subuni\"] is %d and tP[\"net\"] is %d" % (
            tap_desc("artnet parse subuni/net: " + nm), d["universe"] % 256, (d["universe"] // 256) % 128))
        L.append("   test %s when tP[\"length\"] is %d" % (tap_desc("artnet parse length: " + nm), d["length"]))
        L.append("   test %s when tP[\"sequence\"] is %d and tP[\"physical\"] is %d" % (
            tap_desc("artnet parse sequence/physical: " + nm), d.get("sequence", 0), d.get("physical", 0)))
        L.append("   test %s when DataToHex(tP[\"channels\"]) is %s" % (
            tap_desc("artnet parse channel data: " + nm), lcb_str(d["hex"][36:])))
    L.append("end handler\n")

    L.append("public handler TestArtnetPollVectors()")
    for p in v["poll"]:
        L.append("   test %s when DataToHex(artnetBuildPoll()) is %s" % (tap_desc("artnet poll bytes: " + p["name"]), lcb_str(p["hex"])))
    L.append("end handler\n")

    L.append("public handler TestArtnetPollReplyVectors()")
    L.append("   variable tR as Array")
    for r in v["pollreply"]:
        missing = [k for k in REPLY_KEYS if k not in r]
        if missing:
            raise SystemExit("gen_vectors: pollreply vector %r lacks %s" % (r["name"], ", ".join(missing)))
        nm = r["name"]
        L.append("   put artnetParseReply(HexToData(%s)) into tR" % lcb_str(r["hex"]))
        L.append("   test %s when tR[\"opcode\"] is \"ArtPollReply\"" % tap_desc("artnet reply opcode: " + nm))
        for k in ("ip", "shortName", "longName", "nodeReport", "mac"):
            L.append("   test %s when tR[%s] is %s" % (tap_desc("artnet reply %s: %s" % (k, nm)), lcb_str(k), lcb_str(r[k])))
        for k in ("net", "subuni", "port", "version", "style", "bindIndex"):
            L.append("   test %s when tR[%s] is %d" % (tap_desc("artnet reply %s: %s" % (k, nm)), lcb_str(k), r[k]))
        for k in ("outputUniverses", "inputUniverses"):
            L.extend(lcb_list_test("tR", k, r[k], "artnet reply %s: %s" % (k, nm)))
    L.append("end handler\n")

    L.append("public handler TestArtnetRejectVectors()")
    L.append("   variable tP as Array")
    for r in v["reject"]:
        L.append("   put artnetParseDmx(HexToData(%s)) into tP" % lcb_str(r["hex"]))
        L.append("   test %s when tP[\"opcode\"] is \"\" and artnetLastError() is not \"\"" % (
            tap_desc("artnet parse rejects: " + r["name"])))
    for r in v["pollreply_reject"]:
        L.append("   put artnetParseReply(HexToData(%s)) into tP" % lcb_str(r["hex"]))
        L.append("   test %s when tP[\"opcode\"] is \"\" and artnetLastError() is not \"\"" % (
            tap_desc("artnet reply rejects: " + r["name"])))
    L.append("end handler\n")


def lcb_module():
    v = load()
    L = [
        "/*",
        "GENERATED by tools/gen_vectors.py from tests/vectors/artnet.json -- do not edit.",
        "The shared wire-format vectors, asserted through the real LCB binding under",
        "lc-run (the same vectors the Python reference asserts).",
        "*/",
        "-- requires:",
        "",
        "module org.openxtalk.showcontrol.tests.vectors",
        "",
        "use com.livecode.unittest",
        "use org.openxtalk.library.artnet",
        "use org.openxtalk.showcontrol.tests.support",
        "",
    ]
    lcb_artnet(v["artnet"], L)
    L.append("end module")
    return "\n".join(L) + "\n"


def write_lcb_module(path):
    Path(path).write_text(lcb_module(), encoding="utf-8", newline="\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true", help="fail if the vectors cannot be projected")
    g.add_argument("--lcb", metavar="OUT", help="write the LCB vectors test module to OUT")
    a = ap.parse_args()
    if a.lcb:
        write_lcb_module(a.lcb)
        print("wrote " + a.lcb)
        return 0
    n = lcb_module().count("\n   test ")
    print("gen_vectors: tests/vectors/artnet.json projects to %d LCB assertion(s)" % n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
