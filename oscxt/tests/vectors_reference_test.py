#!/usr/bin/env python3
"""Independent reference check of the OSC wire-format vectors (tests/vectors/).

tests/vectors/osc.json is the ONE source of truth for oscxt's wire format. The
same vectors are asserted by three implementations that share no code:

  * this file -- a clean-room Python encoder/decoder written from the OSC 1.0
    specification (tools/sim/refcodec.py), plus an optional cross-check
    against the third-party python-osc package;
  * the C smoke tests -- through tests/vectors/vectors.h, generated from the
    JSON by tools/gen_vectors.py (and gated fresh by `gen_vectors.py --check`);
  * the LCB binding, running headlessly under lc-run -- tools/run-lcb-tests.py
    generates a test module from the same JSON.

So a vector that is wrong fails here, and an implementation that drifts from a
correct vector fails in its own suite. The two OSC 1.0 specification examples
are transcribed byte-for-byte from the spec itself, so at least those goldens do
not depend on any implementation in this repository.

Run:  python3 tests/vectors_reference_test.py
      OSCXT_REQUIRE_PYTHONOSC=1 makes a missing python-osc a failure (CI).
"""

import json
import os
import struct
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
from refcodec import *            # noqa: E402,F401,F403 -- the clean-room codecs
from refcodec import _close        # noqa: E402


def test_osc(v):
    print("OSC")
    by_name = {}
    for vec in v["messages"]:
        args = vec["args"]
        built = osc_encode_message(vec["address"], args).hex()
        check("osc build: " + vec["name"], built == vec["hex"], "got " + built)
        kind, addr, tags, vals = osc_decode(bytes.fromhex(vec["hex"]))
        check("osc parse address: " + vec["name"], addr == vec["address"])
        check("osc parse tags: " + vec["name"], tags == "".join(a[0] for a in args))
        for k, a in enumerate(args):
            if a[0] in "TFNI":
                continue
            check("osc parse arg %d: %s" % (k + 1, vec["name"]), osc_values_equal(a[0], vals[k], a[1]),
                  "got %r want %r" % (vals[k], a[1]))
        by_name[vec["name"]] = bytes.fromhex(vec["hex"])
    # Parse-only vectors: datagrams our encoder never emits (e.g. a ',' hidden in
    # the address padding -- the fuzz crash). The reference must read them by the
    # spec's layout, exactly as the shim now does.
    for vec in v.get("parse_only", []):
        kind, addr, tags, vals = osc_decode(bytes.fromhex(vec["hex"]))
        check("osc parse-only address: " + vec["name"], addr == vec["address"])
        check("osc parse-only tags: " + vec["name"], tags == vec["types"])
        for k, a in enumerate(vec["args"]):
            if a[0] in "TFNI":
                continue
            check("osc parse-only arg %d: %s" % (k + 1, vec["name"]), osc_values_equal(a[0], vals[k], a[1]),
                  "got %r want %r" % (vals[k], a[1]))
    for vec in v["bundles"]:
        elems = [by_name[n] if n in by_name else bytes.fromhex(n) for n in vec["elements"]]
        built = osc_encode_bundle(vec["timetag"], elems).hex()
        check("osc bundle build: " + vec["name"], built == vec["hex"], "got " + built)
        d = osc_decode(bytes.fromhex(vec["hex"]))
        check("osc bundle parse: " + vec["name"], d[0] == "bundle" and str(d[1]) == vec["timetag"]
              and len(d[2]) == len(elems))
    for vec in v["matches"]:
        check("osc match %s ~ %s" % (vec["pattern"], vec["address"]),
              osc_match(vec["pattern"], vec["address"]) == vec["match"])
    for vec in v["malformed"]:
        try:
            osc_decode(bytes.fromhex(vec["hex"]))
            check("osc malformed rejected: " + vec["name"], False, "reference decoder accepted it")
        except (Malformed, struct.error, UnicodeDecodeError, IndexError):
            check("osc malformed rejected: " + vec["name"], True)


def cross_check_python_osc(v):
    """Third-party cross-check: python-osc must build the same bytes and parse ours."""
    try:
        from pythonosc.osc_message_builder import OscMessageBuilder
        from pythonosc.osc_message import OscMessage
    except ImportError:
        msg = "python-osc not installed -- third-party OSC cross-check SKIPPED (pip install python-osc)"
        if os.environ.get("OSCXT_REQUIRE_PYTHONOSC") == "1":
            check("python-osc available", False, msg)
        else:
            print("  [SKIP] " + msg)
        return
    print("OSC cross-check vs python-osc")
    supported = set("ifdsbTFNh")
    for vec in v["messages"]:
        if not set(a[0] for a in vec["args"]) <= supported:
            continue
        # python-osc refuses a zero-length blob ("Blob value cannot be empty"),
        # which OSC 1.0 permits (int32 size 0, no data) -- its limitation, not
        # ours; those vectors are still pinned by the clean-room reference above.
        if any(a[0] == "b" and a[1] == "" for a in vec["args"]):
            continue
        b = OscMessageBuilder(address=vec["address"])
        for a in vec["args"]:
            t = a[0]
            val = None
            if t == "i" or t == "h":
                val = int(a[1])
            elif t in "fd":
                val = float(a[1])
            elif t == "s":
                val = a[1]
            elif t == "b":
                val = bytes.fromhex(a[1])
            elif t in "TF":
                val = (t == "T")
            b.add_arg(val, arg_type=t)
        try:
            got = b.build().dgram.hex()
        except Exception as e:  # noqa: BLE001
            check("python-osc builds: " + vec["name"], False, repr(e))
            continue
        check("python-osc bytes == vector: " + vec["name"], got == vec["hex"], "python-osc " + got)
        parsed = OscMessage(bytes.fromhex(vec["hex"]))
        check("python-osc parses vector: " + vec["name"], parsed.address == vec["address"])
    for vec in v.get("parse_only", []):
        parsed = OscMessage(bytes.fromhex(vec["hex"]))
        check("python-osc reads parse-only vector the same way: " + vec["name"],
              # python-osc drops the 'I' (impulse) tag ("Unhandled parameter type")
              parsed.address == vec["address"]
              and len(parsed.params) == len([x for x in vec["args"] if x[0] != "I"]),
              "%r %r" % (parsed.address, parsed.params))


def main():
    osc = json.loads((VEC / "osc.json").read_text(encoding="utf-8"))
    test_osc(osc)
    cross_check_python_osc(osc)
    print("\nvectors reference: %d passed, %d failed" % (PASSES, len(FAILS)))
    # A floor: a refactor that silently stops reading most vectors cannot print OK.
    floor = 150
    if PASSES < floor:
        print("FAIL: only %d checks ran; the floor is %d" % (PASSES, floor))
        return 1
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
