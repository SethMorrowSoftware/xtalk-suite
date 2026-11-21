#!/usr/bin/env python3
"""test-build-android.py - what can be held about tools/build-android.sh
without an NDK: its tables agree with every other table that names an Android
platform, its pins are the release workflow's, and its refusals refuse.

WHY. Android is named in six places that no compiler connects: the build
script (which ABIs it builds, with which pinned dependencies), the installer
(which ids it accepts and checks as Android), the freshness gate (which ids
it reads), the package builder (which ids a package may carry), the release
workflow (which ABIs its job builds, and which of them it runs tests for)
and each member's packager. An id added to one and not the others is a
library that is built and then refused, or accepted and never built - found
at the end of a release dispatch, the most expensive place there is (the
arm64-linux rows were: release run 37416038113 built every library and
stopped at a table that did not know the id). So the tables are compared
here, on every push, and a new native member or ABI that reaches one of them
fails until it reaches all.

It also holds the one line an Android APP needs from a binding: the four
members that open sockets declare `metadata android.permissions is
"INTERNET"`, which OXT's standalone builder turns into the app's permission,
and the other three declare none.

The pins are the other half: OpenSSL and Boost are pinned in the workflow's
desktop lanes and again in the script, and a bump in one place must not
leave Android linking the old version (root CLAUDE.md: hand-copied numbers
go stale silently).

It runs no compiler. The refusals that need "an NDK" get a folder that only
looks like one (a source.properties and an empty clang), which is enough to
reach the checks under test and can build nothing.
"""

