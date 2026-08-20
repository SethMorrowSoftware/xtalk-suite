#!/usr/bin/env python3
"""check-lcb-signatures.py - hold every foreign bind to its C definition.

WHAT WAS UNCHECKED
    A `.lcb` foreign handler declares a C signature; the shim defines one. Until
    2026-08-19 only ONE member checked that the two agree - box2dxt, whose own
    tools/check-lcb-signatures.py this is modelled on. The other five bindings
    (266 binds between them) had their EXISTENCE gated by
    tools/check-binary-freshness.py, which resolves every bind against an
    exported symbol, and nothing at all checking the SHAPE.

    Existence is the cheap half. A bind that names a real symbol with the wrong
    arity, or `CInt` where the shim wrote `double`, links and loads and then
    reads whatever the ABI happens to put in that register - on a GUI engine,
    with no diagnostic, which is the failure mode this whole tree is arranged to
    keep away from an engine session.

WHY A TABLE AND NOT FIVE COPIES
    The family's other per-member tools are carried byte-identical with a drift
    gate (check-livecodescript.py, ten copies). That shape earns its keep when
    a member must stay self-contained on its own mirror. This one reads FIVE
    trees at once by design - the point is that no binding is left out - so a
    table beats five copies that could drift into five different opinions about
    the same question. box2dxt keeps its own: it additionally checks the
    name bijection (`_X` -> `b2lc_X`) and would have to be reduced to be folded
    in here, which trades a stronger check for a tidier file.

THE TYPE MAP IS DELIBERATELY NOT PERMISSIVE
    An LCB type this file does not know is an ERROR, not a skip. Otherwise "the
    checker did not know that type" reads exactly like "the signatures agree" -
    the failure this repository has recorded from gates that reported what they
    had parsed as what they had checked.

USAGE
    python3 tools/check-lcb-signatures.py
    Exit 0 when clean, 1 on any mismatch.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (member, .lcb, [shim sources], library token, symbol prefix, export macro)
# The export macro is None where the shim declares plain C (coinxt).
BINDINGS = [
    ("sodiumxt", "sodiumxt/src/sodium.lcb", ["sodiumxt/src/sodium_shim.c"],
     "sodiumxt", "sxt_", "SXT_API"),
    ("torrentxt", "torrentxt/src/torrent.lcb", ["torrentxt/src/torrent_shim.cpp"],
     "torrentxt", "btx_", "BTX_API"),
    ("enetxt", "enetxt/src/enet.lcb", ["enetxt/src/enet_shim.cpp"],
     "enetxt", "enx_", "ENX_API"),
    ("datachannelxt", "datachannelxt/src/datachannel.lcb",
     ["datachannelxt/src/datachannel_shim.cpp"],
     "datachannelxt", "dcx_", "DCX_API"),
    ("coinxt", "coinxt/src/coinxt.lcb", ["coinxt/native/coinxt.c"],
     "coinxt", "cnx_", None),
]

# Every LCB type these five bindings use, and the C spelling(s) each may take.
# `Pointer` is the family's buffer convention (an LCB Data does not bridge to a
# void*), so it is any pointer; the width-specific ints are listed exactly.
# uint32_t is listed for CUInt because coinxt's shim spells its iteration count
# that way and LCB has no fixed-width unsigned; they are the same C type on
# every platform this suite builds for. It is listed EXPLICITLY rather than
# matched by a pattern, so the next fixed-width spelling has to be a decision.
LCB_TO_C = {
    "CInt": {"int", "int32_t"},
    "CUInt": {"unsigned int", "unsigned", "uint32_t"},
    "CBool": {"int", "bool"},
    "CDouble": {"double"},
    "UIntSize": {"size_t"},
    "ZStringUTF8": {"char *"},
    "nothing": {"void"},
}

# `Pointer` is the family's raw-buffer convention (an LCB Data does not bridge
# to a void*) and it accepts ANY pointer, char* included. Excluding char* was
# the first rule here and it was wrong in the direction that produces noise
# rather than findings: the OUT-buffer handlers - enx_last_error,
# dcx_local_description, dcx_channel_label and 20 more - pass an
# MCMemoryAllocate block as Pointer into a C parameter the shim quite correctly
# spells `char *`, because it writes text into it. Twenty-three of those, none
# a defect.
#
# The asymmetry is deliberate and is where the real check lives: ZStringUTF8
# accepts ONLY char*, so a ZStringUTF8 bind against a non-char pointer is still
# refused. That is the direction that carries the NUL-termination bet
# (datachannelxt gotcha 9: ZStringUTF8 measures with strlen), and it is the one
# that can be wrong in a way that compiles and then truncates.
def pointer_ok(c_type):
    return c_type.endswith("*")

# The type name may contain DIGITS - ZStringUTF8 is the one that matters, and
# an [A-Za-z]+ class silently stopped at the 8, leaving "8" to fail the anchor
# and every such parameter reported as a type this gate does not know.
PARAM_RE = re.compile(
    r'^\s*(?:in|out|inout)\s+\w+\s+as\s+(?:optional\s+)?([A-Za-z][A-Za-z0-9_]*)\s*$')


def bind_re(token, prefix):
    return re.compile(
        r'^\s*(?:private\s+)?foreign\s+handler\s+(\w+)\s*\((.*?)\)\s*'
        r'(?:returns\s+([A-Za-z][A-Za-z0-9_]*)\s+)?binds\s+to\s+"c:' + re.escape(token) +
        r'>(' + re.escape(prefix) + r'\w+)(?:!cdecl)?"\s*$')


# C type words, so a trailing PARAMETER NAME can be told from part of a type.
# `int cap` is a type plus a name; `unsigned int` is two type words. Without
# this the gate reported every named parameter as a mismatch - 274 of them,
# none real.
C_TYPE_WORDS = {"void", "int", "char", "short", "long", "float", "double",
                "unsigned", "signed", "bool", "size_t", "uint8_t", "uint16_t",
                "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t",
                "int64_t", "const"}


def norm_c(decl):
    """A C parameter or return type, normalised for comparison.

    POINTERS KEEP THEIR POINTEE. Collapsing every pointer to a bare "*" made
    the gate simpler and weaker in the same stroke: `Pointer` and
    `ZStringUTF8` would have become indistinguishable, and telling a raw buffer
    from a NUL-terminated string is one of the few things this boundary can
    actually get wrong in a way that compiles.
    """
    d = " ".join(decl.replace("*", " * ").split())
    star = "*" in d
    toks = [t for t in d.split() if t not in ("const", "*")]
    if len(toks) > 1 and toks[-1] not in C_TYPE_WORDS:
        toks = toks[:-1]                  # drop the parameter name
    elif star and len(toks) == 1 and toks[0] not in C_TYPE_WORDS:
        toks = []                         # `dcx_t *handle` - name only
    base = " ".join(toks).strip()
    return (base + " *").strip() if star else base


def parse_lcb(path, token, prefix):
    """[(lineno, handler, [lcb param types], lcb return, c symbol)]"""
    rx = bind_re(token, prefix)
    out, buf, start = [], "", 0
    for i, raw in enumerate(open(os.path.join(ROOT, path), encoding="utf-8"), 1):
        line = raw.rstrip("\n")
        if not buf:
            start = i
        s = buf + line.strip() if buf else line
        if s.rstrip().endswith("\\"):
            buf = s.rstrip()[:-1] + " "
            continue
        buf = ""
        m = rx.match(s)
        if m:
            params = [p for p in (x.strip() for x in m.group(2).split(",")) if p]
            types = []
            for p in params:
                pm = PARAM_RE.match(" " + p)
                types.append(pm.group(1) if pm else "?" + p)
            out.append((start, m.group(1), types, m.group(3) or "nothing", m.group(4)))
    return out


def parse_shim(paths, prefix, macro):
    """symbol -> (c return, [c param types])"""
    if macro:
        rx = re.compile(re.escape(macro) + r'\s+([A-Za-z_][\w \*]*?)\s*(?:[A-Z]+_CALL\s+)?'
                        r'(' + re.escape(prefix) + r'\w+)\s*\(([^)]*)\)', re.S)
    else:
        rx = re.compile(r'^\s*([A-Za-z_][\w \*]*?)\s*(' + re.escape(prefix) +
                        r'\w+)\s*\(([^)]*)\)\s*\{', re.M | re.S)
    defs = {}
    for p in paths:
        text = open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read()
        for m in rx.finditer(text):
            args = [a.strip() for a in m.group(3).split(",") if a.strip()]
            if args == ["void"]:
                args = []
            defs[m.group(2)] = (norm_c(m.group(1)), [norm_c(a) for a in args])
    return defs


def c_ok(lcb_type, c_type):
    if lcb_type == "Pointer":
        return pointer_ok(c_type)
    allowed = LCB_TO_C.get(lcb_type)
    if allowed is None:
        return None                      # unknown LCB type -> caller reports it
    return c_type in allowed


def main(argv):
    problems, n_binds, n_params, n_defs = [], 0, 0, 0
    for member, lcb, shim, token, prefix, macro in BINDINGS:
        binds = parse_lcb(lcb, token, prefix)
        defs = parse_shim(shim, prefix, macro)
        n_binds += len(binds)
        n_defs += len(defs)
        if not binds:
            problems.append(f"{member}: parsed ZERO foreign binds from {lcb} - the "
                            "regex no longer matches this file, and a clean report "
                            "would be a lie")
            continue
        for lineno, handler, ptypes, rtype, sym in binds:
            if sym not in defs:
                problems.append(f"{lcb}:{lineno}: {handler} binds {sym}, which no "
                                f"{macro or 'plain-C'} definition in {member} provides")
                continue
            cret, cargs = defs[sym]
            verdict = c_ok(rtype, cret)
            if verdict is None:
                problems.append(f"{lcb}:{lineno}: {handler} returns LCB type "
                                f"{rtype!r}, which this gate does not know - add it "
                                "to LCB_TO_C on purpose")
            elif not verdict:
                problems.append(f"{lcb}:{lineno}: {handler} returns {rtype} but "
                                f"{sym} returns C {cret!r}")
            if len(ptypes) != len(cargs):
                problems.append(f"{lcb}:{lineno}: {handler} declares {len(ptypes)} "
                                f"parameter(s) but {sym} takes {len(cargs)}")
                continue
            for i, (lt, ct) in enumerate(zip(ptypes, cargs), 1):
                n_params += 1
                v = c_ok(lt, ct)
                if v is None:
                    problems.append(f"{lcb}:{lineno}: {handler} parameter {i} is LCB "
                                    f"type {lt!r}, which this gate does not know - add "
                                    "it to LCB_TO_C on purpose")
                elif not v:
                    problems.append(f"{lcb}:{lineno}: {handler} parameter {i} is {lt} "
                                    f"but {sym} takes C {ct!r}")
    for p in problems:
        print("check-lcb-signatures: " + p)
    if problems:
        print(f"check-lcb-signatures: {len(problems)} mismatch(es)")
        return 1
    print(f"check-lcb-signatures: OK ({len(BINDINGS)} bindings, {n_binds} foreign "
          f"binds against {n_defs} shim definitions; {n_params} parameters + "
          f"{n_binds} return types matched)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
