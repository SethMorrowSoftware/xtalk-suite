# MIGRATION.md - superseded: CoinXT is published from the suite, not moved out of it

This file used to be the procedure for splitting CoinXT out of the xtalk-suite monorepo into a
repository of its own - a `git subtree split` or `git filter-repo` export, then `git rm -r coinxt`
in the suite - and its last step said to reconsider whether to split at all, and to delete this file
if not. That was decided on 2026-09-22 (the suite's `docs/OPEN-DECISIONS.md`, D-22): CoinXT is
developed in the suite, as its `coinxt/` member, and PUBLISHED from there into
https://github.com/SethMorrowSoftware/CoinXT after every change the suite's gates pass. Nothing is
moved, so there is no split to perform. The file keeps its name because this member's README,
`CLAUDE.md` and `docs/README.md` cite it.

- **The whole workflow** - the one-time setup, the everyday publishing, and porting a pull request
  made in CoinXT's own repository back into the suite - is the suite's
  [docs/MEMBER-REPO-SPLIT.md](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/MEMBER-REPO-SPLIT.md).
  The tool is the suite's `tools/publish-members.py`, run by its
  `.github/workflows/publish-members.yml`.
- **The gates** the old "Before you split" list named by hand are this member's own
  `tools/run-gates.sh` now, which both the suite's `tools/build-all.sh` and CoinXT's generated
  `.github/workflows/gates.yml` run. The `.github/workflows/ci.yml` it cited is gone (replaced
  2026-09-21 by `gates.yml` and `native.yml`, generated from the suite's root lanes).
- **The lesson book** (`templates/CLAUDE.md`) is not maintained per repository, as the old "after the
  split" section planned: its copies are held byte-identical by the suite's
  `tools/check-checker-drift.py` (`TEMPLATE_SETS`), and CoinXT's repository receives the suite's copy
  with every publish.
- **If CoinXT should ever leave the suite for good**, the suite's split document has a section listing
  every registry a departing member must be removed from. The export procedure that stood here is in
  this file's history (`git show cf0484d:coinxt/MIGRATION.md` in the suite) if it is ever wanted
  again; it would need the pre-suite repository's history reconciled first, since a subtree split
  shares none of it.