import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(HERE, "build-android.sh")
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "release-binaries.yml")
TAG = "test-build-android"
# The native members whose library opens a socket (ENet's UDP hosts, libcurl,
# libdatachannel's ICE and SCTP, libtorrent's listeners and DHT). The other
# three (sodiumxt, coinxt, box2dxt) compute and never touch the network.
NETWORK_MEMBERS = ("enetxt", "curlxt", "datachannelxt", "torrentxt")
# The native members that are NOT built for Android, each with its reason
# (2026-11-20). Such a member is held to the opposite of every Android rule
# below: build-android.sh must not name it and its packager must name no
# Android id, so "not built" can never drift into "half built".
NO_ANDROID = {
    "gamepadxt": "SDL reads controllers on Android through its own Java "
                 "activity, which an OXT app does not have (docs/ANDROID.md)",
}
FAILURES = []


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check(ok, label, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {label}")
    if not ok:
        FAILURES.append(f"{label}\n        got: {detail}")
    return ok


def run(argv, env=None):
    base = {k: v for k, v in os.environ.items()
            if not k.startswith(("ANDROID_", "XTALK_ANDROID_")) and k != "ADB"}
    base.update(env or {})
    done = subprocess.run(["bash", SCRIPT] + argv, env=base,
                          capture_output=True, text=True, timeout=120)
    return done.returncode, done.stdout, done.stderr


def fake_ndk(tmp, name, revision, clang=True):
    ndk = os.path.join(tmp, name)
    os.makedirs(os.path.join(ndk, "toolchains", "llvm", "prebuilt",
                             "linux-x86_64", "bin"))
    with open(os.path.join(ndk, "source.properties"), "w") as fh:
        fh.write("Pkg.Desc = Android NDK\nPkg.Revision = %s\n" % revision)
    if clang:
        path = os.path.join(ndk, "toolchains", "llvm", "prebuilt",
                            "linux-x86_64", "bin", "clang")
        with open(path, "w") as fh:
            fh.write("#!/bin/sh\nexit 1\n")
        os.chmod(path, 0o755)
    return ndk


def fake_adb(tmp, name, abilist):
    """An adb that answers the one question build-android.sh asks a device
    before it builds (None: there is no such device)."""
    path = os.path.join(tmp, name)
    with open(path, "w") as fh:
        if abilist is None:
            fh.write("#!/bin/sh\necho \"adb: device 'x' not found\" >&2\nexit 1\n")
        else:
            # CR LF, as adb shell prints without its shell protocol.
            fh.write("#!/bin/sh\nprintf '%s\\r\\n'\n" % abilist)
    os.chmod(path, 0o755)
    return path


def main():
    installer = load("irb", "install-release-binaries.py")
    freshness = load("cbf", "check-binary-freshness.py")
    packages = load("lce", "build-lce-packages.py")
    with open(WORKFLOW, encoding="utf-8") as fh:
        workflow = fh.read()

    # 1. The tables.
    rc, out, err = run(["--list"])
    listed = dict(line.split(":", 1) for line in out.splitlines() if ":" in line)
    members = listed.get("members", "").split()
    platforms = listed.get("platforms", "").split()
    check(rc == 0 and members and platforms, "--list names members and "
          "platform ids", (rc, out, err))
    every_native = [m["name"] for m in freshness.MEMBERS]
    check(set(NO_ANDROID) <= set(every_native),
          "every member in NO_ANDROID is a native member", sorted(NO_ANDROID))
    native = [m for m in every_native if m not in NO_ANDROID]
    check(sorted(members) == sorted(native),
          "it builds exactly the native members the freshness gate knows, "
          "bar NO_ANDROID's", (members, native))
    check(sorted(members) == sorted(m for m in installer.MEMBERS
                                    if m not in NO_ANDROID),
          "  ...which are the members the installer installs, bar NO_ANDROID's",
          (members, sorted(installer.MEMBERS)))
    for member in sorted(NO_ANDROID):
        packer = os.path.join(ROOT, member, "tools", "package-extension.py")
        with open(packer, encoding="utf-8") as fh:
            text = fh.read()
        check("-android" not in text,
              f"{member} is not built for Android, so its packager names no "
              f"Android id")
    check(sorted(platforms) == sorted(installer.ANDROID_ABIS),
          "its platform ids are the installer's ANDROID_ABIS",
          (platforms, sorted(installer.ANDROID_ABIS)))
    gate_ids = [p for p in freshness.PLATFORMS if p.endswith("-android")]
    check(sorted(platforms) == sorted(gate_ids),
          "  ...and the freshness gate's Android PLATFORMS",
          (platforms, gate_ids))
    check(sorted(platforms) == sorted(packages.ANDROID),
          "  ...and the package builder's ANDROID", (platforms, packages.ANDROID))
    for platform in platforms:
        check(installer.platform_kind(platform) == "android"
              and freshness.PLATFORMS.get(platform) == ("so", "elf"),
              f"  ...{platform} is an Android id to the installer and an ELF "
              f".so to the gate", platform)
    for member in native:
        packer = os.path.join(ROOT, member, "tools", "package-extension.py")
        with open(packer, encoding="utf-8") as fh:
            text = fh.read()
        check("android" in text, f"{member}'s packager knows the Android ids")

    # The INTERNET permission. Android gives a process no socket without it,
    # and OXT's standalone builder takes it from an included extension's
    # `metadata android.permissions` (ide-support/revsblibrary: it reads the
    # extension's "android" property and sets the app's permissions from
    # it). So each member that opens a socket declares it, exactly once, and
    # a member that opens none declares nothing: a permission that appears
    # in a crypto or physics library is a question for a reviewer, not a
    # default. WHICH members open sockets is this table, by hand; nothing
    # in a compiler-free gate can derive it.
    for member in native:
        folder = os.path.join(ROOT, member, "src")
        lcbs = [f for f in sorted(os.listdir(folder)) if f.endswith(".lcb")]
        lines = []
        for name in lcbs:
            with open(os.path.join(folder, name), encoding="utf-8") as fh:
                lines += [l.strip() for l in fh
                          if re.match(r"\s*metadata\s+android\.", l)]
        want = (['metadata android.permissions is "INTERNET"']
                if member in NETWORK_MEMBERS else [])
        check(bool(lcbs) and lines == want,
              f"{member}'s binding declares " + ("the INTERNET permission, "
              "once" if want else "no Android permission"), (lcbs, lines))
    check(set(NETWORK_MEMBERS) <= set(native),
          "every member in NETWORK_MEMBERS is a native member",
          NETWORK_MEMBERS)

    # The workflow's Android job: one row per id, emulator rows exactly the
    # x86 pair (the ABIs an x86_64 emulator runs), which is what the
    # workflow's own comments and the docs promise.
    job = workflow[workflow.index("\n  android:\n"):workflow.index("\n  bundle:\n")]
    rows = re.findall(r"- platform_id: (\S+)\n((?:\s+emulator: \S+\n)?)", job)
    check(sorted(p for p, _ in rows) == sorted(platforms),
          "the workflow's android job has one row per platform id",
          (rows, platforms))
    check(sorted(p for p, emu in rows if emu) == ["x86-android", "x86_64-android"],
          "  ...and runs tests (emulator rows) for exactly the two x86 ABIs",
          rows)
    check("tools/build-android.sh --list" in job and
          'bash tools/build-android.sh "$member"' in job,
          "  ...building every member the script lists, through the script",
          "")

    # 2. The pins.
    rc, out, err = run(["--pins"])
    pins = {line.split()[0]: line.split()[1:] for line in out.splitlines()}
    check(rc == 0 and set(pins) == {"ndk", "api", "openssl", "boost"},
          "--pins names the NDK, the API level, OpenSSL and Boost", out)
    check(pins.get("api") == [str(installer.ANDROID_API_FLOOR)],
          "the API level it builds for is the installer's floor",
          (pins.get("api"), installer.ANDROID_API_FLOOR))
    if len(pins.get("openssl", [])) == 2 and len(pins.get("boost", [])) == 2:
        version, sha = pins["openssl"]
        check(f"openssl-{version}/openssl-{version}.tar.gz" in workflow
              and sha in workflow and len(sha) == 64,
              f"OpenSSL {version} and its sha256 are the release workflow's "
              f"desktop pin", pins["openssl"])
        others = set(re.findall(r"openssl-(\d+\.\d+\.\d+)\.tar\.gz", workflow))
        check(others == {version}, "  ...and the workflow names no other "
              "OpenSSL version", others)
        version, sha = pins["boost"]
        check(f"boost-{version}/boost-{version}-b2-nodocs.tar.gz" in workflow
              and sha in workflow and len(sha) == 64,
              f"Boost {version} and its sha256 are the release workflow's "
              f"desktop pin", pins["boost"])
    else:
        check(False, "--pins gives a version and a sha256 for OpenSSL and "
              "Boost", pins)
    ndk_pin = (pins.get("ndk") or [""])[0]

    # 3. The refusals.
    rc, out, err = run([])
    check(rc == 2 and "build-android.sh <member> <platform-id>" in err,
          "no arguments prints the usage (exit 2)", (rc, err))
    rc, out, err = run(["onionxt", "arm64-android"])
    check(rc == 2 and "not a native member" in err,
          "a member with no native library is refused (exit 2)", (rc, err))
    rc, out, err = run(["enetxt", "arm64-linux"])
    check(rc == 2 and "not an Android platform id" in err,
          "a platform id that is not Android's is refused (exit 2)", (rc, err))
    rc, out, err = run(["enetxt", "arm64-android"])
    check(rc == 1 and "no Android NDK found" in err and ndk_pin in err,
          "with no NDK it stops and names the pinned revision", (rc, err))

    with tempfile.TemporaryDirectory(prefix="test-build-android-") as tmp:
        work = os.path.join(tmp, "work")
        other = fake_ndk(tmp, "ndk-other", "27.2.12479018")
        rc, out, err = run(["enetxt", "arm64-android"],
                           {"ANDROID_NDK_HOME": other, "XTALK_ANDROID_WORK": work})
        check(rc == 1 and "the pin is " + ndk_pin in err,
              "an NDK of another revision is refused", (rc, err))
        # The same NDK found under an SDK folder, the way a CI runner holds
        # it: only <sdk>/ndk/<the pinned revision> is looked at, so an SDK
        # with other revisions installed is "no NDK", never a silent pick.
        sdk = os.path.join(tmp, "sdk")
        os.makedirs(os.path.join(sdk, "ndk"))
        os.rename(other, os.path.join(sdk, "ndk", "27.2.12479018"))
        rc, out, err = run(["enetxt", "arm64-android"],
                           {"ANDROID_HOME": sdk, "XTALK_ANDROID_WORK": work})
        check(rc == 1 and "no Android NDK found" in err,
              "an SDK holding only another NDK revision is 'no NDK'",
              (rc, err))
        other = os.path.join(sdk, "ndk", "27.2.12479018")
        hollow = fake_ndk(tmp, "ndk-hollow", "27.2.12479018", clang=False)
        rc, out, err = run(["enetxt", "arm64-android"],
                           {"ANDROID_NDK_HOME": hollow, "XTALK_ANDROID_WORK": work,
                            "XTALK_ANDROID_ANY_NDK": "1"})
        check(rc == 1 and "WARNING: building with NDK 27.2.12479018" in err
              and "must not be committed" in err,
              "XTALK_ANDROID_ANY_NDK=1 lets another revision through, with "
              "a warning that its library must not be committed", (rc, err))

        # The device is asked what it runs BEFORE anything is built.
        pinned = fake_ndk(tmp, "ndk-pinned", ndk_pin)
        env = {"ANDROID_NDK_HOME": pinned, "XTALK_ANDROID_WORK": work,
               "XTALK_ANDROID_SERIAL": "emulator-5554"}
        rc, out, err = run(["enetxt", "arm64-android"],
                           dict(env, ADB=fake_adb(tmp, "adb-x86", "x86_64,x86")))
        check(rc == 1 and "runs 'x86_64,x86', not arm64-v8a" in err,
              "a device that cannot run the ABI is refused (an x86_64 "
              "emulator, an arm64 build)", (rc, err))
        check("== build-android: enetxt for" not in out,
              "  ...before the build starts", out)
        rc, out, err = run(["enetxt", "x86-android"],
                           dict(env, ADB=fake_adb(tmp, "adb-gone", None)))
        check(rc == 1 and "runs 'nothing adb could ask it', not x86" in err,
              "a device adb cannot reach is refused, not skipped", (rc, err))
        # ...and one that does run it gets past the question: the build
        # starts (and then fails, on the hollow NDK - not a pass either).
        rc, out, err = run(["enetxt", "x86-android"],
                           dict(env, ADB=fake_adb(tmp, "adb-ok", "x86_64,x86")))
        check(rc != 0 and "== build-android: enetxt for x86-android" in out,
              "a device that runs the ABI (x86 on an x86_64,x86 emulator) "
              "gets past the question", (rc, out, err))
        check(not os.path.exists(os.path.join(ROOT, "enetxt", "src", "code",
                                              "x86-android", "enetxt.so.tmp")),
              "  ...and a failed build leaves no half-written library")

    if FAILURES:
        print(f"\n{TAG}: {len(FAILURES)} FAILURE(S)")
        for failure in FAILURES:
            print(f"  {failure}")
        return 1
    print(f"\n{TAG}: OK - build-android.sh's members, platform ids and pins "
          f"agree with the installer, the freshness gate, the package "
          f"builder, the packagers and the release workflow, and its "
          f"refusals hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
