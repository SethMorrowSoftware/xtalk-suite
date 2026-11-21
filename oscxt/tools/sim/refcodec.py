#!/usr/bin/env python3
"""Clean-room reference codec for OSC 1.0.

Written from the specification, sharing NO code with the C shim or the LCB
binding, so it can act as an independent oracle:

  * tests/vectors_reference_test.py proves the wire-format vectors
    (tests/vectors/osc.json) against this encoder/decoder;
  * tools/sim/osc_peer.py uses it to play the OTHER end of the wire -- a
    virtual OSC peer -- for the engine-level interop tests and for hand
    testing without any controller, DAW or app.

The OSC part of ShowControl's tools/sim/refcodec.py (midixt and artnetxt carry
the MIDI and Art-Net parts). Pure standard library.
"""

import struct

# ===========================================================================
# OSC 1.0 reference (spec: opensoundcontrol.stanford.edu/spec-1_0.html)
# ===========================================================================

def _pad4(b):
    return b + b"\x00" * ((4 - len(b) % 4) % 4)


def osc_str(s):
    return _pad4(s.encode("utf-8") + b"\x00")       # NUL-terminated, then padded


def osc_encode_arg(t, v):
    if t == "i":
        return struct.pack(">i", int(v))
    if t == "f":
        return struct.pack(">f", float(v))
    if t == "d":
        return struct.pack(">d", float(v))
    if t == "h":
        return struct.pack(">q", int(v))
    if t == "t":
        return struct.pack(">Q", int(v))
    if t == "s":
        return osc_str(v)
    if t == "b":
        raw = bytes.fromhex(v)
        return struct.pack(">i", len(raw)) + _pad4(raw)
    if t in "TFNI":
        return b""
    raise ValueError("unknown OSC type " + t)


def osc_encode_message(address, args):
    tags = "," + "".join(a[0] for a in args)
    body = b"".join(osc_encode_arg(a[0], a[1] if len(a) > 1 else None) for a in args)
    return osc_str(address) + osc_str(tags) + body


def osc_encode_bundle(timetag, elements):
    out = b"#bundle\x00" + struct.pack(">Q", int(timetag))
    for e in elements:
        out += struct.pack(">i", len(e)) + e
    return out


class Malformed(Exception):
    pass


def _read_str(d, p):
    end = d.find(b"\x00", p)
    if end < 0:
        raise Malformed("unterminated string")
    s = d[p:end].decode("utf-8")
    p = end + 1
    p += (4 - p % 4) % 4
    if p > len(d):
        raise Malformed("string padding runs past the end")
    return s, p


def osc_decode(d, depth=0):
    """-> ("message", address, tags, [values]) or ("bundle", timetag, [elements])."""
    if len(d) < 4 or len(d) % 4:
        raise Malformed("length")
    if d[:8] == b"#bundle\x00":
        if depth >= 64:
            raise Malformed("nesting")
        if len(d) < 16:
            raise Malformed("bundle too short")
        tt = struct.unpack(">Q", d[8:16])[0]
        p, elems = 16, []
        while p + 4 <= len(d):
            n = struct.unpack(">i", d[p:p + 4])[0]
            p += 4
            if n < 0 or n > len(d) - p:
                raise Malformed("element size")
            elems.append(osc_decode(d[p:p + n], depth + 1))
            p += n
        return ("bundle", tt, elems)
    if d[0:1] != b"/":
        raise Malformed("address must start with /")
    addr, p = _read_str(d, 0)
    if p >= len(d) or d[p:p + 1] != b",":
        raise Malformed("missing type tag")
    tags, p = _read_str(d, p)
    tags = tags[1:]
    vals = []
    for t in tags:
        if t in "if":
            if p + 4 > len(d):
                raise Malformed("truncated")
            vals.append(struct.unpack(">i" if t == "i" else ">f", d[p:p + 4])[0])
            p += 4
        elif t in "hdt":
            if p + 8 > len(d):
                raise Malformed("truncated")
            vals.append(struct.unpack({"h": ">q", "d": ">d", "t": ">Q"}[t], d[p:p + 8])[0])
            p += 8
        elif t == "s":
            s, p = _read_str(d, p)
            vals.append(s)
        elif t == "b":
            if p + 4 > len(d):
                raise Malformed("truncated")
            n = struct.unpack(">i", d[p:p + 4])[0]
            p += 4
            if n < 0 or n > len(d) - p:
                raise Malformed("blob size")
            vals.append(d[p:p + n].hex())
            p += n + (4 - n % 4) % 4
            if p > len(d):
                raise Malformed("blob padding")
        elif t in "TFNI":
            vals.append({"T": True, "F": False, "N": None, "I": None}[t])
        else:
            raise Malformed("unknown type tag")
    return ("message", addr, tags, vals)


def osc_match(pattern, address):
    """OSC 1.0 address-pattern match (? * [] [!] [a-z] {,}); '*'/'?' never cross '/'."""
    def m(p, s):
        while p:
            c = p[0]
            if c == "?":
                if not s or s[0] == "/":
                    return False
                p, s = p[1:], s[1:]
            elif c == "*":
                p = p.lstrip("*")
                if not p:
                    return "/" not in s
                i = 0
                while True:
                    if m(p, s[i:]):
                        return True
                    if i >= len(s) or s[i] == "/":
                        return False
                    i += 1
            elif c == "[":
                end = p.find("]")
                body, p = (p[1:end], p[end + 1:]) if end >= 0 else (p[1:], "")
                if not s or s[0] == "/":
                    return False
                neg = body.startswith("!")
                if neg:
                    body = body[1:]
                hit, k = False, 0
                while k < len(body):
                    if k + 2 < len(body) and body[k + 1] == "-":
                        hit |= body[k] <= s[0] <= body[k + 2]
                        k += 3
                    else:
                        hit |= body[k] == s[0]
                        k += 1
                if hit == neg:
                    return False
                s = s[1:]
            elif c == "{":
                end = p.find("}")
                opts, rest = (p[1:end], p[end + 1:]) if end >= 0 else (p[1:], "")
                return any(s.startswith(o) and m(rest, s[len(o):]) for o in opts.split(","))
            else:
                if not s or s[0] != c:
                    return False
                p, s = p[1:], s[1:]
        return not s
    return m(pattern, address)


def _close(a, b, tol):
    return abs(float(a) - float(b)) <= tol


def osc_values_equal(t, got, want):
    if t == "f":
        return _close(got, want, 1e-5 * max(1.0, abs(float(want))))
    if t == "d":
        return _close(got, want, 1e-12 * max(1.0, abs(float(want))))
    if t in "iht":
        return int(got) == int(want)
    if t == "s":
        return got == want
    if t == "b":
        return got == want
    if t in "TFNI":
        return True
    return False
