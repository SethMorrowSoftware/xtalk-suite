#!/usr/bin/env python3
"""member-registry.py - the ONE table of what a suite member is.

WHY THIS FILE EXISTS. Every member is developed here and PUBLISHED into a
repository of its own (docs/MEMBER-REPO-SPLIT.md; decided 2026-09-22), and
four tools need the same facts about each one: which repository it is
published to, which siblings its gates reach into, whether it has a native
build lane, and what kind of thing it is. Until 2026-09-21 those facts
lived in prose (the root README's member table, each member's CLAUDE.md,
the runbook) and in the heads of the
people who wrote them - which is the hand-copied-constant failure this
tree's root CLAUDE.md records for ABI numbers and for coverage ratios. A
generator that reads a table cannot disagree with another generator that
reads the same table, so the table is here and the generators import it:

    tools/sync-member-workflows.py   each member's own .github/workflows/
    tools/sync-member-readmes.py     each README's "Relationship to the
                                     xTalk suite" section
    tools/check-member-standalone.py the readiness gate
    tools/publish-members.py         the publisher: which repository each
                                     member's verified trees are pushed to

The registry is DATA, not a scanner: a member not listed here is a member
the split tooling does not see, exactly as tools/sync-demo-embeds.py's
REGISTRY works. check-member-standalone.py refuses a member directory that
is absent from this table and a table row whose directory is gone, so the
two cannot drift apart silently - the archivext lesson, one level up.

    python3 tools/member-registry.py          # prints the table
    python3 tools/member-registry.py --names  # just the names, for a shell
    git diff --name-only --no-renames A B | \
        python3 tools/member-registry.py --affected   # whose gates to run
    python3 tools/member-registry.py --selftest   # the --affected rule's fixtures

Import it the way the rest of tools/ imports its neighbours (exec-load by
path; there is no package here).
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SUITE_REPO = "SethMorrowSoftware/xtalk-suite"
SUITE_URL = "https://github.com/" + SUITE_REPO
OWNER = "SethMorrowSoftware"


class Member(object):
    """One row. Every field is something a generator reads."""

    def __init__(self, name, title, kind, repo, native, siblings,
                 mirror_note=""):
        self.name = name                # directory name == the sibling name
        self.title = title              # how the member spells itself
        self.kind = kind                # "extension" | "app"
        self.repo = repo                # owner/name of its own repository
        self.native = native            # has a root native-<name>.yml lane
        # Sibling members its GATES reach into (tools/run-gates.sh needs them
        # beside the checkout, as ../<name>, or XTALK_SIBLINGS pointed at a
        # directory holding them). This is the gate dependency, which is a
        # different question from what the shipped code needs at run time:
        # a demo that CARRIES a sibling's library needs nothing beside it,
        # because the copy is in the file (tools/sync-demo-embeds.py).
        self.siblings = list(siblings)
        # Where the repository came from, for a reader. Whether it EXISTS is
        # deliberately not a field: a boolean kept by hand here went stale
        # the day the two missing repositories were created (2026-09-22),
        # and `python3 tools/publish-members.py status` observes it live.
        self.mirror_note = mirror_note

    @property
    def url(self):
        return "https://github.com/" + self.repo

    @property
    def path(self):
        return os.path.join(ROOT, self.name)


# The order is the order every generated document lists them in: the eight
# extensions first (native before pure-script, as the root README's table
# has them), then the three apps.
MEMBERS = [
    Member("sodiumxt", "SodiumXT", "extension", OWNER + "/SodiumXT",
           native=True, siblings=[],
           mirror_note="the pre-suite home"),
    Member("torrentxt", "TorrentXT", "extension", OWNER + "/TorrentXT",
           native=True,
           # tools/check-script-vectors.py (2026-09-24) runs the Model C
           # handlers of both demos through riptide's runner, which loads
           # nostrxt's interpreter at import; its tier 2 calls the committed
           # sodiumxt binary. (The runner's coinxt binary is optional and
           # this gate never asks for it.)
           siblings=["riptide", "nostrxt", "sodiumxt"],
           mirror_note="the pre-suite home (it once vendored enetxt/ and "
                       "datachannelxt/ as subfolders)"),
    Member("enetxt", "enetxt", "extension", OWNER + "/enetxt",
           native=True, siblings=[],
           mirror_note="never had a repository of its own - it grew inside "
                       "TorrentXT's tree - so this one was created empty for "
                       "the suite to publish into"),
    Member("datachannelxt", "DataChannelXT", "extension",
           OWNER + "/dataChannelXT", native=True,
           # tools/check-script-vectors.py (2026-09-27) runs the dht-chat's
           # signaling parse through riptide's runner, which loads nostrxt's
           # interpreter at import. (The runner's coinxt binary is optional
           # and this gate never asks for it.)
           siblings=["riptide", "nostrxt"],
           mirror_note="the pre-suite home"),
    Member("box2dxt", "Box2Dxt", "extension", OWNER + "/Box2Dxt",
           native=True,
           # tools/check-platformer-levels.py (2026-10-08) plays the
           # platformer on the family interpreter riptide's runner loads
           # (nostrxt's, at import), over this member's own committed
           # library. (The runner's coinxt binary is optional and this gate
           # never asks for it.)
           siblings=["riptide", "nostrxt"],
           mirror_note="the family ancestor's own repository, folded home "
                       "2026-08-14"),
    Member("coinxt", "CoinXT", "extension", OWNER + "/CoinXT",
           native=True,
           # tools/check-wallet-boot.py REUSES riptide's boot runner rather
           # than copying it, and that runner loads nostrxt's lcs-interp.py
           # and oracle at import time - so the wallet gate needs both.
           siblings=["riptide", "nostrxt"],
           mirror_note="the pre-suite home"),
    Member("onionxt", "OnionXT", "extension", OWNER + "/OnionXT",
           native=False, siblings=[],
           mirror_note="the pre-suite home"),
    Member("nostrxt", "NostrXT", "extension", OWNER + "/NostrXT",
           native=False,
           # tier 2 of tools/check-script-vectors.py executes the composed
           # paths against the COMMITTED coinxt and sodiumxt x86_64-linux
           # binaries; without them it skips that tier and says so.
           siblings=["coinxt", "sodiumxt"],
           mirror_note="born in the suite (2026-08-23), so this one was "
                       "created empty for the suite to publish into"),
    Member("riptide", "Riptide Social", "app", OWNER + "/RipTide",
           native=False,
           # check-script-vectors.py runs the shipped library through
           # nostrxt's interpreter against the committed coinxt binary;
           # riptide_reference.py exec-loads nostrxt's oracle.
           siblings=["nostrxt", "coinxt"],
           mirror_note="the capstone app's pre-suite home"),
    Member("nocloud", "No Cloud Quick Share", "app", OWNER + "/nocloud",
           native=False,
           # check-script-vectors.py boots the helpers through riptide's
           # runner, which in turn needs riptide's own siblings.
           siblings=["riptide", "nostrxt", "coinxt"],
           mirror_note="the pre-suite home, folded in 2026-08-13"),
    Member("holde-em", "holde-em", "app", OWNER + "/hold-em",
           native=False,
           siblings=["riptide", "nostrxt", "coinxt"],
           mirror_note="the pre-suite `hold-em` repository, folded in "
                       "2026-08-15"),
]

BY_NAME = dict((m.name, m) for m in MEMBERS)


def siblings_of(name):
    """The siblings a member's gates need beside it. The list is written
    CLOSED by hand, not computed: a gate that loads riptide's runner inherits
    what that runner loads at import time (nostrxt's interpreter and oracle,
    the committed coinxt binary), so nocloud's row names all three - but a
    gate that loads only coinxt's BINARY does not inherit coinxt's gate
    needs, which is why nostrxt's row stops at coinxt and sodiumxt and no
    transitive walk over this table would get that right. A member is never
    its own sibling: coinxt -> riptide -> coinxt is a real edge (riptide's
    gate loads the committed coinxt binary), and what it means for a
    standalone coinxt is that the checkout must be named `coinxt` so
    ../coinxt resolves to itself - the sibling helpers in the tools resolve
    a member's own name to its own tree for exactly this."""
    return [s for s in BY_NAME[name].siblings if s != name]


