#!/usr/bin/env python3
"""Generate test code from oscxt's wire-format vectors, tests/vectors/osc.json.

The JSON file is the single source of truth (see tests/vectors_reference_test.py,
which proves every vector against a clean-room spec encoder and python-osc).
This tool projects it into the two other implementations' test suites:

  * C:   tests/vectors/vectors.h -- COMMITTED, included by tests/osc_vectors_test.c
         (so the C build needs no Python). `--check` fails if it is stale, which
         CI runs, so a vector edit cannot silently skip the C suite.
  * LCB: a test module (org.openxtalk.showcontrol.tests.vectors) -- generated
         into the build dir at test time by tools/run-lcb-tests.py, never
         committed, so it can never be stale.

Usage:
    python3 tools/gen_vectors.py --write     # regenerate tests/vectors/vectors.h
    python3 tools/gen_vectors.py --check     # exit 1 if vectors.h is out of date
    python3 tools/gen_vectors.py --lcb OUT   # write the LCB vectors module to OUT
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VEC = ROOT / "tests" / "vectors"
C_HEADER = VEC / "vectors.h"


def load():
    return {k: json.loads((VEC / (k + ".json")).read_text(encoding="utf-8"))
            for k in ("osc",)}


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


def c_str(s):
    _ascii_check(s, "a C string literal")
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _f(v):
    """A decimal literal LCB parses on every engine (no exponent form)."""
    x = float(v)
    s = repr(x)
    if "e" in s or "E" in s:
        s = "%.17f" % x
    return s


# ---------------------------------------------------------------------------
# LCB module
# ---------------------------------------------------------------------------

def lcb_arg_list(args):
    """The FLAT [type, value, ...] list oscBuildMessage takes."""
    out = []
    for a in args:
        t = a[0]
        out.append(lcb_str(t))
        if t == "b":
            out.append("HexToData(%s)" % lcb_str(a[1]))
        elif t in "TFNI":
            out.append('""')
        else:
            out.append(lcb_str(a[1]))
    return "[" + ", ".join(out) + "]"


def lcb_parse_handler(L, handler, vectors):
    """One handler asserting oscParse of each vector's bytes, arg by arg."""
    L.append("public handler %s()" % handler)
    L.append("   variable tMsg as Array")
    L.append("   variable tArgs as List")
    if not vectors:
        L.append('   test "no vectors in this category" when true')
    for m in vectors:
        nm = m["name"]
        L.append("   put oscParse(HexToData(%s)) into tMsg" % lcb_str(m["hex"]))
        L.append("   test %s when tMsg[\"isBundle\"] is false" % tap_desc("osc parse is a message: " + nm))
        L.append("   test %s when tMsg[\"address\"] is %s" % (tap_desc("osc parse address: " + nm), lcb_str(m["address"])))
        L.append("   test %s when tMsg[\"types\"] is %s" % (tap_desc("osc parse types: " + nm), lcb_str("".join(a[0] for a in m["args"]))))
        L.append("   put tMsg[\"args\"] into tArgs")
        L.append("   test %s when the number of elements in tArgs is %d" % (tap_desc("osc parse arg count: " + nm), len(m["args"])))
        for k, a in enumerate(m["args"], start=1):
            t, desc = a[0], tap_desc("osc parse arg %d (%s): %s" % (k, a[0], nm))
            if t == "i":
                L.append("   test %s when tArgs[%d] is %d" % (desc, k, int(a[1])))
            elif t == "f":
                tol = 1e-6 * max(1.0, abs(float(a[1])))
                L.append("   test %s when NearlyEqual(tArgs[%d], %s, %s)" % (desc, k, _f(a[1]), _f(tol)))
            elif t == "d":
                tol = 1e-12 * max(1.0, abs(float(a[1])))
                L.append("   test %s when NearlyEqual(tArgs[%d], %s, %s)" % (desc, k, _f(a[1]), _f(tol)))
            elif t == "s":
                L.append("   test %s when tArgs[%d] is %s" % (desc, k, lcb_str(a[1])))
            elif t == "b":
                L.append("   test %s when DataToHex(tArgs[%d]) is %s" % (desc, k, lcb_str(a[1])))
            elif t in "ht":
                L.append("   test %s when tArgs[%d] is %s" % (desc, k, lcb_str(str(int(a[1])))))
            elif t == "T":
                L.append("   test %s when tArgs[%d] is true" % (desc, k))
            elif t == "F":
                L.append("   test %s when tArgs[%d] is false" % (desc, k))
            else:   # N / I carry no value
                L.append("   test %s when tArgs[%d] is \"\"" % (desc, k))
    L.append("end handler\n")


