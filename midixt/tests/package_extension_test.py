#!/usr/bin/env python3
"""package_extension_test.py - tools/package-extension.py never ships the mock.

The test build emits the shim over tests/mock/rtmidi_mock.c as
<build>/mock/midixt.* under the SAME bare name as the real library: a drop-in
for the test suites, and a disaster in a release (an extension that "works"
and talks to no MIDI service at all). ShowControl's gotcha 12. This proves,
on stand-in files and with no compiler, that the packager:

  * never picks the mock out of a build dir, even when it is the only
    midixt library there;
  * refuses a --lib that exports the mock's midimock_* controls;
  * still packages a real library (dry run: nothing is written).
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "tools", "package-extension.py")

failures = 0


def check(desc, ok):
    global failures
    print(("ok     " if ok else "NOT OK ") + desc)
    if not ok:
        failures += 1


def run(*args):
    p = subprocess.run([sys.executable, TOOL, "--platform-id", "x86_64-linux", "--dry-run"] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    return p.returncode, p.stdout + p.stderr


with tempfile.TemporaryDirectory() as tmp:
    mock_dir = os.path.join(tmp, "build", "mock")
    os.makedirs(mock_dir)
    mock = os.path.join(mock_dir, "midixt.so")
    with open(mock, "wb") as f:
        f.write(b"\x7fELF stand-in midi_abi_version midimock_reset midimock_push")

    rc, out = run("--build-dir", os.path.join(tmp, "build"))
    check("a build dir holding only the mock: refused (exit %d)" % rc, rc != 0)
    check("  and it never named the mock as the source", "source:" not in out)

    rc, out = run("--lib", mock)
    check("--lib on the mock: refused (exit %d)" % rc, rc != 0)
    check("  with the reason", "MOCK library" in out)

    real = os.path.join(tmp, "build", "midixt.so")
    with open(real, "wb") as f:
        f.write(b"\x7fELF stand-in midi_abi_version midi_in_drain_bytes")
    rc, out = run("--build-dir", os.path.join(tmp, "build"))
    check("beside a real library the real one is chosen (exit %d)" % rc,
          rc == 0 and "source: " + real in out)
    rc, out = run("--lib", real)
    check("--lib on a real library packages it (dry run, exit %d)" % rc,
          rc == 0 and "WOULD" in out)

print("package_extension_test: %s" % ("FAILED (%d)" % failures if failures else "OK"))
sys.exit(1 if failures else 0)