# What a change can reach, for suite-gates.yml's pull-request runs
# (2026-10-20). A member's gates read its own tree and the siblings listed
# above, and nothing else: tools/check-member-standalone.py refuses a member
# tool that climbs out of the member except through sibling(), and its
# published repository runs the same tools/run-gates.sh with only those
# siblings beside it. So a change to member X can fail the gates of X and of
# every member that lists X as a sibling, and a change outside every member
# (the suite's docs/, tests/, tools/, root files) can fail only the suite's
# own gates, which run on every event. Before this, every pull request ran
# every member's gates, coinxt's wallet gates included (two and a half hours
# of the job), whatever it touched.
#
# Two kinds of path run every member: the walker and the job that runs it
# (WHOLE_WALK - a change there changes how every gate runs), and this table
# itself, whose sibling lists are the rule. An unknown top-level directory
# runs every member too: it is a member being added, or something this rule
# has never seen, and the two mistakes are not symmetric - a redundant run
# costs runner minutes, a missed one lets a red gate merge. main, a manual
# dispatch and a pull request whose base cannot be read run everything
# regardless (suite-gates.yml), so this rule decides only what a pull
# request is told before it merges, never what main publishes.
ROOT_DIRS = (".github", "docs", "tests", "tools")
WHOLE_WALK = ("tools/build-all.sh", ".github/workflows/suite-gates.yml",
              "tools/member-registry.py")


