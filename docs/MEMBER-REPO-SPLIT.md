# Publishing members into their own repositories

**Scope:** suite-wide. **Status:** DECIDED 2026-09-22 (docs/OPEN-DECISIONS.md
D-22): this monorepo stays the **development** repository, and every member
is **published** from it into a repository of its own, automatically, after
each change the suite's gates pass. The readiness machinery (sections 3 and
4) landed 2026-09-21; the publisher, its workflow and its fixture test landed
2026-09-22. **Section 2 is the one-time setup, and it is all the owner has to
do by hand.** The file keeps its 2026-09-21 name because thirty places cite
it; "split" now means the publishing, not a move.

The tools are the authority and this page describes them:
`python3 tools/member-registry.py` prints the member table,
`python3 tools/publish-members.py status` prints what a publish would do to
every member repository right now, and `tools/publish-members.py`'s own
docstring is the full contract.

## 1. The model

**Development happens here.** Every change is made, reviewed, gated and
merged in the suite, as it always has been; nothing about the daily work
changes. The cross-member gates - one name per library, the carried-copy
drift gates, embed freshness, the suite paste and its coverage ratchet
(section 7) - can only run where every member is present, which is the
reason the decision went this way rather than the other.

**Publishing is a one-way street, and it is automatic.**
`.github/workflows/publish-members.yml` runs when a `suite gates` run on
`main` finishes green and hands `tools/publish-members.py` the commit it
verified. For each member, the commits on `main`'s FIRST-PARENT line that
changed `<member>/` are replayed, oldest first, onto the member repository's
default branch: the member directory's own tree byte for byte, the suite
commit's author and committer, the suite's message (a merge becomes its pull
request's title, linked into the suite, with that pull request's commits to
the member listed and linked), and a `Suite-Commit: <sha>` trailer naming the
suite commit it came from. First-parent because those are the states `main`
actually held and the gates actually ran on.

**The trailer is the whole of the publisher's state.** The newest
`Suite-Commit:` on a member repository's first-parent line says which suite
commit it already holds, so a run publishes exactly what landed after that.
Nothing is recorded anywhere else, so there is nothing to drift, and a
re-run of the same publish produces the same commits byte for byte (the
fixture test proves it into two empty repositories).

**What it never does**, each one held by a case in
`tools/test-publish-members.py`, which runs in the gate set:

- **Force-push.** Every push is a fast-forward of the branch the member
  repository already has; one that moved while the publisher ran is refused,
  not overwritten (the fixture injects exactly that race with a `git` shim).
- **Write a repository the suite has never written.** The first publish into
  a repository - ADOPTION - is a `workflow_dispatch` input naming the member,
  never automatic. It keeps that repository's own history and replays the
  suite's on top of it (section 2).
- **Overwrite a commit it did not write.** A member repository whose tree is
  not the tree of its last published commit has had something pushed to it
  directly; the member is REFUSED, the commits are named in the run, and the
  owner either PORTS them into the suite (section 6) or accepts replacing
  them. Nothing else in the run is held up.
- **Publish what the suite did not verify.** Only a commit on `main`'s
  first-parent line, with a green `suite gates` run, and - for a member with
  a native lane - a green `native-<member>.yml` run on that member's last
  change. A red lane holds that member back and fails the run; a cancelled
  one (the lanes cancel superseded runs on `main`) holds it back quietly for
  the next publish.

**Why not `git subtree split`,** which the 2026-09-21 version of this page
prescribed: its history shares no commit with a pre-suite repository's, so
pushing it to SodiumXT, TorrentXT or any of the other seven is refused as a
non-fast-forward, and GitHub cannot open it as a pull request either
("entirely different commit histories"). The only way through is a
force-push that throws the pre-suite history away. The publisher's replay
lands ON TOP of that history instead, and it needs no history rewriting, so
its output does not depend on which git version ran it.

## 2. Setting it up (once)

1. **Create the repositories that do not exist yet** - `enetxt` and
   `NostrXT` on 2026-09-22 - EMPTY: no README, no license, no `.gitignore`.
   The first publish brings everything.
