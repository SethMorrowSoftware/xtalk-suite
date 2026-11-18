#!/usr/bin/env python3
"""test-android-run.py - fixture test of tools/android-run.sh, the script that
runs one Android test executable on a device and reports ITS exit status.

WHY IT NEEDS ONE. android-run.sh is the only thing between "a member's test
failed on the emulator" and a green release lane, and the two ways it can lie
are both silent: trusting `adb shell`'s own exit status (Android 5.0's adbd,
the API 21 emulator the release lane boots, reports 0 whatever the command
returned, as documented for adb before Android 7.0's shell protocol), and
reading "the device printed nothing" as "nothing failed". Neither shows up
on a lane where every test passes, which is every lane until the day one
matters (root CLAUDE.md: fixture before gate; a blind gate still prints OK).

HOW. A fake `adb` (android-run.sh takes it from $ADB) stands in for the
device: `push` copies into a scratch folder that plays /data/local/tmp, and
`shell` runs its command through sh with that path rewritten. The "test
executables" are shell scripts, which is all the wrapper needs them to be.
The fake ALWAYS EXITS 0 from `shell`, as the old adbd does, so every status
this test sees arrived the way it must on the real floor: in the marker line.
Its other modes are the failures a real device produces: output with CR LF
line ends (adb shell without the shell protocol), and a device that goes
away and prints nothing.

It executes no Android code and needs no NDK, so it runs in the compiler-free
gates. What it cannot show is that a real adb and a real device behave as the
fake does; the release workflow's emulator lanes are where that is observed.
"""

import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = os.path.join(HERE, "android-run.sh")
TAG = "test-android-run"
FAILURES = []

# argv: -s SERIAL (push SRC DST | shell COMMAND). FAKE_DEVICE is the folder
# that plays /data/local/tmp; FAKE_MODE picks the device's behaviour.
FAKE_ADB = r'''#!/usr/bin/env python3
import os, shutil, subprocess, sys
args = sys.argv[1:]
device, mode = os.environ["FAKE_DEVICE"], os.environ.get("FAKE_MODE", "")
with open(os.path.join(device, "..", "adb.log"), "a") as log:
    log.write(repr(args) + "\n")
if args[:1] != ["-s"] or len(args) < 3:
    sys.exit("fake adb: expected -s SERIAL ..., got %r" % (args,))
if args[1] != os.environ["FAKE_SERIAL"]:
    sys.exit("fake adb: device %r not found" % args[1])
verb, rest = args[2], args[3:]
local = lambda path: path.replace("/data/local/tmp", device)
if verb == "push":
    shutil.copy(rest[0], local(rest[1]))
    sys.exit(0)
if verb == "shell":
    if mode == "gone" and "XTALK_ANDROID_EXIT" in rest[0]:
        sys.exit(0)             # the device went away: no output, and adb "succeeds"
    done = subprocess.run(["sh", "-c", local(rest[0])], capture_output=True, text=True)
    out = done.stdout + done.stderr
    if mode == "crlf":
        out = out.replace("\n", "\r\n")
    sys.stdout.write(out)
    sys.exit(0)                 # Android 5.0's adbd: 0 whatever the command returned
sys.exit("fake adb: unexpected verb %r" % verb)
'''


