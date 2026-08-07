# MIGRATION.md - splitting CoinXT into its own repository

CoinXT is staged inside the OnionXT repository but is fully self-contained under `CoinXT/`: the static
gates, the CI workflow, the portable xTalk/LCB lesson book, the vendored sources and their integrity
manifest all live inside this directory, and no doc or tool reaches outside it. This file is the
procedure for the split and the checklist for afterwards. **Delete this file (and the staging paragraph
in README.md) once the move is complete.**

## Before you split

Run the gates from `CoinXT/` and confirm all five are green (they are the same five CI runs):

```sh
python3 tools/check-livecodescript.py
python3 tools/check-docs-style.py
python3 tools/coin-kat.py --check
sh native/build.sh asan
( cd native && sha256sum -c MANIFEST.sha256 )
```

## The split (pick ONE)

Create the new, EMPTY GitHub repository first (no auto-generated README / license / gitignore), for
example `SethMorrowSoftware/CoinXT`.

### Option A: `git subtree split` (no extra tooling; preserves the directory's history)

```sh
git clone https://github.com/SethMorrowSoftware/OnionXT.git
cd OnionXT
git subtree split --prefix=CoinXT -b coinxt-split

cd ..
mkdir CoinXT && cd CoinXT
git init -b main
git pull ../OnionXT coinxt-split
git remote add origin git@github.com:SethMorrowSoftware/CoinXT.git
git push -u origin main
```

### Option B: `git filter-repo` (cleaner rewrite; follows renames; needs `pip install git-filter-repo`)

```sh
git clone https://github.com/SethMorrowSoftware/OnionXT.git CoinXT
cd CoinXT
git filter-repo --subdirectory-filter CoinXT
git remote add origin git@github.com:SethMorrowSoftware/CoinXT.git
git push -u origin main
```

Either way the former `CoinXT/` contents become the repository ROOT, which is exactly what the layout
expects: `.github/workflows/ci.yml` (dormant while nested, because GitHub only reads the root
`.github/`) goes live on the first push, and every path in the docs already resolves.

## After the split: the new CoinXT repository

1. Confirm CI ran and all five gate steps passed on the first push.
2. Remove this `MIGRATION.md` and the clearly-marked staging paragraph in `README.md`.
3. **Decide the project license.** The MIT `LICENSE` in `native/vendor/` covers only the vendored
   trezor-crypto files (a redistribution requirement); the repository itself ships no top-level license
   yet. That choice is the owner's; MIT would match the vendored code and the family's habits.
4. Protect `main` (PRs only) if that matches the family workflow; development stays on per-task
   branches with draft PRs, exactly as [CLAUDE.md](CLAUDE.md) prescribes.

## After the split: the OnionXT repository

1. `git rm -r CoinXT` on a branch, with a commit message pointing at the new repository, and PR it.
2. Nothing else in OnionXT references `CoinXT/` (verified at prep time with a repo-wide search), so no
   doc or CI edits are needed there.

## The lesson book after the split

`templates/CLAUDE.md` (the portable xTalk/LiveCode/LCB engineering guide) was synced byte-identical
with OnionXT's copy when this split was prepared, including the newest on-engine lessons. From the
split onward each repository maintains its OWN copy, the family pattern: keep appending confirmed
engine gotchas to the living log, and carry notable ones across the family deliberately (a small PR to
the sibling), not by assuming the copies stay in sync on their own.
