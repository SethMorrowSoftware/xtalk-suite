#!/usr/bin/env python3
"""test-platformer-levels.py - prove tools/check-platformer-levels.py can FAIL.

A gate that has gone blind prints OK (the suite root CLAUDE.md: "fixture
before gate"), and this gate's OK is a large claim - every level of the
platformer built once and played to its flag, with the art, from a saved
stack and with none - made by a model of the engine, which is exactly the
kind of thing that goes quietly blind. So this drives the gate the way
run-gates.sh does (a subprocess, the real entry point, --file on a copy of
the SHIPPED game) with one defect edited into the copy each time, and
requires a non-zero exit with the defect NAMED in the output. Then it drives
the untouched copy and requires OK, so a fixture that "fails" because the
copy would not load at all cannot pass as discrimination.

The seeded defects, and what each stands in for:
  1. The level-4 floor loop as it shipped before 2026-10-08: `next repeat`
     above the loop's own `add`, so x stopped at the lava pit and the build
     never ended (box2dxt CLAUDE.md gotcha 32; the IDE froze as L4 began).
     The gate must stop it on the statement budget and name the L4 build.
  2. The level picker synced AFTER gBuilding went false with messages on,
     as before PR #153: its menuHistory set sends menuPick (engine note
     5.14), whose jump built every level a flag advanced to a second time.
  3. A throw inside the frame: b2kStep's frame `try` swallows it on an
     engine (gotcha 31), so a level that throws every frame still "plays".
     The gate must name the catch.
  4. The no-art hero set up with messages on again (pfEmbedPlaceholder
     above the build's `lock messages`, as before 2026-10-08, which this
     gate found): a newImage and a deleteImage per old slice, every no-art
     build (engine note 5.15).
  5. A saved stack that no longer adopts its own import (pfMedia always
     false): reopened with no art folder, it asks for one. Only the reopen
     profile can see it.
  6. The flag clearing a level without the coins (its gate on gCoins
     removed): the tour stands on the flag first, which must refuse.
  7. An error no `try` catches, thrown as a flag advances to L3: on an
     engine the script-error dialog, and the end of that handler chain.
     The gate must report it as such, never as a Python traceback.

Each mutation is asserted to APPLY (its anchor must occur exactly once), so
a rename in the shipped game fails this test rather than silently turning a
fixture into a no-op. The runs are independent processes, so they run side
by side; each asks only for the profiles that can see its defect.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-platformer-levels.py")
GAME = os.path.join(MEMBER, "examples", "box2dxt-platformer.livecodescript")

# (label, anchor, replacement, profiles, what the output must name; every
# string in the last must appear)
FIXTURES = [
    ("the level-4 floor loop that froze the IDE (gotcha 32)",
     '         if tX < 2944 or tX >= 3456 then pfTile "terrain_purple_block_top", tX, 576\n',
     '         if tX >= 2944 and tX < 3456 then next repeat\n'
     '         pfTile "terrain_purple_block_top", tX, 576\n',
     "art",
     ("the L4 build never finished", "pfL4Scene")),
    ("the level picker synced after the build, so its menuPick built again",
     '   if there is a button "pfbtn_level" then set the menuHistory of button'
     ' "pfbtn_level" to gLevel\n'
     '   unlock screen\n   unlock messages\n   put empty into gHudLast\n'
     '   put true into gStarted\n   put false into gBuilding\n',
     '   unlock screen\n   unlock messages\n   put empty into gHudLast\n'
     '   put true into gStarted\n   put false into gBuilding\n'
     '   if there is a button "pfbtn_level" then set the menuHistory of button'
     ' "pfbtn_level" to gLevel\n',
     "placeholder",
     ("sent it menuPick (engine note 5.14)",)),
    ("a throw inside the frame, which b2kStep's try swallows (gotcha 31)",
     '   if gHero is empty then exit b2kFrame\n',
     '   if gHero is empty then exit b2kFrame\n'
     '   if gLevel is 2 then put the width of graphic "pfNoSuchControl" into tHud\n',
     "placeholder",
     ("b2kStep caught an error", "pfNoSuchControl")),
    ("the no-art hero set up with messages on (pfEmbedPlaceholder unlocked)",
     '   lock messages\n   lock screen\n'
     '   if gAssetsOK is not true then pfEmbedPlaceholder\n',
     '   if gAssetsOK is not true then pfEmbedPlaceholder\n'
     '   lock messages\n   lock screen\n',
     "placeholder",
     ("the quiet build is not quiet", "pfEmbedPlaceholder")),
    ("a saved stack that no longer adopts its own import (pfMedia false)",
     '   return (there is an image "b2ksheet_chars")\nend pfMedia\n',
     '   return false\nend pfMedia\n',
     "reopen",
     ("FAIL reopen", "an unplanned answer folder dialog")),
    ("the flag clearing a level without its coins",
     '      if gCoins >= gCoinsTotal or gCamOK is not true then\n',
     '      if gCoins >= 0 or gCamOK is not true then\n',
     "placeholder",
     ("the flag cleared the level with 0 of",)),
    ("an error no `try` catches as a flag advances (the script-error dialog)",
     '   add 1 to gLevel\n   pfStartGame\nend pfNextLevel\n',
     '   add 1 to gLevel\n'
     '   if gLevel is 3 then put the width of graphic "pfNoSuchControl" into gLevelName\n'
     '   pfStartGame\nend pfNextLevel\n',
     "placeholder",
     ("a script error no `try` caught", "pfNoSuchControl")),
]


def run_gate(path, profiles=None):
    cmd = [sys.executable, GATE, "--file", path]
    if profiles:
        cmd += ["--profiles", profiles]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    with open(GAME, "r", encoding="utf-8") as fh:
        shipped = fh.read()
    tmp = tempfile.mkdtemp(prefix="platformer-levels-fixtures-")
    failed = 0
    try:
        jobs = []
        for k, (label, anchor, replacement, profiles, names) in enumerate(FIXTURES):
            if shipped.count(anchor) != 1:
                print("FAIL  %s - the anchor occurs %d times in the shipped game, "
                      "so the fixture cannot apply" % (label, shipped.count(anchor)))
                failed += 1
                continue
            path = os.path.join(tmp, "mutant-%d.livecodescript" % (k + 1))
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(shipped.replace(anchor, replacement))
            jobs.append((label, path, profiles, names))
        clean = os.path.join(tmp, "clean.livecodescript")
        with open(clean, "w", encoding="utf-8") as fh:
            fh.write(shipped)
        with ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as pool:
            runs = [pool.submit(run_gate, path, profiles)
                    for _label, path, profiles, _names in jobs]
            clean_run = pool.submit(run_gate, clean)
            for (label, _path, _profiles, names), fut in zip(jobs, runs):
                rc, out = fut.result()
                missing = [n for n in names if n not in out]
                if rc == 0:
                    failed += 1
                    print("FAIL  %s - the gate passed a game carrying it" % label)
                elif rc != 1 or missing:
                    failed += 1
                    print("FAIL  %s - the gate failed (exit %d) without naming %s\n"
                          "      %s" % (label, rc, " and ".join(repr(n) for n in missing)
                                        or "it", "\n      ".join(out.strip().split("\n")[-6:])))
                else:
                    print("PASS  %s" % label)
            rc, out = clean_run.result()
        if rc != 0:
            failed += 1
            print("FAIL  the untouched copy does not pass, so nothing above was "
                  "discrimination\n      " + "\n      ".join(out.strip().split("\n")[-8:]))
        else:
            print("PASS  the untouched copy passes every profile")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if failed:
        print("test-platformer-levels: FAIL (%d)" % failed)
        return 1
    print("test-platformer-levels: OK (%d seeded defects caught, the clean copy passes)"
          % len(FIXTURES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
