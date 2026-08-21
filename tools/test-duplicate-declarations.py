#!/usr/bin/env python3
"""test-duplicate-declarations.py - fixtures for check-duplicate-declarations.py.

A gate that has never been shown to FIRE is a gate nobody should trust. This
file drives the checker's scanner over hand-built sources whose answer is known,
including the four parsing traps its docstring claims to handle - and then,
under --mutate, re-runs every fixture against deliberately BROKEN
implementations of the scanner to prove the fixtures discriminate.

The mutations are not invented. Each one is a bug that actually shipped in this
family:
  comma_first   split on commas before `=`, so `constant kDeck = "Ac,Ad"`
                reports Ac and Ad as declarations. sync-demo-embeds.py's names()
                shipped with this shape.
  keep_comments do not cut comments, so a commented-out `local sFoo` counts.
  any_indent    treat an indented `local` as script-level, so every handler-body
                local collides with every other.
  no_join       do not join backslash continuations, so a wrapped declaration
                loses every name after the break.

A FIFTH MUTATION WAS TRIED AND DROPPED, and it is worth recording why. The
checker's docstring originally claimed its string-aware comment stripping was
load-bearing "because the thing being read is sometimes inside a literal" - the
lesson from the demo control-derivation scan, carried over. Under --mutate a
blank-the-literals-first implementation SURVIVED every fixture, and it survived
because for THIS scanner it is genuinely equivalent: the value right of `=` is
discarded, so nothing this gate reads ever lives inside a literal. The claim was
imported, not measured. The string-aware scanner is kept as the safer of two
equivalent implementations, and the docstring now says precautionary rather than
load-bearing.

USAGE
    python3 tools/test-duplicate-declarations.py
    python3 tools/test-duplicate-declarations.py --mutate
"""

import importlib.util
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

_spec = importlib.util.spec_from_file_location(
    "cdd", os.path.join(HERE, "check-duplicate-declarations.py"))
cdd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cdd)


def dupes(source):
    """Names the scanner reports more than once, for a source string."""
    with tempfile.NamedTemporaryFile("w", suffix=".livecodescript",
                                     delete=False, encoding="utf-8") as fh:
        fh.write(source)
        path = fh.name
    try:
        seen = cdd.scan(path)
    finally:
        os.unlink(path)
    return sorted(n for n, hits in seen.items() if len(hits) > 1)


FIXTURES = [
    # (name, source, expected duplicate names)
    ("a duplicate script-level local is CAUGHT - the sPolling bug",
     'script "x"\nlocal sPolling\nlocal sFoo\nlocal sPolling\n', ["sPolling"]),

    ("a duplicate handler is CAUGHT",
     'script "x"\ncommand doIt\nend doIt\ncommand doIt\nend doIt\n', ["doIt"]),

    ("a name that is BOTH a declaration and a handler is CAUGHT",
     'script "x"\nlocal sThing\ncommand sThing\nend sThing\n', ["sThing"]),

    ("two locals on ONE line are two names",
     'script "x"\nlocal sA, sB\nlocal sB\n', ["sB"]),

    ("a wrapped declaration is joined before parsing",
     'script "x"\nlocal sA, \\\n      sB\nlocal sB\n', ["sB"]),

    # --- the four parsing traps ---
    # The value's items must COLLIDE with a real declaration, or splitting on
    # commas first produces harmless extra names and the fixture passes while
    # the bug is present. That is exactly what the first draft of this fixture
    # did, and --mutate is what said so.
    ("TRAP: a constant's VALUE is not a declaration list",
     'script "x"\nconstant kDeck = "Ac,sFoo,Ah"\nlocal sFoo\n', []),

    ("TRAP: a commented-out declaration does not count",
     'script "x"\nlocal sFoo\n-- local sFoo\n', []),

    ("TRAP: a `--` INSIDE a literal is not a comment",
     'script "x"\nconstant kDash = "a -- local sFoo"\nlocal sBar\n', []),

    ("TRAP: an INDENTED local is a handler-body local and legal",
     'script "x"\ncommand a\n   local tX\nend a\ncommand b\n   local tX\nend b\n', []),

    ("a trailing comment on a declaration does not hide the name",
     'script "x"\nlocal sFoo   -- the flag\nlocal sFoo\n', ["sFoo"]),

    ("a clean file reports nothing",
     'script "x"\nlocal sA, sB\nconstant kC = 1\ncommand go\n   local tA\nend go\n', []),
]


def run(label=""):
    bad = 0
    for name, source, expect in FIXTURES:
        got = dupes(source)
        ok = got == expect
        if not ok:
            bad += 1
            print("  FAIL%s %s\n        expected %r, got %r" % (label, name, expect, got))
    return bad


MUTATIONS = {
    "comma_first": lambda: _patch_scan(comma_first=True),
    "keep_comments": lambda: _patch_scan(keep_comments=True),
    "any_indent": lambda: _patch_scan(any_indent=True),
    "no_join": lambda: _patch_scan(no_join=True),
}


def _patch_scan(comma_first=False, keep_comments=False, any_indent=False,
                no_join=False):
    """Return a broken scan() with one historical bug reintroduced."""
    real_strip = cdd.strip_comment

    def broken(path):
        seen = {}
        lines = open(path, encoding="utf-8").read().split("\n")
        joined, acc = [], None
        for i, raw in enumerate(lines, 1):
            line = raw.rstrip()
            if acc is not None:
                line = acc + " " + line.strip()
                acc = None
            if line.endswith("\\") and not no_join:
                acc = line[:-1].rstrip()
                continue
            joined.append((i, line))
        for no, line in joined:
            m = cdd.HANDLER.match(line.strip())
            if m and line[:1] not in (" ", "\t"):
                seen.setdefault(m.group(2), []).append(("handler", no))
                continue
            if not any_indent and line[:1] in (" ", "\t"):
                continue
            m = cdd.DECL.match(line.strip() if any_indent else line)
            if not m:
                continue
            rest = m.group(2)
            if not keep_comments:
                rest = real_strip(rest)
            if comma_first:
                parts = [p.split("=")[0] for p in rest.split(",")]
            else:
                parts = rest.split("=")[0].split(",")
            for nm in parts:
                nm = nm.strip()
                if cdd.IDENT.fullmatch(nm):
                    seen.setdefault(nm, []).append((m.group(1), no))
        return seen
    return broken


def main(argv):
    print("test-duplicate-declarations: %d fixture(s)" % len(FIXTURES))
    bad = run()
    if bad:
        print("test-duplicate-declarations: %d fixture failure(s)" % bad)
        return 1

    if "--mutate" in argv:
        real = cdd.scan
        survivors = []
        for name, make in MUTATIONS.items():
            cdd.scan = make()
            caught = run(label="[%s]" % name) > 0
            cdd.scan = real
            if not caught:
                survivors.append(name)
            print("  mutation %-15s %s" % (name, "CAUGHT" if caught else "SURVIVED"))
        if survivors:
            print("test-duplicate-declarations: mutation(s) SURVIVED (%s) - the "
                  "fixtures do not discriminate" % ", ".join(survivors))
            return 1

    # And the real tree, so the fixtures and the gate agree about it.
    seen_total = 0
    for root, _, files in os.walk(ROOT):
        if ".git" in root:
            continue
        for f in files:
            if f.endswith(".livecodescript"):
                seen_total += len(cdd.scan(os.path.join(root, f)))
    if seen_total == 0:
        print("test-duplicate-declarations: the tree scan found nothing")
        return 1
    print("test-duplicate-declarations: OK (%d names across the tree)" % seen_total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
