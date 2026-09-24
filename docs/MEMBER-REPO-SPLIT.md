# Publishing members into their own repositories

**Scope:** suite-wide. **Status:** LIVE. Decided 2026-09-22
(docs/OPEN-DECISIONS.md D-22): this monorepo stays the **development**
repository, and every member is **published** from it into a repository of its
own, automatically, after each change the suite's gates pass. Publishing went
live on 2026-09-23, when `publish-members.yml` run 3 (attempt 2) adopted and
published all eleven member repositories at 16:11 UTC (section 2).

The tools are the authority: `tools/member-registry.py` prints the member
table, `tools/publish-members.py status` shows what a publish would do now, and
`tools/publish-members.py`'s docstring is the full contract.

## 1. The model

- **Development happens here.** Every change is made, reviewed, gated and merged
  in the suite; the cross-member gates (section 7) can only run where every
  member is present, which is why the decision went this way.
- **Publishing is one-way and automatic.** `.github/workflows/publish-members.yml`
  runs when a `suite gates` run on `main` finishes green and hands
  `tools/publish-members.py` the verified commit. For each member, the commits on
  `main`'s FIRST-PARENT line (the states the gates ran on) that changed
  `<member>/` are replayed, oldest first, onto the member repository's default
  branch: the member tree byte for byte, the suite author and committer, the
  suite message (a merge becomes its pull request's title, linked, with that
  pull request's member commits listed) and a `Suite-Commit: <sha>` trailer.
- **The trailer is the publisher's entire state.** The newest `Suite-Commit:` on
  a member repository's first-parent line says what it holds; nothing is stored
  elsewhere, and a re-run produces byte-identical commits (the fixture proves it
  into two empty repositories).

**What it never does**, each held by a case in `tools/test-publish-members.py`
(in the gate set):

- **Force-push.** Fast-forward only; a repository that moved mid-run is refused
  (the fixture injects that race with a `git` shim on PATH).
- **Write a repository the suite has never written** without the explicit
  `adopt` dispatch input.
- **Overwrite commits it did not write.** The member is REFUSED with the commits
  named: port them (section 3), or pass `accept_divergence`, which lands the
  suite tree as ONE commit on top and keeps theirs in history. Other members
  are not held up.
- **Publish what the suite did not verify:** only first-parent `main` with a
  green `suite gates` run and, for a native member, a green `native-<member>.yml`
  on its last change. A red lane holds the member back and fails the run; a
  cancelled one holds it back quietly.

**Why not `git subtree split`:** it shares no history with the pre-suite
repositories, so every push is a refused non-fast-forward and GitHub cannot
open a pull request ("entirely different commit histories"). The replay lands
ON TOP of the existing history and needs no rewriting.

## 2. Setup (done 2026-09-23) and renewal

**The adoption record.** `publish-members.yml` run 3, attempt 2, adopted and
published all eleven repositories at 16:11 UTC on 2026-09-23 (the commits each
received are in section 6). The first attempt that morning met eleven refusals:
the token could read everything and push nowhere, and the plan run had looked
healthy because reading a PUBLIC repository needs no token. Since then
`--check-push` asks each repository, with a dry-run push that sends nothing,
whether the credentials may push; the workflow passes it whenever the secret
exists, dry runs included, and a refused push names its cause (section 3).

**What adoption did.** Each repository's history is KEPT (the first published
commit sits on its old head and says so); its tree became the suite's
`<member>/`, so old workflows became the generated `gates.yml`/`native.yml` and
READMEs gained the generated "Relationship to the xTalk suite" section.
TorrentXT's adoption removed the `enetxt/` and `datachannelxt/` subfolders it
once vendored. The suite's first commit replays as nothing for SodiumXT (its
tree was identical), which confirms the verbatim copy-in.

**For a re-setup or a token rotation:**

1. **Repositories** are created EMPTY (no README, license or `.gitignore`) and
   kept **public**: a private one bills Actions minutes (coinxt's gate job runs
   for hours) and its forks cannot run its gates.
