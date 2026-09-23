#!/usr/bin/env python3
"""publish-members.py - every member published into its own repository, from
the suite, one verified change at a time.

THE DECISION THIS SERVES (2026-09-22; docs/OPEN-DECISIONS.md D-22). The suite
stays the DEVELOPMENT repository, and each member ALSO lives in a repository
of its own (tools/member-registry.py names them). archivext's departure on
2026-09-21 was a MOVE - the directory left, and the suite lost it. This is
the other shape: nothing leaves, and each member repository receives the
suite's verified trees. It is a tool rather than a procedure because a
procedure run by hand after every merge is a procedure that stops being run,
and .github/workflows/publish-members.yml runs it after the suite's gates go
green on main.

WHAT PUBLISHING IS. For each member, the commits on the suite's main
FIRST-PARENT line that changed `<member>/` are replayed, oldest first, onto
the member repository's default branch: the member directory's own tree
object byte for byte, the suite commit's author and committer, a message
that keeps the suite's words, and a `Suite-Commit: <sha>` trailer naming the
suite commit it came from. First-parent because those are the states main
actually HELD - the states the suite's gates ran on - rather than every
intermediate commit of every pull request; a merge's published message
lists that pull request's own commits to the member, each linked into the
suite, so the detail is one click away rather than copied.

THE WATERMARK LIVES IN THE DESTINATION. The newest `Suite-Commit:` trailer on
the member repository's first-parent line is the whole state: it says which
suite commit that repository already holds, so a run publishes exactly what
landed after it. Nothing is recorded anywhere else, so there is nothing to
drift - which is the lesson this tree keeps relearning about hand-copied
numbers - and the output does not depend on git's version or on the replay
being byte-reproducible (it is anyway: same metadata, same parent, same SHA).

NOTHING IS EVER FORCE-PUSHED. Every push is a fast-forward of the branch the
repository already has. That is also what makes ADOPTION safe: the first
publish into a pre-suite repository (SodiumXT, TorrentXT, ...) replays the
suite's history ON TOP of that repository's own, so the pre-suite history
is kept, not rewritten; the first published commit simply replaces the tree.
A `git subtree split` pushed there could not do that - its history shares no
commit with the pre-suite one, so the push is refused and GitHub cannot even
open it as a pull request - which is the gap the 2026-09-21 procedure left.

ADOPTION IS EXPLICIT. A repository whose history carries no watermark has
never been written by the suite, and the first write replaces its tree, so
it happens only with --adopt naming that member. The automatic run never
adopts: it extends histories the suite already owns and reports the rest.

DIVERGENCE IS REFUSED, NOT OVERWRITTEN. A commit pushed to a member
repository directly (a web edit, a merged outside pull request) makes that
repository's tree differ from the tree of its last published commit. Replay
would silently revert it, so the member is refused with the commits listed
and the command that fixes it. Two things lift the refusal: every such
commit having been PORTED into the suite (below), or --accept-divergence
naming the member (the owner's call that the content goes; history keeps
it). Either way the suite's tree is then published as ONE commit on top of
them, because replaying commit by commit would revert their content and
re-apply it.

PORTING (`port <member> [--ref REF]`) is how a contribution that arrived at
a member repository comes home: each commit made there since its last
published commit (or, with --ref, each commit a pull request adds to the
default branch - never one the publisher wrote) is applied to the current
suite branch with
`git am -3 --directory=<member>` (authorship kept) and stamped with a
`Mirror-Commit: <owner/repo>@<sha>` trailer. The trailer is written into the
PATCH, not added afterwards, so a commit finished by hand after a conflict
(`git am --continue`) carries it too - and that trailer, once merged to the
suite's main, is what lets the next publish accept the member repository's
history instead of refusing it. `--ref pull/7/head` ports an open pull
request there.

    python3 tools/publish-members.py status                 # what a publish would do
    python3 tools/publish-members.py publish --dry-run      # the same, spelled as CI spells it
    python3 tools/publish-members.py publish --adopt enetxt nostrxt
    python3 tools/publish-members.py port sodiumxt [--ref pull/7/head]

Credentials are git's: the workflow configures a credential helper that
answers with the XTALK_PUBLISH_TOKEN secret, so no token is ever on a
command line or in a URL, and a local run uses whatever git already has.
--check-push asks every reachable repository whether those credentials may
PUSH to it - a dry-run push, which GitHub answers at its first request and
which sends nothing - and refuses the member when they may not. The workflow
passes it whenever the secret exists, dry runs included, because reading a
public repository needs no credentials at all: a plan run that only reads
cannot tell a working token from a useless one. That is not a hypothetical.
The first real adoption (2026-09-23) was refused eleven times over by a token
that could read everything and push nowhere, after a plan run that had
looked entirely healthy.
Mirror refs are fetched into a private bare cache (by default
<git-common-dir>/xtalk-publish, borrowing the suite's objects through
alternates), so a status run leaves no refs in the suite repository.

Exit 0 = every selected member is published, up to date, or reported as not
yet adopted/created; 1 = at least one member was refused (divergence, a
watermark main does not contain, a rejected push, a missing member tree,
credentials that were offered and refused), each named above the exit, a
refused push by its cause: credentials, workflow files, branch protection,
or a repository that moved. tools/test-publish-members.py drives this file's
real command line over throwaway repositories, one case per refusal.
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


REG = _load("member_registry", os.path.join(HERE, "member-registry.py"))

TRAILER = "Suite-Commit"
PORT_TRAILER = "Mirror-Commit"
DEFAULT_URL = "https://github.com/{repo}.git"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
# GitHub's two spellings of "this came from pull request N": a merge commit's
# subject, and the "(#N)" a squash or rebase merge appends to the title. Only
# these are rewritten to name the suite explicitly, because in a member
# repository a bare "#N" links to THAT repository's issue N. Free-text "#N"
# is left alone: "TorrentXT PR #60" in a suite message is TorrentXT's, and no
# rewrite could know which repository any other one means.
MERGE_RE = re.compile(r"^Merge pull request #(\d+) from (\S+)\s*$")
SQUASH_RE = re.compile(r"^(.*\S)\s+\(#(\d+)\)$")
LIST_CAP = 40
FIELD = "\x00"

# Why a push was refused, in the words git and GitHub use for each cause.
# Credentials that may not push at all are turned away at the FIRST request
# ("The requested URL returned error: 403"), before anything is sent - which
# is what makes push_access's dry run a real test of them - while workflow
# files and branch protection are judged against the pack, on a real push
# ("[remote rejected] (...)"). Until these existed every refusal read "did
# the repository move while this ran?", which is what the first real
# adoption (2026-09-23) printed eleven times over a token that could not
# push anywhere.
PUSH_CAUSES = (
    (re.compile(r"without .?workflow.? scope|to create or update workflow", re.I),
     "{repo} refused it because it changes .github/workflows/ files: "
     "XTALK_PUBLISH_TOKEN needs Workflows: Read and write"),
    (re.compile(r"protected branch|GH006|GH013|rule violation|verified signature",
                re.I),
     "{repo}'s branch protection or ruleset on {branch} refused it - the "
     "publisher pushes directly and does not sign: let the token's owner "
     "bypass it, or lift it (docs/MEMBER-REPO-SPLIT.md)"),
    (re.compile(r"returned error: 40[13]\b|permission to \S+ denied|not granted"
                r"|authentication failed|could not read username"
                r"|invalid username or password", re.I),
     "the credentials in use may not push to {repo}: in the workflow that is "
     "XTALK_PUBLISH_TOKEN, which needs {repo} in its repository access with "
     "Contents and Workflows both Read and write"),
    (re.compile(r"\(fetch first\)|non-fast-forward|\(stale info\)", re.I),
     "{repo} moved while this ran - nothing is ever force-pushed, so the next "
     "run replays onto its new head"),
)
# A read refused to credentials that WERE offered. No credentials get a 401
# (git: "could not read Username"), which GitHub also answers for a missing
# repository, so that stays "unreachable"; a 403 means a token that does not
# cover this repository, which is a configuration to fix, not a state.
READ_DENIED = re.compile(r"returned error: 403\b|not granted"
                         r"|permission to \S+ denied", re.I)


class Failure(Exception):
    """A refusal for ONE member: reported, and the run goes on to the next."""


def _tail(text, n=4):
    lines = [l for l in (text or "").strip().splitlines() if l.strip()]
    return " | ".join(lines[-n:]) if lines else "(no output)"


def _verb(args):
    """`git fetch`, not `git -C /long/path fetch`: the subcommand is what a
    reader of a refusal needs, and the path is noise."""
    rest = list(args[1:])
    while rest and (rest[0].startswith("--git-dir") or rest[0] == "-C"):
        rest = rest[2:] if rest[0] == "-C" else rest[1:]
    return "git " + (rest[0] if rest else "")


def run(args, cwd=None, env=None, stdin=None, check=True):
    p = subprocess.run(args, cwd=cwd, env=env, input=stdin,
                       capture_output=True, text=True, encoding="utf-8",
                       errors="surrogateescape")
    if check and p.returncode != 0:
        raise Failure("`%s` failed: %s" % (_verb(args),
                                           _tail(p.stderr or p.stdout)))
    return p


# A remote that asks for a password must fail, not hang a CI job forever.
NET_ENV = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never")


class Git(object):
    """One repository: the suite (a work tree) or the cache (bare)."""

    def __init__(self, worktree=None, gitdir=None):
        self.worktree = worktree
        self.gitdir = gitdir

    def argv(self, *args):
        if self.worktree:
            return ["git", "-C", self.worktree] + list(args)
        return ["git", "--git-dir=" + self.gitdir] + list(args)

    def __call__(self, *args, **kw):
        return run(self.argv(*args), **kw).stdout

    def ok(self, *args, **kw):
        return run(self.argv(*args), check=False, **kw).returncode == 0


# ---------------------------------------------------------------------------
# reading both sides
# ---------------------------------------------------------------------------

def member_trees(suite, commits, name):
    """{commit: tree id of <name>/ at that commit, or None}. One cat-file
    process for the whole chain rather than one rev-parse per commit."""
    if not commits:
        return {}
    out = suite("cat-file", "--batch-check=%(objectname) %(objecttype)",
                stdin="".join("%s:%s\n" % (c, name) for c in commits))
    res = {}
    for c, line in zip(commits, out.split("\n")):
        parts = line.split()
        res[c] = parts[0] if len(parts) == 2 and parts[1] == "tree" else None
    return res


def first_parent(suite, target, base=None):
    """The first-parent line up to `target`, oldest first, after `base`."""
    args = ["rev-list", "--first-parent", "--reverse", target]
    if base:
        args.append("^" + base)
    return suite(*args).split()


def commit_info(repo, rev):
    out = repo("log", "-1", "--date=raw",
               "--format=%H%x00%P%x00%an%x00%ae%x00%ad%x00%cn%x00%ce%x00%cd%x00%B",
               rev)
    f = out.split(FIELD, 8)
    return {"sha": f[0], "parents": f[1].split(), "an": f[2], "ae": f[3],
            "ad": f[4], "cn": f[5], "ce": f[6], "cd": f[7],
            "message": f[8].rstrip("\n") + "\n"}


def watermark(cache, ref):
    """(mirror commit, its tree, suite commit) of the newest published commit
    on `ref`'s first-parent line, or None if the suite never wrote there."""
    out = cache("log", "--first-parent",
                "--format=%H%x00%T%x00%(trailers:key=" + TRAILER +
                ",valueonly,separator=%x2C)", ref)
    for line in out.splitlines():
        sha, tree, vals = line.split(FIELD)
        vals = [v.strip() for v in vals.split(",") if v.strip()]
        if vals:
            return sha, tree, vals[-1]
    return None