2. **Make every member repository public.** The suite is public, so every
   member's code already is; a private member repository only costs: its own
   CI bills private-repository Actions minutes (coinxt's gate job runs for
   hours, and the macOS lanes bill at a multiple), and a fork of it cannot
   run its gates. On 2026-09-22 `CoinXT`, `nocloud` and `hold-em` were
   private.
3. **Create the token.** A fine-grained personal access token (GitHub >
   Settings > Developer settings > Personal access tokens > Fine-grained
   tokens > Generate new token), resource owner
   `SethMorrowSoftware`, repository access "only select repositories": the
   eleven in section 5 ("Public repositories" is READ-ONLY access, and every
   push is refused). Permissions: **Contents: Read and write** and
   **Workflows: Read and write** - a permission starts at Read-only when it
   is added, so set both. The second is not optional: every member
   carries a generated `.github/workflows/`, and GitHub refuses any push that
   touches a workflow file without it - the first publish fails on it, not
   gradually. Give it an expiry and put the date in a calendar; an expired
   token makes the publish run fail loudly on its first push, which is the
   right failure but not a pleasant surprise.
4. **Store it** in `xtalk-suite` as the Actions secret
   `XTALK_PUBLISH_TOKEN` (Settings > Secrets and variables > Actions). Until
   it exists every run of the workflow is a DRY RUN that prints its plan, so
   nothing can be published by accident before this step.
5. **Look before anything is written.** Actions > `publish members` > Run
   workflow, on `main`, with the defaults (`members: all`, `dry_run: true`).
   The run's summary is a table with one row per member: `not adopted` and
   how many commits adopting would replay, or `unreachable` if a repository
   is still missing or private. Once the secret exists this run also TESTS
   it: every repository is asked whether the token may push there (a
   dry-run push, which writes nothing), and one it may not is refused with
   what to change. Reading a public repository needs no token, so without
   that question a plan cannot tell a working token from a useless one -
   which is how the first adoption, 2026-09-23, met eleven refusals after a
   plan that had looked healthy.
6. **Adopt.** Start a new run by hand, with `adopt` naming the members and
   `dry_run` unticked. **Re-run** on an earlier run does not do this: it
   replays that run with its own inputs, and the automatic runs have none,
   so it adopts nothing (also 2026-09-23). The names are the suite's
   directory names, space-separated - `holde-em`, `datachannelxt` - not the
   repositories' (`hold-em`, `dataChannelXT`); a name the registry does not
   know is refused before anything runs. One at a time is a perfectly good
   way to start. What adoption does to each repository is in the next
   paragraph; read it once.
7. **Nothing else.** From then on every green `suite gates` run on `main`
   publishes by itself. Re-run step 5 whenever you want the current table.

**What adoption does to a repository.** Its existing history is KEPT: the
first published commit sits on its old head (and says so in its message), so
the pre-suite commits stay reachable exactly where they were. Its TREE is
replaced by the suite's `<member>/` from that commit on, which means, for the
pre-suite repositories: their old `.github/workflows/` are replaced by the
generated `gates.yml` and `native.yml` (section 4), their READMEs by the
suite's (with the generated "Relationship to the xTalk suite" section), and
anything the suite's copy does not have is removed. **TorrentXT is the one
where that is visible**: it once vendored `enetxt/` and `datachannelxt/` as
subfolders, and its first published commit removes them, because both are
their own repositories now. Measured on 2026-09-22 by a real dry run against
the six public repositories: SodiumXT 42 commits, TorrentXT 53,
dataChannelXT 47, Box2Dxt 30, OnionXT 42, RipTide 46, each landing on that
repository's own `main` and each ending on a tree byte-identical to the
suite's. (The suite's very first commit replays as nothing for SodiumXT: its
`sodiumxt/` tree was identical to SodiumXT's last pre-suite tree, which is
what "copied in verbatim" should mean, now checked.)

**Two repository settings would stop it**, so check each member repository
for them once: a branch protection rule or ruleset on the default branch that
requires pull requests (the publisher pushes; let the token's owner bypass
it, or leave the branch unprotected), and "Require signed commits" (the
published commits are unsigned, by design: a signature would make the same
publish produce a different commit on every machine that ran it). A refused
push is reported per member and overwrites nothing, so finding one this way
costs a re-run, not a repair.

## 3. What "ready" means, and the gate that holds it

