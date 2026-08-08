# MIGRATION.md - splitting CoinXT into its own repository

CoinXT is staged inside the xtalk-suite monorepo (the source of truth; the former standalone
repositories, including the OnionXT repo where CoinXT was first staged, are mirrors now) but is fully
self-contained under `coinxt/`: the static gates, the CI workflow, the portable xTalk/LCB lesson book,
the vendored sources and their integrity manifest all live inside this directory, and no doc or tool
reaches outside it. This file is the procedure for the split and the checklist for afterwards.
**Delete this file (and the staging paragraph in README.md) once the move is complete.**

## Before you split

Run the gates from `coinxt/` (the directory is lowercase; only the eventual repository name is
capitalised) and confirm all eight are green. They are the same steps `.github/workflows/ci.yml`
runs, and the same ones the suite's `tools/build-all.sh --gates` runs today:

```sh
python3 tools/check-livecodescript.py         # static gate for .lcb / .livecodescript
python3 tools/check-docs-style.py             # house-style gate for .md
python3 tools/coin-kat.py --check             # builds the shim, runs the known-answer vectors
python3 tools/check-selftest-vectors.py       # the OXT self-test's vectors have not drifted
python3 tools/check-binary-freshness.py       # the committed library still matches the shim
sh native/build.sh asan                       # ASan + UBSan native self-test
( cd native && sha256sum -c MANIFEST.sha256 )   # vendored-source integrity
( cd src/code && sha256sum -c MANIFEST.sha256 ) # committed-binary integrity
```

## The split (pick ONE)

Create the new, EMPTY GitHub repository first (no auto-generated README / license / gitignore), for
example `SethMorrowSoftware/CoinXT`.

### Option A: `git subtree split` (no extra tooling; preserves the directory's history)

```sh
git clone https://github.com/SethMorrowSoftware/xtalk-suite.git
cd xtalk-suite
git subtree split --prefix=coinxt -b coinxt-split

cd ..
mkdir CoinXT && cd CoinXT
git init -b main
git pull ../xtalk-suite coinxt-split
git remote add origin git@github.com:SethMorrowSoftware/CoinXT.git
git push -u origin main
```

### Option B: `git filter-repo` (cleaner rewrite; follows renames; needs `pip install git-filter-repo`)

```sh
git clone https://github.com/SethMorrowSoftware/xtalk-suite.git CoinXT
cd CoinXT
git filter-repo --subdirectory-filter coinxt
git remote add origin git@github.com:SethMorrowSoftware/CoinXT.git
git push -u origin main
```

Either way the former `coinxt/` contents become the repository ROOT, which is exactly what the layout
expects: `.github/workflows/ci.yml` (dormant while nested, because GitHub only reads the root
`.github/`) goes live on the first push, and every path in the docs already resolves.

## After the split: the new CoinXT repository

1. Confirm CI ran and all eight gate steps passed on the first push.
2. Remove this `MIGRATION.md` and the clearly-marked staging paragraph in `README.md`.
3. **Check the license files came across, all three of them.** `LICENSE` is CoinXT's own MIT.
   `native/vendor/LICENSE` is trezor-crypto's MIT, which covers only the vendored files that are
   actually trezor's. `THIRD-PARTY-LICENSES.md` covers the ones that are not: the vendored subset
   also contains BSD-3-Clause (SHA-2), public-domain (RIPEMD-160), CC0 (BLAKE-256, BLAKE2b) and a
   separately-held MIT (Groestl). That third file is a **redistribution requirement, not a
   courtesy** - the BSD-3-Clause clause 2 binds binary distribution and this repository commits
   built libraries - so a split that leaves it behind ships those binaries out of compliance.
4. Protect `main` (PRs only) if that matches the family workflow; development stays on per-task
   branches with draft PRs, exactly as [CLAUDE.md](CLAUDE.md) prescribes.

## After the split: the xtalk-suite monorepo

> **Historical note.** This section used to describe removing CoinXT from the *OnionXT* repository,
> where CoinXT was first staged. That is obsolete: CoinXT now lives in the xtalk-suite monorepo, so
> the monorepo is what a split would remove it from.

1. `git rm -r coinxt` on a branch, with a commit message pointing at the new repository, and PR it.
2. Unlike the OnionXT staging, the monorepo DOES reference `coinxt/` from shared infrastructure, and
   each of these needs an edit in the same PR. Re-run a repo-wide search rather than trusting this
   list, which is accurate as of 2026-08-08:
   - `tools/build-all.sh` walks coinxt for its gates and runs `native/build.sh asan`;
   - `.github/workflows/suite-gates.yml` runs that walker, and `native-coinxt.yml` is coinxt's own
     matrix at the root;
   - `.github/workflows/release-binaries.yml` builds coinxt as one of its five members, and
     `tools/install-release-binaries.py` knows coinxt's export surface;
   - the root `README.md` release matrix, `CLAUDE.md`, `docs/README.md`, and
     `docs/OXT-PASS-RUNBOOK.md` all describe coinxt as a member;
   - the root `LICENSE` carries CoinXT's third-party attribution block (trezor-crypto's MIT plus the
     six other licenses in the vendored subset), which must move WITH the code rather than simply be
     deleted: it is a redistribution requirement, not a courtesy, and `coinxt/THIRD-PARTY-LICENSES.md`
     is the per-file detail behind it;
   - `tests/suite-selftest.livecodescript` probes for CoinXT and runs its vectors.
3. **Reconsider whether to split at all.** The suite `CLAUDE.md` states the monorepo is now the
   source of truth and the former standalone repositories are mirrors, so splitting CoinXT out runs
   against the direction the rest of the family moved in. This file predates that consolidation. Keep
   it as a procedure if the owner still wants a separate CoinXT repository; delete it if not.

## The lesson book after the split

`templates/CLAUDE.md` (the portable xTalk/LiveCode/LCB engineering guide) was synced byte-identical
with OnionXT's copy when this split was prepared, including the newest on-engine lessons. From the
split onward each repository maintains its OWN copy, the family pattern: keep appending confirmed
engine gotchas to the living log, and carry notable ones across the family deliberately (a small PR to
the sibling), not by assuming the copies stay in sync on their own.