def lcb_osc(v, L):
    L.append("public handler TestOscBuildVectors()")
    L.append("   variable tData as Data")
    for m in v["messages"]:
        L.append("   put oscBuildMessage(%s, %s) into tData" % (lcb_str(m["address"]), lcb_arg_list(m["args"])))
        L.append("   test %s when DataToHex(tData) is %s" % (tap_desc("osc build bytes: " + m["name"]), lcb_str(m["hex"])))
        L.append("   if DataToHex(tData) is not %s then" % lcb_str(m["hex"]))
        L.append("      test diagnostic \"  got \" & DataToHex(tData)")
        L.append("   end if")
    L.append("end handler\n")

    lcb_parse_handler(L, "TestOscParseVectors", v["messages"])
    # Datagrams our encoder never produces (hostile padding, ...): parse only.
    lcb_parse_handler(L, "TestOscParseOnlyVectors", v.get("parse_only", []))

    by = {m["name"]: m["hex"] for m in v["messages"]}
    L.append("public handler TestOscBundleVectors()")
    L.append("   variable tElems as List")
    L.append("   variable tData as Data")
    L.append("   variable tB as Array")
    for b in v["bundles"]:
        L.append("   put [] into tElems")
        for e in b["elements"]:
            L.append("   push HexToData(%s) onto tElems" % lcb_str(by.get(e, e)))
        L.append("   put oscBuildBundle(%s, tElems) into tData" % lcb_str(b["timetag"]))
        L.append("   test %s when DataToHex(tData) is %s" % (tap_desc("osc bundle bytes: " + b["name"]), lcb_str(b["hex"])))
        L.append("   put oscParse(HexToData(%s)) into tB" % lcb_str(b["hex"]))
        L.append("   test %s when tB[\"isBundle\"] is true" % tap_desc("osc bundle parses as a bundle: " + b["name"]))
        L.append("   test %s when tB[\"timetag\"] is %s" % (tap_desc("osc bundle timetag: " + b["name"]), lcb_str(b["timetag"])))
        L.append("   test %s when the number of elements in tB[\"messages\"] is %d" % (
            tap_desc("osc bundle element count: " + b["name"]), len(b["elements"])))
    L.append("end handler\n")

    L.append("public handler TestOscMatchVectors()")
    for m in v["matches"]:
        L.append("   test %s when oscMatch(%s, %s) is %s" % (
            tap_desc("osc match %s ~ %s -> %s" % (m["pattern"], m["address"], "yes" if m["match"] else "no")),
            lcb_str(m["pattern"]), lcb_str(m["address"]), "true" if m["match"] else "false"))
    L.append("end handler\n")

    L.append("public handler TestOscMalformedVectors()")
    L.append("   variable tMsg as Array")
    for m in v["malformed"]:
        L.append("   put oscParse(HexToData(%s)) into tMsg" % lcb_str(m["hex"]))
        L.append("   test %s when tMsg[\"address\"] is \"\" and tMsg[\"error\"] is not \"\"" % (
            tap_desc("osc malformed is a clean error: " + m["name"])))
    L.append("end handler\n")


def lcb_module():
    v = load()
    L = [
        "/*",
        "GENERATED by tools/gen_vectors.py from tests/vectors/osc.json -- do not edit.",
        "The shared wire-format vectors, asserted through the real LCB bindings under",
        "lc-run (the same vectors the Python reference and the C tests assert).",
        "*/",
        "-- requires: oscxt",
        "",
        "module org.openxtalk.showcontrol.tests.vectors",
        "",
        "use com.livecode.unittest",
        "use org.openxtalk.library.osc",
        "use org.openxtalk.showcontrol.tests.support",
        "",
    ]
    lcb_osc(v["osc"], L)
    L.append("end module")
    return "\n".join(L) + "\n"


def write_lcb_module(path):
    Path(path).write_text(lcb_module(), encoding="utf-8", newline="\n")


# ---------------------------------------------------------------------------
# C header
# ---------------------------------------------------------------------------

