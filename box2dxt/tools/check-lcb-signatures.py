#!/usr/bin/env python3
"""Hold every ``foreign handler`` in ``src/box2dxt.lcb`` to the ``LC_API``
definition it binds to in ``src/box2d_lc.c``.

The LCB binding is a 1:1 wrapper over the C shim: 370 ``private foreign
handler`` declarations, each naming its C symbol in a
``binds to "c:box2dxt>b2lc_*!cdecl"`` string. Nothing checks that the two
sides agree. **Nothing can, at run time either**: the engine resolves the
symbol by NAME through ``the revLibraryMapping`` and then calls it with
whatever the declaration says, so a declaration that promises ``CInt`` where
the shim returns ``double`` does not fail to load and does not raise — it
reads a garbage register and hands the result to script as a plausible
number. That is the same silence as the family's other expensive traps (an
undeclared LiveCodeScript name evaluating to its own text; ``b2SetShapeFilter``
refusing a call above the 2^53 guard), and it is worse here because the wrong
answer crosses the FFI wearing the right type.

What this compares, per bound symbol:

  * the RETURN type   (``returns CInt`` / ``CDouble`` / ``nothing`` vs
    ``int`` / ``double`` / ``void``),
  * the ARITY, and
  * each PARAMETER type, in order.

It also reports a bind whose symbol has no ``LC_API`` definition (a typo in
the bind string is otherwise a load-time failure the user meets, not the
build) and an ``LC_API`` export nothing binds to (dead ABI, or a wrapper
somebody forgot).

The regex is anchored on the ``c:box2dxt>`` token, which is what keeps the
three POSIX binds in the loader assist (``dlopen``/``dlerror``/``realpath``,
bound as ``c:>``) out of the comparison WITHOUT an exemption list — an
exemption list is a thing that goes stale, and a token that names the library
cannot.

Usage::

    python3 tools/check-lcb-signatures.py

Exits non-zero on any mismatch, and prints the honest counts either way.
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LCB = ROOT / "src" / "box2dxt.lcb"
SHIM = ROOT / "src" / "box2d_lc.c"

# The only LCB types this binding uses. Deliberately NOT a permissive map: a
# new type on either side must be added here on purpose, so "the checker did
# not know that type" can never read as "the signatures agree".
LCB_TO_C = {
    "CInt": "int",
    "CDouble": "double",
    "nothing": "void",
}

# `binds to "c:box2dxt>b2lc_world_step!cdecl"` -- the library token is what
# scopes this to the shim's own exports (see the module docstring).
BIND_RE = re.compile(
    r'^\s*(?:private\s+)?foreign\s+handler\s+(\w+)\s*\((.*?)\)\s*'
    r'returns\s+(\w+)\s+binds\s+to\s+"c:box2dxt>(b2lc_\w+)!cdecl"\s*$'
)
PARAM_RE = re.compile(r'^\s*(?:in|out|inout)\s+\w+\s+as\s+(\w+)\s*$')

# The shim's definitions. Every export is `LC_API <ret> b2lc_name(params) {`,
# some of them wrapped over two lines, hence the DOTALL on the parameter list.
DEF_RE = re.compile(
    r'LC_API\s+(void|int|double)\s+(b2lc_\w+)\s*\(([^)]*)\)', re.S
)


def parse_lcb(text):
    """symbol -> (lcb_handler_name, return_c_type, [param_c_types]), by line."""
    out = {}
    problems = []
    for lineno, line in enumerate(text.splitlines(), 1):
        m = BIND_RE.match(line)
        if not m:
            continue
        handler, params, ret, symbol = m.groups()
        if ret not in LCB_TO_C:
            problems.append(f"{LCB.name}:{lineno}: unknown LCB return type {ret!r} on {handler}")
            continue
        types, raw = [], []
        for p in [p for p in params.split(",") if p.strip()]:
            pm = PARAM_RE.match(p)
            if not pm or pm.group(1) not in LCB_TO_C:
                problems.append(f"{LCB.name}:{lineno}: unparsed parameter {p.strip()!r} on {handler}")
                types = None
                break
            types.append(LCB_TO_C[pm.group(1)])
            raw.append(pm.group(1))
        if types is None:
            continue
        if symbol in out:
            problems.append(f"{LCB.name}:{lineno}: {symbol} is bound twice")
        out[symbol] = (handler, lineno, LCB_TO_C[ret], types, ret, raw)
    return out, problems


def parse_shim(text):
    """symbol -> (return_c_type, [param_c_types])."""
    out = {}
    for m in DEF_RE.finditer(text):
        ret, name, params = m.group(1), m.group(2), m.group(3)
        types = []
        for p in [p for p in params.split(",") if p.strip()]:
            p = re.sub(r"\s+", " ", p.strip())
            if p == "void":
                continue
            types.append(re.sub(r"\s*\b\w+$", "", p).strip())
        out[name] = (ret, types)
    return out


def main(argv):
    lcb_text = LCB.read_text(encoding="utf-8")
    shim_text = SHIM.read_text(encoding="utf-8")
    binds, problems = parse_lcb(lcb_text)
    defs = parse_shim(shim_text)

    for symbol in sorted(binds):
        handler, lineno, ret, params, lcb_ret, lcb_params = binds[symbol]
        if symbol not in defs:
            problems.append(
                f"{LCB.name}:{lineno}: {handler} binds {symbol}, which has no LC_API "
                f"definition in {SHIM.name} (the engine would fail to resolve it at load)"
            )
            continue
        cret, cparams = defs[symbol]
        if ret != cret:
            problems.append(
                f"{LCB.name}:{lineno}: {handler} -> {symbol}: declares {lcb_ret} "
                f"(= {ret}), the shim returns {cret}"
            )
        if len(params) != len(cparams):
            problems.append(
                f"{LCB.name}:{lineno}: {handler} -> {symbol}: declares {len(params)} "
                f"parameter(s), the shim takes {len(cparams)}"
            )
            continue
        for i, (a, b) in enumerate(zip(params, cparams), 1):
            if a != b:
                problems.append(
                    f"{LCB.name}:{lineno}: {handler} -> {symbol}: parameter {i} is "
                    f"declared {lcb_params[i - 1]} (= {a}), the shim takes {b}"
                )

    unbound = sorted(set(defs) - set(binds))
    for symbol in unbound:
        problems.append(
            f"{SHIM.name}: {symbol} is exported with no foreign handler bound to it "
            f"(dead ABI, or a missing wrapper)"
        )

    if problems:
        print("check-lcb-signatures: FAILED")
        for p in problems:
            print(f"  - {p}")
        return 1

    # Report what was CHECKED, not what was parsed -- the coinxt constant-gate
    # lesson: a gate that reports its parse count answers a question nobody
    # asks twice.
    args = sum(len(v[3]) for v in binds.values())
    print(
        f"check-lcb-signatures: OK ({len(binds)} foreign handlers checked against "
        f"{len(defs)} LC_API exports; {args} parameters + {len(binds)} return types matched)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
