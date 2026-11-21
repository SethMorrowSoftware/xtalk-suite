#!/usr/bin/env python3
"""check-lcb-signatures.py - src/render3dxt.lcb against src/render3d_shim.c
(box3dxt's gate of the same name, for this member).

A mismatch between a foreign bind and the C function it names is not a
compile error anywhere: lc-compile cannot see the C, and the C compiler
cannot see the binding. It is a marshalling fault at run time, on an engine,
in somebody's stack. So every line is held here, all derived from the shim's
own LC_API definitions:

  1. EVERY EXPORT IS BOUND ONCE, by `_<name without r3x_>`, with the C
     function's parameter and return types (int = CInt, double = CDouble,
     text in = ZStringUTF8, bytes in = Pointer, text or bytes out = Pointer,
     void = nothing), and nothing is bound that the shim does not define.
  2. NO RETURN IS A C STRING. A returned ZStringNative or ZStringUTF8 is
     freed by the engine, and the shim's text lives in a static buffer:
     box3dxt's first engine run died of exactly that (2026-11-20).
  3. NAMES ARE MECHANICAL: r3x_node_set_position is wrapped by the one public
     handler r3NodeSetPosition, whose whole signature line is derived (an
     int is an Integer, an int named `flag` a Boolean in, an `_is_` result a
     Boolean out, a double a Number, text a String, bytes with their length
     one Data). No public r3 handler exists without an export, and each
     wrapper's body calls its own bind.
  4. THE ENGINE BUILTINS are the four the header explains, spelled exactly.
  5. THE ABI NUMBER in the shim is the one both literals of checkABI() name.
  6. EVERY PUBLIC HANDLER HAS ITS DOC BLOCK directly above it, with a
     Summary and a line for each of its parameters.
  7. THE SWEEP in tests/engine-selftest.lc (between the SWEEP markers) calls
     every public handler once with zeros and empties, generated from the
     binding so a new handler meets a real engine the day it is written.

    python3 tools/check-lcb-signatures.py            # the gate
    python3 tools/check-lcb-signatures.py --write    # regenerate the sweep

Exit status: 0 held, 1 a difference (each named), 2 the gate could not read
its inputs (a blind gate must not print OK).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

INTERNAL = {"r3x_text_length"}
TOKEN = {"abi": "ABI"}
MIN_EXPORTS = 100
SWEEP_BEGIN = "-- >>> BEGIN SWEEP (generated: tools/check-lcb-signatures.py --write) >>>"
SWEEP_END = "-- <<< END SWEEP <<<"

BUILTINS = [
    'foreign handler MCStringCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
    'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String) returns CBool binds to "<builtin>"',
    'foreign handler MCDataGetBytePtr(in pData as Data) returns Pointer binds to "<builtin>"',
    'foreign handler MCDataGetLength(in pData as Data) returns CUInt binds to "<builtin>"',
    'foreign handler MCDataCreateWithBytes(in pBytes as Pointer, in pCount as CUInt, out rData as Data) '
    'returns CBool binds to "<builtin>"',
]

C_TO_LCB_IN = {"int": "CInt", "double": "CDouble", "const char *": "ZStringUTF8",
               "const unsigned char *": "Pointer", "const void *": "Pointer"}
C_TO_LCB_OUT = {"int": "CInt", "double": "CDouble", "const char *": "Pointer",
                "const unsigned char *": "Pointer", "void": "nothing"}
# The two handlers whose public shape is the picture itself, not the C
# function's value: they return the frame as Data.
PICTURE = {"r3x_scene_render", "r3x_scene_frame"}

DEF_RE = re.compile(r"^LC_API\s+(.+?)\b(r3x_\w+)\s*\(([^)]*)\)", re.M)
BIND_RE = re.compile(r'^private foreign handler (\w+)\((.*?)\) returns (\w+) binds to "c:render3dxt>(r3x_\w+)!cdecl"$')
PUBLIC_RE = re.compile(r"^public handler (\w+)\((.*?)\) returns (\w+)$")


def strip_c_comments(text):
    return re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)


def norm_type(t):
    return re.sub(r"\s*\*", " *", re.sub(r"\s+", " ", t.strip())).strip()


def parse_shim(text):
    """[(name, ret, [(type, pname)])] in file order: definitions only."""
    text = strip_c_comments(text)
    out, seen = [], set()
    for m in DEF_RE.finditer(text):
        line_end = text.find("\n", m.start())
        if text[m.start():line_end].rstrip().endswith(";"):
            continue                      # a prototype
        name = m.group(2)
        if name in seen:
            continue
        seen.add(name)
        params = []
        body = m.group(3).strip()
        if body and body != "void":
            for p in body.split(","):
                pm = re.match(r"(.+?)(\w+)$", p.strip())
                params.append((norm_type(pm.group(1)), pm.group(2)))
        out.append((name, norm_type(m.group(1)), params))
    return out


def public_name(symbol):
    return "r3" + "".join(TOKEN.get(w, w[:1].upper() + w[1:]) for w in symbol[4:].split("_"))


def p_name(n):
    return "p" + n[:1].upper() + n[1:]


def expected_public(name, ret, params):
    """The whole `public handler ...` line the mechanical rule gives."""
    pp = []
    i = 0
    while i < len(params):
        t, n = params[i]
        if t == "const unsigned char *":
            pp.append("in %s as Data" % p_name(n))
            i += 2                         # the length rides with the Data
            continue
        if t == "int":
            pp.append("in %s as %s" % (p_name(n), "Boolean" if n == "flag" else "Integer"))
        elif t == "double":
            pp.append("in %s as Number" % p_name(n))
        else:
            pp.append("in %s as String" % p_name(n))
        i += 1
    if name in PICTURE:
        r = "Data"
    elif ret == "void":
        r = "nothing"
    elif ret == "const char *":
        r = "String"
    elif ret == "double":
        r = "Number"
    else:
        r = "Boolean" if "_is_" in name else "Integer"
    return "public handler %s(%s) returns %s" % (public_name(name), ", ".join(pp), r)


# The exports that are a stack's first calls: each asks checkABI() first.
ABI_CHECKED = ("create", "load", "parse", "decode", "from_", "_box", "_sphere", "_plane",
               "_cylinder", "_capsule", "checker", "library_version", "scene_render")


def expected_body(name, ret, params):
    """The wrapper's whole body, line for line: the rule is mechanical, so
    the body is derived and compared, not pattern-matched. That holds the
    argument order, asInt() on every Boolean, textOf() on every text result
    and the Data-to-pointer steps in one comparison."""
    short = name[4:]
    args, has_data = [], False
    i = 0
    while i < len(params):
        t, n = params[i]
        if t == "const unsigned char *":
            args += ["tPtr", "tLen"]
            has_data = True
            i += 2
            continue
        args.append("asInt(%s)" % p_name(n) if (t == "int" and n == "flag") else p_name(n))
        i += 1
    checked = any(k in name for k in ABI_CHECKED)
    if name in PICTURE:
        body = ["   variable tPtr as Pointer", "   variable tLen as Integer", "   variable tData as Data",
                "   variable tOk as CBool"]
        if checked:
            body.append("   checkABI()")
        body += ["   put the empty data into tData", "   unsafe"]
        body.append("      put _scene_render(pScene, pW, pH) into tLen" if short == "scene_render"
                    else "      put _scene_frame_length(pScene) into tLen")
        body += ["      if tLen > 0 then", "         put _scene_frame(pScene) into tPtr",
                 "         put MCDataCreateWithBytes(tPtr, tLen, tData) into tOk", "      end if",
                 "   end unsafe", "   return tData"]
        return body
    call = "_%s(%s)" % (short, ", ".join(args))
    body = []
    if ret == "const char *":
        body.append("   variable tR as Pointer")
    elif ret == "double":
        body.append("   variable tR as Number")
    elif ret != "void":
        body.append("   variable tR as Integer")
    if has_data:
        body += ["   variable tPtr as Pointer", "   variable tLen as Integer"]
    if checked:
        body.append("   checkABI()")
    body.append("   unsafe")
    if has_data:
        body += ["      put MCDataGetBytePtr(pBytes) into tPtr", "      put MCDataGetLength(pBytes) into tLen"]
    body.append("      " + (call if ret == "void" else "put %s into tR" % call))
    body.append("   end unsafe")
    if ret == "const char *":
        body.append("   return textOf(tR)")
    elif ret == "int" and "_is_" in name:
        body.append("   return tR is not 0")
    elif ret != "void":
        body.append("   return tR")
    return body


def sweep_block(lcb_lines):
    names = []
    out = [SWEEP_BEGIN,
           "-- Every public handler of src/render3dxt.lcb, in file order, called once with",
           "-- zeros (false for a Boolean, empty for text and bytes). One try for the lot:",
           "-- tName is the call that was being made when anything threw.",
           "command sweepEveryHandler", "   local tName", "   try"]
    for line in lcb_lines:
        m = PUBLIC_RE.match(line)
        if not m:
            continue
        name, params, ret = m.groups()
        args = []
        for p in [p for p in params.split(",") if p.strip()]:
            t = p.strip().split(" as ")[1]
            args.append({"Boolean": "false", "String": "empty", "Data": "empty"}.get(t, "0"))
        names.append(name)
        out.append('      put "%s" into tName' % name)
        if ret == "nothing":
            out.append("      %s%s" % (name, (" " + ", ".join(args)) if args else ""))
        else:
            out.append("      get %s(%s)" % (name, ", ".join(args)))
    out += ["   catch tError", '      check "sweep: " & tName, false, oneLine(tError)',
            "      exit sweepEveryHandler", "   end try",
            '   check "sweep: all %d public handlers called with zeros, none threw", true' % len(names),
            "end sweepEveryHandler", SWEEP_END]
    return "\n".join(out)


SHIM = os.path.join(ROOT, "src", "render3d_shim.c")
LCB = os.path.join(ROOT, "src", "render3dxt.lcb")
SELFTEST = os.path.join(ROOT, "tests", "engine-selftest.lc")


def check(lcb, shim_text, test):
    """(problems, the self-test with its sweep regenerated, counts). Pure:
    the fixture test calls it on texts it has broken in memory."""
    exports = parse_shim(shim_text)
    if len(exports) < MIN_EXPORTS:
        return (["only %d exports found in the shim (fewer than %d): the scanner is blind"
                 % (len(exports), MIN_EXPORTS)], test, (0, 0))
    bad = []
    lines = lcb.split("\n")
    by_name = dict((e[0], e) for e in exports)

    # 1, 2, 4: the foreign handlers
    bound = {}
    builtins_seen = []
    for i, line in enumerate(lines):
        if not re.match(r"^\s*(private\s+)?foreign\s+handler\b", line):
            continue
        m = BIND_RE.match(line)
        if m:
            handler, params, ret, symbol = m.groups()
            if symbol in bound:
                bad.append("render3dxt.lcb:%d: %s is bound twice" % (i + 1, symbol))
            bound[symbol] = i + 1
            if symbol not in by_name:
                bad.append("render3dxt.lcb:%d: %s is bound but the shim does not define it" % (i + 1, symbol))
                continue
            _, cret, cparams = by_name[symbol]
            if handler != "_" + symbol[4:]:
                bad.append("render3dxt.lcb:%d: %s must be bound as _%s, not %s" % (i + 1, symbol, symbol[4:], handler))
            want = ", ".join("in %s as %s" % (p_name(n), C_TO_LCB_IN.get(t, "?")) for t, n in cparams)
            if params != want:
                bad.append("render3dxt.lcb:%d: %s parameters are (%s), the shim's are (%s)" % (i + 1, symbol, params, want))
            if ret != C_TO_LCB_OUT.get(cret, "?"):
                bad.append("render3dxt.lcb:%d: %s returns %s, the shim's %s is %s"
                           % (i + 1, symbol, ret, cret, C_TO_LCB_OUT.get(cret, "?")))
            if ret.startswith("ZString"):
                bad.append("render3dxt.lcb:%d: %s returns a C string: the engine would free the shim's static buffer"
                           % (i + 1, symbol))
            continue
        if line in BUILTINS:
            builtins_seen.append(line)
            continue
        bad.append("render3dxt.lcb:%d: a foreign handler this gate cannot read (one line, "
                   "c:render3dxt>r3x_...!cdecl, or one of the four builtins exactly)" % (i + 1))
    for b in BUILTINS:
        if builtins_seen.count(b) != 1:
            bad.append("render3dxt.lcb: the builtin %s... must appear exactly once" % b[:40])
    for name, _, _ in exports:
        if name not in bound:
            bad.append("render3dxt.lcb: %s is exported by the shim and never bound" % name)

    # 3, 6: the public handlers
    publics = {}
    for i, line in enumerate(lines):
        if not line.startswith("public handler"):
            continue
        m = PUBLIC_RE.match(line)
        if not m:
            bad.append("render3dxt.lcb:%d: a public handler line this gate cannot read" % (i + 1))
            continue
        publics[m.group(1)] = i
    want_names = {}
    for name, ret, params in exports:
        if name in INTERNAL:
            continue
        pub = public_name(name)
        want_names[pub] = name
        if pub not in publics:
            bad.append("render3dxt.lcb: no public handler %s for %s" % (pub, name))
            continue
        i = publics[pub]
        want = expected_public(name, ret, params)
        if lines[i] != want:
            bad.append("render3dxt.lcb:%d: %s is declared\n       %s\n     the shim gives\n       %s"
                       % (i + 1, pub, lines[i], want))
        # the body calls its own bind
        j = i + 1
        body = []
        while j < len(lines) and lines[j] != "end handler":
            body.append(lines[j])
            j += 1
        if body != expected_body(name, ret, params):
            bad.append("render3dxt.lcb:%d: %s's body is not the mechanical wrapper of %s; it should read\n       %s"
                       % (i + 1, pub, name, "\n       ".join(expected_body(name, ret, params))))
        # the doc block directly above
        if i == 0 or lines[i - 1] != "*/":
            bad.append("render3dxt.lcb:%d: %s has no doc block directly above it" % (i + 1, pub))
            continue
        k = i - 1
        while k > 0 and not lines[k].startswith("/**"):
            k -= 1
        block = lines[k:i]
        if not any(l.startswith("Summary: ") for l in block):
            bad.append("render3dxt.lcb:%d: %s's doc block has no Summary" % (i + 1, pub))
        for p in re.findall(r"in (\w+) as", lines[i]):
            if not any(l.startswith(p + ": ") for l in block):
                bad.append("render3dxt.lcb:%d: %s's doc block does not describe %s" % (i + 1, pub, p))
    for pub in publics:
        if pub not in want_names:
            bad.append("render3dxt.lcb:%d: public handler %s wraps no export of the shim" % (publics[pub] + 1, pub))

    # 5: the ABI number
    m = re.search(r"^#define R3X_ABI_VERSION (\d+)$", shim_text, re.M)
    if not m:
        bad.append("render3d_shim.c: no #define R3X_ABI_VERSION")
    else:
        abi = m.group(1)
        if ("if tV is not %s then" % abi) not in lcb or ("this binding needs ABI %s)" % abi) not in lcb:
            bad.append("render3dxt.lcb: checkABI() does not name ABI %s in both its test and its message" % abi)

    # 7: the sweep
    a, b = test.find(SWEEP_BEGIN), test.find(SWEEP_END)
    if a < 0 or b < a:
        bad.append("tests/engine-selftest.lc has no SWEEP block")
        return bad, test, (len(exports), len(want_names))
    want_test = test[:a] + sweep_block(lines) + test[b + len(SWEEP_END):]
    if want_test != test:
        bad.append("tests/engine-selftest.lc: the sweep is stale (run --write)")
    return bad, want_test, (len(exports), len(want_names))


def run(write=False):
    try:
        lcb = open(LCB, encoding="utf-8").read()
        shim_text = open(SHIM, encoding="utf-8").read()
        test = open(SELFTEST, encoding="utf-8").read()
    except OSError as err:
        print("check-lcb-signatures: cannot read an input: %s" % err)
        return 2
    bad, want_test, counts = check(lcb, shim_text, test)
    if write and want_test != test:
        with open(SELFTEST, "w", encoding="utf-8", newline="\n") as f:
            f.write(want_test)
        print("check-lcb-signatures: wrote tests/engine-selftest.lc")
        bad, want_test, counts = check(lcb, shim_text, want_test)
    if bad:
        for line in bad:
            print("FAIL " + line)
        return 2 if counts == (0, 0) else 1
    print("check-lcb-signatures: OK - %d exports bound as defined, %d public handlers mechanical and documented, ABI and sweep held"
          % counts)
    return 0


def main():
    return run(write="--write" in sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
