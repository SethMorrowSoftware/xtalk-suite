#!/usr/bin/env python3
"""check-launcher-registry.py - the start-here launcher's directory is true.

start-here.livecodescript at the repo root is the suite's front door: a
hand-maintained registry of every runnable stack, by repo-relative path.
Hand-maintained ON PURPOSE (a glob cannot write descriptions or say what a
stack needs), which means it can rot in two directions, and this gate
closes both:

  - a registry entry whose file is gone (a rename or move left the front
    door pointing at nothing);
  - a runnable stack the registry does not offer (a new demo that the
    front door silently hides). "Runnable stack" is measured, not
    guessed: it is the union of the two carried-block adopter lists (the
    UI-kit demos and the scaffold-carrying harnesses), which the drift
    gates already hold complete.

Some adopters are launched through a DIFFERENT file than the one that
carries the block - the onionxt sources are edited, but their GENERATED
all-in-one standalones are what a fresh download should open; the suite
core is a build input, but the generated fold is the paste target. Those
pairs live in LAUNCH_AS, each with the reason, and the gate accepts
either spelling while refusing a stale alias.
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

LAUNCHER = os.path.join(ROOT, "start-here.livecodescript")

# adopter -> the file the launcher offers instead, with the reason
#
# THE TWO ONIONXT ENTRIES ARE GONE (2026-08-17), and their absence is the
# point. They mapped onionxt-demo -> onionxt-demo-standalone and spike ->
# standalone, because the demo needed `start using` wiring and only the
# GENERATED twin could be pasted and run. That is exactly the confusion the
# demo-embed pass removed: every demo now carries the script libraries it
# needs (tools/sync-demo-embeds.py), so the demo IS the launchable artifact
# and there is no twin to redirect to. Both generated standalones and the
# generator that produced them were retired in the same change.
LAUNCH_AS = {
    os.path.join("tests", "suite-selftest.core.livecodescript"):
        (os.path.join("tests", "suite-selftest.livecodescript"),
         "the core is a build input; the generated fold is what runs"),
}

# adopters that are deliberately NOT in the launcher, with the reason
NOT_LAUNCHED = {
    # (none today; an entry here needs a written reason like the others)
}


def load_adopters(tool, attr="ADOPTERS"):
    path = os.path.join(HERE, tool)
    spec = importlib.util.spec_from_file_location(tool.replace("-", "_"), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return list(getattr(mod, attr))


def registry_paths():
    """The first |-field of every quoted registry line in slRegistry."""
    text = open(LAUNCHER, encoding="utf-8").read()
    m = re.search(r"(?ms)^function slRegistry\b.*?^end slRegistry", text)
    if not m:
        return None
    paths = []
    for lit in re.findall(r'put "([^"]+)"', m.group(0)):
        rel = lit.split("|")[0]
        if rel.endswith(".livecodescript"):
            paths.append(rel.replace("/", os.sep))
    return paths


def main():
    problems = []
    if not os.path.exists(LAUNCHER):
        print("check-launcher-registry: FAILED - start-here.livecodescript "
              "is missing from the repo root")
        return 1
    listed = registry_paths()
    if listed is None:
        print("check-launcher-registry: FAILED - slRegistry not found in "
              "the launcher")
        return 1

    # direction 1: every listed path exists
    for rel in listed:
        if not os.path.exists(os.path.join(ROOT, rel)):
            problems.append("registry lists %s, which does not exist" % rel)

    # direction 2: every runnable adopter is offered (directly or via alias)
    runnable = set()
    for rel in load_adopters("check-ui-kit-drift.py"):
        if rel == "start-here.livecodescript":
            continue  # the launcher does not list itself
        runnable.add(rel)
    for rel in load_adopters("check-harness-scaffold-drift.py"):
        runnable.add(rel)
    listed_set = set(listed)
    for rel in sorted(runnable):
        offer = rel
        if rel in LAUNCH_AS:
            offer = LAUNCH_AS[rel][0]
        if rel in NOT_LAUNCHED:
            continue
        if offer not in listed_set and rel not in listed_set:
            problems.append("%s is a runnable stack (a carried-block "
                            "adopter) but the launcher does not offer it - "
                            "add it to slRegistry, or to NOT_LAUNCHED here "
                            "with the reason" % rel)

    # the alias table itself must stay live
    for src, (dst, _why) in LAUNCH_AS.items():
        if not os.path.exists(os.path.join(ROOT, src)):
            problems.append("LAUNCH_AS source %s no longer exists" % src)
        if not os.path.exists(os.path.join(ROOT, dst)):
            problems.append("LAUNCH_AS target %s no longer exists" % dst)

    if problems:
        print("check-launcher-registry: FAILED")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("check-launcher-registry: OK (%d entries, all present; every "
          "runnable adopter offered)" % len(listed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
