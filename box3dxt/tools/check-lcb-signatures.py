#!/usr/bin/env python3
"""check-lcb-signatures.py - src/box3dxt.lcb against src/box3d_shim.c, and the
engine self-test's sweep against both.

The binding is a 1:1 wrapper over the C shim, and nothing at run time checks
that the two agree: the engine resolves a symbol by NAME and calls it with
whatever the declaration says, so a declaration that promises CInt where the
shim returns double does not fail to load and does not raise - it reads a
garbage register and hands script a plausible number (box2dxt's gate of the
same name says the same; this one is that gate, widened for a binding whose
names are mechanical and whose results include text).

What is held, each named when it fails:

  1. every `private foreign handler` against the LC_API definition it binds:
     the symbol exists, the return type, the arity, each parameter type;
  2. the names are MECHANICAL, both steps: the foreign handler for
     b3x_body_set_position is _body_set_position and its one public wrapper
     is b3BodySetPosition. Every export is bound once and wrapped once, no
     public handler wraps anything else, and none is left over;
  3. each public wrapper matches its foreign handler: the same number of
     parameters, in the same order, Integer or Boolean over CInt, Number
     over CDouble, String over Pointer; a Boolean parameter is passed
     through asInt() and a Boolean result is `tR is not 0`. (A Boolean handed
     to a CInt unconverted is a type error at the first call.) A text result
     is a Pointer copied by textOf(), and NO foreign handler may return
     ZStringNative: the engine frees a returned C string, and the shim's
     texts are static buffers (the first engine run died of exactly that);
  4. every public handler has its own doc block: a Summary, one entry per
     parameter by name, a Returns when it returns something. The IDE's
     dictionary is made from these blocks and from nothing else;
  5. checkABI() names the shim's B3X_ABI_VERSION, and so does the doc block
     of b3ABIVersion ("this binding needs N.", the IDE dictionary's text);
  6. the SWEEP in tests/engine-selftest.lc calls every public handler once,
     and is exactly what this tool would write.

    python3 tools/check-lcb-signatures.py           # the gate
    python3 tools/check-lcb-signatures.py --write   # regenerate the sweep

Exit status: 0 held, 1 a difference, 2 an input could not be read.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LCB = os.path.join(ROOT, "src", "box3dxt.lcb")
SHIM = os.path.join(ROOT, "src", "box3d_shim.c")
SELFTEST = os.path.join(ROOT, "tests", "engine-selftest.lc")

SWEEP_BEGIN = "-- >>> BEGIN SWEEP (generated: tools/check-lcb-signatures.py --write) >>>"
SWEEP_END = "-- <<< END SWEEP <<<"

# The only types this binding uses. Deliberately not a permissive map: a new
# type on either side must be added here on purpose, so "the checker did not
# know that type" can never read as "the signatures agree".
LCB_TO_C = {"CInt": "int", "CDouble": "double", "nothing": "void", "Pointer": "const char*"}
PUBLIC_OVER = {"CInt": ("Integer", "Boolean"), "CDouble": ("Number",), "Pointer": ("String", "Data"),
               "nothing": ("nothing",)}
# The exports whose Pointer is BYTES, not text: public as Data, copied by
# dataOf(). Every other Pointer is text and public as String. A name is
# here on purpose: textOf() on a picture would stop at its first zero byte,
# and dataOf() on a text would copy a picture's length out of a short buffer.
DATA = {"b3x_render_pixels"}
# The export with no public handler: the helper textOf() calls it to measure
# a text result before the engine copies it (the shim says why).
INTERNAL = {"b3x_text_length"}
# Spellings that are not plain capitalised words (the binding's header says so).
TOKEN = {"aabb": "AABB", "avx2": "AVX2", "abi": "ABI"}
MIN_EXPORTS = 300

BIND_RE = re.compile(r'^\s*private\s+foreign\s+handler\s+(\w+)\s*\((.*?)\)\s*returns\s+(\w+)\s+'
                     r'binds\s+to\s+"c:box3dxt>(b3x_\w+)!cdecl"\s*$')
PARAM_RE = re.compile(r"^\s*in\s+(\w+)\s+as\s+(\w+)\s*$")
BUILTIN_RES = {
    "MCStringCreateWithBytes": re.compile(
        r'^foreign handler MCStringCreateWithBytes\(in pBytes as Pointer, in pByteCount as CUInt, '
        r'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String\) returns CBool '
        r'binds to "<builtin>"\s*$'),
    "MCDataCreateWithBytes": re.compile(
        r'^foreign handler MCDataCreateWithBytes\(in pBytes as Pointer, in pByteCount as CUInt, '
        r'out rData as Data\) returns CBool binds to "<builtin>"\s*$'),
}
PUBLIC_RE = re.compile(r"^public\s+handler\s+(\w+)\s*\((.*?)\)\s*returns\s+(\w+)\s*$")
DEF_RE = re.compile(r"^LC_API\s+([^(;{]+?)\b(b3x_\w+)\s*\(([^)]*)\)", re.M | re.S)


def public_name(symbol):
    return "b3" + "".join(TOKEN.get(w, w[:1].upper() + w[1:]) for w in symbol[4:].split("_"))


def strip_c_comments(text):
    return re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)


def parse_shim(text):
    out = {}
    for m in DEF_RE.finditer(strip_c_comments(text)):
        ret = re.sub(r"\s+", " ", m.group(1).strip()).replace(" *", "*")
        types = []
        for p in [p for p in m.group(3).split(",") if p.strip() and p.strip() != "void"]:
            types.append(re.sub(r"\s+", " ", re.sub(r"\b\w+\s*$", "", p.strip()).strip()).replace(" *", "*"))
        out[m.group(2)] = (ret, types)
    return out


def split_params(text):
    out = []
    for p in [p for p in text.split(",") if p.strip()]:
        m = PARAM_RE.match(p)
        if not m:
            return None
        out.append((m.group(1), m.group(2)))
    return out


def parse_lcb(text):
    """(foreign, public, problems). foreign: symbol -> dict; public: name -> dict."""
    foreign, public, problems = {}, {}, []
    builtins = {name: [] for name in BUILTIN_RES}
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = BIND_RE.match(line)
        if m:
            handler, params, ret, symbol = m.groups()
            pp = split_params(params)
            if pp is None or ret not in LCB_TO_C or any(t not in LCB_TO_C for _, t in pp):
                problems.append("box3dxt.lcb:%d: %s uses a type this gate does not know" % (i + 1, handler))
                continue
            if symbol in foreign:
                problems.append("box3dxt.lcb:%d: %s is bound twice" % (i + 1, symbol))
            foreign[symbol] = {"handler": handler, "line": i + 1, "ret": ret, "params": pp}
            continue
        which = [name for name, rx in BUILTIN_RES.items() if rx.match(line)]
        if which:
            # The TWO engine builtins the binding may name, each in the one
            # spelling above: textOf() copies a static C text with the first
            # (check 3) and dataOf() the picture with the second. Any other
            # builtin is a way around this gate, so it is refused by the
            # catch-all below.
            builtins[which[0]].append(i + 1)
            continue
        if re.match(r"^\s*(private\s+)?foreign\s+handler\b", line):
            problems.append("box3dxt.lcb:%d: a foreign handler this gate cannot read (one line, "
                            "c:box3dxt>b3x_...!cdecl)" % (i + 1))
            continue
        m = PUBLIC_RE.match(line)
        if m:
            name, params, ret = m.groups()
            pp = split_params(params)
            if pp is None:
                problems.append("box3dxt.lcb:%d: %s has a parameter this gate cannot read" % (i + 1, name))
                continue
            body = []
            j = i + 1
            while j < len(lines) and lines[j].strip() != "end handler":
                body.append(lines[j])
                j += 1
            # the doc block: the nearest `*/` must be the line right above
            doc = None
            if i > 0 and lines[i - 1].strip() == "*/":
                k = i - 2
                while k >= 0 and not lines[k].startswith("/**"):
                    k -= 1
                if k >= 0:
                    doc = "\n".join(lines[k + 1:i - 1])
            if name in public:
                problems.append("box3dxt.lcb:%d: public handler %s is defined twice" % (i + 1, name))
            public[name] = {"line": i + 1, "ret": ret, "params": pp, "body": "\n".join(body), "doc": doc}
        elif line.startswith("public handler"):
            problems.append("box3dxt.lcb:%d: a public handler this gate cannot read (one line, typed, "
                            "with a return type)" % (i + 1))
    for name, found in sorted(builtins.items()):
        if len(found) != 1:
            problems.append("box3dxt.lcb: %s must be declared exactly once "
                            "(found on lines: %s)" % (name, ", ".join(map(str, found)) or "none"))
    return foreign, public, problems


def sweep_block(lcb_text):
    """The generated sweep: every public handler once, with zeros."""
    _, public, _ = parse_lcb(lcb_text)
    zero = {"Integer": "0", "Number": "0", "Boolean": "false"}
    out = ["-- Every public handler of src/box3dxt.lcb, in file order, called once with",
           "-- zeros (false for a Boolean). One try for the lot: tName is the call that",
           "-- was being made when anything threw.",
           "command sweepEveryHandler",
           "   local tName",
           "   try"]
    for name, h in public.items():
        args = ", ".join(zero.get(t, "0") for _, t in h["params"])
        out.append('      put "%s" into tName' % name)
        if h["ret"] == "nothing":
            out.append("      %s%s" % (name, (" " + args) if args else ""))
        else:
            out.append("      get %s(%s)" % (name, args))
    out += ["   catch tError",
            '      check "sweep: " & tName, false, oneLine(tError)',
            "      exit sweepEveryHandler",
            "   end try",
            '   check "sweep: all %d public handlers called with zeros, none threw", true' % len(public),
            "end sweepEveryHandler"]
    return "\n".join(out) + "\n"


def between(text, begin, end):
    if text.count(begin) != 1 or text.count(end) != 1:
        return None
    i = text.index(begin) + len(begin) + 1
    j = text.index(end)
    return (text[i:j], i, j) if j >= i - 1 else None


def check(lcb_text, shim_text, selftest_text):
    """Problems and stats. Pure: the fixture test drives it on mutated text."""
    foreign, public, problems = parse_lcb(lcb_text)
    defs = parse_shim(shim_text)
    stats = {"exports": len(defs), "foreign": len(foreign), "public": len(public)}
    if len(defs) < MIN_EXPORTS:
        return ["only %d LC_API exports parsed from the shim (floor %d): the scanner is blind"
                % (len(defs), MIN_EXPORTS)], stats

    # 1. foreign against C
    for symbol, f in sorted(foreign.items()):
        where = "box3dxt.lcb:%d: %s -> %s" % (f["line"], f["handler"], symbol)
        if symbol not in defs:
            problems.append("%s: no LC_API definition in the shim (the engine could not resolve it)" % where)
            continue
        cret, cparams = defs[symbol]
        if LCB_TO_C[f["ret"]] != cret:
            problems.append("%s: declares %s (= %s), the shim returns %s" % (where, f["ret"], LCB_TO_C[f["ret"]], cret))
        if len(f["params"]) != len(cparams):
            problems.append("%s: declares %d parameter(s), the shim takes %d" % (where, len(f["params"]), len(cparams)))
            continue
        for n, ((_, lt), ct) in enumerate(zip(f["params"], cparams), 1):
            if LCB_TO_C[lt] != ct:
                problems.append("%s: parameter %d is declared %s (= %s), the shim takes %s"
                                % (where, n, lt, LCB_TO_C[lt], ct))
        # 2a. the foreign handler's own name
        if f["handler"] != "_" + symbol[4:]:
            problems.append("%s: the foreign handler must be named _%s" % (where, symbol[4:]))
    for symbol in sorted(set(defs) - set(foreign)):
        problems.append("box3d_shim.c: %s is exported with no foreign handler bound to it" % symbol)

    # 2b + 3. one public wrapper per export, by the mechanical name
    wanted = {}
    for symbol in defs:
        if symbol not in INTERNAL:
            wanted.setdefault(public_name(symbol), []).append(symbol)
    if "ZStringNative" in re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", lcb_text, flags=re.S)):
        problems.append("box3dxt.lcb names ZStringNative: a text result must cross as a Pointer (the engine "
                        "frees a returned C string)")
    helper = re.search(r"private handler textOf\(in pText as Pointer\) returns String(.*?)end handler", lcb_text, re.S)
    if not helper or "_text_length(pText)" not in helper.group(1) or "MCStringCreateWithBytes(pText, tLength," not in helper.group(1):
        problems.append("box3dxt.lcb: textOf() must measure with _text_length and copy with MCStringCreateWithBytes")
    helper = re.search(r"private handler dataOf\(in pBytes as Pointer\) returns Data(.*?)end handler", lcb_text, re.S)
    if not helper or "_render_byte_count()" not in helper.group(1) or "MCDataCreateWithBytes(pBytes, tLength," not in helper.group(1):
        problems.append("box3dxt.lcb: dataOf() must measure with _render_byte_count and copy with MCDataCreateWithBytes")
    for name, symbols in sorted(wanted.items()):
        if len(symbols) > 1:
            problems.append("the exports %s would share the public name %s" % (", ".join(symbols), name))
    for symbol, f in sorted(foreign.items()):
        if symbol in INTERNAL:
            continue
        name = public_name(symbol)
        p = public.get(name)
        if p is None:
            problems.append("box3dxt.lcb: %s has no public handler %s" % (symbol, name))
            continue
        where = "box3dxt.lcb:%d: %s" % (p["line"], name)
        calls = re.findall(r"(?<![\w.])(_[a-z]\w*)\s*\(", p["body"])
        if calls != [f["handler"]]:
            problems.append("%s must call %s once and no other foreign handler (it calls: %s)"
                            % (where, f["handler"], ", ".join(calls) or "none"))
            continue
        if p["ret"] not in PUBLIC_OVER[f["ret"]]:
            problems.append("%s returns %s over a %s" % (where, p["ret"], f["ret"]))
        if f["ret"] == "Pointer" and (p["ret"] == "Data") != (symbol in DATA):
            problems.append("%s returns %s, but %s gives %s" % (where, p["ret"], symbol,
                                                               "bytes (Data, by dataOf)" if symbol in DATA
                                                               else "text (String, by textOf)"))
        if len(p["params"]) != len(f["params"]):
            problems.append("%s takes %d parameter(s), its foreign handler %d"
                            % (where, len(p["params"]), len(f["params"])))
            continue
        m = re.search(re.escape(f["handler"]) + r"\s*\((.*)\)", p["body"])
        args = [a.strip() for a in m.group(1).split(",")] if m and m.group(1).strip() else []
        if len(args) != len(p["params"]):
            problems.append("%s passes %d argument(s) to %s, which takes %d"
                            % (where, len(args), f["handler"], len(f["params"])))
            continue
        for (pn, pt), (_, ft), arg in zip(p["params"], f["params"], args):
            if pt not in PUBLIC_OVER[ft]:
                problems.append("%s: %s is %s over a %s" % (where, pn, pt, ft))
            want = "asInt(%s)" % pn if pt == "Boolean" else pn
            if arg != want:
                problems.append("%s: passes %s where %s belongs (parameters in order; a Boolean through asInt)"
                                % (where, arg, want))
        if p["ret"] == "Boolean" and not re.search(r"^\s*return tR is not 0\s*$", p["body"], re.M):
            problems.append("%s returns Boolean but does not end `return tR is not 0`" % where)
        if p["ret"] in ("Integer", "Number") and not re.search(r"^\s*return tR\s*$", p["body"], re.M):
            problems.append("%s does not end `return tR`" % where)
        if p["ret"] == "String" and not re.search(r"^\s*return textOf\(tP\)\s*$", p["body"], re.M):
            problems.append("%s returns text but does not end `return textOf(tP)`" % where)
        if p["ret"] == "Data" and not re.search(r"^\s*return dataOf\(tP\)\s*$", p["body"], re.M):
            problems.append("%s returns bytes but does not end `return dataOf(tP)`" % where)
        if not re.search(r"^\s*unsafe\s*$", p["body"], re.M):
            problems.append("%s makes its foreign call outside `unsafe`" % where)
        # 4. the doc block
        if p["doc"] is None:
            problems.append("%s has no /** */ doc block directly above it" % where)
        else:
            if not re.search(r"^Summary: \S", p["doc"], re.M):
                problems.append("%s: its doc block has no Summary" % where)
            for pn, _ in p["params"]:
                if not re.search(r"^%s: \S" % re.escape(pn), p["doc"], re.M):
                    problems.append("%s: its doc block does not describe %s" % (where, pn))
            for documented in re.findall(r"^(p[A-Z]\w*): ", p["doc"], re.M):
                if documented not in [pn for pn, _ in p["params"]]:
                    problems.append("%s: its doc block describes %s, which it does not take" % (where, documented))
            has_returns = re.search(r"^Returns: \S", p["doc"], re.M) is not None
            if (p["ret"] != "nothing") != has_returns:
                problems.append("%s: %s" % (where, "returns a value its doc block does not describe"
                                            if p["ret"] != "nothing" else "returns nothing but documents a Returns"))
    for name in sorted(set(public) - set(public_name(s) for s in defs if s not in INTERNAL)):
        problems.append("box3dxt.lcb:%d: public handler %s wraps no export (names are mechanical)"
                        % (public[name]["line"], name))

    # 5. the ABI number, everywhere a bump must reach: the shim's define,
    # the number checkABI() tests and the one its message names, and the
    # doc block of b3ABIVersion, whose "this binding needs N." is what the
    # IDE's dictionary says. The sky (ABI 3, #190) moved the first three and
    # left the doc saying 2, and nothing here asked about it.
    abi = re.search(r"#define\s+B3X_ABI_VERSION\s+(\d+)", shim_text)
    guard = re.search(r"private handler checkABI\(\)(.*?)end handler", lcb_text, re.S)
    if not abi or not guard:
        problems.append("cannot find B3X_ABI_VERSION in the shim or checkABI() in the binding")
    else:
        n = abi.group(1)
        if not re.search(r"if tV is not %s then" % n, guard.group(1)) or ("ABI %s)" % n) not in guard.group(1):
            problems.append("checkABI() does not test for, and name, the shim's ABI %s" % n)
        said = re.findall(r"this binding needs (\d+)\.", (public.get("b3ABIVersion") or {}).get("doc") or "")
        if said != [n]:
            problems.append("b3ABIVersion's doc block must say once that this binding needs the shim's "
                            "ABI %s (it says: %s)" % (n, ", ".join(said) or "nothing"))

    # 6. the sweep
    span = between(selftest_text, SWEEP_BEGIN, SWEEP_END)
    if span is None:
        problems.append("engine-selftest.lc: the SWEEP marker pair is missing or repeated")
    else:
        if span[0] != sweep_block(lcb_text):
            problems.append("engine-selftest.lc: the sweep is stale (run tools/check-lcb-signatures.py --write)")
        rest = selftest_text[:span[1]] + selftest_text[span[2]:]
        if not re.search(r"^\s*sweepEveryHandler\s*$", rest, re.M):
            problems.append("engine-selftest.lc: nothing calls sweepEveryHandler")
    stats["params"] = sum(len(f["params"]) for f in foreign.values())
    return problems, stats


def main(argv):
    try:
        lcb_text = open(LCB, encoding="utf-8").read()
        shim_text = open(SHIM, encoding="utf-8").read()
        selftest_text = open(SELFTEST, encoding="utf-8").read()
    except OSError as e:
        print("check-lcb-signatures: cannot read its inputs: %s" % e)
        return 2
    if "--write" in argv:
        span = between(selftest_text, SWEEP_BEGIN, SWEEP_END)
        if span is None:
            print("check-lcb-signatures: engine-selftest.lc has no SWEEP marker pair to write between")
            return 2
        new = selftest_text[:span[1]] + sweep_block(lcb_text) + selftest_text[span[2]:]
        if new != selftest_text:
            with open(SELFTEST, "w", encoding="utf-8", newline="\n") as f:
                f.write(new)
            print("check-lcb-signatures: wrote the sweep of tests/engine-selftest.lc")
        selftest_text = new
    problems, stats = check(lcb_text, shim_text, selftest_text)
    if problems:
        print("check-lcb-signatures: FAILED")
        for p in problems[:60]:
            print("  - " + p)
        if len(problems) > 60:
            print("  ... and %d more" % (len(problems) - 60))
        return 1
    print("check-lcb-signatures: OK (%d foreign handlers against %d LC_API exports: %d parameters and %d "
          "return types matched; %d public handlers, each wrapping its one export by the mechanical name, "
          "documented, and called by the engine self-test's sweep)"
          % (stats["foreign"], stats["exports"], stats["params"], stats["foreign"], stats["public"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
