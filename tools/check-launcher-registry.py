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

  - a row that advertises a SETUP STEP the file no longer needs. Field 2
    of a registry line is the comma list of script libraries the launcher
    puts in use before opening, and the launcher card prints it under
    "Put in use first". Since the demo-embed pass a stack CARRIES the
    libraries it needs, so this gate imports tools/sync-demo-embeds.py's
    REGISTRY - the authority on what is embedded where - and refuses a row
    naming a helper its own file already contains.

Some adopters are launched through a DIFFERENT file than the one that
carries the block - the onionxt sources are edited, but their GENERATED
all-in-one standalones are what a fresh download should open; the suite
core is a build input, but the generated fold is the paste target. Those
pairs live in LAUNCH_AS, each with the reason, and the gate accepts
either spelling while refusing a stale alias.

The union of the two adopter lists is not the whole truth either: a
GENERATED stack carries a banner both drift gates skip, so it appears in
neither list however runnable it is. Those live in EXTRA_RUNNABLE, listed
by hand for the same reason LAUNCH_AS is - so the exemption fails the
build when the file it names moves.
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

# Runnable stacks the two drift gates CANNOT see, so the union above cannot
# reach them. tests/preflight.livecodescript is GENERATED (build-preflight.py),
# and both drift gates skip a file whose first 4000 bytes carry the
# "GENERATED - do not edit" banner - so it sits in neither ADOPTERS list even
# though it builds a window, carries the scaffold block, and is runbook step
# 3.1, the paste that runs first. Listed here so dropping its registry row
# fails the build instead of hiding it again.
EXTRA_RUNNABLE = {
    os.path.join("tests", "preflight.livecodescript"):
        "generated: invisible to both drift gates, but a paste-and-run window stack",
}


def load_attr(tool, attr):
    """Read one module-level table out of a sibling tool, by import.

    Importing rather than re-parsing is deliberate: these tables are the OTHER
    gate's definition of the thing, and a copy here would be a second source of
    truth that drifts silently - the exact failure this file exists to catch,
    one level up."""
    path = os.path.join(HERE, tool)
    spec = importlib.util.spec_from_file_location(tool.replace("-", "_"), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, attr)


def load_adopters(tool, attr="ADOPTERS"):
    return list(load_attr(tool, attr))


def registry_rows():
    """(path, helpers) for every quoted registry line in slRegistry.

    THE HELPERS FIELD USED TO BE DROPPED HERE, and that was the hole. The old
    body read `lit.split("|")[0]` and returned paths only, so field 2 - the
    comma list of script libraries the launcher puts in use before opening -
    was read by no gate at all. It went stale exactly the way an unread field
    does: the 2026-08-18 demo-embed pass gave six demos their own verbatim copy
    of the library they used to need, the two onionxt rows were updated to say
    so, and the other six kept advertising a setup step that no longer exists.
    A launcher that tells a reader to wire up something already inside the file
    is worse than one that says nothing, because it teaches the shape that the
    embed pass exists to retire."""
    text = open(LAUNCHER, encoding="utf-8").read()
    m = re.search(r"(?ms)^function slRegistry\b.*?^end slRegistry", text)
    if not m:
        return None
    rows = []
    for lit in re.findall(r'put "([^"]+)"', m.group(0)):
        parts = lit.split("|")
        rel = parts[0]
        helpers = parts[1] if len(parts) > 1 else ""
        if rel.endswith(".livecodescript"):
            rows.append((rel.replace("/", os.sep),
                         [h.strip().replace("/", os.sep)
                          for h in helpers.split(",") if h.strip()]))
    return rows


def main():
    problems = []
    if not os.path.exists(LAUNCHER):
        print("check-launcher-registry: FAILED - start-here.livecodescript "
              "is missing from the repo root")
        return 1
    rows = registry_rows()
    if rows is None:
        print("check-launcher-registry: FAILED - slRegistry not found in "
              "the launcher")
        return 1
    listed = [rel for rel, _helpers in rows]

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
    runnable |= set(EXTRA_RUNNABLE)
    listed_set = set(listed)
    for rel in sorted(runnable):
        offer = rel
        if rel in LAUNCH_AS:
            offer = LAUNCH_AS[rel][0]
        if rel in NOT_LAUNCHED:
            continue
        if offer not in listed_set and rel not in listed_set:
            why = EXTRA_RUNNABLE.get(rel, "a carried-block adopter")
            problems.append("%s is a runnable stack (%s) but the launcher "
                            "does not offer it - add it to slRegistry, or to "
                            "NOT_LAUNCHED here with the reason" % (rel, why))

    # direction 3: a row must not advertise a helper its own file CARRIES.
    # tools/sync-demo-embeds.py is the authority on what is embedded where, so
    # this imports its REGISTRY rather than restating it. Without this check
    # the helpers field is read by nothing, which is how six rows kept telling
    # a reader to put a library in use that had been inside the file since the
    # 2026-08-18 embed pass.
    embedded = load_attr("sync-demo-embeds.py", "REGISTRY")
    embedded = {os.path.normpath(demo): {os.path.normpath(lib) for lib in libs}
                for demo, libs in embedded.items()}
    for rel, helpers in rows:
        carried = embedded.get(os.path.normpath(rel), set())
        for helper in helpers:
            if os.path.normpath(helper) in carried:
                problems.append(
                    "registry row %s declares helper %s, which that file "
                    "already embeds (tools/sync-demo-embeds.py REGISTRY) - "
                    "empty the helpers field and say so in the note instead"
                    % (rel, helper))

    # the alias table itself must stay live
    for src, (dst, _why) in LAUNCH_AS.items():
        if not os.path.exists(os.path.join(ROOT, src)):
            problems.append("LAUNCH_AS source %s no longer exists" % src)
        if not os.path.exists(os.path.join(ROOT, dst)):
            problems.append("LAUNCH_AS target %s no longer exists" % dst)

    # and so must the third table - same discipline as LAUNCH_AS: a rename
    # must fail the build rather than leave a dead exemption behind it
    for rel in EXTRA_RUNNABLE:
        if not os.path.exists(os.path.join(ROOT, rel)):
            problems.append("EXTRA_RUNNABLE entry %s no longer exists" % rel)

    if problems:
        print("check-launcher-registry: FAILED")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("check-launcher-registry: OK (%d entries, all present; every "
          "runnable adopter offered; no row advertises a helper it already "
          "carries)" % len(listed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
