#!/usr/bin/env python3
"""Golden-packet tests for artnetxt's binding (src/artnet.lcb).

Art-Net is pure byte-packing, and its one real trap is MIXED ENDIANNESS
(CLAUDE.md, "The rules"): the OpCode is little-endian, but the protocol-version
and length fields are big-endian. Reverse either big-endian field and a real
node silently ignores the packet -- a bug no compiler catches.

This file is the executable specification for the wire format, kept from
ShowControl beside the shared vectors: a THIRD encoder and decoder, written
straight from the specification and sharing no code with tools/sim/refcodec.py
or the binding, asserts byte-exact GOLDEN packets with each endianness trap
called out on its own, and round-trips them. The LCB handlers pack bytes the
same way; these goldens are what an OXT-side test (and Wireshark,
udp.port == 6454) compares artnetBuildDmx output against.

Run:  python3 tests/artnet_golden_test.py
"""

ART_NET_ID = b"Art-Net\x00"
OP_DMX        = 0x5000
OP_POLL       = 0x2000
OP_POLLREPLY  = 0x2100
PROTO_VER     = 14


# ---- reference encoders (the spec, byte for byte) -------------------------
def build_dmx(universe, channels, sequence=0, physical=0):
    """ArtDmx. channels: bytes, one per DMX channel. Length forced even, 2..512."""
    data = bytes(channels[:512])
    n = len(data)
    if n < 2:
        data = data + b"\x00" * (2 - n)
    if len(data) % 2:
        data = data + b"\x00"
    n = len(data)
    sub = universe & 0xFF
    net = (universe >> 8) & 0x7F
    pkt = bytearray()
    pkt += ART_NET_ID
    pkt += bytes([OP_DMX & 0xFF, (OP_DMX >> 8) & 0xFF])      # OpCode  LITTLE-endian
    pkt += bytes([(PROTO_VER >> 8) & 0xFF, PROTO_VER & 0xFF])# ProtVer  BIG-endian
    pkt += bytes([sequence & 0xFF, physical & 0xFF])
    pkt += bytes([sub, net])                                 # SubUni then Net
    pkt += bytes([(n >> 8) & 0xFF, n & 0xFF])                # Length   BIG-endian
    pkt += data
    return bytes(pkt)


def build_poll():
    pkt = bytearray()
    pkt += ART_NET_ID
    pkt += bytes([OP_POLL & 0xFF, (OP_POLL >> 8) & 0xFF])    # OpCode  LITTLE-endian
    pkt += bytes([(PROTO_VER >> 8) & 0xFF, PROTO_VER & 0xFF])# ProtVer  BIG-endian
    pkt += bytes([0, 0])                                     # TalkToMe, Priority
    return bytes(pkt)


def parse_dmx(pkt):
    if len(pkt) < 18 or pkt[0:8] != ART_NET_ID:
        return None
    opcode = pkt[8] | (pkt[9] << 8)                          # little-endian
    if opcode != OP_DMX:
        return None
    length = (pkt[16] << 8) | pkt[17]                        # big-endian
    sub, net = pkt[14], pkt[15]
    return {
        "opcode": "ArtDmx",
        "sequence": pkt[12],
        "physical": pkt[13],
        "subuni": sub,
        "net": net,
        "universe": (net << 8) | sub,
        "length": length,
        "channels": pkt[18:18 + length],
    }


# ---- test harness ---------------------------------------------------------
_p = _f = 0
def check(name, ok):
    global _p, _f
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    if ok:
        _p += 1
    else:
        _f += 1


def hx(b):
    return " ".join(f"{x:02X}" for x in b)


def main():
    # GOLDEN 1: universe 0, two channels [255, 128].
    g1 = build_dmx(0, bytes([255, 128]))
    expect1 = bytes.fromhex("41 72 74 2D 4E 65 74 00 00 50 00 0E 00 00 00 00 00 02 FF 80".replace(" ", ""))
    print("  golden ArtDmx u0 [255,128]:", hx(g1))
    check("golden 1 is byte-exact", g1 == expect1)
    # the two endianness traps, called out individually:
    check("OpCode is little-endian (00 50)", g1[8:10] == bytes([0x00, 0x50]))
    check("ProtVer is big-endian (00 0E)", g1[10:12] == bytes([0x00, 0x0E]))
    check("Length is big-endian (00 02)", g1[16:18] == bytes([0x00, 0x02]))

    # GOLDEN 2: universe 0x0102 = 258 -> SubUni 0x02, Net 0x01.
    g2 = build_dmx(258, bytes([1, 2, 3, 4]))
    check("universe 258 -> subuni 0x02", g2[14] == 0x02)
    check("universe 258 -> net 0x01", g2[15] == 0x01)
    check("4 channels -> length 0x0004", g2[16:18] == bytes([0x00, 0x04]))

    # Odd channel count is padded up to even.
    g3 = build_dmx(0, bytes([10, 20, 30]))
    check("odd length padded to even (4)", (g3[16] << 8 | g3[17]) == 4)
    check("padding byte is zero", g3[-1] == 0)

    # Over-512 is truncated to 512.
    g4 = build_dmx(0, bytes(range(256)) * 3)   # 768 bytes
    check("over-512 truncated to 512", (g4[16] << 8 | g4[17]) == 512)
    check("packet total is 18 + 512", len(g4) == 18 + 512)

    # Full-frame round-trip through the parser.
    payload = bytes((i * 7) & 0xFF for i in range(512))
    g5 = build_dmx(5, payload, sequence=12)
    d = parse_dmx(g5)
    check("parse round-trips universe", d and d["universe"] == 5)
    check("parse round-trips sequence", d and d["sequence"] == 12)
    check("parse round-trips length", d and d["length"] == 512)
    check("parse round-trips channels", d and d["channels"] == payload)

    # A non-Art-Net datagram is rejected.
    check("garbage is rejected", parse_dmx(b"not artnet at all!!") is None)

    # ArtPoll golden.
    gp = build_poll()
    # the expected bytes spelled field by field, to avoid hex-spacing mistakes:
    expect_poll = ART_NET_ID + bytes([0x00, 0x20]) + bytes([0x00, 0x0E]) + bytes([0x00, 0x00])
    print("  golden ArtPoll:", hx(gp))
    check("ArtPoll is byte-exact", gp == expect_poll)
    check("ArtPoll OpCode little-endian (00 20)", gp[8:10] == bytes([0x00, 0x20]))

    print(f"\n{_p} passed, {_f} failed")
    if _p < 18:
        print("FAIL: only %d checks ran; the floor is 18" % _p)
        return 1
    return 0 if _f == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