def ported(suite, rev):
    """{mirror commit sha: suite commit that ported it}, from every
    Mirror-Commit trailer reachable from `rev` (pull request branches
    included - the port lands there, not on the first-parent line)."""
    out = suite("log", "--format=%H%x00%(trailers:key=" + PORT_TRAILER +
                ",valueonly,separator=%x2C)", rev)
    got = {}
    for line in out.splitlines():
        sha, vals = line.split(FIELD)
        for v in vals.split(","):
            m = re.search(r"\b([0-9a-f]{40})\b", v)
            if m:
                got.setdefault(m.group(1), sha)
    return got


def own_commits(cache, base, ref):
    """The commits on `ref` after `base` that the member repository made
    itself, oldest first. Merges carry no change of their own. A commit
    stamped with a Suite-Commit trailer is one the PUBLISHER wrote, which
    the suite already has, so it is never a divergence and never ported -
    applying one would make a suite change twice. The range normally keeps
    such commits out on its own (they live on the default branch's
    first-parent line, at or below the watermark, and a pull request's range
    starts at the default branch); the trailer filter is the backstop for a
    history where that stopped being true, such as a default branch reset
    under a pull request that had merged it."""
    rng = ref if base is None else "%s..%s" % (base, ref)
    out = cache("log", "--reverse", "--no-merges",
                "--format=%H%x00%(trailers:key=" + TRAILER +
                ",valueonly,separator=%x2C)", rng)
    got = []
    for line in out.splitlines():
        sha, vals = line.split(FIELD)
        if not vals.strip():
            got.append(sha)
    return got


