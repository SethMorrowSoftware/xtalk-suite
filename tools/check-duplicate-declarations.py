#!/usr/bin/env python3
"""check-duplicate-declarations.py - one name, declared once, per script.

WHY THIS EXISTS
    A .livecodescript compiles as ONE unit. Two script-level declarations of a
    name, or two definitions of a handler, is not a warning - it is a hard
    compile error ("name shadows another variable or constant"), and it takes
    the WHOLE file with it. The maintainer meets that at PASTE time, on an
    engine, which is the most expensive place in this project to learn anything.

    It has already happened. datachannel-dht-chat declared `local sPolling`
    while the enet/datachannel helper layer it now EMBEDS declares its own
    `sPolling` for the poll chain; before the embed they lived in two stacks and
    nothing collided. That reached an engine. See OXT-ENGINE-NOTES 1.6 and the
    rename note in that demo's own declarations.

WHY A NEW GATE RATHER THAN AN EXISTING ONE
    Measured, not assumed: check-livecodescript.py has no duplicate rule at all,
    and sync-demo-embeds.py's collision detector compares a demo against THE
    LIBRARY IT IS ABOUT TO EMBED and nothing else. That covers one of the four
    carried-block families. The ui kit, the harness scaffold and the demo
    self-check are each pasted into a dozen-odd files by a different tool, and
    none of those three is collision-checked against its host at all.

WHAT IT CHECKS, per file
    1. a script-level `local` or `constant` name declared more than once;
    2. a handler or function defined more than once;
    3. a name that is both a declaration and a handler.

PARSING NOTES, each paid for by a bug in this family
    - COMMENTS ARE CUT BEFORE PARSING, with a scanner that tracks string state.
      PRECAUTIONARY, not load-bearing, and the distinction was measured rather
      than assumed: tools/test-duplicate-declarations.py --mutate ran a
      blank-the-literals-first implementation against every fixture and it
      SURVIVED, because this scanner discards everything right of `=` and so
      never reads anything that lives inside a literal. The claim that it was
      load-bearing was imported from the demo control-derivation scan, where it
      genuinely is. Kept as the safer of two equivalent implementations.
    - `constant kDeck = "Ac,Ad,Ah"` splits on `=` FIRST and commas second.
      Doing it the other way round reported the deck's contents as declarations.
      This is the same bug sync-demo-embeds.py's names() shipped with.
    - Column 0 only. An indented `local` is a handler-body local and legal.

USAGE
    python3 tools/check-duplicate-declarations.py
    Exit 0 when clean, 1 on any finding.
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DECL = re.compile(r"^(local|constant)\s+(.*)$")
HANDLER = re.compile(r"^(?:private\s+)?(command|function|on|getprop|setprop)\s+(\w+)")
IDENT = re.compile(r"[A-Za-z_]\w*$")


def strip_comment(line):
    """Cut a `--` comment, outside string literals only."""
    out, in_str, i = [], False, 0
    while i < len(line):
        c = line[i]
        if c == '"':
            in_str = not in_str
        elif not in_str and line[i:i + 2] == "--":
            break
        out.append(c)
        i += 1
    return "".join(out)


def join_continuations(lines):
    """A declaration may wrap with a trailing backslash."""
    out, acc = [], None
    for raw in lines:
        line = raw.rstrip("\n")
        if acc is not None:
            line = acc + " " + line.strip()
            acc = None
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            acc = stripped[:-1].rstrip()
            continue
        out.append(line)
    if acc is not None:
        out.append(acc)
    return out


def scan(path):
    """Returns {name: [(kind, line_number), ...]} for every declared name."""
    seen = {}
    raw_lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    # keep original numbers for the report: count as we go, continuations fold
    lineno = 0
    joined = []
    acc, acc_no = None, None
    for raw in raw_lines:
        lineno += 1
        line = raw.rstrip()
        if acc is not None:
            line = acc + " " + line.strip()
            acc = None
        if line.rstrip().endswith("\\"):
            acc = line.rstrip()[:-1].rstrip()
            if acc_no is None:
                acc_no = lineno
            continue
        joined.append((acc_no if acc_no is not None else lineno, line))
        acc_no = None

    for no, line in joined:
        m = HANDLER.match(line.strip())
        if m and line[:1] not in (" ", "\t"):
            seen.setdefault(m.group(2), []).append(("handler", no))
            continue
        if line[:1] in (" ", "\t"):
            continue                      # handler-body local: legal
        m = DECL.match(line)
        if not m:
            continue
        rest = strip_comment(m.group(2))
        rest = rest.split("=")[0]         # `=` FIRST, then commas
        for name in rest.split(","):
            name = name.strip()
            if IDENT.fullmatch(name):
                seen.setdefault(name, []).append((m.group(1), no))
    return seen


def main():
    problems, nfiles, ndecls = [], 0, 0
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.livecodescript"),
                                 recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel.startswith(".git"):
            continue
        nfiles += 1
        seen = scan(path)
        ndecls += sum(len(v) for v in seen.values())
        for name, hits in sorted(seen.items()):
            if len(hits) < 2:
                continue
            kinds = sorted({k for k, _ in hits})
            where = ", ".join("%s:%d" % (k, n) for k, n in hits)
            problems.append(
                "%s: `%s` is declared %d times (%s) - one script, one unit: "
                "this does not compile, and the whole file goes with it.\n"
                "    %s" % (rel, name, len(hits), "/".join(kinds), where))

    for p in problems:
        print(p)
    if problems:
        print("check-duplicate-declarations: %d finding(s)" % len(problems))
        return 1
    if ndecls == 0:
        print("check-duplicate-declarations: found NO declarations at all - the "
              "scan is broken, and a clean report would be a lie")
        return 1
    print("check-duplicate-declarations: OK (%d file(s), %d script-level name(s) "
          "and handler(s), no name declared twice)" % (nfiles, ndecls))
    return 0


if __name__ == "__main__":
    sys.exit(main())
