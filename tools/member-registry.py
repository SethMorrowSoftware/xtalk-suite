#!/usr/bin/env python3
"""member-registry.py - the ONE table of what a suite member is.

WHY THIS FILE EXISTS. Every member directory is on its way to being its own
repository (docs/MEMBER-REPO-SPLIT.md), and three tools need the same facts
about each one to prepare it: which repository it moves to, which siblings
its gates reach into, whether it has a native build lane, and what kind of
thing it is. Until 2026-09-21 those facts lived in prose (the root README's
member table, each member's CLAUDE.md, the runbook) and in the heads of the
people who wrote them - which is the hand-copied-constant failure this
tree's root CLAUDE.md records for ABI numbers and for coverage ratios. A
generator that reads a table cannot disagree with another generator that
reads the same table, so the table is here and the generators import it:

    tools/sync-member-workflows.py   each member's own .github/workflows/
    tools/sync-member-readmes.py     each README's "Relationship to the
                                     xTalk suite" section
    tools/check-member-standalone.py the readiness gate

The registry is DATA, not a scanner: a member not listed here is a member
the split tooling does not see, exactly as tools/sync-demo-embeds.py's
REGISTRY works. check-member-standalone.py refuses a member directory that
is absent from this table and a table row whose directory is gone, so the
two cannot drift apart silently - the archivext lesson, one level up.

    python3 tools/member-registry.py      # prints the table

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
                 repo_exists=True, mirror_note=""):
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
        # Whether the target repository already exists (the pre-suite mirror
        # it was folded in from, or a new one). False means the name is the
        # one the split will create; the generated workflows use it either
        # way, and the split checklist says to create it first.
        self.repo_exists = repo_exists
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
           native=True, siblings=[],
           mirror_note="the pre-suite home (it once vendored enetxt/ and "
                       "datachannelxt/ as subfolders)"),
    Member("enetxt", "enetxt", "extension", OWNER + "/enetxt",
           native=True, siblings=[], repo_exists=False,
           mirror_note="never had a repository of its own - it grew inside "
                       "TorrentXT's tree - so the split CREATES this one"),
    Member("datachannelxt", "DataChannelXT", "extension",
           OWNER + "/dataChannelXT", native=True, siblings=[],
           mirror_note="the pre-suite home"),
    Member("box2dxt", "Box2Dxt", "extension", OWNER + "/Box2Dxt",
           native=True, siblings=[],
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
           siblings=["coinxt", "sodiumxt"], repo_exists=False,
           mirror_note="born in the suite (2026-08-23), so the split "
                       "CREATES this one"),
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


def main():
    print("%-14s %-10s %-32s %-6s %s" % ("member", "kind", "repository",
                                          "native", "gate siblings"))
    for m in MEMBERS:
        sib = ", ".join(siblings_of(m.name)) or "-"
        print("%-14s %-10s %-32s %-6s %s%s" % (
            m.name, m.kind, m.repo, "yes" if m.native else "no", sib,
            "" if m.repo_exists else "   (repository to be created)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
