#!/usr/bin/env python3
"""test-cross-library-names.py - prove each cross-library check FIRES.

The family's mutation-test law (root CLAUDE.md): a gate is exercised the way
the BUILD runs it, not the way its docstring describes it - the false
declaration-drop claim survived a fixture-only test for exactly that reason.
So this runs the real gate over the real tree first (it must be clean), then
reconstructs each defect class faithfully by mutating a REAL corpus file in
place, runs the gate the same way the build does, and restores the file -
try/finally, byte-identical - before the next case.

Cases, one per check:
  1. a handler name defined in two libraries          -> check 1 fires
  2. an engine socket message with its `pass` removed -> check 2 fires
  3. a script-level name declared in two libraries    -> check 3 fires
  4. a public handler without its library's prefix    -> check 4 fires

USAGE
    python3 tools/test-cross-library-names.py
    Exit 0 when the clean tree passes AND every mutation is caught.
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join(ROOT, "tools", "check-cross-library-names.py")
# The mutation host: nostrxt's core (any corpus file works; this one is the
# newest and the reason the gate exists).
HOST = os.path.join(ROOT, "nostrxt", "src", "nostrxt.livecodescript")
RELAY = os.path.join(ROOT, "nostrxt", "src", "nostr-relay.livecodescript")


def run_gate():
    proc = subprocess.run([sys.executable, GATE], capture_output=True,
                          text=True, cwd=ROOT)
    return proc.returncode, proc.stdout + proc.stderr


def check(label, rc_want_nonzero, must_contain, rc, out):
    fired = (rc != 0) if rc_want_nonzero else (rc == 0)
    ok = fired and (must_contain in out)
    verdict = "ok  " if ok else "FAIL"
    print(f"  {verdict} {label}")
    if not ok:
        print("       expected" +
              (" a failure containing " if rc_want_nonzero else " success containing ") +
              repr(must_contain) + ", got rc=" + str(rc) + ":\n" + out)
    return ok


def main():
    all_ok = True
    rc, out = run_gate()
    all_ok &= check("the real tree is clean to begin with", False,
                    "check-cross-library-names: OK", rc, out)
    if not all_ok:
        return 1

    host_original = open(HOST, encoding="utf-8").read()
    relay_original = open(RELAY, encoding="utf-8").read()

    # 1. duplicate handler across two libraries: nostrxt grows riptide's
    #    rsLastError (a real sibling public, reconstructed faithfully).
    try:
        open(HOST, "w", encoding="utf-8").write(
            host_original + "\nfunction rsLastError\n   return empty\nend rsLastError\n")
        rc, out = run_gate()
        all_ok &= check("a handler defined in two libraries is caught", True,
                        "`rsLastError` is defined in BOTH", rc, out)
    finally:
        open(HOST, "w", encoding="utf-8").write(host_original)

    # 2. an engine socket message that swallows: strip the relay layer's
    #    `pass socketError` (the exact defect onionxt shipped with).
    try:
        mutated = relay_original.replace("   pass socketError\n", "", 1)
        assert mutated != relay_original, "fixture stale: no pass socketError"
        open(RELAY, "w", encoding="utf-8").write(mutated)
        rc, out = run_gate()
        all_ok &= check("a socket message without `pass` is caught", True,
                        "without a `pass socketError`", rc, out)
    finally:
        open(RELAY, "w", encoding="utf-8").write(relay_original)

    # 3. duplicate script-level declaration: nostrxt declares riptide's
    #    sRsLastError at column 0 (the sPolling class, reconstructed).
    try:
        open(HOST, "w", encoding="utf-8").write(
            host_original + "\nlocal sRsLastError\n")
        rc, out = run_gate()
        all_ok &= check("a script-level name in two libraries is caught", True,
                        "`sRsLastError` is declared in BOTH", rc, out)
    finally:
        open(HOST, "w", encoding="utf-8").write(host_original)

    # 4. an unprefixed public handler (the collision-in-waiting ratchet).
    try:
        open(HOST, "w", encoding="utf-8").write(
            host_original + "\nfunction zzStray\n   return empty\nend zzStray\n")
        rc, out = run_gate()
        all_ok &= check("an unprefixed public handler is caught", True,
                        "`zzStray` does not carry this library's prefix",
                        rc, out)
    finally:
        open(HOST, "w", encoding="utf-8").write(host_original)

    # the restores really restored (a mutated tree left behind would fail
    # every later gate for a reason nobody could see here)
    rc, out = run_gate()
    all_ok &= check("the tree is byte-identical after the mutations", False,
                    "check-cross-library-names: OK", rc, out)

    if not all_ok:
        print("test-cross-library-names: FAILURES above")
        return 1
    print("test-cross-library-names: all 4 mutations caught, tree restored")
    return 0


if __name__ == "__main__":
    sys.exit(main())
