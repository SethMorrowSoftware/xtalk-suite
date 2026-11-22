"""Clean-room reference codec for MIDI 1.0 (the channel-voice messages midixt
decodes and its convenience senders encode), written from the MIDI 1.0
specification with no code shared with the binding: tests/vectors_reference_test.py
proves tests/vectors/midi.json against it, so a wrong vector fails here and a
binding that drifts from a right one fails in its own suite.

The MIDI part of ShowControl's tools/sim/refcodec.py.
"""


# ===========================================================================
# MIDI 1.0 reference (status nibble + 7-bit data; channels 1..16 on the API)
# ===========================================================================

def midi_decode(raw):
    if not raw:
        return {"kind": "empty"}
    st = raw[0]
    d1 = raw[1] if len(raw) > 1 else 0
    d2 = raw[2] if len(raw) > 2 else 0
    if st >= 0xF0:
        return {"kind": "sysex" if st == 0xF0 else "system", "channel": 0, "data1": d1, "data2": d2}
    kind = {0x90: "noteOn", 0x80: "noteOff", 0xB0: "controlChange", 0xC0: "programChange",
            0xE0: "pitchBend", 0xD0: "channelPressure", 0xA0: "polyAftertouch"}.get(st & 0xF0, "other")
    if kind == "noteOn" and d2 == 0:
        kind = "noteOff"
    out = {"kind": kind, "channel": (st & 0x0F) + 1, "data1": d1, "data2": d2}
    if kind == "pitchBend":
        out["value14"] = d1 + d2 * 128
    return out


def _c7(x):
    return max(0, min(127, x))


def _nib(ch):
    return ((ch - 1) % 16 + 16) % 16


def midi_encode(call, ch, a=0, b=0):
    n = _nib(ch)
    if call == "noteOn":
        return bytes([0x90 + n, _c7(a), _c7(b)])
    if call == "noteOff":
        return bytes([0x80 + n, _c7(a), _c7(b)])
    if call == "controlChange":
        return bytes([0xB0 + n, _c7(a), _c7(b)])
    if call == "programChange":
        return bytes([0xC0 + n, _c7(a)])
    if call == "channelPressure":
        return bytes([0xD0 + n, _c7(a)])
    if call == "pitchBend":
        v = max(0, min(16383, a))
        return bytes([0xE0 + n, v % 128, (v // 128) % 128])
    raise ValueError(call)
