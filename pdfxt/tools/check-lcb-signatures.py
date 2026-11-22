#!/usr/bin/env python3
"""check-lcb-signatures.py - src/pdfxt.lcb against src/pdfium_shim.c, and the
engine self-test's sweep against both.

The binding is a 1:1 wrapper over the C shim, and nothing at run time checks
that the two agree: the engine resolves a symbol by NAME and calls it with
whatever the declaration says, so a declaration that promises CInt where the
shim returns double does not fail to load and does not raise - it reads a
garbage register and hands script a plausible number. This is box3dxt's gate
of the same name, widened for a binding that also carries text IN (a path, a
password, a word to find) and bytes both ways (a PDF in, a drawn page out).

What is held, each named when it fails:

  1. every `private foreign handler` against the LC_API definition it binds:
     the symbol exists, the return type, the arity, each parameter type;
  2. the names are MECHANICAL, both steps: the foreign handler for
     pdx_page_count is _pdx_page_count and its one public wrapper is
     pdfPageCount. Every export is bound once and wrapped once, no public
     handler wraps anything else, and none is left over;
  3. each public wrapper matches its foreign handler: the same parameters in
     the same order, Integer or Boolean over CInt, Number over CDouble,
     String over ZStringUTF8, and a Data over the PAIR (Pointer, CInt),
     passed as tBytes, tLength after MCDataGetBytePtr and a length of 0
     turned away first (the pointer of an empty Data is not one to pass). A
     Boolean parameter goes through asInt() and a Boolean result is
     `tR is not 0`. A text result is a Pointer copied by textOf(), a bytes
     result a Pointer copied by dataOf(), and NO foreign handler may return
     ZStringNative or ZStringUTF8: the engine frees a returned C string, and
     the shim's results are its own buffers;
  4. every public handler has its own doc block: a Summary, one entry per
     parameter by name, a Returns when it returns something. The IDE's
     dictionary is made from these blocks and from nothing else;
  5. checkABI() names the shim's PDX_ABI_VERSION;
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
LCB = os.path.join(ROOT, "src", "pdfxt.lcb")
SHIM = os.path.join(ROOT, "src", "pdfium_shim.c")
SELFTEST = os.path.join(ROOT, "tests", "engine-selftest.lc")

SWEEP_BEGIN = "-- >>> BEGIN SWEEP (generated: tools/check-lcb-signatures.py --write) >>>"
SWEEP_END = "-- <<< END SWEEP <<<"

# The only types this binding uses. Deliberately not a permissive map: a new
# type on either side must be added here on purpose, so "the checker did not
# know that type" can never read as "the signatures agree".
# A Pointer is text coming back (const char*) or bytes either way (const
# unsigned char*); which one decides the public type over it, so both are
# named and nothing else is a Pointer.
LCB_TO_C = {"CInt": ("int",), "CDouble": ("double",), "nothing": ("void",),
            "Pointer": ("const char*", "const unsigned char*"), "ZStringUTF8": ("const char*",)}
PUBLIC_OVER = {"CInt": ("Integer", "Boolean"), "CDouble": ("Number",), "ZStringUTF8": ("String",),
               "nothing": ("nothing",)}
RESULT_OVER = {"const char*": ("String", "textOf"), "const unsigned char*": ("Data", "dataOf")}
# The exports with no public handler: textOf() and dataOf() call them to
# measure a result before the engine copies it, and to release a drawn page.
INTERNAL = {"pdx_text_length", "pdx_data_length", "pdx_data_release"}
# Spellings that are not plain capitalised words.
TOKEN = {"abi": "ABI", "bmp": "BMP"}
MIN_EXPORTS = 30

BIND_RE = re.compile(r'^\s*private\s+foreign\s+handler\s+(\w+)\s*\((.*?)\)\s*returns\s+(\w+)\s+'
                     r'binds\s+to\s+"c:pdfxt>(pdx_\w+)!cdecl"\s*$')
PARAM_RE = re.compile(r"^\s*in\s+(\w+)\s+as\s+(\w+)\s*$")
# The THREE engine builtins the binding may name, each as exactly this line:
# textOf() and dataOf() copy a result with the first two, and a Data going in
# is reached through the third (check 3). Any other builtin is a way around
# this gate, so it is refused by the catch-all in parse_lcb.
BUILTINS = (
    'foreign handler MCStringCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
    'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String) returns CBool '
    'binds to "<builtin>"',
    'foreign handler MCDataCreateWithBytes(in pBytes as Pointer, in pCount as CUInt, out rData as Data) '
    'returns CBool binds to "<builtin>"',
    'foreign handler MCDataGetBytePtr(in pData as Data) returns Pointer binds to "<builtin>"',
)
PUBLIC_RE = re.compile(r"^public\s+handler\s+(\w+)\s*\((.*?)\)\s*returns\s+(\w+)\s*$")
DEF_RE = re.compile(r"^LC_API\s+([^(;{]+?)\b(pdx_\w+)\s*\(([^)]*)\)", re.M | re.S)


def public_name(symbol):
    return "pdf" + "".join(TOKEN.get(w, w[:1].upper() + w[1:]) for w in symbol[4:].split("_"))


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
    builtins = []
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = BIND_RE.match(line)
        if m:
            handler, params, ret, symbol = m.groups()
            pp = split_params(params)
            if pp is None or ret not in LCB_TO_C or any(t not in LCB_TO_C for _, t in pp):
                problems.append("pdfxt.lcb:%d: %s uses a type this gate does not know" % (i + 1, handler))
                continue
            if symbol in foreign:
                problems.append("pdfxt.lcb:%d: %s is bound twice" % (i + 1, symbol))
            foreign[symbol] = {"handler": handler, "line": i + 1, "ret": ret, "params": pp}
            continue
        if line.rstrip() in BUILTINS:
            builtins.append(line.rstrip())
            continue
        if re.match(r"^\s*(private\s+)?foreign\s+handler\b", line):
            problems.append("pdfxt.lcb:%d: a foreign handler this gate cannot read (one line, "
                            "c:pdfxt>pdx_...!cdecl, or one of the three builtins as written)" % (i + 1))
            continue
        m = PUBLIC_RE.match(line)
        if m:
            name, params, ret = m.groups()
            pp = split_params(params)
            if pp is None:
                problems.append("pdfxt.lcb:%d: %s has a parameter this gate cannot read" % (i + 1, name))
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
                problems.append("pdfxt.lcb:%d: public handler %s is defined twice" % (i + 1, name))
            public[name] = {"line": i + 1, "ret": ret, "params": pp, "body": "\n".join(body), "doc": doc}
        elif line.startswith("public handler"):
            problems.append("pdfxt.lcb:%d: a public handler this gate cannot read (one line, typed, "
                            "with a return type)" % (i + 1))
    if sorted(builtins) != sorted(BUILTINS):
        problems.append("pdfxt.lcb: each of the three engine builtins must be declared exactly once "
                        "(found %d declarations)" % len(builtins))
    return foreign, public, problems


def sweep_block(lcb_text):
    """The generated sweep: every public handler once, with zeros."""
    _, public, _ = parse_lcb(lcb_text)
    zero = {"Integer": "0", "Number": "0", "Boolean": "false", "String": "empty", "Data": "empty"}
    out = ["-- Every public handler of src/pdfxt.lcb, in file order, called once with",
           "-- zeros (false for a Boolean, empty for text and bytes). One try for the",
           "-- lot: tName is the call that was being made when anything threw.",
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
            '   check "sweep: all %d public handlers called with zeros and empties, none threw", true' % len(public),
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
        where = "pdfxt.lcb:%d: %s -> %s" % (f["line"], f["handler"], symbol)
        if symbol not in defs:
            problems.append("%s: no LC_API definition in the shim (the engine could not resolve it)" % where)
            continue
        cret, cparams = defs[symbol]
        if cret not in LCB_TO_C[f["ret"]] or f["ret"] == "ZStringUTF8":
            problems.append("%s: declares %s, the shim returns %s" % (where, f["ret"], cret))
        if len(f["params"]) != len(cparams):
            problems.append("%s: declares %d parameter(s), the shim takes %d" % (where, len(f["params"]), len(cparams)))
            continue
        for n, ((_, lt), ct) in enumerate(zip(f["params"], cparams), 1):
            if ct not in LCB_TO_C[lt] or (lt == "Pointer" and ct != "const unsigned char*"
                                          and symbol not in INTERNAL):
                problems.append("%s: parameter %d is declared %s, the shim takes %s" % (where, n, lt, ct))
        # 2a. the foreign handler's own name
        if f["handler"] != "_" + symbol:
            problems.append("%s: the foreign handler must be named _%s" % (where, symbol))
    for symbol in sorted(set(defs) - set(foreign)):
        problems.append("pdfium_shim.c: %s is exported with no foreign handler bound to it" % symbol)

    # 2b + 3. one public wrapper per export, by the mechanical name
    wanted = {}
    for symbol in defs:
        if symbol not in INTERNAL:
            wanted.setdefault(public_name(symbol), []).append(symbol)
    if "ZStringNative" in re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", lcb_text, flags=re.S)):
        problems.append("pdfxt.lcb names ZStringNative: a text result must cross as a Pointer (the engine "
                        "frees a returned C string)")
    helper = re.search(r"private handler textOf\(in pText as Pointer\) returns String(.*?)end handler", lcb_text, re.S)
    if not helper or "_pdx_text_length(pText)" not in helper.group(1) or "MCStringCreateWithBytes(pText, tLength, 4," not in helper.group(1):
        problems.append("pdfxt.lcb: textOf() must measure with _pdx_text_length and copy with "
                        "MCStringCreateWithBytes as UTF-8 (encoding 4)")
    helper = re.search(r"private handler dataOf\(in pBytes as Pointer\) returns Data(.*?)end handler", lcb_text, re.S)
    if not helper or "_pdx_data_length()" not in helper.group(1) or "_pdx_data_release()" not in helper.group(1) \
            or "MCDataCreateWithBytes(pBytes, tLength," not in helper.group(1):
        problems.append("pdfxt.lcb: dataOf() must measure with _pdx_data_length, copy with "
                        "MCDataCreateWithBytes and release with _pdx_data_release")
    for name, symbols in sorted(wanted.items()):
        if len(symbols) > 1:
            problems.append("the exports %s would share the public name %s" % (", ".join(symbols), name))
    for symbol, f in sorted(foreign.items()):
        if symbol in INTERNAL:
            continue
        name = public_name(symbol)
        p = public.get(name)
        if p is None:
            problems.append("pdfxt.lcb: %s has no public handler %s" % (symbol, name))
            continue
        where = "pdfxt.lcb:%d: %s" % (p["line"], name)
        calls = re.findall(r"(?<![\w.])(_[a-z]\w*)\s*\(", p["body"])
        if calls != [f["handler"]]:
            problems.append("%s must call %s once and no other foreign handler (it calls: %s)"
                            % (where, f["handler"], ", ".join(calls) or "none"))
            continue
        cret = defs[symbol][0] if symbol in defs else ""
        if f["ret"] == "Pointer":
            want_ret, copier = RESULT_OVER.get(cret, ("?", "?"))
            if p["ret"] != want_ret:
                problems.append("%s returns %s over a %s" % (where, p["ret"], cret))
            if not re.search(r"^\s*return %s\(tP\)\s*$" % copier, p["body"], re.M):
                problems.append("%s does not end `return %s(tP)`" % (where, copier))
        elif p["ret"] not in PUBLIC_OVER[f["ret"]]:
            problems.append("%s returns %s over a %s" % (where, p["ret"], f["ret"]))
        # The foreign parameters the public ones stand for: a Data is the
        # pair (Pointer, CInt), everything else one for one.
        m = re.search(re.escape(f["handler"]) + r"\s*\((.*)\)", p["body"])
        args = [a.strip() for a in m.group(1).split(",")] if m and m.group(1).strip() else []
        want_args, want_types, bad = [], [], False
        for pn, pt in p["params"]:
            if pt == "Data":
                want_args += ["tBytes", "tLength"]
                want_types += ["Pointer", "CInt"]
                if ("put the number of bytes in %s into tLength" % pn) not in p["body"] \
                        or ("put MCDataGetBytePtr(%s) into tBytes" % pn) not in p["body"] \
                        or not re.search(r"if tLength is 0 then\s*\n\s*return 0\s*\n\s*end if", p["body"]):
                    problems.append("%s: %s is a Data and must be measured, turned away when empty, and "
                                    "reached through MCDataGetBytePtr" % (where, pn))
            elif pt in ("Integer", "Boolean"):
                want_args.append("asInt(%s)" % pn if pt == "Boolean" else pn)
                want_types.append("CInt")
            elif pt == "Number":
                want_args.append(pn)
                want_types.append("CDouble")
            elif pt == "String":
                want_args.append(pn)
                want_types.append("ZStringUTF8")
            else:
                problems.append("%s: %s has a type this gate does not know (%s)" % (where, pn, pt))
                bad = True
        if bad:
            continue
        if want_types != [t for _, t in f["params"]]:
            problems.append("%s: its parameters (%s) do not stand for its foreign handler's (%s)"
                            % (where, ", ".join(t for _, t in p["params"]), ", ".join(t for _, t in f["params"])))
            continue
        if args != want_args:
            problems.append("%s: passes (%s) where (%s) belongs (parameters in order; a Boolean through "
                            "asInt; a Data as tBytes, tLength)" % (where, ", ".join(args), ", ".join(want_args)))
        if p["ret"] == "Boolean" and not re.search(r"^\s*return tR is not 0\s*$", p["body"], re.M):
            problems.append("%s returns Boolean but does not end `return tR is not 0`" % where)
        if p["ret"] in ("Integer", "Number") and not re.search(r"^\s*return tR\s*$", p["body"], re.M):
            problems.append("%s does not end `return tR`" % where)
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
        problems.append("pdfxt.lcb:%d: public handler %s wraps no export (names are mechanical)"
                        % (public[name]["line"], name))

    # 5. the ABI number
    abi = re.search(r"#define\s+PDX_ABI_VERSION\s+(\d+)", shim_text)
    guard = re.search(r"private handler checkABI\(\)(.*?)end handler", lcb_text, re.S)
    if not abi or not guard:
        problems.append("cannot find PDX_ABI_VERSION in the shim or checkABI() in the binding")
    else:
        n = abi.group(1)
        if not re.search(r"if tV is not %s then" % n, guard.group(1)) or ("ABI %s)" % n) not in guard.group(1):
            problems.append("checkABI() does not test for, and name, the shim's ABI %s" % n)

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