A member directory is ready to be published when it works as a repository
from its first commit: its README does not 404 on its own links, its CI runs
the gates the suite ran for it, its tools do not crash looking for a suite
that is not there, and a contributor can find out what it carries from
elsewhere and what it cannot check alone. Every one of those is generated
from a registry or refused by a gate, so readiness is a property of the tree
rather than of the afternoon someone last checked:

| What | Where it lives | Held by |
|---|---|---|
| The member table: name, title, kind, repository, native lane, gate siblings | `tools/member-registry.py` | `check-member-standalone.py` refuses a member-shaped directory the table does not list, and a row whose directory is gone |
| The member's own gate list | `<member>/tools/run-gates.sh` (hand-written, with the why-comments that used to live in `build-all.sh`) | `build-all.sh` DELEGATES to it, so the suite and the member repository run one list; `check-member-standalone.py` refuses a gate file under `tools/` or `tests/` the script's code never names (a mention in a comment does not count, since 2026-09-22) |
| The member's own CI | `<member>/.github/workflows/native.yml` (native members) and `gates.yml` (all) | GENERATED by `tools/sync-member-workflows.py` from the root `native-<member>.yml` lanes and the registry; `--check` refuses drift and any other file in that directory |
| The README's "Relationship to the xTalk suite" section | between two HTML-comment sentinels at the end of `<member>/README.md` | GENERATED by `tools/sync-member-readmes.py` from the registry and the carried-copy registries; `--check` refuses drift |
| The kit: `README.md`, `LICENSE`, `CLAUDE.md`, `.gitignore`, `.gitattributes` where binaries are committed, no markdown link that climbs out of the member, no tool that climbs to the suite root except through the sibling helper | the member directory | `tools/check-member-standalone.py`, with `tools/test-member-standalone.py` proving each check fires |
| The publisher's promises (section 1) | `tools/publish-members.py` | `tools/test-publish-members.py`, over throwaway repositories, every refusal required to fire |

All of them run in `tools/build-all.sh --gates` (the suite block), so a push
that un-readies a member, or breaks the publisher, fails CI here before a
publish could carry it anywhere.

## 4. The sibling layout

Some gates reach into sibling members, and a member repository has to
arrange that. The rule, implemented by a small `sibling()` helper in each
tool that needs it:

- A sibling member is found at `../<name>` beside the member's checkout,
  under its **member name** (`coinxt`, not `CoinXT`). In the suite tree that
  is simply the neighbouring directory.
- `XTALK_SIBLINGS=<dir>` names a directory holding all of them instead;
  `XTALK_SIBLING_<NAME>=<path>` names one (`XTALK_SIBLING_COINXT`,
  `XTALK_SIBLING_HOLDE_EM`).
- A member's own name resolves to its own tree before any override is read,
  because riptide's runner asks for `coinxt` when coinxt's gate is running
  it. That test compares the checkout's DIRECTORY NAME to the member name, so
  a member repository must be checked out under its member name - which
  `git clone` does not do by default (`git clone .../CoinXT` makes `CoinXT/`;
  clone it as `git clone .../CoinXT coinxt`). This page said "whatever the
  directory is called" until 2026-09-22; the helpers never did.
- A sibling that is absent is reported by the gate that needs it, naming the
  path, the repository to clone and the two variables - never a traceback.
  Where a gate used to SKIP a tier without its sibling (nostrxt's tier 2,
  riptide's native signing paths), `XTALK_REQUIRE_SIBLINGS=1` turns that
  skip into a failure, for the reason `tests/cross-member-test.py` records:
  in CI a skip and a pass both exit 0.

**In a member repository's CI the siblings come from the suite**, not from
each sibling's own repository: the generated `gates.yml` reads the newest
`Suite-Commit:` trailer in the member's history, sparse-checks-out the suite
(public) at that commit, and moves each sibling directory beside the member.
So the siblings are exactly the versions the suite's gates ran with that
tree. The 2026-09-21 generator checked each sibling out of its own
repository at its default branch instead, which could not work for a
private sibling (CoinXT, nocloud and hold-em were private) or one whose
repository did not exist yet (enetxt, NostrXT), and could race a publish
that updates the repositories one after another.

**Gate dependency is not runtime dependency.** The table lists what a
member's GATES load. What its shipped stacks need, they carry: a demo that
uses a sibling's library holds a verbatim copy between sentinels
(`tools/sync-demo-embeds.py`), so nothing has to be installed or cloned to
paste and run it. The list is written closed by hand - a gate that loads
riptide's runner inherits what that runner loads at import time (nostrxt's
interpreter and oracle), while a gate that loads only coinxt's committed
binary inherits none of coinxt's gate needs - and the registry's docstring
says why no transitive walk over the table would get that right.

