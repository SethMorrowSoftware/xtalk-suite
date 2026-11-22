#!/usr/bin/env python3
"""Self-test of the virtual OSC peer in tools/sim/ (fixture before gate).

The engine interop suite (tests/lcs/interop_test.livecodescript) trusts
tools/sim/osc_peer.py to behave like real gear. This proves it does, over real
UDP on 127.0.0.1, using only the vectors: the peer must ack every vector message
with exactly the canonical arguments, ack every vector bundle with its timetag
and element count, and NAK every malformed datagram. If the peer were wrong,
the interop suite could pass while lying.

Run:  python3 tests/simulators_test.py
"""

import json
import socket
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "sim"))
import refcodec as R            # noqa: E402
from osc_peer import OscPeer, canonical   # noqa: E402

VEC = ROOT / "tests" / "vectors"
FAILS, PASSES = [], [0]
# A floor: a refactor that silently stops reading most vectors cannot print OK.
FLOOR = 30


def check(name, ok, detail=""):
    if ok:
        PASSES[0] += 1
    else:
        FAILS.append(name)
        print("  [FAIL] %s %s" % (name, detail))


def client():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", 0))
    s.settimeout(2.0)
    return s


def wait_until(pred, secs=2.0):
    end = time.time() + secs
    while time.time() < end:
        if pred():
            return True
        time.sleep(0.01)
    return pred()


def test_osc_peer():
    v = json.loads((VEC / "osc.json").read_text(encoding="utf-8"))
    peer = OscPeer(port=0, ack=True).start_background()
    c = client()
    try:
        for m in v["messages"]:
            c.sendto(bytes.fromhex(m["hex"]), ("127.0.0.1", peer.port))
            ack = R.osc_decode(c.recvfrom(65535)[0])
            tags = "".join(a[0] for a in m["args"])
            ok = ack[1] == "/oscpeer/ack" and ack[3][0] == m["address"] and ack[3][1] == tags
            vals = R.osc_decode(bytes.fromhex(m["hex"]))[3]
            want = [canonical(t, x) for t, x in zip(tags, vals)]
            check("peer acks with address, tags and canonical args: " + m["name"], ok and ack[3][2:] == want,
                  repr(ack[3][:4]))
        for m in v["malformed"]:
            if not m["hex"]:
                continue                     # an empty datagram is not delivered by every stack
            c.sendto(bytes.fromhex(m["hex"]), ("127.0.0.1", peer.port))
            nak = R.osc_decode(c.recvfrom(65535)[0])
            check("peer NAKs malformed: " + m["name"], nak[1] == "/oscpeer/nak")
        for b in v["bundles"]:
            c.sendto(bytes.fromhex(b["hex"]), ("127.0.0.1", peer.port))
            ack = R.osc_decode(c.recvfrom(65535)[0])
            check("peer acks bundle: " + b["name"],
                  ack[1] == "/oscpeer/ack-bundle" and ack[3] == [b["timetag"], len(b["elements"])])
    finally:
        c.close()
        peer.stop()


def main():
    test_osc_peer()
    print("simulators: %d passed, %d failed" % (PASSES[0], len(FAILS)))
    if PASSES[0] < FLOOR:
        print("FAIL: only %d checks ran (floor %d)" % (PASSES[0], FLOOR))
        return 1
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
