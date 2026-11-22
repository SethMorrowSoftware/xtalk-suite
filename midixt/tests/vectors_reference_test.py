#!/usr/bin/env python3
"""Independent reference check of midixt's wire-format vectors (tests/vectors/).

tests/vectors/midi.json is the ONE source of truth for the MIDI bytes midixt
decodes (midiDecode, midiPoll) and its convenience senders produce. The same
vectors are asserted by two implementations that share no code:

  * this file -- a clean-room MIDI 1.0 codec written from the specification
    (tools/sim/refcodec.py);
  * the LCB binding, running headlessly under lc-run -- tools/run-lcb-tests.py
    generates a test module from the same JSON (tools/gen_vectors.py), and the
    encoders' bytes are read back from the MOCK library's sent log.

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
from refcodec import midi_decode, midi_encode   # noqa: E402 -- the clean-room codec


def test_midi(v):
    print("MIDI")
    for vec in v["decode"]:
        got = midi_decode(bytes.fromhex(vec["hex"]))
        want = {k: vec[k] for k in ("kind", "channel", "data1", "data2", "value14") if k in vec}
        check("midi decode: " + vec["name"], all(got.get(k) == w for k, w in want.items()),
              "got %r" % got)
    for vec in v["encode"]:
        got = midi_encode(vec["call"], vec["channel"], vec.get("a", 0), vec.get("b", 0)).hex()
        check("midi encode: " + vec["name"], got == vec["hex"], "got " + got)


def main():
    midi = json.loads((VEC / "midi.json").read_text(encoding="utf-8"))
    test_midi(midi)
    print("\nvectors reference: %d passed, %d failed" % (PASSES, len(FAILS)))
    # A floor: a refactor that silently stops reading most vectors cannot print OK.
    floor = 30
    if PASSES < floor:
        print("FAIL: only %d checks ran; the floor is %d" % (PASSES, floor))
        return 1
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