def probe(url):
    """(default branch, its head or None, error or None). An empty
    repository has no HEAD to follow; it gets `main`, which becomes its
    default on the first push."""
    p = run(["git", "ls-remote", "--symref", url, "HEAD", "refs/heads/*"],
            env=NET_ENV, check=False)
    if p.returncode != 0:
        return None, None, _tail(p.stderr)
    branch, heads = None, {}
    for line in p.stdout.splitlines():
        if line.startswith("ref: "):
            target, name = line[5:].split("\t", 1)
            if name == "HEAD" and target.startswith("refs/heads/"):
                branch = target[len("refs/heads/"):]
        elif "\t" in line:
            sha, name = line.split("\t", 1)
            if name.startswith("refs/heads/"):
                heads[name[len("refs/heads/"):]] = sha
    if branch is None:
        branch = next((b for b in ("main", "master") if b in heads),
                      sorted(heads)[0] if heads else "main")
    return branch, heads.get(branch), None


# ---------------------------------------------------------------------------
# writing
# ---------------------------------------------------------------------------

def add_trailer(msg, key, value, cwd):
    # Every placement option spelled out: a contributor's trailer.where or
    # trailer.ifexists config must not move the watermark or duplicate it.
    return run(["git", "interpret-trailers", "--where", "end", "--if-exists",
                "replace", "--if-missing", "add",
                "--trailer", "%s: %s" % (key, value)],
               cwd=cwd, stdin=msg).stdout


