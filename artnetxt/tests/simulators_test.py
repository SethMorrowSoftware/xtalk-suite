#!/usr/bin/env python3
"""Self-test of the virtual Art-Net node in tools/sim/ (fixture before gate).

The engine interop suite (tests/lcs/interop_test.livecodescript) trusts
tools/sim/artnet_node.py to behave like real gear. This proves it does, over
real UDP on 127.0.0.1, using only the vectors and the clean-room codec: the
node must answer ArtPoll with an ArtPollReply that decodes to its own name and
universe, accept every vector ArtDmx, refuse every reject vector, and echo on
universe + 1 when asked. If the node were wrong, the interop suite could pass
while lying.

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
from artnet_node import ArtNetNode   # noqa: E402

VEC = ROOT / "tests" / "vectors"
FAILS, PASSES = [], [0]


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


def test_artnet_node():
    v = json.loads((VEC / "artnet.json").read_text(encoding="utf-8"))
    node = ArtNetNode(port=0, short_name="Node", long_name="artnetxt test node", universe=291).start_background()
    c = client()
    try:
        c.sendto(R.artnet_poll(), ("127.0.0.1", node.port))
        reply, _ = c.recvfrom(65535)
        r = R.artnet_pollreply_decode(reply)
        check("node answers ArtPoll with an ArtPollReply", r is not None, reply[:16].hex())
        check("the reply is the full Art-Net 4 length", len(reply) == R.POLLREPLY_LEN, str(len(reply)))
        if r:
            check("reply names the node", (r["shortName"], r["longName"]) == ("Node", "artnetxt test node"))
            check("reply carries 127.0.0.1 and port 6454", (r["ip"], r["port"]) == ("127.0.0.1", 6454))
            check("reply's one output port is on the node's universe", r["outputUniverses"] == [291],
                  repr(r["outputUniverses"]))
            check("reply has no input ports", r["inputUniverses"] == [])
        for d in v["dmx"]:
            c.sendto(bytes.fromhex(d["hex"]), ("127.0.0.1", node.port))
        check("node records every vector ArtDmx", wait_until(lambda: len(node.frames) == len(v["dmx"])),
              "%d of %d" % (len(node.frames), len(v["dmx"])))
        for d, f in zip(v["dmx"], node.frames):
            check("node decodes universe: " + d["name"], f[0] == d["universe"])
            check("node decodes channels: " + d["name"], f[3].hex() == d["hex"][36:])
        before = len(node.frames)
        for r in v["reject"]:
            if r["hex"]:
                c.sendto(bytes.fromhex(r["hex"]), ("127.0.0.1", node.port))
        time.sleep(0.3)
        check("node accepts none of the reject vectors", len(node.frames) == before)
        # (an ArtPoll among the rejects is answered, not refused: it is not an ArtDmx)
        refused = [r for r in v["reject"] if r["hex"] and R.opcode(bytes.fromhex(r["hex"])) != R.OP_POLL]
        check("node says why for each", len(node.rejected) == len(refused), repr(node.rejected))
    finally:
        c.close()
        node.stop()

    echo = ArtNetNode(port=0, echo_offset=1).start_background()
    c = client()
    try:
        c.sendto(R.artnet_dmx(7, b"\x10\x20"), ("127.0.0.1", echo.port))
        back, _ = c.recvfrom(65535)
        check("echo mode returns the frame on universe + 1", back == R.artnet_dmx(8, b"\x10\x20"))
    finally:
        c.close()
        echo.stop()

    # --reply-port: answer to a fixed port, as hardware answers to 6454.
    listener = client()
    hw = ArtNetNode(port=0, reply_port=listener.getsockname()[1]).start_background()
    c = client()
    try:
        c.sendto(R.artnet_poll(), ("127.0.0.1", hw.port))
        reply, _ = listener.recvfrom(65535)
        check("reply-port mode answers to the fixed port", R.opcode(reply) == R.OP_POLLREPLY)
        c.settimeout(0.3)
        try:
            c.recvfrom(65535)
            check("reply-port mode does not answer the sender's port", False)
        except socket.timeout:
            check("reply-port mode does not answer the sender's port", True)
    finally:
        c.close()
        listener.close()
        hw.stop()


def main():
    test_artnet_node()
    print("simulators: %d passed, %d failed" % (PASSES[0], len(FAILS)))
    if PASSES[0] < 25:
        print("FAIL: only %d checks ran (floor 25)" % PASSES[0])
        return 1
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
