#!/usr/bin/env python3
"""test-script-vectors.py - prove tools/check-script-vectors.py can FAIL.

A gate that has gone blind prints OK, and the family has met that shape more
than once (coinxt's constant gate counting what it parsed as what it checked;
the demo-embed collision detector shipping blind). So this drives the gate the
way build-all.sh does - the real entry point, over a real copy of the shipped
script - with one defect of the class the gate exists to catch edited into
the copy each time, and requires a non-zero exit with the defect NAMED in the
output. Then it drives the untouched copy and requires OK, so a fixture that
"fails" because the copy would not load at all cannot pass as discrimination.

Each mutation is asserted to APPLY (the anchor text must occur exactly once),
so a rename in the shipped script fails this test rather than silently
turning a fixture into a no-op - the lesson every fixture set in this tree
carries.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-script-vectors.py")
DEMO = os.path.join(MEMBER, "src", "nocloudquickshare.livecodescript")

# (label, anchor, replacement, the label the gate must name)
FIXTURES = [
    ("the dotfile guard answering false for a hidden segment",
     "function qsHasDotSegment pPath\n",
     "function qsHasDotSegment pPath\n   return false\n",
     "qsHasDotSegment('/.git/config')"),
    ("the head parser keeping the FIRST Content-Length (the smuggling lever)",
     "         put tValue into tOut[tName]\n",
     "         if tOut[tName] is empty then\n            put tValue into tOut[tName]\n         end if\n",
     "qsHttpParseHead duplicate Content-Length"),
    ("the editor confinement admitting a '..' segment",
     "function qsEditSafePath pRoot, pRelPath\n",
     "function qsEditSafePath pRoot, pRelPath\n   replace \"..\" with \"x\" in pRelPath\n",
     "qsEditSafePath('../etc/passwd')"),
    ("the Tor text reply sending a body for HEAD",
     "   if sFsMethod[pStream] is \"HEAD\" then\n      put \"\" into tBody\n",
     "   if sFsMethod[pStream] is \"NEVER\" then\n      put \"\" into tBody\n",
     "qsFsSendText HEAD sends the GET head and no body"),
    # The case-exact route table (WORK-PLAN nocloud #6, 2026-09-25). The first is the
    # defect itself: route keys built from the raw "METHOD /path" text, which the engine's
    # array subscript folds (engine note 2.7) and so, since 2026-09-24, does the model's.
    ("the folding lookup: route keys built from the raw METHOD /path text",
     "   return qsHexKey(toUpper(pMethod) & space & pPath)\n",
     "   return toUpper(pMethod) & space & pPath\n",
     "qsRouteLookupKey('GET','/API/hello') over the built-in table"),
    ("share roots keyed by the raw folder path (two folders, one folded table)",
     "   return qsHexKey(pRoot)\n",
     "   return pRoot\n",
     "qsHttpAllow under root '/srv/site'"),
    # The route layer's path comparison as bare `is`: the model's `is` is case-exact (its
    # named divergence), so the case half is invisible here; its number half is not (it
    # reads plain decimals as numbers, as the engine does), which is what names this.
    ("the route path comparison as bare `is`",
     "function qsSameText pA, pB\n",
     "function qsSameText pA, pB\n   return (pA is pB)\n",
     "qsSameText('01','1')"),
    ("the reserved-namespace guard compared case-exactly (looser than the engine)",
     "   put toLower(pPath) into tLow\n",
     "   put pPath into tLow\n",
     "qsHttpReservedPath('/_QS/info')"),
    ("duplicate capture names compared case-exactly (:id and :ID, one array key)",
     "      if toLower(tName) is among the lines of tSeen then\n",
     "      if tName is among the lines of tSeen then\n",
     "qsUserPatternValid('/api/:id/:ID')"),
    ("the pattern tie-break on the readable key (the engine folds text `<`)",
     "(tCount is tBestCount and (\"k\" & tKey) < (\"k\" & tBestKey))",
     "(tCount is tBestCount and (sUserRoutes[tRootKey][tKey][\"method\"] & space & tRoutePath)"
     " < (sUserRoutes[tRootKey][tBestKey][\"method\"] & space"
     " & sUserRoutes[tRootKey][tBestKey][\"path\"]))",
     "qsUserRouteFind('GET','/api/files/x') over ['GET /api/:a/x', 'GET /api/:Z/x']"),
]


def run_gate(path):
    proc = subprocess.run([sys.executable, GATE, "--source", path],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    with open(DEMO, "r", encoding="utf-8") as fh:
        shipped = fh.read()
    tmp = tempfile.mkdtemp(prefix="nocloud-vectors-fixtures-")
    failed = 0
    try:
        for label, anchor, replacement, must_name in FIXTURES:
            if shipped.count(anchor) != 1:
                print("FAIL  %s - the anchor occurs %d times in the shipped script, "
                      "so the fixture cannot apply" % (label, shipped.count(anchor)))
                failed += 1
                continue
            path = os.path.join(tmp, "mutated.livecodescript")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(shipped.replace(anchor, replacement))
            rc, out = run_gate(path)
            if rc == 0:
                failed += 1
                print("FAIL  %s - the gate passed a script carrying it" % label)
            elif must_name not in out:
                failed += 1
                print("FAIL  %s - the gate failed without naming the check (%r)\n      %s"
                      % (label, must_name, out.strip().split("\n")[0]))
            else:
                print("PASS  %s" % label)
        path = os.path.join(tmp, "clean.livecodescript")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(shipped)
        rc, out = run_gate(path)
        if rc != 0:
            failed += 1
            print("FAIL  the untouched copy does not pass, so nothing above was discrimination\n"
                  "      " + "\n      ".join(out.strip().split("\n")[-6:]))
        else:
            print("PASS  the untouched copy passes")
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    if failed:
        print("test-script-vectors: FAIL (%d)" % failed)
        return 1
    print("test-script-vectors: OK (%d seeded defects caught, the clean copy passes)"
          % len(FIXTURES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
