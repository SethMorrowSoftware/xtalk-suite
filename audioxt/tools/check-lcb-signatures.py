#!/usr/bin/env python3
"""check-lcb-signatures.py - src/audioxt.lcb against src/audio_shim.c, and the
engine self-test's sweep against both.

The binding is a 1:1 wrapper over the C shim, and nothing at run time checks
that the two agree: the engine resolves a symbol by NAME and calls it with
whatever the declaration says, so a declaration that promises CInt where the
shim returns double does not fail to load and does not raise - it reads a
garbage register and hands script a plausible number (box3dxt's gate of the
same name says the same; this one is that gate, widened for a binding that
also carries text arguments and bytes in both directions).

What is held, each named when it fails:

  1. every `private foreign handler` against the LC_API definition it binds:
     the symbol exists, the return type, the arity, each parameter type;
  2. the names are MECHANICAL, both steps: the foreign handler for
     aux_sound_set_volume is _sound_set_volume and its one public wrapper
     is auSoundSetVolume. Every export is bound once and wrapped once, no
     public handler wraps anything else, and none is left over;
  3. each public wrapper matches its foreign handler: the same parameters,
     in the same order, Integer or Boolean over CInt, Number over CDouble,
     String over ZStringUTF8; a Boolean parameter is passed through asInt()
     and a Boolean result is `tR is not 0`. (A Boolean handed to a CInt
     unconverted is a type error at the first call.) A text result is a
     Pointer copied by textOf(), and NO foreign handler may return
     ZStringNative: the engine frees a returned C string, and the shim's
     texts are static buffers (box3dxt's first engine run died of exactly
     that). BYTES IN are the one place a wrapper and its foreign handler
     differ in arity: the C pair (const void *bytes, int length) is ONE
     public `pData as Data`, measured with `the number of bytes in pData`
     and pointed at with MCDataGetBytePtr(pData), nothing else. BYTES OUT
     are a byte count copied by dataOf(): the wrappers that return Data are
     exactly DATA_OUT below, so a count can never reach script as a number
     by accident, nor a number be read as a count;
  4. every public handler has its own doc block: a Summary, one entry per
     parameter by name, a Returns when it returns something. The IDE's
     dictionary is made from these blocks and from nothing else;
  5. checkABI() names the shim's AUX_ABI_VERSION;
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
LCB = os.path.join(ROOT, "src", "audioxt.lcb")
SHIM = os.path.join(ROOT, "src", "audio_shim.c")
SELFTEST = os.path.join(ROOT, "tests", "engine-selftest.lc")

SWEEP_BEGIN = "-- >>> BEGIN SWEEP (generated: tools/check-lcb-signatures.py --write) >>>"
SWEEP_END = "-- <<< END SWEEP <<<"

# The only types this binding uses. Deliberately not a permissive map: a new
# type on either side must be added here on purpose, so "the checker did not
# know that type" can never read as "the signatures agree".
# RETURNS: what a foreign handler may declare over each C return type.
RET_TO_C = {"CInt": ("int",), "CDouble": ("double",), "nothing": ("void",),
            "Pointer": ("const char*", "const void*")}
# PARAMETERS: text goes in as ZStringUTF8 (the engine makes and frees the C
# string), bytes as a Pointer. A Pointer over `const char*` is right in one
# place only, the internal aux_text_length, which is handed a pointer the
# shim itself returned.
PARAM_TO_C = {"CInt": ("int",), "CDouble": ("double",), "ZStringUTF8": ("const char*",),
              "Pointer": ("const void*",)}
PUBLIC_RET = {"CInt": ("Integer", "Boolean", "Data"), "CDouble": ("Number",), "Pointer": ("String",),
              "nothing": ("nothing",)}
PUBLIC_PARAM = {"CInt": ("Integer", "Boolean"), "CDouble": ("Number",), "ZStringUTF8": ("String",)}
# The exports with no public handler: the helpers textOf() and dataOf() call
# them to measure a text result and to find the out buffer (the shim says why).
INTERNAL = {"aux_text_length", "aux_out_pointer"}
# The wrappers whose CInt result is a BYTE COUNT in the out buffer, returned
# to script as Data. Named, not inferred: nothing in a C signature tells a
# count of bytes from any other int.
DATA_OUT = {"aux_engine_render", "aux_capture_read", "aux_decode_file", "aux_decode_data",
            "aux_wav_encode"}
# Spellings that are not plain capitalised words (the binding's header says so).
TOKEN = {"abi": "ABI", "pcm": "PCM", "xyz": "XYZ", "wav": "WAV"}
# What the sweep passes where zeros would not be safe: device 0 is the
# machine's real default device, so the sweep opens the silent test device
# instead (the sweep ends with auShutDown, the last handler of the file,
# which closes it).
SWEEP_ARGS = {"auEngineCreate": "-1, 0, 0"}
MIN_EXPORTS = 100

BIND_RE = re.compile(r'^\s*private\s+foreign\s+handler\s+(\w+)\s*\((.*?)\)\s*returns\s+(\w+)\s+'
                     r'binds\s+to\s+"c:audioxt>(aux_\w+)!cdecl"\s*$')
PARAM_RE = re.compile(r"^\s*in\s+(\w+)\s+as\s+(\w+)\s*$")
BUILTINS = {
    "MCStringCreateWithBytes":
        'foreign handler MCStringCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
        'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String) returns CBool '
        'binds to "<builtin>"',
    "MCDataCreateWithBytes":
        'foreign handler MCDataCreateWithBytes(in pBytes as Pointer, in pCount as CUInt, '
        'out rData as Data) returns CBool binds to "<builtin>"',
    "MCDataGetBytePtr":
        'foreign handler MCDataGetBytePtr(in pData as Data) returns Pointer binds to "<builtin>"',
}
PUBLIC_RE = re.compile(r"^public\s+handler\s+(\w+)\s*\((.*?)\)\s*returns\s+(\w+)\s*$")
DEF_RE = re.compile(r"^LC_API\s+([^(;{]+?)\b(aux_\w+)\s*\(([^)]*)\)", re.M | re.S)


def public_name(symbol):
    return "au" + "".join(TOKEN.get(w, w[:1].upper() + w[1:]) for w in symbol[4:].split("_"))


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
    builtins = {name: [] for name in BUILTINS}
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = BIND_RE.match(line)
        if m:
            handler, params, ret, symbol = m.groups()
            pp = split_params(params)
            if pp is None or ret not in RET_TO_C or any(t not in PARAM_TO_C for _, t in pp):
                problems.append("audioxt.lcb:%d: %s uses a type this gate does not know" % (i + 1, handler))
                continue
            if symbol in foreign:
                problems.append("audioxt.lcb:%d: %s is bound twice" % (i + 1, symbol))
            foreign[symbol] = {"handler": handler, "line": i + 1, "ret": ret, "params": pp}
            continue
        known = [name for name, text in BUILTINS.items() if line.rstrip() == text]
        if known:
            # The THREE engine builtins the binding may name, each exactly as
            # written above: textOf() and dataOf() copy out of the shim's
            # buffers with two of them, and a Data parameter is pointed at
            # with the third (check 3). Any other builtin is a way around
            # this gate, so it is refused by the catch-all below.
            builtins[known[0]].append(i + 1)
            continue
        if re.match(r"^\s*(private\s+)?foreign\s+handler\b", line):
            problems.append("audioxt.lcb:%d: a foreign handler this gate cannot read (one line, "
                            "c:audioxt>aux_...!cdecl)" % (i + 1))
            continue
        m = PUBLIC_RE.match(line)
        if m:
            name, params, ret = m.groups()
            pp = split_params(params)
            if pp is None:
                problems.append("audioxt.lcb:%d: %s has a parameter this gate cannot read" % (i + 1, name))
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
                problems.append("audioxt.lcb:%d: public handler %s is defined twice" % (i + 1, name))
            public[name] = {"line": i + 1, "ret": ret, "params": pp, "body": "\n".join(body), "doc": doc}
        elif line.startswith("public handler"):
            problems.append("audioxt.lcb:%d: a public handler this gate cannot read (one line, typed, "
                            "with a return type)" % (i + 1))
    for name, found in builtins.items():
        if len(found) != 1:
            problems.append("audioxt.lcb: %s must be declared exactly once "
                            "(found on lines: %s)" % (name, ", ".join(map(str, found)) or "none"))
    return foreign, public, problems


def sweep_block(lcb_text):
    """The generated sweep: every public handler once, with zeros."""
    _, public, _ = parse_lcb(lcb_text)
    zero = {"Integer": "0", "Number": "0", "Boolean": "false", "String": "empty", "Data": "empty"}
    out = ["-- Every public handler of src/audioxt.lcb, in file order, called once with",
           "-- zeros (false for a Boolean, empty for text and for data; the silent",
           "-- test device where 0 would open a real one). One try for the lot: tName",
           "-- is the call that was being made when anything threw.",
           "command sweepEveryHandler",
           "   local tName",
           "   try"]
    for name, h in public.items():
        args = SWEEP_ARGS.get(name) or ", ".join(zero.get(t, "0") for _, t in h["params"])
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
        where = "audioxt.lcb:%d: %s -> %s" % (f["line"], f["handler"], symbol)
        if symbol not in defs:
            problems.append("%s: no LC_API definition in the shim (the engine could not resolve it)" % where)
            continue
        cret, cparams = defs[symbol]
        if cret not in RET_TO_C[f["ret"]]:
            problems.append("%s: declares %s (= %s), the shim returns %s"
                            % (where, f["ret"], " or ".join(RET_TO_C[f["ret"]]), cret))
        if len(f["params"]) != len(cparams):
            problems.append("%s: declares %d parameter(s), the shim takes %d" % (where, len(f["params"]), len(cparams)))
            continue
        for n, ((_, lt), ct) in enumerate(zip(f["params"], cparams), 1):
            allowed = PARAM_TO_C[lt]
            if symbol in INTERNAL:
                # handed a pointer the shim returned, never a script string:
                # declared ZStringUTF8, the engine refuses the Pointer that
                # textOf() passes (the first engine run of this binding)
                allowed = ("const char*",) if lt == "Pointer" else ()
            if ct not in allowed:
                problems.append("%s: parameter %d is declared %s (= %s), the shim takes %s"
                                % (where, n, lt, " or ".join(allowed), ct))
        # 2a. the foreign handler's own name
        if f["handler"] != "_" + symbol[4:]:
            problems.append("%s: the foreign handler must be named _%s" % (where, symbol[4:]))
    for symbol in sorted(set(defs) - set(foreign)):
        problems.append("audio_shim.c: %s is exported with no foreign handler bound to it" % symbol)

    # 2b + 3. one public wrapper per export, by the mechanical name
    wanted = {}
    for symbol in defs:
        if symbol not in INTERNAL:
            wanted.setdefault(public_name(symbol), []).append(symbol)
    if "ZStringNative" in re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", lcb_text, flags=re.S)):
        problems.append("audioxt.lcb names ZStringNative: a text result must cross as a Pointer (the engine "
                        "frees a returned C string)")
    helper = re.search(r"private handler textOf\(in pText as Pointer\) returns String(.*?)end handler", lcb_text, re.S)
    if not helper or "_text_length(pText)" not in helper.group(1) or "MCStringCreateWithBytes(pText, tLength," not in helper.group(1):
        problems.append("audioxt.lcb: textOf() must measure with _text_length and copy with MCStringCreateWithBytes")
    helper = re.search(r"private handler dataOf\(in pCount as Integer\) returns Data(.*?)end handler", lcb_text, re.S)
    if (not helper or "put _out_pointer() into tBytes" not in helper.group(1)
            or "MCDataCreateWithBytes(tBytes, pCount," not in helper.group(1)
            or not re.search(r"if pCount <= 0 then\s+return the empty data", helper.group(1))):
        problems.append("audioxt.lcb: dataOf() must return the empty data for a count of 0 or less, and "
                        "otherwise copy pCount bytes from _out_pointer() with MCDataCreateWithBytes")
    for name, symbols in sorted(wanted.items()):
        if len(symbols) > 1:
            problems.append("the exports %s would share the public name %s" % (", ".join(symbols), name))
    for symbol, f in sorted(foreign.items()):
        if symbol in INTERNAL:
            continue
        name = public_name(symbol)
        p = public.get(name)
        if p is None:
            problems.append("audioxt.lcb: %s has no public handler %s" % (symbol, name))
            continue
        where = "audioxt.lcb:%d: %s" % (p["line"], name)
        calls = re.findall(r"(?<![\w.])(_[a-z]\w*)\s*\(", p["body"])
        if calls != [f["handler"]]:
            problems.append("%s must call %s once and no other foreign handler (it calls: %s)"
                            % (where, f["handler"], ", ".join(calls) or "none"))
            continue
        if p["ret"] not in PUBLIC_RET[f["ret"]]:
            problems.append("%s returns %s over a %s" % (where, p["ret"], f["ret"]))
        if (p["ret"] == "Data") != (symbol in DATA_OUT):
            problems.append("%s: %s" % (where, "returns Data but is not one of the byte-count exports (DATA_OUT)"
                                        if p["ret"] == "Data" else
                                        "wraps a byte-count export and must return Data through dataOf()"))
        # What the wrapper must take and pass, built from the foreign
        # handler: one public parameter per foreign one, bar the bytes pair.
        want_params, want_args, shape_ok, has_data = [], [], True, False
        fp = f["params"]
        n = 0
        while n < len(fp):
            fn, ft = fp[n]
            if ft == "Pointer":
                if (fn, ft) != ("pBytes", "Pointer") or n + 1 >= len(fp) or fp[n + 1] != ("pLength", "CInt") or has_data:
                    problems.append("%s: a Pointer parameter must be the one pair (pBytes as Pointer, "
                                    "pLength as CInt)" % where)
                    shape_ok = False
                    break
                want_params.append(("pData", ("Data",)))
                want_args += ["tBytes", "tLength"]
                has_data = True
                n += 2
                continue
            want_params.append((fn, PUBLIC_PARAM[ft]))
            want_args.append(None)   # the public parameter itself; asInt() if Boolean
            n += 1
        if not shape_ok:
            continue
        if len(p["params"]) != len(want_params):
            problems.append("%s takes %d parameter(s) where its foreign handler needs %d"
                            % (where, len(p["params"]), len(want_params)))
            continue
        m = re.search(re.escape(f["handler"]) + r"\s*\((.*)\)", p["body"])
        args = [a.strip() for a in m.group(1).split(",")] if m and m.group(1).strip() else []
        # asInt(pX) holds no comma, so the split above is exact
        if len(args) != len(want_args):
            problems.append("%s passes %d argument(s) to %s, which takes %d"
                            % (where, len(args), f["handler"], len(want_args)))
            continue
        a = 0
        for (pn, pt), (wn, wt) in zip(p["params"], want_params):
            if pn != wn:
                problems.append("%s: parameter %s where %s belongs (the foreign handler's names, in order)"
                                % (where, pn, wn))
            if pt not in wt:
                problems.append("%s: %s is %s where %s belongs" % (where, pn, pt, " or ".join(wt)))
            if wt == ("Data",):
                if args[a:a + 2] != ["tBytes", "tLength"]:
                    problems.append("%s: passes %s where tBytes, tLength belong" % (where, ", ".join(args[a:a + 2])))
                a += 2
                continue
            want = "asInt(%s)" % pn if pt == "Boolean" else pn
            if args[a] != want:
                problems.append("%s: passes %s where %s belongs (parameters in order; a Boolean through asInt)"
                                % (where, args[a], want))
            a += 1
        if has_data:
            if not re.search(r"^\s*put the number of bytes in pData into tLength\s*$", p["body"], re.M):
                problems.append("%s must measure its data with `put the number of bytes in pData into tLength`" % where)
            if not re.search(r"^\s*put MCDataGetBytePtr\(pData\) into tBytes\s*$", p["body"], re.M):
                problems.append("%s must point at its data with `put MCDataGetBytePtr(pData) into tBytes`" % where)
        elif "MCDataGetBytePtr" in p["body"]:
            problems.append("%s names MCDataGetBytePtr without a Data parameter" % where)
        if p["ret"] == "Data" and not re.search(r"^\s*return dataOf\(tR\)\s*$", p["body"], re.M):
            problems.append("%s returns Data but does not end `return dataOf(tR)`" % where)
        if p["ret"] == "Boolean" and not re.search(r"^\s*return tR is not 0\s*$", p["body"], re.M):
            problems.append("%s returns Boolean but does not end `return tR is not 0`" % where)
        if p["ret"] in ("Integer", "Number") and not re.search(r"^\s*return tR\s*$", p["body"], re.M):
            problems.append("%s does not end `return tR`" % where)
        if p["ret"] == "String" and not re.search(r"^\s*return textOf\(tP\)\s*$", p["body"], re.M):
            problems.append("%s returns text but does not end `return textOf(tP)`" % where)
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
        problems.append("audioxt.lcb:%d: public handler %s wraps no export (names are mechanical)"
                        % (public[name]["line"], name))

    # 5. the ABI number
    abi = re.search(r"#define\s+AUX_ABI_VERSION\s+(\d+)", shim_text)
    guard = re.search(r"private handler checkABI\(\)(.*?)end handler", lcb_text, re.S)
    if not abi or not guard:
        problems.append("cannot find AUX_ABI_VERSION in the shim or checkABI() in the binding")
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
