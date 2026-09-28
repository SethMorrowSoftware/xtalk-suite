#!/usr/bin/env python3
"""test-script-vectors.py - prove tools/check-script-vectors.py can FAIL.

A gate that has gone blind prints OK (the suite root's "fixture before gate"). So this
drives the gate the way run-gates.sh does - the real entry point, over a real copy of
the shipped datachannel-dht-chat - with one defect of the class the gate exists to
catch edited into the copy each time, and requires a non-zero exit with the defect's
check NAMED in the output. Then it drives an untouched copy and requires OK, so a
fixture that "fails" because the copy would not load cannot pass as discrimination.

Each anchor must occur exactly once in the shipped demo, so a rename there fails this
test rather than silently turning a fixture into a no-op. The first fixture IS the
pre-2026-09-27 demo's parse boundary (the suite work plan's datachannelxt coding #9):
with the nonce check gone, the "an" offer is answered on its first delivery and its
second meets `"nan" is "nan"`, which the family interpreter refuses to answer (the
suite's engine note 2.11).
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-script-vectors.py")
DEMO = os.path.join(MEMBER, "examples", "datachannel-dht-chat.livecodescript")

# (label, anchor, replacement, the check the gate must name)
FIXTURES = [
    ("the nonce check at the parse boundary removed (the pre-fix demo)",
     "   if not wxNonceValid(tNonce) then\n"
     "      exit wxApplyRemote\n"
     "   end if\n",
     "",
     "join: offer 'an' twice delivery 2: a comparison REFUSED"),
    ("wxNonceValid folding case (A-F admitted)",
     "      if not ((tN >= 48 and tN <= 57) or (tN >= 97 and tN <= 102)) then\n",
     "      if not ((tN >= 48 and tN <= 57) or (tN >= 97 and tN <= 102) "
     "or (tN >= 65 and tN <= 70)) then\n",
     "wxNonceValid('0123ABCD')"),
    ("wxNonceValid admitting a short nonce",
     "   if the number of chars of pNonce is not 8 then\n",
     "   if the number of chars of pNonce > 8 then\n",
     "wxNonceValid('0123abc')"),
    ("the join dedup back on bare `is` (the 2026-09-25 fix undone)",
     "   if (\"n\" & pNonce) is (\"n\" & sSeenOfferNonce) then\n",
     "   if pNonce is sSeenOfferNonce then\n",
     "join: two nonces that are one number (00000001, 1e000000)"),
    ("the host's echo check back on bare `is not`",
     "   if (\"n\" & pNonce) is not (\"n\" & sNonce) then\n",
     "   if pNonce is not sNonce then\n",
     "host: an answer echoing 1e000000 to the offer 00000001"),
    ("the chunk-list compare back on bare `is` (the head's twin, 2026-09-27)",
     "      if (\"t\" & tRest) is (\"t\" & sFetchTargets) then\n",
     "      if tRest is sFetchTargets then\n",
     "fetch: two one-chunk lists that are both +inf"),
]


def run_gate(path):
    proc = subprocess.run([sys.executable, GATE, "--check", "--demo", path],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    with open(DEMO, "r", encoding="utf-8") as fh:
        shipped = fh.read()
    tmp = tempfile.mkdtemp(prefix="datachannelxt-vectors-fixtures-")
    failed = caught = 0
    try:
        for label, anchor, replacement, must_name in FIXTURES:
            if shipped.count(anchor) != 1:
                failed += 1
                print("FAIL  %s - the anchor occurs %d times in the shipped demo, so "
                      "the fixture cannot apply" % (label, shipped.count(anchor)))
                continue
            path = os.path.join(tmp, "mutated.livecodescript")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(shipped.replace(anchor, replacement))
            rc, out = run_gate(path)
            if rc == 0:
                failed += 1
                print("FAIL  %s - the gate passed a demo carrying it" % label)
            elif must_name not in out:
                failed += 1
                print("FAIL  %s - the gate failed without naming %r\n      %s"
                      % (label, must_name, out.strip().split("\n")[-1]))
            else:
                caught += 1
                print("PASS  %s" % label)
        path = os.path.join(tmp, "clean.livecodescript")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(shipped)
        rc, out = run_gate(path)
        if rc != 0:
            failed += 1
            print("FAIL  the untouched copy does not pass, so nothing above was "
                  "discrimination\n      %s" % "\n      ".join(out.strip().split("\n")[-6:]))
        else:
            print("PASS  the untouched copy passes")
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    if failed:
        print("test-script-vectors: FAIL (%d)" % failed)
        return 1
    print("test-script-vectors: OK (%d seeded defects caught, the clean copy passes)"
          % caught)
    return 0


if __name__ == "__main__":
    sys.exit(main())
