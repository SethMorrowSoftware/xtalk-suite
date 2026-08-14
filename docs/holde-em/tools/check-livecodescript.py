#!/usr/bin/env python3
"""Static gates for the .livecodescript layer.

OXT / LiveCode is a GUI runtime: there is no headless way to compile or run the
``.livecodescript`` files in CI or from an agent's sandbox. This script catches
the mistakes that are statically catchable *before* a human compiles in OXT —
the same gates documented in CLAUDE.md, bundled into one command.

Carried from Box2Dxt's ``tools/check-livecodescript.py`` (where every check has
caught real breakage); adapted for this repo: targets are every
``.livecodescript`` under ``src/`` and ``examples/``, and the embedded-kit
drift check was dropped as not-yet-applicable (restore it if this repo ever
embeds a library between sentinels).

It checks every target for:

  1. Smart/curly quotes — U+2018/2019/201C/201D anywhere (even in a comment or
     string) fail to compile in OXT. Must be zero.
  2. Handler balance — every ``on`` / ``command`` / ``function`` / ``getprop`` /
     ``setprop`` / ``before`` / ``after`` has a matching ``end <name>``.
  3. Control-structure balance — every block ``if … then`` / ``repeat`` /
     ``switch`` / ``try`` is closed by its ``end`` inside the handler that opens
     it. (Logical lines are reassembled across ``\\`` continuations and comments
     are stripped first, so multi-line ``if … then`` and ``else if`` do not
     false-positive.)
  4. The dangling-else pairing (a bare ``else`` after a single-line
     ``if … then <stmt>``), which the structural pass cannot see.

Usage::

    python3 tools/check-livecodescript.py

Exit status is non-zero if any gate fails (suitable for CI and pre-commit use).
"""

import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGETS = sorted(
    list((ROOT / "src").glob("*.livecodescript"))
    + list((ROOT / "examples").glob("*.livecodescript"))
)

SMART_QUOTES = {0x2018, 0x2019, 0x201C, 0x201D}
# Handler openers. The closer is always "end <name>"; "end if/repeat/switch/try"
# close control structures, not handlers, and are handled separately.
OPENERS = ("on", "command", "function", "getprop", "setprop", "before", "after")


def strip_comment(line):
    """Drop a trailing ``--`` line comment, but not a ``--`` inside a string.
    LiveCode strings have no backslash escapes, so a double quote always toggles
    in/out of a string."""
    out = []
    in_string = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"':
            in_string = not in_string
            out.append(c)
        elif not in_string and c == "-" and i + 1 < len(line) and line[i + 1] == "-":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def logical_lines(text):
    """Yield ``(lineno, code)`` logical lines: comments stripped, and physical
    lines joined across a trailing ``\\`` continuation. ``lineno`` is the first
    physical line of the logical line, for reporting."""
    out = []
    buf = ""
    start = None
    for i, raw in enumerate(text.split("\n"), 1):
        if start is None:
            start = i
        code = strip_comment(raw)
        if code.rstrip().endswith("\\"):
            buf += code.rstrip()[:-1] + " "
        else:
            buf += code
            out.append((start, buf))
            buf = ""
            start = None
    if buf:
        out.append((start, buf))
    return out


def check_smart_quotes(text):
    bad = []
    for i, raw in enumerate(text.split("\n"), 1):
        hits = [c for c in raw if ord(c) in SMART_QUOTES]
        if hits:
            bad.append(f"  L{i}: smart quote(s) {''.join(sorted(set(hits)))} — use straight ASCII")
    return bad