| Member | Gate siblings | Why |
|---|---|---|
| nostrxt | coinxt, sodiumxt | tier 2 of `check-script-vectors.py` executes the composed paths against the committed x86_64-linux binaries |
| riptide | nostrxt, coinxt | `lcs-interp.py` and the nostrxt library and oracle are loaded, not copied; the committed coinxt binary signs |
| coinxt | riptide, nostrxt | `check-wallet-boot.py` reuses riptide's boot runner, which loads nostrxt's interpreter and oracle at import |
| nocloud | riptide, nostrxt, coinxt | `check-script-vectors.py` boots the helpers through riptide's runner |
| holde-em | riptide, nostrxt, coinxt | the same runner plus riptide's oracle |
| every other member | none | `bash tools/run-gates.sh` needs nothing but the checkout and Python 3 |

## 5. The member repositories

| Member | Repository | Before the suite |
|---|---|---|
| sodiumxt | `SethMorrowSoftware/SodiumXT` | the pre-suite home |
| torrentxt | `SethMorrowSoftware/TorrentXT` | the pre-suite home (it once vendored enetxt/ and datachannelxt/ as subfolders) |
| enetxt | `SethMorrowSoftware/enetxt` | none - it grew inside TorrentXT's tree |
| datachannelxt | `SethMorrowSoftware/dataChannelXT` | the pre-suite home |
| box2dxt | `SethMorrowSoftware/Box2Dxt` | the family ancestor's own repository |
| coinxt | `SethMorrowSoftware/CoinXT` | the pre-suite home |
| onionxt | `SethMorrowSoftware/OnionXT` | the pre-suite home |
| nostrxt | `SethMorrowSoftware/NostrXT` | none - born in the suite |
| riptide | `SethMorrowSoftware/RipTide` | the capstone's pre-suite home |
| nocloud | `SethMorrowSoftware/nocloud` | the pre-suite home |
| holde-em | `SethMorrowSoftware/hold-em` | the pre-suite `hold-em` repository |

The names are in `tools/member-registry.py` and nowhere else; the publisher
pushes to them, and the README sections point at them. Whether each one
exists, is readable, and what it holds is deliberately NOT in this table:
`python3 tools/publish-members.py status` observes it live, and a column here
would be a hand-kept fact that goes stale the day it changes (the
2026-09-21 version of this table said "to be created" for two repositories
the owner created the next day). To rename a repository, change the registry
and re-run the two generators; the publisher follows. A member's checkout
directory must still be its member name (section 4), whatever the
repository is called.

## 6. Everyday: what to do when

**A change merges to `main`.** Nothing. When `suite gates` goes green on it,
`publish members` runs and its summary table says, per member, `published N
commit(s)`, `up to date`, or why not.

**A publish run is red.** Its summary names the member and the reason; the
others were published anyway. The reasons, and the answer to each:

- *"has N commit(s) since its last publish that the suite never wrote and
  never ported"* - somebody pushed to the member repository directly, or
  merged a pull request there. Port it (next paragraph), or, if the change
  should simply go, run the workflow by hand with `accept_divergence` naming
  the member: the suite's tree is published as ONE commit on top of theirs,
  which stay in that repository's history.
- *"native-<member> ... concluded 'failure'"* - that member's own lane is red
  on its last change. Fix it in the suite; the next green publish carries it.
- *"push refused: ..."* - the rest of the sentence names the cause, and
  nothing was overwritten in any of them:
  - *"the credentials in use may not push to ..."* (or *"may not read"*, or
    *"a dry-run push ... was refused"*) - the token. It needs that
    repository in its repository access ("Only select repositories"; the
    "Public repositories" choice is read-only) with **Contents** and
    **Workflows** both Read and write. Edit the token; the secret does not
    change. This is what the first real adoption met, 2026-09-23, on all
    eleven.
  - *"... changes .github/workflows/ files"* - the token has Contents but
    not Workflows.
  - *"... branch protection or ruleset ..."* - the repository refuses direct
    or unsigned pushes to its default branch (section 2, last paragraph).
  - *"... moved while this ran"* - somebody pushed while the run was going.
    The next run recomputes from what is there.
