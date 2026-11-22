"""Clean-room reference codec for Art-Net 4 (the packets artnetxt builds and
reads), written from Artistic Licence's published specification with no code
shared with the binding: tests/vectors_reference_test.py proves
tests/vectors/artnet.json against it, so a wrong vector fails here and a
binding that drifts from a right one fails in its own suite. tools/sim/
artnet_node.py speaks Art-Net through it.

The Art-Net part of ShowControl's tools/sim/refcodec.py, with the
ArtPollReply's port, status and identity fields added (artnetxt reads them).

Byte order, the format's one real trap: the OpCode and the ArtPollReply Port
are LITTLE-endian; the protocol version and the ArtDmx Length are BIG-endian.
"""

import struct

ART_ID = b"Art-Net\x00"
OP_POLL, OP_POLLREPLY, OP_DMX = 0x2000, 0x2100, 0x5000
PROT_VER = 14
ART_NET_PORT = 0x1936                                    # 6454
POLLREPLY_LEN = 239                                      # Art-Net 4


def artnet_dmx(universe, channels, sequence=0, physical=0):
    """ArtDmx. channels: bytes, one per DMX channel; Length forced even, 2..512."""
    data = bytes(channels[:512])
    if len(data) < 2:
        data += b"\x00" * (2 - len(data))
    if len(data) % 2:
        data += b"\x00"
    return (ART_ID + struct.pack("<H", OP_DMX) + struct.pack(">H", PROT_VER)
            + bytes([sequence, physical, universe & 0xFF, (universe >> 8) & 0x7F])
            + struct.pack(">H", len(data)) + data)


def artnet_poll():
    """ArtPoll in its 14-byte form: Flags 0 (reply only when polled), DiagPriority 0."""
    return ART_ID + struct.pack("<H", OP_POLL) + struct.pack(">H", PROT_VER) + b"\x00\x00"


def artnet_pollreply(ip, short, long_, net, sub, port=ART_NET_PORT, version=0,
                     node_report="", port_types=(0, 0, 0, 0), sw_in=(0, 0, 0, 0),
                     sw_out=(0, 0, 0, 0), style=0, mac="00:00:00:00:00:00",
                     bind_ip="0.0.0.0", bind_index=0, length=POLLREPLY_LEN):
    """ArtPollReply (Art-Net 4, 239 bytes; `length` cuts it short like an older node).

    Offsets (0-based) from the specification's field table: IP 10-13, Port 14-15
    (LITTLE-endian), VersInfoH/L 16-17, NetSwitch 18, SubSwitch 19, Oem 20-21,
    UbeaVersion 22, Status1 23, EstaMan 24-25, ShortName 26 (18), LongName 44
    (64), NodeReport 108 (64), NumPortsHi/Lo 172-173, PortTypes 174-177,
    GoodInput 178-181, GoodOutputA 182-185, SwIn 186-189, SwOut 190-193,
    AcnPriority 194, SwMacro 195, SwRemote 196, Spare 197-199, Style 200,
    MAC 201-206 (high byte first), BindIp 207-210, BindIndex 211, Status2 212.
    """
    b = bytearray(POLLREPLY_LEN)
    b[0:8] = ART_ID
    b[8:10] = struct.pack("<H", OP_POLLREPLY)
    b[10:14] = bytes(int(x) for x in ip.split("."))
    b[14:16] = struct.pack("<H", port)
    b[16:18] = struct.pack(">H", version)
    b[18], b[19] = net, sub
    b[26:26 + len(short)] = short.encode("ascii")
    b[44:44 + len(long_)] = long_.encode("ascii")
    b[108:108 + len(node_report)] = node_report.encode("ascii")
    b[172:174] = struct.pack(">H", sum(1 for t in port_types if t & 0xC0))
    b[174:178] = bytes(port_types)
    b[186:190] = bytes(sw_in)
    b[190:194] = bytes(sw_out)
    b[200] = style
    b[201:207] = bytes(int(x, 16) for x in mac.split(":"))
    b[207:211] = bytes(int(x) for x in bind_ip.split("."))
    b[211] = bind_index
    return bytes(b[:length])


# ---------------------------------------------------------------------------
# Decoders (what a node or a monitor reads)
# ---------------------------------------------------------------------------

def is_artnet(pkt):
    return len(pkt) >= 10 and pkt[:8] == ART_ID


def opcode(pkt):
    return struct.unpack("<H", pkt[8:10])[0] if is_artnet(pkt) else None


def artnet_dmx_decode(pkt):
    """ArtDmx -> dict, or None. Length is clamped to 512 and to the bytes present."""
    if not is_artnet(pkt) or len(pkt) < 18 or opcode(pkt) != OP_DMX:
        return None
    n = min(struct.unpack(">H", pkt[16:18])[0], 512, len(pkt) - 18)
    return {"sequence": pkt[12], "physical": pkt[13], "subuni": pkt[14], "net": pkt[15],
            "universe": pkt[15] * 256 + pkt[14], "length": n, "channels": bytes(pkt[18:18 + n])}


def _text(raw):
    return raw.split(b"\x00", 1)[0].decode("latin-1")


def artnet_pollreply_decode(pkt):
    """ArtPollReply -> dict, or None. A short reply reads as far as it goes."""
    if not is_artnet(pkt) or len(pkt) < 26 or opcode(pkt) != OP_POLLREPLY:
        return None
    p = bytes(pkt) + b"\x00" * max(0, POLLREPLY_LEN - len(pkt))
    out = {"ip": ".".join(str(x) for x in p[10:14]),
           "port": struct.unpack("<H", p[14:16])[0],
           "version": struct.unpack(">H", p[16:18])[0],
           "net": p[18], "subuni": p[19],
           "shortName": _text(pkt[26:44]), "longName": _text(pkt[44:108]),
           "nodeReport": _text(pkt[108:172]),
           "style": p[200], "bindIndex": p[211],
           "mac": ":".join("%02x" % x for x in p[201:207]) if len(pkt) >= 207 else "",
           "outputUniverses": [], "inputUniverses": []}
    if len(pkt) >= 194:
        base = (p[18] & 0x7F) << 8 | (p[19] & 0x0F) << 4
        for i in range(4):
            if p[174 + i] & 0x80:
                out["outputUniverses"].append(base | (p[190 + i] & 0x0F))
            if p[174 + i] & 0x40:
                out["inputUniverses"].append(base | (p[186 + i] & 0x0F))
    return out