def check(ok, label, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {label}")
    if not ok:
        FAILURES.append(f"{label}\n        got: {detail}")
    return ok


def main():
    with tempfile.TemporaryDirectory(prefix="test-android-run-") as tmp:
        device = os.path.join(tmp, "device")
        build = os.path.join(tmp, "build")
        os.makedirs(device)
        os.makedirs(build)
        adb = os.path.join(tmp, "adb")
        with open(adb, "w") as fh:
            fh.write(FAKE_ADB)
        os.chmod(adb, 0o755)

        def exe(name, body):
            path = os.path.join(build, name)
            with open(path, "w") as fh:
                fh.write("#!/bin/sh\n" + body)
            # NOT executable on the "host": the wrapper must chmod it on the
            # device, since adb push does not promise to keep the bit.
            os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
            return path

        def run(argv, mode="", serial="emulator-5554", env_serial=True):
            env = dict(os.environ, ADB=adb, FAKE_DEVICE=device,
                       FAKE_SERIAL="emulator-5554", FAKE_MODE=mode)
            env.pop("XTALK_ANDROID_SERIAL", None)
            if env_serial:
                env["XTALK_ANDROID_SERIAL"] = serial
            done = subprocess.run(["bash", RUNNER] + argv, env=env,
                                  capture_output=True, text=True, timeout=60)
            return done.returncode, done.stdout, done.stderr

        # 1. A passing test: its output is shown, the marker line is not.
        ok = exe("pass_test", 'echo "all 3 checks passed"\nexit 0\n')
        rc, out, err = run([ok])
        check(rc == 0 and "all 3 checks passed" in out, "a passing test "
              "exits 0 and its output is shown", (rc, out, err))
        check("XTALK_ANDROID_EXIT" not in out, "  ...without the marker line "
              "in what is printed", out)
        check(not os.path.exists(os.path.join(device, "xtalk-pass_test")),
              "  ...and its folder on the device is removed afterwards",
              os.listdir(device))

        # 2. THE POINT: a failing test fails the wrapper although adb said 0.
        bad = exe("fail_test", 'echo "1 check FAILED"\nexit 3\n')
        rc, out, err = run([bad])
        check(rc == 3 and "1 check FAILED" in out and "exited 3" in err,
              "a test that exits 3 makes the wrapper exit 3 (adb itself "
              "returned 0)", (rc, out, err))
        rc, out, err = run([bad], mode="crlf")
        check(rc == 3, "  ...and through CR LF line ends too", (rc, out, err))
        rc, out, err = run([ok], mode="crlf")
        check(rc == 0, "  ...where a passing test still passes", (rc, out, err))

        # 3. A test killed by a signal: the device's shell reports 128+n.
        seg = exe("crash_test", 'kill -SEGV $$\n')
        rc, out, err = run([seg])
        check(rc == 139, "a test killed by SIGSEGV makes the wrapper exit "
              "139", (rc, out, err))

        # 4. No marker at all is a failure, never "nothing failed".
        rc, out, err = run([ok], mode="gone")
        check(rc == 1 and "returned no exit status" in err,
              "a device that goes away (no marker) is a FAILURE",
              (rc, out, err))

        # 5. A test that prints a line shaped like the marker cannot vouch
        #    for itself: the shell's own line comes last, and the last wins.
        liar = exe("liar_test", 'echo "XTALK_ANDROID_EXIT=0"\nexit 5\n')
        rc, out, err = run([liar])
        check(rc == 5, "a test that prints its own XTALK_ANDROID_EXIT=0 and "
              "exits 5 still fails with 5", (rc, out, err))

        # 6. Where it runs: in its own folder, which is also its temporary
        #    folder and its library path, with the libraries beside it.
        with open(os.path.join(build, "member.so"), "w") as fh:
            fh.write("library")
        with open(os.path.join(build, "member_seams.so"), "w") as fh:
            fh.write("seams")
        where = exe("where_test",
                    'echo "cwd=$(pwd)"\necho "tmp=$TMPDIR"\n'
                    'echo "libs=$LD_LIBRARY_PATH"\n'
                    'echo "files=$(ls | sort | tr "\\n" " ")"\n'
                    'echo "x=$(test -x where_test && echo yes)"\n')
        rc, out, err = run([where])
        folder = os.path.join(device, "xtalk-where_test")
        check(rc == 0 and f"cwd={folder}" in out and f"tmp={folder}" in out
              and f"libs={folder}" in out,
              "a test runs in its own folder under /data/local/tmp, which "
              "is its TMPDIR and LD_LIBRARY_PATH", (rc, out, err))
        check("files=member.so member_seams.so where_test " in out,
              "  ...with every .so that was beside it, and nothing else",
              out)
        check("x=yes" in out, "  ...made executable there", out)

        # 7. A library left by an earlier run is never the one a test loads:
        #    the folder is emptied first.
        os.makedirs(folder)
        with open(os.path.join(folder, "stale.so"), "w") as fh:
            fh.write("stale")
        rc, out, err = run([where])
        check(rc == 0 and "stale.so" not in out,
              "a library left in the folder by an earlier run is gone "
              "before the test starts", (rc, out, err))

        # 8. Arguments arrive as given: spaces, a single quote, a glob, a
        #    dollar sign - nothing the device's shell may expand.
        argv_test = exe("argv_test", 'for a in "$@"; do echo "arg=[$a]"; done\n')
        rc, out, err = run([argv_test, "two words", "it's", "*", "$HOME", ""])
        check(rc == 0 and out.splitlines() == [
            "arg=[two words]", "arg=[it's]", "arg=[*]", "arg=[$HOME]",
            "arg=[]"], "arguments reach the test unchanged (spaces, a "
              "quote, a glob, a dollar sign, an empty one)", (rc, out, err))

        # 9. The refusals: no serial, a file that is not there, no argument,
        #    and a serial adb does not know (its own error is not a pass).
        rc, out, err = run([ok], env_serial=False)
        check(rc != 0 and "XTALK_ANDROID_SERIAL" in err,
              "without XTALK_ANDROID_SERIAL it refuses to run",
              (rc, out, err))
        rc, out, err = run([os.path.join(build, "no_such_test")])
        check(rc == 2 and "is not a file" in err,
              "a missing executable is refused (exit 2)", (rc, out, err))
        rc, out, err = run([])
        check(rc == 2, "no argument prints the usage (exit 2)",
              (rc, out, err))
        rc, out, err = run([ok], serial="emulator-9999")
        check(rc != 0, "a serial adb does not know is a failure",
              (rc, out, err))

    if FAILURES:
        print(f"\n{TAG}: {len(FAILURES)} FAILURE(S)")
        for failure in FAILURES:
            print(f"  {failure}")
        return 1
    print(f"\n{TAG}: OK - tools/android-run.sh reports each test's own exit "
          f"status through a fake adb that always returns 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