- *"its last publish came from X, which main at Y does not contain"* - `main`
  was rewritten under a published commit. That is a decision to take by hand,
  not a thing to automate: stop and look.

**A contribution arrives at a member repository.** Bring it home rather than
merging it there:

```sh
# in a suite checkout, on a new branch
python3 tools/publish-members.py port sodiumxt --ref pull/7/head
```

Each commit the pull request adds to the default branch (`main..pull/7/head`,
the range GitHub shows; a merge carries no change of its own, and a commit
the publisher wrote is never ported) is applied under `sodiumxt/` with
`git am -3` (its author kept) and stamped
`Mirror-Commit: SethMorrowSoftware/SodiumXT@<sha>`. Open the suite pull
request as usual. Close the member-repository pull request with a link to
it; when the suite's pull request merges and publishes, the member repository
receives the change as a published commit. If it had been MERGED there first,
the same
command without `--ref` ports it from the default branch, and the
`Mirror-Commit:` trailers are what let the next publish accept that
repository's history instead of refusing it - the suite's tree then lands as
one commit over theirs. A port that conflicts stops with the files to
resolve; `git am --continue` keeps the trailer (it is written into the patch,
not added afterwards), and re-running `port` applies only what is left. A
ported commit that edits a generated file (a `.github/workflows/*.yml`, the
README section) will be refused by the suite's gates, correctly: make the
change in the root workflow, the generator or the registry instead.

**A member should LEAVE the suite for good** (the archivext case, section
8) - develop it elsewhere from now on. That is a different operation from
publishing, and it is rare; publishing is the default.

## 7. What a member repository cannot check

These run only in the suite, because their question is about more than one
member. A member's `run-gates.sh` does not pretend to ask them:

- **Carried-copy drift.** The demo UI kit, the boot self-check block and the
  harness scaffold are carried verbatim into each stack; their masters and
  drift gates (`tools/ui-kit.livecodescript` and friends) live here.
- **Embed freshness.** A demo carrying a sibling's library holds a copy;
  `tools/sync-demo-embeds.py --check` holds it current here and nowhere else.
- **One name, one library** (`tools/check-cross-library-names.py`), the
  cross-member handler-call and typed-boundary gates
  (`check-handler-calls.py`, `check-lcb-call-types.py`), the timer-pin
  closure, the shim scaffold drift, the binary-freshness walk and the suite
  paste's coverage ratchet.
- **The suite paste itself** (`tests/suite-selftest.livecodescript`), which
  folds every member's harness into one stack, and `tests/cross-member-test.py`.

That list is the reason development stays here (D-22): every one of those
gates runs on every push in the suite, and a member repository receives only
trees that passed them.

## 8. When a member leaves: the registries that name it

archivext was deleted from this tree on 2026-09-21 with none of its rows
removed, and the fast gate set went red in thirteen places. Every one names
what is missing, so the build points at each site; this is the list so the
next departure removes them in the same change as the directory. (A member
that is PUBLISHED does not leave; this section is for one that stops being
developed here at all.)

- `tools/member-registry.py` - the row (and `check-member-standalone.py`
  refuses a row whose directory is gone).
- `tools/check-checker-drift.py` - `COPY_SETS` (the checker, docs-style and
  interpreter copies) and `TEMPLATE_SETS`.
- `tools/test-checker.py` - `MEMBERS`.
- `tools/check-ui-kit-drift.py` - `ADOPTERS` (and `EXEMPT`, if the member
  had a written exemption).
- `tools/check-demo-selfcheck-drift.py` - `ADOPTERS` (which
  `check-demo-control-lists.py` reads).
- `tools/check-harness-scaffold-drift.py` - `ADOPTERS`, if the member's
  selftest carried the scaffold.
- `tools/test-stack-size.py` - the expected dimension count and its dated
  comment.