2. **The token** is a fine-grained personal access token: resource owner
   `SethMorrowSoftware`; repository access "Only select repositories" = the
   eleven ("Public repositories" is read-only, so every push is refused);
   **Contents** and **Workflows** both **Read and write** (a permission is added
   at Read-only, so set both; without Workflows every push touching
   `.github/workflows/` is refused). Give it an expiry and calendar the date.
3. **The secret** is `XTALK_PUBLISH_TOKEN` in `xtalk-suite` (Settings > Secrets
   and variables > Actions). Without it every run is a dry run. Rotating means
   editing or replacing the token and updating this secret.
4. **Look first:** Actions > `publish members` > Run workflow on `main` with the
   defaults (`members: all`, `dry_run: true`). One row per member (`not adopted`
   with the commits adoption would replay, `unreachable`, `would publish`,
   `up to date`); with the secret present it also tests the token everywhere.
5. **Adopt** with a NEW run: `adopt` naming SUITE DIRECTORY names,
   space-separated (`holde-em`, `datachannelxt`, not `hold-em`/`dataChannelXT`),
   and `dry_run` unticked. **Re-run** replays the old run's inputs, and automatic
   runs have none, so it never adopts. An unknown name is refused up front.

**Two repository settings stop publishing:** a branch protection rule or
ruleset requiring pull requests (let the token's owner bypass it), and "Require
signed commits" (published commits are unsigned by design: a signature would
make one publish differ per machine). A refused push overwrites nothing.

## 3. Everyday: what to do when

**A change merges to `main`:** nothing. When `suite gates` goes green the
publish summary says, per member, `published N commit(s)`, `up to date`, or why
not. **A publish run is red:** the summary names the member and the reason; the
others were published anyway.

- *"has N commit(s) since its last publish ... that the suite never wrote and
  never ported"*: someone pushed or merged in the member repository. Port it
  (below), or dispatch with `accept_divergence` naming the member.
- *"native-<member> ... concluded 'failure'"*: fix the lane in the suite; the
  next green publish carries it.
