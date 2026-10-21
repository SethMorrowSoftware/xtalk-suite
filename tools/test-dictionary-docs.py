#!/usr/bin/env python3
"""test-dictionary-docs.py - prove each dictionary-docs check FIRES.

The family's mutation-test law (root CLAUDE.md): a gate is exercised the way
the BUILD runs it. So this runs the real gate over the real tree first (it
must be clean), then reconstructs each defect class by mutating a REAL
corpus file in place, runs the gate as the build does, and restores the file
(try/finally, byte-identical) before the next case.

Cases:
  1. a doc block above a private handler          -> orphan (check 2)
  2. a block without its Summary: line            -> check 3
  3. a misspelled parameter line                  -> check 3, both ways
  4. a public handler's block deleted             -> coverage (check 4)
  5. the .lcb library block deleted               -> check 1
  6. a script library whose library block meets a
     handler before a second block opens          -> check 1
  7. a link to a handler nobody documents         -> check 5
  8. a doc block added above an exempt handler    -> stale exemption (4)
  8b. an exempt handler declared `command`         -> check 4
  9. `end if` on a line inside a script block      -> check 6
 10. a description line led by an unknown word and
     a colon ("automatic: ...")                      -> check 7
 11. one led by a word the parser knows but the
     corpus does not use ("it: ...", a return value) -> check 7
 12. a library block line led by "closeStack:",
     which ends the parser's library entry           -> check 7
 13. a second Description: line in one block         -> check 7

USAGE
    python3 tools/test-dictionary-docs.py
    Exit 0 when the clean tree passes AND every mutation is caught.
"""

import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join(ROOT, "tools", "check-dictionary-docs.py")
LCB = os.path.join(ROOT, "enetxt", "src", "enet.lcb")
LCS = os.path.join(ROOT, "enetxt", "examples", "enet-helpers.livecodescript")


def load_gate():
    spec = importlib.util.spec_from_file_location("check_dictionary_docs", GATE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_gate():
    proc = subprocess.run([sys.executable, GATE], capture_output=True, text=True, cwd=ROOT)
    return proc.returncode, proc.stdout + proc.stderr


def read(path):
    with open(path, "rb") as f:
        return f.read()


def mutate_case(label, path, mutate, must_contain):
    original = read(path)
    text = original.decode("utf-8")
    new = mutate(text)
    if new == text:
        print(f"  FAIL {label}: the mutation did not apply (the host file changed?)")
        return False
    try:
        with open(path, "wb") as f:
            f.write(new.encode("utf-8"))
        rc, out = run_gate()
    finally:
        with open(path, "wb") as f:
            f.write(original)
    assert read(path) == original
    ok = rc != 0 and must_contain in out
    print(f"  {'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        print(f"       expected a failure containing {must_contain!r}, got rc={rc}:\n{out}")
    return ok


def once(pattern, repl, flags=0):
    def f(text):
        new, n = re.subn(pattern, repl, text, count=1, flags=flags)
        return new if n == 1 else text
    return f


def main():
    gate = load_gate()
    results = []
    rc, out = run_gate()
    clean = rc == 0
    print(f"  {'ok  ' if clean else 'FAIL'} the real tree is clean")
    if not clean:
        print(out)
        return 1

    results.append(mutate_case(
        "a block above a private handler is an orphan", LCB,
        once(r"^(private handler )", "/**\nSummary: misplaced\n*/\n\\1", re.M),
        "orphan doc block"))
    results.append(mutate_case(
        "a block without Summary: fails", LCB,
        once(r"Summary: Initialize the ENet library", "Initialize the ENet library"),
        "enInitialize has no Summary: line"))
    results.append(mutate_case(
        "a misspelled parameter fails both ways", LCB,
        once(r"^pBindHost:", "pBindHst:", re.M),
        "documents pBindHst, which is not one of its parameters"))
    results.append(mutate_case(
        "a misspelled parameter leaves the real one undocumented", LCB,
        once(r"^pBindHost:", "pBindHst:", re.M),
        "does not document its parameter pBindHost"))
    results.append(mutate_case(
        "a deleted block leaves its handler undocumented", LCB,
        once(r"/\*\*\nSummary: Clear the last error message\.(?:.|\n)*?\*/\n", ""),
        "public handler enClearError has no doc block"))
    results.append(mutate_case(
        "the .lcb library block is required", LCB,
        once(r"\A/\*\*(?:.|\n)*?\*/\n", ""),
        "no doc block above the library line"))

    def drop_second_block(text):
        blocks = list(re.finditer(r"^/\*\*(?:.|\n)*?\*/\n", text, re.M))
        if len(blocks) < 2:
            return text
        b = blocks[1]
        return text[:b.start()] + text[b.end():]
    results.append(mutate_case(
        "a script library block that meets a handler first is lost", LCS,
        drop_second_block, "no library doc block"))
    results.append(mutate_case(
        "a dead link fails", LCB,
        once(r"Summary: Clear the last error message\.",
             "Summary: Clear the last error message, see <enNoSuchHandler>."),
        "<enNoSuchHandler> links to no documented handler"))

    results.append(mutate_case(
        "a code-shaped line inside a script block fails", LCS,
        once(r"^(Summary: .*)$", "\\1\nend if", re.M),
        "a block line reads as code to the line-based tools: end if"))

    # check 7, each found 2026-10-12 by running Beyond's real parser over
    # the corpus: the prose wrapped so a "word:" led a line
    results.append(mutate_case(
        "a description line led by an unknown word and a colon fails", LCB,
        once(r"^(Description:\n)", "\\1automatic: creating the first channel\n", re.M),
        "as a new element named 'automatic'"))
    results.append(mutate_case(
        "a line led by a parser word the corpus does not use fails", LCB,
        once(r"^(Description:\n)", "\\1it: it arrives there as an event\n", re.M),
        "as a new element named 'it'"))
    results.append(mutate_case(
        "a library block line led by an unknown word fails", LCS,
        once(r"^(Author: Seth Morrow Software\n)", "\\1closeStack: there is no automatic unload.\n", re.M),
        "of the library block as a new element named 'closeStack'"))
    results.append(mutate_case(
        "a second Description: line in one block fails", LCB,
        once(r"^(Description:\n)", "\\1Description:\n", re.M),
        "has a second Description: line"))

    exempt = [(rel, name) for rel, names in sorted(gate.EXEMPT.items()) for name in sorted(names)]
    if not exempt:
        print("  FAIL no EXEMPT entry to mutate (case 8 cannot run)")
        results.append(False)
    else:
        rel, name = exempt[0]
        host = os.path.join(ROOT, rel)
        results.append(mutate_case(
            f"documenting an exempt handler ({name}) is a stale exemption", host,
            once(r"^((?:on|command|function) " + re.escape(name) + r"\b)",
                 "/**\nSummary: x\n*/\n\\1", re.M | re.I),
            f"stale exemption {name} (it is documented)"))
        results.append(mutate_case(
            f"an exempt handler ({name}) declared `command` fails", host,
            once(r"^on (" + re.escape(name) + r")\b", "command \\1", re.M | re.I),
            f"exempt handler {name} is declared `command`"))

    if all(results):
        print(f"test-dictionary-docs: OK ({len(results) + 1} case(s), each caught; tree restored byte for byte)")
        return 0
    print("test-dictionary-docs: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