- `tools/check-cross-library-names.py` - the library corpus.
- `start-here.livecodescript` - the launcher's registry rows (held by
  `check-launcher-registry.py`).
- `tools/check-suite-coverage.py` - the coverage row and, if the member's
  library was embedded in the paste, `REQUIRED_EMBEDS`.
- `tools/check-suite-selftest.py` - `PREFIXES` and `ENTRY_POINTS`.
- `tools/build-suite-selftest.py` - its `Member(...)` row and any
  `Layer(...)` row; then `python3 tools/build-suite-selftest.py` to
  regenerate the paste, and `tests/suite-selftest.core.livecodescript`'s
  probe and deep-self-test sections for it.
- `tools/build-preflight.py` - its script-layer probe; then
  `python3 tools/build-preflight.py`.
- `tools/sync-demo-embeds.py` - `REGISTRY` rows for its demos, and any row
  in another member's demo that carried its library (that copy stays in the
  carrier as a snapshot; say so in the carrier's README).
- `tools/build-all.sh` - the member loop.
- The root docs: `README.md`'s member table, release matrix and coverage
  table; `CLAUDE.md`'s tree; `docs/EXTENSIONS-OVERVIEW.md`,
  `docs/OXT-PASS-RUNBOOK.md` and `docs/REMAINING-WORK.md`, which keep their
  dated records under a MOVED OUT note rather than losing them.

Then `bash tools/build-all.sh --gates`. The gates that read the tree by
glob (the harness scaffold, the stack-size scan, the duplicate-declaration
scan, the timer-pin closure) need no edit; the ones above are registries,
and a registry is exactly what a departure has to be told about. Before
deleting the directory, publish it one last time, so its repository holds
the last state the suite verified.

## 9. Per-member notes

Every member passes `check-member-standalone.py`. What is worth knowing
beyond the green:

| Member | Notes |
|---|---|
| sodiumxt | Nothing beside it needed. Its `native.yml` builds all five platforms; the committed binaries and MANIFEST travel with it. |
| torrentxt | Adoption removes the `enetxt/` and `datachannelxt/` subfolders it once vendored (both are their own repositories). `examples/torrent-quickshare.livecodescript` deliberately embeds nothing (it defines the engine socket handlers itself) and still wants `start using stack "onionxt"` for Tor. |
| enetxt | A new repository. `enet-internet-chat` carries torrentxt's helpers as an embedded copy. |
| datachannelxt | Nothing beside it needed. |
| box2dxt | README badge points at the suite lane until its own `native.yml` has run. Its Kit is carried into its own examples by its own `sync-embedded-kit.py`, which travels with it. |
| coinxt | Gate siblings riptide and nostrxt. Its full gate list takes hours (the three wallet gates; `run-gates.sh` says why and runs them at once), so its `gates.yml` states the six-hour ceiling - a cost its own repository pays on every publish, which is one more reason for step 2 of section 2. |
| onionxt | Nothing beside it needed. Its library is carried into six other stacks (nocloud, coin-wallet, torrent-dht-channels, riptide-social, holde-em, the suite's closing pass); publishing keeps every copy current, because the suite's embed gate holds them current before anything is published. |
| nostrxt | A new repository. Gate siblings coinxt and sodiumxt (binaries only); its `lcs-interp.py` is the copy riptide, nocloud and holde-em load, so it must stay byte-identical to coinxt's - a rule only the suite's `check-checker-drift.py` enforces. Its `tools/test-script-vectors.py` seeds defects into the SHIPPED `src/nostrxt.livecodescript` in place and restores it, so two of its gates must never run at once in one checkout (`run-gates.sh` is serial; a parallel CI matrix over one checkout would read a mutated library). The publisher is immune to that: it publishes git trees, never a working copy. |
| riptide | Gate siblings nostrxt and coinxt. `LICENSE` added 2026-09-21 (it had none). The capstone specs (`RIPTIDE-SOCIAL-SPEC.md`, `RIPTIDE-PROTOCOL.md`) stay suite-level and are cited by URL. |
| nocloud | Gate siblings riptide, nostrxt, coinxt. |
| holde-em | Gate siblings riptide, nostrxt, coinxt. Its README's extension table links the sibling repositories rather than `../<member>/`. |
