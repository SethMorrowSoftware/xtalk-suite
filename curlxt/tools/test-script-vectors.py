#!/usr/bin/env python3
"""test-script-vectors.py - prove tools/check-script-vectors.py FIRES.

Each case breaks one behaviour of the shipped tsNet or helpers layer in a
COPY, runs the execution gate over the copy with --source, and requires it
to fail; the unbroken files must pass. Needs what the gate needs (a built
library); without one the gate SKIPs, and so does this, saying so - unless
CURLXT_REQUIRE_LIB=1, where both fail.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join(HERE, "tools", "check-script-vectors.py")

# (label, file, old, new)
CASES = [
    ("callback parameters out of order", "tsnet.livecodescript",
     'with tID, cuInfo(pReq, "responseCode"), tBytes, tsnxCurlCode(pReq)',
     'with tID, tBytes, cuInfo(pReq, "responseCode"), tsnxCurlCode(pReq)'),
    ("redirects no longer followed", "tsnet.livecodescript",
     'put 1 into tOpts["followRedirects"]', 'put 0 into tOpts["followRedirects"]'),
    ("tsnet settings username ignored", "tsnet.livecodescript",
     'put pSettings["username"] into tOpts["username"]', 'get pSettings["username"]'),
    ("a 404 reported as a failure", "tsnet.livecodescript",
     "   if tResult is 0 then\n      return empty\n   end if\n   return tsnxErr(",
     "   if tResult is 0 and cuInfo(pReq, \"responseCode\") < 400 then\n      return empty\n   end if\n   return tsnxErr("),
    ("the timer never stops", "curl-helpers.livecodescript",
     "   if cuWaitingCount() is 0 then\n      put \"false\" into sCuPolling\n      exit cuPollOnce\n   end if\n",
     ""),
    ("integer options not validated", "curl-helpers.livecodescript",
     "            if tValue is not an integer then", "            if false then"),
]


def run(extra):
    p = subprocess.run([sys.executable, GATE] + extra, capture_output=True, text=True, timeout=600)
    return p.returncode, (p.stdout + p.stderr).strip().splitlines()[-1:] or [""]


def main():
    code, last = run([])
    if "SKIP" in last[0]:
        print("test-script-vectors: SKIP - " + last[0])
        return 1 if os.environ.get("CURLXT_REQUIRE_LIB") == "1" else 0
    bad = []
    if code != 0:
        bad.append("the shipped files fail: " + last[0])
    for label, name, old, new in CASES:
        src = open(os.path.join(HERE, "src", name), encoding="utf-8").read()
        if old not in src:
            bad.append("%s: the fixture's anchor is gone" % label)
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".livecodescript", delete=False,
                                         encoding="utf-8") as fh:
            fh.write(src.replace(old, new, 1))
            path = fh.name
        try:
            code, last = run(["--source", name, path])
        finally:
            os.unlink(path)
        if code == 0:
            bad.append("%s: the gate passed the broken copy" % label)
    if bad:
        print("test-script-vectors: FAIL\n  " + "\n  ".join(bad))
        return 1
    print("test-script-vectors: OK (%d mutations each caught; the shipped files pass)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