def published_message(ctx, info, name, note=None):
    """The suite commit's message, as the member repository should read it."""
    lines = info["message"].rstrip("\n").split("\n")
    subject, body = lines[0], "\n".join(lines[1:]).strip("\n")
    extra = []
    m = MERGE_RE.match(subject)
    if m and len(info["parents"]) >= 2:
        number, branch = m.groups()
        blines = body.split("\n") if body else []
        title = blines[0].strip() if blines and blines[0].strip() else branch
        body = "\n".join(blines[1:]).strip("\n")
        subject = "%s (%s#%s)" % (title, REG.SUITE_REPO, number)
        log = ctx.suite("log", "--reverse", "--no-merges", "--format=%H %s",
                        "%s^1..%s" % (info["sha"], info["sha"]),
                        "--", name + "/").splitlines()
        if log:
            items = ["- %s (%s@%s)" % (l[41:], REG.SUITE_REPO, l[:12])
                     for l in log[:LIST_CAP]]
            if len(log) > LIST_CAP:
                items.append("- ... and %d more: %s/pull/%s/commits"
                             % (len(log) - LIST_CAP, REG.SUITE_URL, number))
            extra.append("The commits in that pull request that changed %s/:\n%s"
                         % (name, "\n".join(items)))
    else:
        s = SQUASH_RE.match(subject)
        if s:
            subject = "%s (%s#%s)" % (s.group(1), REG.SUITE_REPO, s.group(2))
    paras = [p for p in [body] + extra if p]
    if note:
        paras.insert(0, note)
    msg = subject + "".join("\n\n" + p for p in paras) + "\n"
    return add_trailer(msg, TRAILER, info["sha"], ctx.suite.worktree)


def make_commit(ctx, tree, parent, msg, info):
    env = dict(os.environ,
               GIT_AUTHOR_NAME=info["an"], GIT_AUTHOR_EMAIL=info["ae"],
               GIT_AUTHOR_DATE=info["ad"], GIT_COMMITTER_NAME=info["cn"],
               GIT_COMMITTER_EMAIL=info["ce"], GIT_COMMITTER_DATE=info["cd"])
    # --no-gpg-sign: a published commit is a pure function of the suite
    # commit and its parent. A contributor's commit.gpgsign would make the
    # same publish produce a different SHA on their machine than in CI.
    args = ["commit-tree", "--no-gpg-sign", tree]
    if parent:
        args += ["-p", parent]
    return ctx.cache(*args, env=env, stdin=msg).strip()


# ---------------------------------------------------------------------------
# one member
# ---------------------------------------------------------------------------

class Result(object):
    def __init__(self, m):
        self.m = m
        self.branch = "-"
        self.state = ""
        self.detail = ""
        self.failed = False
        self.new_head = None

    def set(self, state, detail, failed=False):
        self.state, self.detail, self.failed = state, detail, failed
        return self


class Ctx(object):
    def __init__(self, args):
        self.suite = Git(worktree=args.suite)
        self.url_template = args.url_template
        self.check_push = getattr(args, "check_push", False)
        self.target = None
        self.cache = None

    def url(self, m):
        return self.url_template.format(repo=m.repo, name=m.name)


def replay(ctx, m, commits, parent, cur_tree, note=None):
    """Replay the first-parent commits that changed <m>/ onto `parent`.
    Returns (new head, [(suite commit, published commit)])."""
    trees = member_trees(ctx.suite, commits, m.name)
    made = []
    for c in commits:
        t = trees[c]
        if t is None or t == cur_tree:
            continue
        info = commit_info(ctx.suite, c)
        msg = published_message(ctx, info, m.name, note if not made else None)
        parent = make_commit(ctx, t, parent, msg, info)
        made.append((c, parent))
        cur_tree = t
    return parent, made


def squash(ctx, m, head, w_suite, target_tree, stray, port_map):
    """ONE commit, on top of a member repository that has commits of its
    own, whose tree is the suite's at the target."""
    chain = first_parent(ctx.suite, ctx.target, w_suite)
    trees = member_trees(ctx.suite, [w_suite] + chain, m.name)
    prev, changed = trees[w_suite], []
    for c in chain:
        if trees[c] is not None and trees[c] != prev:
            changed.append(c)
            prev = trees[c]
    info = commit_info(ctx.suite, ctx.target)
    short = ctx.target[:12]
    theirs = []
    for s in stray:
        subj = ctx.cache("log", "-1", "--format=%s", s).strip()
        if s in port_map:
            how = "ported to the suite as %s@%s" % (REG.SUITE_REPO, port_map[s][:12])
        else:
            how = "not ported; replaced by the suite's tree (--accept-divergence)"
        theirs.append("- %s %s (%s)" % (s[:12], subj, how))
    ours = []
    for c in changed[-LIST_CAP:]:
        subj = ctx.suite("log", "-1", "--format=%s", c).strip()
        ours.append("- %s (%s@%s)" % (subj, REG.SUITE_REPO, c[:12]))
    if len(changed) > LIST_CAP:
        ours.insert(0, "- ... %d earlier" % (len(changed) - LIST_CAP))
    msg = ("Publish %s/ from %s@%s over this repository's own commits\n\n"
           "This repository had commits the suite did not write, so the "
           "suite's tree\nis published as ONE commit on top of them instead "
           "of being replayed\ncommit by commit, which would revert their "
           "content and then re-apply it.\nThey stay in this history; the "
           "tree from here on is the suite's.\n\n"
           "Commits made here since the last publish:\n%s\n\n"
           "Suite commits this publishes:\n%s\n"
           % (m.name, REG.SUITE_REPO, short, "\n".join(theirs),
              "\n".join(ours) or "- (none: the tree was already the suite's)"))
    msg = add_trailer(msg, TRAILER, ctx.target, ctx.suite.worktree)
    return make_commit(ctx, target_tree, head, msg, info)