def affected(paths):
    """The members whose gates a change to `paths` can fail, in table order,
    or None for every member."""
    touched = set()
    for p in paths:
        p = p.strip().replace("\\", "/")
        if not p:
            continue
        if p in WHOLE_WALK:
            return None
        if "/" not in p:
            continue                      # a root file: README.md, LICENSE, ...
        top = p.split("/", 1)[0]
        if top in BY_NAME:
            touched.add(top)
        elif top not in ROOT_DIRS:
            return None
    return [m.name for m in MEMBERS
            if m.name in touched or touched.intersection(siblings_of(m.name))]


def selftest():
    """The rule on made-up changes. Exits non-zero on the first wrong answer."""
    cases = [
        (["holde-em/src/x.livecodescript"], ["holde-em"]),
        # coinxt's gates load riptide's runner: a riptide change reaches them
        (["riptide/tools/check-demo-boot.py"],
         [m.name for m in MEMBERS
          if m.name == "riptide" or "riptide" in siblings_of(m.name)]),
        (["sodiumxt/README.md"],
         [m.name for m in MEMBERS
          if m.name == "sodiumxt" or "sodiumxt" in siblings_of(m.name)]),
        (["docs/WORK-PLAN.md", "tools/check-doc-anchors.py", "README.md",
          "tests/cross-member-test.py", ".github/workflows/native-coinxt.yml"], []),
        ([], []),
        (["tools/build-all.sh"], None),
        ([".github/workflows/suite-gates.yml", "docs/x.md"], None),
        (["tools/member-registry.py"], None),
        (["newmember/tools/run-gates.sh"], None),
    ]
    bad = 0
    for paths, want in cases:
        got = affected(paths)
        if got != want:
            print("member-registry --selftest: %r gave %r, wanted %r"
                  % (paths, got, want))
            bad += 1
    # and by name, the one edge the split exists for
    if "coinxt" not in (affected(["nostrxt/tools/lcs-interp.py"]) or []):
        print("member-registry --selftest: a nostrxt change must reach "
              "coinxt's wallet gates (riptide's runner loads its interpreter)")
        bad += 1
    # the rule's premise: nothing in the table names a member that is not one
    for m in MEMBERS:
        for s in m.siblings:
            if s not in BY_NAME:
                print("member-registry --selftest: %s lists sibling %r, which "
                      "is not a member" % (m.name, s))
                bad += 1
    if bad:
        return 1
    print("member-registry --selftest: OK (%d cases)" % len(cases))
    return 0


def main(argv=()):
    # `--names`: the member names alone, space-separated, for a shell that
    # needs the list (.github/workflows/publish-members.yml) without parsing
    # the table below.
    if "--names" in argv:
        print(" ".join(m.name for m in MEMBERS))
        return 0
    # `--affected`: changed paths on stdin, one per line; prints the members
    # whose gates they can reach, space-separated, `all`, or `none`.
    if "--affected" in argv:
        got = affected(sys.stdin.read().splitlines())
        print("all" if got is None else (" ".join(got) or "none"))
        return 0
    if "--selftest" in argv:
        return selftest()
    print("%-14s %-10s %-32s %-6s %s" % ("member", "kind", "repository",
                                          "native", "gate siblings"))
    for m in MEMBERS:
        sib = ", ".join(siblings_of(m.name)) or "-"
        print("%-14s %-10s %-32s %-6s %s" % (
            m.name, m.kind, m.repo, "yes" if m.native else "no", sib))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
