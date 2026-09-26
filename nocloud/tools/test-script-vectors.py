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
    # A REFUSAL IS NEVER A PASS (2026-09-26). The folding pre-test as bare `is` is caught
    # on the engine by the exact stage after it, so every answer here reads right; but the
    # model REFUSES "1e2" is not "100" (engine note 2.11: one number there, two texts
    # here), and the gate must fail on that by name. Its first named_calls handed the
    # refusal back as text, which boolish() read as false - the answer qsSameText('1e2',
    # '100') expects - and qsRouteMatch's dict filter as "no match": this script passed the
    # whole gate green.
    ("the folding pre-test as bare `is` (refused by the model, whatever the rows read)",
     "   if (\"s\" & pA) is not (\"s\" & pB) then\n",
     "   if pA is not pB then\n",
     "qsSameText('1e2', '100'): REFUSED by the family interpreter"),
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
    # The route layer's case-exact COMPARISONS, which only the gate's [engine is] pass can
    # see (2026-09-25): under the interpreter's own `is` (case-exact) each of these reverts
    # answered exactly what the fix answers, and all four passed the gate. Each is named
    # by a row of the pass where `is` folds as the engine's does.
    ("Allow over the built-in table claims a path with bare `is` (folds on the engine)",
     "         if qsSameText(sHttpRoutes[tKey][\"path\"], pPath) then\n",
     "         if sHttpRoutes[tKey][\"path\"] is pPath then\n",
     "qsHttpAllow exact('/_EDIT/api/write') [engine is]"),
    ("Allow over a folder's table claims a path with bare `is` (folds on the engine)",
     "            if qsSameText(tRoutePath, pPath) then\n"
     "               put tMethod & return after tExtras\n            else if",
     "            if tRoutePath is pPath then\n"
     "               put tMethod & return after tExtras\n            else if",
     "qsHttpAllow exact('/API/submit') [engine is]"),
    ("the CORS preflight claims a path with bare `is` (folds on the engine)",
     "         put qsSameText(tRoutePath, pPath) into tClaims\n",
     "         put (tRoutePath is pPath) into tClaims\n",
     "qsCorsPreflight('/API/SUBMIT') [engine is]"),
    ("qsSameText without its exact stage (the folded pre-test answers alone)",
     "   return ((\"h\" & qsHexKey(pA)) is (\"h\" & qsHexKey(pB)))\n",
     "   return true\n",
     "qsSameText('/api/x','/API/x') [engine is]"),
    # A declared route METHOD is a token (2026-09-25): each entry's own method is what
    # Allow copies into the header, so a CR, LF or space in it reached that header.
    ("the declared-method predicate accepting anything",
     "function qsHttpMethodValid pMethod\n",
     "function qsHttpMethodValid pMethod\n   return true\n",
     "qsHttpMethodValid('POST\\r\\nX-EVIL: 1')"),
    ("the route loader filing a method it never checked",
     "         if not qsHttpMethodValid(tMethod) then\n"
     "            next repeat                       -- a method is a token: no space, CR or LF\n"
     "         end if\n",
     "",
     "qsLoadUserRoutes refuses a method that is not a token before it files the route"),
    # A share code can be a bare 40-hex info-hash (2026-09-26): "0e1..." and "0e2..." are
    # one number to a bare `is`, which the interpreter refuses and the gate names.
    ("the own-code test comparing a retained share's code with bare `is`",
     "      if (\"c\" & sShareCodeByHandle[tK]) is (\"c\" & pCode) then\n",
     "      if sShareCodeByHandle[tK] is pCode then\n",
     "qsIsOwnCode('0e2222"),
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