def publish_one(ctx, m, adopt, accept, dry_run):
    r = Result(m)
    url = ctx.url(m)
    target_tree = member_trees(ctx.suite, [ctx.target], m.name)[ctx.target]
    if target_tree is None:
        raise Failure("%s/ does not exist at %s - a member that leaves takes "
                      "its registry row with it (docs/MEMBER-REPO-SPLIT.md)"
                      % (m.name, ctx.target[:12]))
    branch, head, err = probe(url)
    if err is not None:
        if READ_DENIED.search(err):
            raise Failure("the credentials in use may not read %s: add it to "
                          "XTALK_PUBLISH_TOKEN's repository access, or make it "
                          "public (%s)" % (m.repo, err))
        if m.name in adopt:
            raise Failure("cannot reach %s: %s" % (m.repo, err))
        # GitHub answers a private repository and a missing one alike, so
        # the advice names both rather than guessing which this is.
        return r.set("unreachable", "%s - missing, or private and unreadable "
                     "with this run's credentials. Create it EMPTY (no README, "
                     "license or .gitignore) if missing, then publish with "
                     "--adopt %s" % (err, m.name))
    r.branch = branch
    ref = "refs/mirrors/" + m.name
    wm = None
    head_tree = None
    if head is not None:
        ctx.cache("fetch", "--no-tags", "--quiet", url,
                  "+refs/heads/%s:%s" % (branch, ref), env=NET_ENV)
        # Build on what was FETCHED, not on what ls-remote said a moment
        # earlier: if the branch moved in between, this reads the newer head
        # consistently, and the push below is still refused if it moves
        # again - never a replay onto one head judged by another.
        head = ctx.cache("rev-parse", ref).strip()
        wm = watermark(ctx.cache, ref)
        head_tree = ctx.cache("rev-parse", head + "^{tree}").strip()
    # Before anything else is judged: a plan whose every push will be refused
    # is not a plan, and a member that has nothing to publish today will have
    # something tomorrow, when an expired token should already be red.
    if ctx.check_push:
        why = push_access(ctx, m, url, branch, head)
        if why:
            raise Failure(why)

    if wm is None:
        chain = adoption_chain(ctx, m, head_tree)
        if m.name not in adopt:
            n = sum(1 for _ in _changes(ctx, m, chain, head_tree))
            where = ("onto its own history (kept)" if head
                     else "into the empty repository")
            return r.set("not adopted",
                         "the suite has never published here; --adopt %s "
                         "replays %d commit(s) %s" % (m.name, n, where))
        note = None
        if head:
            note = ("The first commit the xTalk suite published into this "
                    "repository. The\nhistory before it is this repository's "
                    "own, from before the suite,\nand is kept; from here on "
                    "this repository is published from the\nsuite's %s/ "
                    "(%s)." % (m.name, REG.SUITE_URL))
        new, made = replay(ctx, m, chain, head, head_tree, note)
        if not made:
            # The repository already holds the suite's tree (a pre-suite
            # repository nothing changed in since the fold). Replay has
            # nothing to write, and without a published commit there is no
            # Suite-Commit trailer, so the repository would read as "not
            # adopted" forever. One commit with the same tree carries it.
            info = commit_info(ctx.suite, ctx.target)
            msg = ("Adopt this repository: published from the xTalk suite from "
                   "here on\n\n%s\n" % note)
            msg = add_trailer(msg, TRAILER, ctx.target, ctx.suite.worktree)
            new = make_commit(ctx, target_tree, head, msg, info)
            made = [(ctx.target, new)]
        return _finish(ctx, r, url, branch, head, new, made, dry_run,
                       "adopted: ")

    wm_sha, wm_tree, w_suite = wm
    if not SHA_RE.match(w_suite) or not ctx.suite.ok(
            "cat-file", "-e", w_suite + "^{commit}"):
        raise Failure("its last published commit %s names suite commit %r, "
                      "which this suite history does not have (a shallow or "
                      "rewritten main?)" % (wm_sha[:12], w_suite))
    if w_suite != ctx.target and not ctx.suite.ok(
            "merge-base", "--is-ancestor", w_suite, ctx.target):
        if ctx.suite.ok("merge-base", "--is-ancestor", ctx.target, w_suite):
            return r.set("ahead", "already holds %s, newer than %s - nothing "
                         "to do" % (w_suite[:12], ctx.target[:12]))
        raise Failure("its last publish came from %s, which main at %s does "
                      "not contain - was main rewritten?"
                      % (w_suite[:12], ctx.target[:12]))
    w_tree_suite = member_trees(ctx.suite, [w_suite], m.name)[w_suite]
    if wm_tree != w_tree_suite and m.name not in accept:
        raise Failure("its commit %s claims %s: %s but does not hold that "
                      "commit's %s/ tree - a hand-written trailer? Check it, "
                      "then --accept-divergence %s"
                      % (wm_sha[:12], TRAILER, w_suite[:12], m.name, m.name))

    # Diverged = the repository's tree is not the suite's tree at the last
    # publish. Compared against the SUITE's tree, not the watermark commit's,
    # so a hand-edited watermark that --accept-divergence let through above
    # takes this path too rather than replaying onto a tree the suite never
    # held (and publishing nothing when no later suite commit touched it).
    if head_tree != w_tree_suite:
        stray = own_commits(ctx.cache, wm_sha, head)
        port_map = ported(ctx.suite, ctx.target)
        unported = [s for s in stray if s not in port_map]
        if unported and m.name not in accept:
            lines = ["  %s %s" % (s[:12], ctx.cache("log", "-1", "--format=%s (%an)", s).strip())
                     for s in unported]
            raise Failure(
                "%s has %d commit(s) since its last publish (%s) that the suite "
                "never wrote and never ported:\n%s\n    Port them into the "
                "suite (`python3 tools/publish-members.py port %s`, then merge "
                "that change to main), or pass --accept-divergence %s to "
                "replace them with the suite's tree (they stay in history)."
                % (m.repo, len(unported), wm_sha[:12], "\n".join(lines),
                   m.name, m.name))
        new = squash(ctx, m, head, w_suite, target_tree, stray, port_map)
        return _finish(ctx, r, url, branch, head, new,
                       [(ctx.target, new)], dry_run,
                       "over %d commit(s) made there: " % len(stray))

    chain = first_parent(ctx.suite, ctx.target, w_suite)
    new, made = replay(ctx, m, chain, head, head_tree)
    return _finish(ctx, r, url, branch, head, new, made, dry_run, "")


