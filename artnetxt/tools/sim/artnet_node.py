#!/usr/bin/env python3
"""A virtual Art-Net node: test Art-Net output with NO lighting hardware.

It answers ArtPoll discovery with an ArtPollReply (one DMX output port, on the
universe it is given) and records every ArtDmx frame it receives, decoding both
with the clean-room codec (tools/sim/refcodec.py) -- an implementation that
shares no code with artnetxt, so a frame it accepts is a frame a real node
would accept (OpCode little-endian, ProtVer/Length big-endian, SubUni before
Net, an even Length from 2 to 512).

Hand testing -- run it, then point your OXT stack at it:

    python3 tools/sim/artnet_node.py                 # listens on 0.0.0.0:6454
    python3 tools/sim/artnet_node.py --port 16454    # a non-privileged test port
    python3 tools/sim/artnet_node.py --universe 5    # its output port uses universe 5
    python3 tools/sim/artnet_node.py --echo 1        # also echo each frame back
                                                     #   on universe + 1

    -- in OXT:  write artnetBuildDmx(0, tChannels) to socket "127.0.0.1:6454"

Each frame prints as a one-line level meter of the first channels, so a fader
sweep is visible at a glance. Ctrl+C to stop.

A real node sends its ArtPollReply to port 6454 of the computer that asked.
This one answers to the port the ArtPoll came FROM, so a test can listen on any
port; --reply-port 6454 makes it answer like hardware.

As a library (tools/run-lcs-tests.py uses it for the engine interop suite):

    node = ArtNetNode(port=0).start_background()   # port 0 = pick a free port
    ... node.frames, node.polls, node.port ...
    node.stop()

The Art-Net part of ShowControl's tools/sim, carried into artnetxt.
"""

import argparse
import socket
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import refcodec as R  # noqa: E402


class ArtNetNode:
    def __init__(self, host="127.0.0.1", port=6454, short_name="SimNode",
                 long_name="artnetxt virtual Art-Net node", universe=0,
                 echo_offset=None, reply_port=None, verbose=False):
        self.host, self.short_name, self.long_name = host, short_name, long_name
        self.universe, self.echo_offset, self.reply_port = universe, echo_offset, reply_port
        self.verbose = verbose
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((host, port))
        self.sock.settimeout(0.2)
        self.port = self.sock.getsockname()[1]
        self.frames = []        # (universe, sequence, physical, channels: bytes, sender)
        self.polls = []         # sender addresses
        self.rejected = []      # (reason, raw bytes)
        self._stop = threading.Event()
        self._thread = None

    def reply(self):
        """This node's ArtPollReply: one output port on self.universe."""
        u = self.universe
        ip = self.host if self.host != "0.0.0.0" else "127.0.0.1"
        return R.artnet_pollreply(ip, self.short_name, self.long_name, (u >> 8) & 0x7F, (u >> 4) & 0x0F,
                                  node_report="#0001 [%04d] artnetxt virtual node ready" % len(self.polls),
                                  port_types=(0x80, 0, 0, 0), sw_out=(u & 0x0F, 0, 0, 0),
                                  mac="02:00:00:00:00:01", bind_ip=ip)

    # -- protocol --------------------------------------------------------------
    def handle(self, data, addr):
        if not R.is_artnet(data):
            self.rejected.append(("not Art-Net", data))
            return
        op = R.opcode(data)
        if op == R.OP_POLL:
            self.polls.append(addr)
            to = (addr[0], self.reply_port) if self.reply_port else addr
            self.sock.sendto(self.reply(), to)
            self.log("ArtPoll from %s:%d -> ArtPollReply '%s' to port %d" % (addr[0], addr[1], self.short_name, to[1]))
        elif op == R.OP_DMX:
            if len(data) < 18:
                self.rejected.append(("ArtDmx too short", data))
                return
            ver = data[10] * 256 + data[11]
            n = data[16] * 256 + data[17]
            d = R.artnet_dmx_decode(data)
            if ver < R.PROT_VER or n < 2 or n > 512 or n % 2 or d["length"] != n:
                self.rejected.append(("bad ArtDmx header (ver %d, length %d, have %d)"
                                      % (ver, n, len(data) - 18), data))
                return
            self.frames.append((d["universe"], d["sequence"], d["physical"], d["channels"], addr))
            self.log("ArtDmx u%-5d seq %3d len %3d  %s" % (d["universe"], d["sequence"], n, meter(d["channels"])))
            if self.echo_offset is not None:
                self.sock.sendto(R.artnet_dmx((d["universe"] + self.echo_offset) % 32768, d["channels"]), addr)
        else:
            self.log("ignored OpCode 0x%04x from %s:%d" % (op, addr[0], addr[1]))

    def log(self, msg):
        if self.verbose:
            print(msg, flush=True)

    # -- lifecycle -------------------------------------------------------------
    def serve_forever(self):
        while not self._stop.is_set():
            try:
                data, addr = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            self.handle(data, addr)

    def start_background(self):
        self._thread = threading.Thread(target=self.serve_forever, daemon=True)
        self._thread.start()
        return self

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)
        self.sock.close()


def meter(chans, width=16):
    """A one-line level meter of the first `width` channels."""
    bars = " .:-=+*#%@"
    return "".join(bars[min(9, c * 10 // 256)] for c in chans[:width]) + ("..." if len(chans) > width else "")


def main():
    ap = argparse.ArgumentParser(description="Virtual Art-Net node (no hardware needed).")
    ap.add_argument("--bind", default="0.0.0.0", help="address to listen on (default all)")
    ap.add_argument("--port", type=int, default=6454, help="UDP port (Art-Net is 6454)")
    ap.add_argument("--name", default="SimNode", help="ShortName in ArtPollReply")
    ap.add_argument("--universe", type=int, default=0, help="the universe of its one output port (0..32767)")
    ap.add_argument("--reply-port", type=int, help="answer ArtPoll to this port (hardware uses 6454)")
    ap.add_argument("--echo", type=int, metavar="OFFSET",
                    help="echo every ArtDmx back to the sender on universe + OFFSET")
    a = ap.parse_args()
    if not 0 <= a.universe <= 32767:
        ap.error("--universe must be 0..32767")
    node = ArtNetNode(a.bind, a.port, a.name, universe=a.universe, echo_offset=a.echo,
                      reply_port=a.reply_port, verbose=True)
    print("virtual Art-Net node '%s' (universe %d) listening on %s:%d (Ctrl+C to stop)"
          % (a.name, a.universe, a.bind, node.port), flush=True)
    try:
        node.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        print("\n%d frame(s), %d poll(s), %d rejected" % (len(node.frames), len(node.polls), len(node.rejected)))
        for why, raw in node.rejected[:10]:
            print("  rejected: %s  %s" % (why, raw[:24].hex()))
        node.stop()


if __name__ == "__main__":
    main()