def check_structure(text):
    """Single pass that proves handler-name matching *and* control-structure
    balance. Returns a list of human-readable error strings.

    ``repeat`` / ``switch`` / ``try`` are unambiguous blocks, matched strictly.
    ``if`` is matched leniently: LiveCode allows single-line ``if … then X`` and
    hybrid chains (``if … then X`` / ``else if … then`` block / ``end if``), so a
    block ``if … then`` is pushed but an ``end if`` with no open ``if`` is
    ignored rather than flagged. A truly unclosed block ``if`` is still caught,
    because its open frame trips the end-of-handler "unclosed" check below."""
    errors = []
    handler = None          # (name, lineno) of the open handler, or None
    ctrl = []               # stack of (kind, lineno) inside the current handler

    for lineno, code in logical_lines(text):
        low = code.strip().lower()
        if not low:
            continue
        toks = low.split()

        if handler is None:
            if toks[0] in OPENERS:
                handler = (toks[1] if len(toks) > 1 else "?", lineno)
                ctrl = []
            continue

        # --- inside a handler ---
        if toks[0] == "end" and len(toks) >= 2 and toks[1] in ("if", "repeat", "switch", "try"):
            kind = toks[1]
            if kind == "if":
                if ctrl and ctrl[-1][0] == "if":
                    ctrl.pop()                   # else: hybrid chain / stray — leniently ignore
            elif ctrl and ctrl[-1][0] == kind:
                ctrl.pop()
            else:
                errors.append(f"  L{lineno}: stray 'end {kind}' in handler '{handler[0]}'")
        elif toks[0] == "end":
            name = toks[1] if len(toks) > 1 else ""
            if ctrl:
                kind, opened = ctrl[-1]
                errors.append(
                    f"  handler '{handler[0]}' (L{handler[1]}): unclosed '{kind}' opened at L{opened}"
                )
            elif name != handler[0]:
                errors.append(f"  L{lineno}: 'end {name}' closes handler '{handler[0]}' (L{handler[1]})")
            handler = None
            ctrl = []
        elif re.match(r"^if\b", low) and re.search(r"\bthen$", low):
            ctrl.append(("if", lineno))          # block if; "else if" starts with "else", so excluded
        elif toks[0] == "repeat":
            ctrl.append(("repeat", lineno))
        elif toks[0] == "switch":
            ctrl.append(("switch", lineno))
        elif low == "try":
            ctrl.append(("try", lineno))

    if handler is not None:
        errors.append(f"  handler '{handler[0]}' (L{handler[1]}): never closed (missing 'end {handler[0]}')")
    return errors


def check_dangling_else(text):
    """A single-line ``if … then <stmt>`` directly followed by a BARE ``else``
    line. LiveCode/OXT binds that else to the single-line if (the dangling-else
    rule), so the bare else opens a block belonging to the *inner* if — its
    ``end if`` then closes the wrong frame and the *outer* block-if is left
    open, surfacing as a baffling "missing end if" at the handler's end. Legal
    neighbours are ``else <statement>`` (single-line chain) or a bare ``else``
    under a block ``if … then``; this exact pairing is the only broken one,
    and the purely structural pass above cannot see it."""
    errors = []
    lines = logical_lines(text)
    for (ln, code), (ln2, nxt) in zip(lines, lines[1:]):
        low = code.strip().lower()
        nlow = nxt.strip().lower()
        if (
            re.match(r"^if\b.+\bthen\s+\S", low)
            and not re.search(r"\bthen$", low)
            and nlow == "else"
        ):
            errors.append(
                f"  L{ln2}: bare 'else' after single-line 'if … then <stmt>' (L{ln}) — "
                "OXT binds the else to the inner if; make that if block-form"
            )
    return errors


def main():
    if not TARGETS:
        print("no .livecodescript files yet (src/ and examples/ are empty) — nothing to gate.")
        return 0

    failures = 0
    for path in TARGETS:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        problems = []
        problems += check_smart_quotes(text)
        problems += check_structure(text)
        problems += check_dangling_else(text)
        if problems:
            failures += 1
            print(f"FAIL  {rel}")
            for p in problems:
                print(p)
        else:
            print(f"ok    {rel}")

    print()
    if failures:
        print(f"FAILED — {failures} check(s) need attention.")
        return 1
    print("All .livecodescript gates passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