def adoption_chain(ctx, m, head_tree):
    """The first-parent commits an adoption replays. It starts AFTER the
    newest suite commit whose <m>/ tree the repository already holds - the
    fold commit, for a pre-suite repository nothing changed in since - so a
    repository somebody synced by hand to a later state is extended from that
    state, instead of being rewound to the fold and replayed forward. No
    match (an empty repository, or a tree the suite never held) replays the
    whole line."""
    chain = first_parent(ctx.suite, ctx.target)
    if head_tree is None:
        return chain
    trees = member_trees(ctx.suite, chain, m.name)
    last = None
    for i, c in enumerate(chain):
        if trees[c] == head_tree:
            last = i
    return chain if last is None else chain[last + 1:]


def _changes(ctx, m, chain, start_tree):
    trees = member_trees(ctx.suite, chain, m.name)
    cur = start_tree
    for c in chain:
        if trees[c] is not None and trees[c] != cur:
            cur = trees[c]
            yield c


def push_problem(text, m, branch):
    for rx, why in PUSH_CAUSES:
        if rx.search(text or ""):
            return why.format(repo=m.repo, branch=branch)
    return "%s turned it away" % m.repo


def push_access(ctx, m, url, branch, head):
    """None when the credentials in use may push to the repository, else
    why not. A DRY-RUN push: git asks for the receive-pack advertisement,
    which GitHub serves only to credentials allowed to push, then sends
    nothing and moves nothing. The source is the repository's own head (an
    "Everything up-to-date"), or for an empty repository the target commit,
    whose pack a dry run never builds. What it cannot see is a missing
    Workflows permission - GitHub judges that against the pack, on a real
    push - so push_problem names that one when a real push meets it."""
    src = head or ctx.target
    p = run(["git", "--git-dir=" + ctx.cache.gitdir, "push", "--dry-run",
             "--porcelain", url, "%s:refs/heads/%s" % (src, branch)],
            env=NET_ENV, check=False)
    if p.returncode == 0:
        return None
    text = p.stderr + p.stdout
    return "a dry-run push, which writes nothing, was refused: %s (%s)" % (
        push_problem(text, m, branch), _tail(text))


def _finish(ctx, r, url, branch, head, new, made, dry_run, prefix):
    if not made:
        return r.set("up to date", "holds %s's %s/" % (ctx.target[:12], r.m.name))
    span = "%s..%s" % ((head or "(root)")[:12], new[:12])
    if dry_run:
        return r.set("would publish", "%s%d commit(s), %s (dry run)"
                     % (prefix, len(made), span))
    p = run(["git", "--git-dir=" + ctx.cache.gitdir, "push", "--porcelain",
             url, "%s:refs/heads/%s" % (new, branch)], env=NET_ENV, check=False)
    if p.returncode != 0:
        text = p.stderr + p.stdout
        raise Failure("push refused: %s (%s)"
                      % (push_problem(text, r.m, branch), _tail(text)))
    ctx.cache("update-ref", "refs/mirrors/" + r.m.name, new)
    r.new_head = new
    return r.set("published", "%s%d commit(s), %s" % (prefix, len(made), span))


# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------

def open_cache(ctx, path):
    common = ctx.suite("rev-parse", "--path-format=absolute",
                       "--git-common-dir").strip()
    path = path or os.path.join(common, "xtalk-publish")
    if not os.path.isdir(path):
        run(["git", "init", "--bare", "--quiet", path])
    alt = os.path.join(path, "objects", "info", "alternates")
    want = os.path.join(common, "objects") + "\n"
    cur = open(alt).read() if os.path.exists(alt) else None
    if cur != want:
        with open(alt, "w") as fh:
            fh.write(want)
    ctx.cache = Git(gitdir=path)