def c_header():
    v = load()["osc"]
    H = [
        "/* GENERATED by tools/gen_vectors.py from tests/vectors/osc.json -- do not edit.",
        " * Regenerate with `python3 tools/gen_vectors.py --write`; CI runs --check.",
        " * Values are decimal strings (blobs: hex), exactly as the LCB binding passes them. */",
        "#ifndef OSCXT_TEST_VECTORS_H",
        "#define OSCXT_TEST_VECTORS_H",
        "",
        "typedef struct { char type; const char *value; } scv_arg;",
        "typedef struct { const char *name; const char *address; int argc; scv_arg args[16]; const char *hex; } scv_osc_msg;",
        "typedef struct { const char *name; const char *timetag; int count; const char *elems[8]; const char *hex; } scv_osc_bundle;",
        "typedef struct { const char *pattern; const char *address; int match; } scv_osc_match;",
        "typedef struct { const char *name; const char *hex; } scv_named_hex;",
        "",
        "static const scv_osc_msg SCV_OSC_MESSAGES[] = {",
    ]
    for m in v["messages"]:
        if len(m["args"]) > 16:
            raise SystemExit("gen_vectors: raise scv_osc_msg.args capacity")
        args = ", ".join("{'%s', %s}" % (a[0], c_str(a[1]) if len(a) > 1 else '""') for a in m["args"])
        H.append("    {%s, %s, %d, {%s}, %s}," % (c_str(m["name"]), c_str(m["address"]), len(m["args"]),
                                                 args if args else "{0, 0}", c_str(m["hex"])))
    H.append("};")
    by = {m["name"]: m["hex"] for m in v["messages"]}
    H.append("/* datagrams our encoder never produces (e.g. hostile padding): parse-only */")
    H.append("static const scv_osc_msg SCV_OSC_PARSE_ONLY[] = {")
    for m in v.get("parse_only", []):
        args = ", ".join("{'%s', %s}" % (a[0], c_str(a[1]) if len(a) > 1 else '""') for a in m["args"])
        H.append("    {%s, %s, %d, {%s}, %s}," % (c_str(m["name"]), c_str(m["address"]), len(m["args"]),
                                                 args if args else "{0, 0}", c_str(m["hex"])))
    H.append("};")
    H.append("static const scv_osc_bundle SCV_OSC_BUNDLES[] = {")
    for b in v["bundles"]:
        if len(b["elements"]) > 8:
            raise SystemExit("gen_vectors: raise scv_osc_bundle.elems capacity")
        el = ", ".join(c_str(by.get(e, e)) for e in b["elements"])
        H.append("    {%s, %s, %d, {%s}, %s}," % (c_str(b["name"]), c_str(b["timetag"]), len(b["elements"]),
                                                 el if el else "0", c_str(b["hex"])))
    H.append("};")
    H.append("static const scv_osc_match SCV_OSC_MATCHES[] = {")
    for m in v["matches"]:
        H.append("    {%s, %s, %d}," % (c_str(m["pattern"]), c_str(m["address"]), 1 if m["match"] else 0))
    H.append("};")
    H.append("static const scv_named_hex SCV_OSC_MALFORMED[] = {")
    for m in v["malformed"]:
        H.append("    {%s, %s}," % (c_str(m["name"]), c_str(m["hex"])))
    H.append("};")
    H += ["",
          "#define SCV_COUNT(a) ((int)(sizeof(a) / sizeof((a)[0])))",
          "",
          "#endif /* OSCXT_TEST_VECTORS_H */", ""]
    return "\n".join(H)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--write", action="store_true", help="regenerate tests/vectors/vectors.h")
    g.add_argument("--check", action="store_true", help="fail if tests/vectors/vectors.h is stale")
    g.add_argument("--lcb", metavar="OUT", help="write the LCB vectors test module to OUT")
    g.add_argument("--corpus", metavar="DIR", help="write every OSC vector as a libFuzzer seed file into DIR")
    a = ap.parse_args()
    if a.corpus:
        v = load()["osc"]
        out = Path(a.corpus)
        out.mkdir(parents=True, exist_ok=True)
        n = 0
        for cat in ("messages", "bundles", "malformed", "parse_only"):
            for i, m in enumerate(v.get(cat, [])):
                (out / ("%s-%02d.bin" % (cat, i))).write_bytes(bytes.fromhex(m["hex"]))
                n += 1
        print("wrote %d seed file(s) to %s" % (n, out))
        return 0
    if a.lcb:
        write_lcb_module(a.lcb)
        print("wrote " + a.lcb)
        return 0
    want = c_header()
    if a.write:
        C_HEADER.write_text(want, encoding="utf-8", newline="\n")
        print("wrote " + str(C_HEADER.relative_to(ROOT)))
        return 0
    have = C_HEADER.read_text(encoding="utf-8") if C_HEADER.is_file() else ""
    if have.replace("\r\n", "\n") != want:
        print("gen_vectors: tests/vectors/vectors.h is STALE -- run `python3 tools/gen_vectors.py --write`")
        return 1
    print("gen_vectors: tests/vectors/vectors.h is fresh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
