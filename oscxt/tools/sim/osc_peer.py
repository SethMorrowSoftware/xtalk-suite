#!/usr/bin/env python3
"""A virtual OSC peer: test OSC send/receive with NO controller, DAW or app.

It decodes every datagram with the clean-room codec (tools/sim/refcodec.py, which
shares no code with oscxt), prints it, and -- with --ack -- replies to the
sender with what IT understood:

    /oscpeer/ack  ,s s s ...   address, type tags, then each argument
                                   rendered canonically as a string
    /oscpeer/ack-bundle ,s i   timetag, element count
    /oscpeer/nak  ,s           why the datagram was rejected

so a test (or you) can check that an independent implementation read exactly
what oscxt meant to send. Canonical renderings: ints and int64/timetags in
decimal, floats as the float32 value with 6 significant digits ("%.6g"),
doubles with 15 ("%.15g"), strings verbatim, blobs as lower-case hex, T F N I as
the letter.

Hand testing:

    python3 tools/sim/osc_peer.py --port 9000          # print what arrives
    python3 tools/sim/osc_peer.py --port 9000 --ack    # ...and acknowledge it
    python3 tools/sim/osc_peer.py --send 127.0.0.1:8000 /1/fader1 f 0.5
                                                       # fire one message at OXT

As a library: OscPeer(port=0, ack=True).start_background() -> .received, .port.
"""

import argparse
import socket
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import refcodec as R  # noqa: E402


def canonical(t, v):
    if t in "iht":
        return str(int(v))
    if t == "f":
        return "%.6g" % v
    if t == "d":
        return "%.15g" % v
    if t == "s":
        return v
    if t == "b":
        return v                       # refcodec decodes blobs to hex already
    return t                           # T F N I


class OscPeer:
    def __init__(self, host="127.0.0.1", port=9000, ack=False, verbose=False):
        self.ack, self.verbose = ack, verbose
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((host, port))
        self.sock.settimeout(0.2)
        self.port = self.sock.getsockname()[1]
        self.received = []             # (decoded tuple or None, raw bytes, sender)
        self._stop = threading.Event()
        self._thread = None

    def reply(self, addr, address, args):
        self.sock.sendto(R.osc_encode_message(address, args), addr)

    def handle(self, data, addr):
        try:
            d = R.osc_decode(data)
        except Exception as e:  # noqa: BLE001 -- any decode failure is a NAK
            self.received.append((None, data, addr))
            self.log("REJECTED from %s:%d: %s  %s" % (addr[0], addr[1], e, data[:32].hex()))
            if self.ack:
                self.reply(addr, "/oscpeer/nak", [["s", str(e)]])
            return
        self.received.append((d, data, addr))
        if d[0] == "bundle":
            self.log("bundle t=%d with %d element(s) from %s:%d" % (d[1], len(d[2]), addr[0], addr[1]))
            if self.ack:
                self.reply(addr, "/oscpeer/ack-bundle", [["s", str(d[1])], ["i", str(len(d[2]))]])
            return
        _, address, tags, vals = d
        rendered = [canonical(t, v) for t, v in zip(tags, vals)]
        self.log("%s ,%s %s" % (address, tags, " ".join(rendered)))
        if self.ack:
            self.reply(addr, "/oscpeer/ack", [["s", address], ["s", tags]] + [["s", x] for x in rendered])

    def log(self, msg):
        if self.verbose:
            print(msg, flush=True)

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


def main():
    ap = argparse.ArgumentParser(description="Virtual OSC peer (no controller needed).")
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=9000)
    ap.add_argument("--ack", action="store_true", help="reply with what was understood")
    ap.add_argument("--send", metavar="HOST:PORT", help="send ONE message (address type value ...) and exit")
    ap.add_argument("message", nargs="*", help="with --send: /address [type value]...")
    a = ap.parse_args()
    if a.send:
        host, port = a.send.rsplit(":", 1)
        if not a.message:
            ap.error("--send needs an address")
        address, rest, args = a.message[0], a.message[1:], []
        while rest:
            t = rest.pop(0)
            args.append([t] if t in "TFNI" else [t, rest.pop(0)])
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.sendto(R.osc_encode_message(address, args), (host, int(port)))
        print("sent %s to %s:%s" % (address, host, port))
        return
    peer = OscPeer(a.bind, a.port, ack=a.ack, verbose=True)
    print("virtual OSC peer on %s:%d%s (Ctrl+C to stop)" % (a.bind, peer.port, " [ack]" if a.ack else ""), flush=True)
    try:
        peer.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        peer.stop()


if __name__ == "__main__":
    main()