def resolve_target(ctx, args):
    if ctx.suite("rev-parse", "--is-shallow-repository").strip() == "true":
        raise SystemExit("publish-members: the suite checkout is shallow - the "
                         "first-parent line and every watermark need the whole "
                         "history (fetch-depth: 0, or `git fetch --unshallow`)")
    main = args.main
    if main is None:
        for cand in ("refs/remotes/origin/main", "refs/heads/main"):
            if ctx.suite.ok("rev-parse", "--verify", "--quiet", cand):
                main = cand
                break
        else:
            raise SystemExit("publish-members: no origin/main or main here; "
                             "name the branch the suite publishes with --main")
    ctx.target = ctx.suite("rev-parse", "--verify",
                           (args.commit or main) + "^{commit}").strip()
    # Only states main actually held are published: the invariant the
    # workflow checks too, held here so a local run cannot publish a branch.
    if ctx.target not in set(first_parent(ctx.suite, main)):
        raise SystemExit("publish-members: %s is not on %s's first-parent "
                         "line - only states main held are published"
                         % (ctx.target[:12], main))


def pick(names):
    flat = [n for arg in names or [] for n in re.split(r"[\s,]+", arg) if n]
    if not flat or flat == ["all"]:
        return list(REG.MEMBERS)
    unknown = [n for n in flat if n not in REG.BY_NAME]
    if unknown:
        raise SystemExit("publish-members: not in tools/member-registry.py: %s"
                         % ", ".join(unknown))
    return [REG.BY_NAME[n] for n in flat]


def names(arg):
    got = set(n for a in arg or [] for n in re.split(r"[\s,]+", a) if n)
    unknown = sorted(n for n in got if n not in REG.BY_NAME)
    if unknown:
        raise SystemExit("publish-members: not in tools/member-registry.py: %s"
                         % ", ".join(unknown))
    return got


def cmd_publish(args, dry_run):
    ctx = Ctx(args)
    resolve_target(ctx, args)
    open_cache(ctx, args.cache)
    adopt, accept = names(args.adopt), names(args.accept_divergence)
    results = []
    print("publish-members: suite %s at %s%s" % (
        REG.SUITE_REPO, ctx.target[:12], " (dry run)" if dry_run else ""))
    for m in pick(args.members):
        try:
            r = publish_one(ctx, m, adopt, accept, dry_run)
        except Failure as e:
            r = Result(m).set("REFUSED", str(e), failed=True)
        results.append(r)
        print("  %-14s %-32s %-8s %-14s %s" % (m.name, m.repo, r.branch,
                                               r.state, r.detail))
    notes = []
    waiting = [r.m.name for r in results if r.state == "not adopted"]
    if waiting and os.environ.get("GITHUB_ACTIONS") == "true":
        # No run adopts by itself, and Re-run replays the same event with the
        # same (empty) inputs - which is how the first adoption attempt,
        # 2026-09-23, published nothing and read like a fault. The way
        # forward is a run started by hand, so say it in that form's words
        # rather than as a command-line flag.
        notes.append("Adopting is never automatic, and re-running a run does not "
                     "change its inputs. To adopt: Actions > publish members > "
                     "Run workflow, on main, with Members to ADOPT set to `%s` "
                     "and \"Plan and report only\" unticked."
                     % " ".join(waiting))
    for note in notes:
        print("::notice::" + note)
    summary(ctx, results, dry_run, notes)
    bad = [r for r in results if r.failed]
    if bad:
        print("publish-members: %d member(s) refused: %s"
              % (len(bad), ", ".join(r.m.name for r in bad)))
        return 1
    return 0


def summary(ctx, results, dry_run, notes=()):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    rows = ["### Member repositories at %s@%s%s" % (
                REG.SUITE_REPO, ctx.target[:12], " (dry run)" if dry_run else ""),
            "", "| member | repository | branch | state | detail |",
            "|---|---|---|---|---|"]
    for r in results:
        detail = r.detail.replace("|", "\\|").replace("\n", "<br>")
        rows.append("| %s | [%s](%s) | %s | %s | %s |" % (
            r.m.name, r.m.repo, r.m.url, r.branch,
            ("**%s**" % r.state) if r.failed else r.state, detail))
    rows += [""] + list(notes)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("\n".join(rows) + "\n")