- *"push refused: ..."* names its cause, and nothing was overwritten:
  *"the credentials in use may not push to ..."* (or *"may not read"*, or *"a
  dry-run push ... was refused"*): give the token that repository with Contents
  and Workflows Read and write (the secret does not change);
  *"... changes .github/workflows/ files"*: Workflows is missing;
  *"... branch protection or ruleset ..."*: see the end of section 2;
  *"... moved while this ran"*: the next run recomputes.
- *"its last publish came from X, which main at Y does not contain"*: `main` was
  rewritten under a published commit. Stop and decide by hand.

**A contribution arrives at a member repository:** bring it home.

```sh
# in a suite checkout, on a new branch
python3 tools/publish-members.py port sodiumxt --ref pull/7/head
```

Each commit in `main..pull/7/head` (merges carry nothing; publisher-written
commits are never ported) is applied under `sodiumxt/` with `git am -3`, author
kept, and stamped `Mirror-Commit: SethMorrowSoftware/SodiumXT@<sha>` INSIDE the
patch, so `git am --continue` keeps it after a conflict and re-running `port`
applies only what is left. Open the suite pull request and close the member one
with a link; the change reaches the member repository as a published commit.
Without `--ref`, `port` takes what was already merged there, and its trailers
let the next publish accept that history. A ported edit to a generated file is
refused by the suite's gates: change the root workflow, generator or registry.

## 4. What "ready" means, and the gate that holds it

A member is ready when it works as a repository from its first commit: its
links resolve, its CI runs the gates the suite ran for it, and its tools do not
crash looking for the suite. All of it is generated or gated, in
`tools/build-all.sh --gates`:

| What | Where | Held by |
|---|---|---|
| The member table (name, title, kind, repository, native lane, gate siblings) | `tools/member-registry.py` | `check-member-standalone.py` refuses an unlisted member-shaped directory and a row whose directory is gone |
| The gate list | `<member>/tools/run-gates.sh` | `build-all.sh` delegates to it; `check-member-standalone.py` refuses a gate file under `tools/` or `tests/` the script's CODE never names (a comment does not count) |
| The member's CI | `<member>/.github/workflows/gates.yml` (+ `native.yml`) | GENERATED by `tools/sync-member-workflows.py` from the root lanes; `--check` refuses drift and extra files |
| The README "Relationship to the xTalk suite" section | HTML-comment sentinels at the end of `<member>/README.md` | GENERATED by `tools/sync-member-readmes.py`, never hand-edited; `--check` refuses drift |
| The kit: `README.md`, `LICENSE`, `CLAUDE.md`, `.gitignore`, `.gitattributes` where binaries are committed; no markdown link climbing out of the member; no tool climbing to the suite root except via `sibling()` | the member directory | `tools/check-member-standalone.py`, proven by `tools/test-member-standalone.py` |
| The publisher's promises (section 1) | `tools/publish-members.py` | `tools/test-publish-members.py` |

## 5. The sibling layout

- A sibling is found at `../<member-name>` (`coinxt`, not `CoinXT`);
  `XTALK_SIBLINGS=<dir>` or `XTALK_SIBLING_<NAME>=<path>` (`XTALK_SIBLING_COINXT`,
  `XTALK_SIBLING_HOLDE_EM`) override. A member's own name resolves to its own
  tree first, by the checkout DIRECTORY name, so clone as
  `git clone .../CoinXT coinxt`.
- An absent sibling is reported with its path, repository and variables, never a
  traceback; `XTALK_REQUIRE_SIBLINGS=1` turns a sibling-absent skip into a
  failure (in CI a skip and a pass both exit 0).
- **In member CI the siblings come from the suite:** `gates.yml` reads the newest
  `Suite-Commit:` trailer, sparse-checks-out the public suite at that commit and
  moves each sibling beside the member, so they are exactly what the suite's
  gates ran with.

**Gate dependency is not runtime dependency:** shipped stacks carry their
libraries (`tools/sync-demo-embeds.py`). This list is what a member's GATES load,
written closed by hand rather than walked transitively (the registry says why):

| Member | Gate siblings | Why |
|---|---|---|
| nostrxt | coinxt, sodiumxt | tier 2 of `check-script-vectors.py` runs against the committed x86_64-linux binaries |
| riptide | nostrxt, coinxt | `lcs-interp.py`, the nostrxt library and oracle are loaded; the committed coinxt binary signs |
| coinxt | riptide, nostrxt | `check-wallet-boot.py` reuses riptide's boot runner, which loads nostrxt's interpreter and oracle |
| nocloud | riptide, nostrxt, coinxt | `check-script-vectors.py` boots the helpers through riptide's runner |
| holde-em | riptide, nostrxt, coinxt | the same runner plus riptide's oracle |
| every other member | none | `bash tools/run-gates.sh` needs only the checkout and Python 3 |

## 6. The member repositories

| Member | Repository | Before the suite | Commits at adoption (2026-09-23) |
|---|---|---|---|
| sodiumxt | `SethMorrowSoftware/SodiumXT` | the pre-suite home | 43 |
| torrentxt | `SethMorrowSoftware/TorrentXT` | the pre-suite home (once vendored enetxt/, datachannelxt/) | 54 |
| enetxt | `SethMorrowSoftware/enetxt` | none: grew inside TorrentXT; created 2026-09-22 | 50 |
| datachannelxt | `SethMorrowSoftware/dataChannelXT` | the pre-suite home | 48 |
| box2dxt | `SethMorrowSoftware/Box2Dxt` | the family ancestor's repository | 31 |
| coinxt | `SethMorrowSoftware/CoinXT` | the pre-suite home | 81 |
| onionxt | `SethMorrowSoftware/OnionXT` | the pre-suite home | 43 |
| nostrxt | `SethMorrowSoftware/NostrXT` | none: born in the suite; created 2026-09-22 | 19 |
| riptide | `SethMorrowSoftware/RipTide` | the capstone's pre-suite home | 47 |
| nocloud | `SethMorrowSoftware/nocloud` | the pre-suite home | 29 |
| holde-em | `SethMorrowSoftware/hold-em` | the pre-suite `hold-em` repository | 29 |

The names live ONLY in `tools/member-registry.py`; to rename a repository,
change the registry and re-run `sync-member-workflows.py` and
`sync-member-readmes.py`, and the publisher follows. `publish-members.py status`
observes each repository's live state; this table does not try to.

## 7. What a member repository cannot check

These run only in the suite, because their question spans members:
carried-copy drift (the demo UI kit, the boot self-check block, the harness
scaffold); embed freshness (`tools/sync-demo-embeds.py --check`); one name, one
library (`tools/check-cross-library-names.py`); the cross-member handler-call
and typed-boundary gates (`check-handler-calls.py`, `check-lcb-call-types.py`);
the timer-pin closure; the shim scaffold drift; the binary-freshness walk; the
suite paste and its coverage ratchet; and `tests/cross-member-test.py`. That is
why development stays here (D-22): a member repository receives only trees that
passed them.

## 8. When a member leaves: the registries that name it

Publishing is not leaving; this is for a member that stops being developed here.
archivext left on 2026-09-21 with its rows intact and thirteen gates went red.
Remove the member, in the same change as its directory, from:

- `tools/member-registry.py` (a row whose directory is gone is refused);
- `tools/check-checker-drift.py` `COPY_SETS`/`TEMPLATE_SETS`; `tools/test-checker.py` `MEMBERS`;
- `ADOPTERS` in `tools/check-ui-kit-drift.py` (and `EXEMPT`),
  `tools/check-demo-selfcheck-drift.py` (read by `check-demo-control-lists.py`)
  and `tools/check-harness-scaffold-drift.py`;
- `tools/test-stack-size.py`'s expected dimension count; the
  `tools/check-cross-library-names.py` corpus;
- `start-here.livecodescript`'s launcher rows (`check-launcher-registry.py`);
- `tools/check-suite-coverage.py`'s row and `REQUIRED_EMBEDS`;
  `tools/check-suite-selftest.py` `PREFIXES` and `ENTRY_POINTS`;
- `tools/build-suite-selftest.py` `Member(...)`/`Layer(...)` rows (regenerate,
  and edit the core's probe and deep-self-test sections);
  `tools/build-preflight.py`'s probe (regenerate);
- `tools/sync-demo-embeds.py` `REGISTRY` rows (a copy carried elsewhere stays as
  a snapshot, noted in the carrier's README); `tools/build-all.sh`'s member loop;
- the root `README.md` tables, the `CLAUDE.md` layout, and the suite docs that
  name it (`docs/OXT-PASS-RUNBOOK.md`, `docs/WORK-PLAN.md`), which keep its dated
  records under a MOVED OUT note.

Then `bash tools/build-all.sh --gates` (glob-driven gates need no edit).
**Publish it one last time before deleting the directory**, so its repository
holds the last state the suite verified.

## 9. Per-member notes

Every member passes `check-member-standalone.py`. Beyond that:

| Member | Notes |
|---|---|
| sodiumxt | `native.yml` builds all five platforms; the committed binaries and MANIFEST travel with it. |
| torrentxt | `examples/torrent-quickshare.livecodescript` deliberately embeds nothing (it defines the engine socket handlers) and still needs `start using stack "onionxt"` for Tor. |
| enetxt | `enet-internet-chat` carries torrentxt's helpers as an embedded copy. |
| box2dxt | The README badge points at the suite's lane until its own `native.yml` has run. Its Kit is carried into its examples by its own `sync-embedded-kit.py`. |
| coinxt | The full gate list takes hours (three wallet gates, run at once by `run-gates.sh`); `gates.yml` states a six-hour ceiling, paid on every publish. |
| onionxt | Its library is carried into six other stacks (nocloud, coin-wallet, torrent-dht-channels, riptide-social, holde-em, the suite's closing pass); the suite's embed gate keeps every copy current before anything is published. |
| nostrxt | Its `lcs-interp.py` is the copy riptide, nocloud and holde-em load, and must stay byte-identical to coinxt's (only the suite's `check-checker-drift.py` enforces it). `tools/test-script-vectors.py` mutates the SHIPPED `src/nostrxt.livecodescript` in place and restores it, so never run two of its gates at once in one checkout (the publisher is immune: it publishes git trees). |
| riptide | `LICENSE` added 2026-09-21. The capstone specs (`docs/RIPTIDE-SOCIAL-SPEC.md`, `docs/RIPTIDE-PROTOCOL.md`) stay suite-level and are cited by URL. |
| holde-em | Its README's extension table links the sibling repositories rather than `../<member>/`. |