def cmd_port(args):
    ctx = Ctx(args)
    open_cache(ctx, args.cache)
    m = REG.BY_NAME.get(args.member)
    if m is None:
        raise SystemExit("publish-members: %s is not in tools/member-registry.py"
                         % args.member)
    if ctx.suite("status", "--porcelain", "--untracked-files=no").strip():
        raise SystemExit("publish-members: the suite work tree has uncommitted "
                         "changes; commit or stash them first")
    gitdir = ctx.suite("rev-parse", "--path-format=absolute", "--git-dir").strip()
    for busy in ("rebase-apply", "rebase-merge", "MERGE_HEAD", "CHERRY_PICK_HEAD"):
        if os.path.exists(os.path.join(gitdir, busy)):
            raise SystemExit("publish-members: finish or abort the %s in "
                             "progress first" % busy)
    url = ctx.url(m)
    branch, head, err = probe(url)
    if err is not None:
        raise SystemExit("publish-members: cannot reach %s: %s" % (m.repo, err))
    if head is None:
        raise SystemExit("publish-members: %s is empty - nothing to port"
                         % m.repo)
    main_ref = "refs/mirrors/" + m.name
    try:
        ctx.cache("fetch", "--no-tags", "--quiet", url,
                  "+refs/heads/%s:%s" % (branch, main_ref), env=NET_ENV)
        if args.ref:
            src = args.ref
            ref = "refs/port/" + m.name
            ctx.cache("fetch", "--no-tags", "--quiet", url,
                      "+%s:%s" % (src, ref), env=NET_ENV)
    except Failure as e:
        raise SystemExit("publish-members: %s" % e)
    if args.ref:
        # A pull request's own commits are what it adds to the default
        # branch - `main..ref`, the range GitHub itself shows. Anything it
        # merged in FROM the default branch is already accounted for there:
        # a published commit came from the suite, and a commit made there
        # directly is the default branch's to port (or to have been
        # accepted away), not this pull request's.
        base, what = main_ref, "not on %s's %s" % (m.repo, branch)
    else:
        wm = watermark(ctx.cache, main_ref)
        if wm is None:
            raise SystemExit("publish-members: nothing in %s's %s came from "
                             "the suite, so there is no published base to "
                             "port from" % (m.repo, branch))
        src, ref = "refs/heads/" + branch, main_ref
        base, what = wm[0], "since its last publish (%s)" % wm[0][:12]
    stray = own_commits(ctx.cache, base, ref)
    done = ported(ctx.suite, "HEAD")
    todo = [s for s in stray if s not in done]
    print("publish-members: %s %s - %d commit(s) %s, %d already ported here"
          % (m.repo, src, len(stray), what, len(stray) - len(todo)))
    for s in todo:
        patch = ctx.cache("format-patch", "-1", "--stdout", "--binary", s)
        patch = run(["git", "interpret-trailers", "--where", "end",
                     "--if-exists", "addIfDifferent", "--if-missing", "add",
                     "--trailer",
                     "%s: %s@%s" % (PORT_TRAILER, m.repo, s)],
                    cwd=ctx.suite.worktree, stdin=patch).stdout
        p = run(ctx.suite.argv("am", "-3", "--directory=" + m.name),
                stdin=patch, check=False)
        subj = ctx.cache("log", "-1", "--format=%s", s).strip()
        if p.returncode != 0:
            print("  CONFLICT %s %s\n%s\n  Resolve it, `git add` the files and "
                  "`git am --continue` (the %s trailer is already in the "
                  "message), or `git am --abort`; then run this again to port "
                  "the rest." % (s[:12], subj, _tail(p.stdout + p.stderr, 8),
                                 PORT_TRAILER))
            return 1
        print("  ported   %s %s" % (s[:12], subj))
    if todo:
        print("publish-members: open a pull request in the suite as usual; once "
              "it is on main, the next publish accepts %s's history" % m.repo)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(
        prog="publish-members.py",
        description="Publish suite members into their own repositories.")
    ap.add_argument("--suite", default=ROOT,
                    help="the suite repository (default: this tree)")
    ap.add_argument("--url-template",
                    default=os.environ.get("XTALK_PUBLISH_URL_TEMPLATE", DEFAULT_URL),
                    help="member repository URL; {repo} is owner/name and "
                         "{name} the member (default %(default)s)")
    ap.add_argument("--cache", help="bare cache repository for fetched member "
                    "refs (default <git-common-dir>/xtalk-publish)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("status", "publish"):
        p = sub.add_parser(name)
        p.add_argument("--members", nargs="*", help="members, or `all` (default)")
        p.add_argument("--commit", help="suite commit to publish (default: "
                       "the tip of --main)")
        p.add_argument("--main", help="the suite branch whose first-parent "
                       "line is published (default origin/main, else main)")
        p.add_argument("--adopt", nargs="*", help="members whose repository "
                       "the suite may write for the first time")
        p.add_argument("--accept-divergence", nargs="*", help="members whose "
                       "unported commits may be replaced by the suite's tree")
        p.add_argument("--check-push", action="store_true", help="refuse any "
                       "member whose repository the credentials in use may not "
                       "push to (a dry-run push, which writes nothing)")
        if name == "publish":
            p.add_argument("--dry-run", action="store_true",
                           help="plan and report; push nothing")
    p = sub.add_parser("port")
    p.add_argument("member")
    p.add_argument("--ref", help="the ref to port from (default: the "
                   "repository's default branch; e.g. pull/7/head)")
    args = ap.parse_args(argv)
    args.suite = os.path.abspath(args.suite)
    if args.cmd == "port":
        return cmd_port(args)
    return cmd_publish(args, dry_run=(args.cmd == "status" or args.dry_run))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
