#!/usr/bin/env python3
"""test-publish-members.py - fixtures for publish-members.py, driven the way
the workflow drives it.

The publisher writes to eleven repositories that are not this one, so the
place to find out that it replays the wrong tree, force-pushes, or waves a
diverged repository through is here, over throwaway repositories, and not
in somebody's member repository after a merge. Every case runs the tool's
REAL command line as a subprocess against a synthetic suite and bare
`file://` member repositories - the root CLAUDE.md's rule that a gate is
exercised the way the build runs it, not the way its docstring describes
it - and each refusal is required to FIRE and to leave the repository it
refused untouched. The scenario is sequential on purpose, because
publishing is: adopt, extend, diverge, port, publish over the port, accept.

Git runs under a throwaway global config (GIT_CONFIG_GLOBAL), so a
contributor's commit.gpgsign or push.negotiate cannot change what the
fixtures see - the publisher must not depend on either, and this proves it
does not.

    python3 tools/test-publish-members.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "publish-members.py")
SUITE_REPO = "SethMorrowSoftware/xtalk-suite"

RESULTS = []


def check(label, ok, detail=""):
    RESULTS.append(ok)
    print("  %s %s" % ("ok  " if ok else "FAIL", label))
    if not ok and detail:
        print("       " + str(detail).replace("\n", "\n       ")[:3000])


class Env(object):
    def __init__(self, tmp):
        self.tmp = tmp
        cfg = os.path.join(tmp, "gitconfig")
        with open(cfg, "w") as fh:
            fh.write("[init]\n\tdefaultBranch = main\n"
                     "[user]\n\tname = Fixture\n\temail = fixture@example.invalid\n")
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=cfg, GIT_CONFIG_NOSYSTEM="1",
                        GIT_TERMINAL_PROMPT="0")
        for k in ("GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS",
                  "XTALK_PUBLISH_URL_TEMPLATE",
                  "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME",
                  "GIT_COMMITTER_EMAIL", "GIT_DIR", "GIT_WORK_TREE"):
            self.env.pop(k, None)
        self.suite = os.path.join(tmp, "suite")
        self.mirrors = os.path.join(tmp, "mirrors")

    def sh(self, args, cwd=None, stdin=None, check=True):
        p = subprocess.run(args, cwd=cwd, env=self.env, input=stdin,
                           capture_output=True, text=True)
        if check and p.returncode != 0:
            raise SystemExit("fixture setup failed: %s\n%s%s"
                             % (" ".join(args), p.stdout, p.stderr))
        return p

    def git(self, repo, *args, **kw):
        flag = ("--git-dir=" + repo) if repo.endswith(".git") else None
        argv = ["git", flag] if flag else ["git", "-C", repo]
        return self.sh(argv + list(args), **kw).stdout.strip()

    def tool(self, *args, mirrors=None, suite=None, env=None):
        tmpl = "file://%s/{name}.git" % (mirrors or self.mirrors)
        argv = [sys.executable, TOOL, "--suite", suite or self.suite,
                "--url-template", tmpl] + list(args)
        if args and args[0] in ("status", "publish") and "--main" not in args:
            argv += ["--main", "main"]
        p = subprocess.run(argv, env=dict(self.env, **(env or {})),
                           capture_output=True, text=True)
        return p.returncode, p.stdout + p.stderr

    # --- building blocks ----------------------------------------------
    def write(self, rel, text, repo=None):
        path = os.path.join(repo or self.suite, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(text)

    def commit(self, msg, repo=None):
        repo = repo or self.suite
        self.git(repo, "add", "-A")
        self.git(repo, "commit", "-q", "--no-gpg-sign", "-m", msg)
        return self.git(repo, "rev-parse", "HEAD")

    def bare(self, name, base=None):
        path = os.path.join(base or self.mirrors, name + ".git")
        self.sh(["git", "init", "-q", "--bare", "-b", "main", path])
        return path

    def head(self, bare):
        p = self.sh(["git", "--git-dir=" + bare, "rev-parse", "--verify", "-q",
                     "refs/heads/main"], check=False)
        return p.stdout.strip() or None

    def tree(self, rev, bare=None, path=None):
        if bare:
            return self.git(bare, "rev-parse", rev + "^{tree}")
        return self.git(self.suite, "rev-parse", "%s:%s" % (rev, path))

    def trailers(self, bare, key="Suite-Commit"):
        out = self.git(bare, "log", "--first-parent",
                       "--format=%(trailers:key=" + key +
                       ",valueonly,separator=%x2C)", "main")
        return [l for l in out.split("\n")]

    def stray(self, bare, rel, text, msg):
        """A commit made in a member repository directly."""
        work = os.path.join(self.tmp, "work-%d" % len(os.listdir(self.tmp)))
        self.sh(["git", "clone", "-q", "file://" + bare, work])
        self.write(rel, text, repo=work)
        sha = self.commit(msg, repo=work)
        self.git(work, "push", "-q", "origin", "HEAD:main")
        return sha


def race(e, bare, trigger, name):
    """A `git` shim that, the first time the publisher runs `git <trigger>`,
    first pushes a racer's commit to `bare`, then hands over to the real git.
    Returns (the racer's commit, the PATH that puts the shim first)."""
    real = shutil.which("git")
    racer = os.path.join(e.tmp, name)
    e.sh(["git", "clone", "-q", "file://" + bare, racer])
    e.write("RACE.txt", "pushed while the publisher ran\n", repo=racer)
    sha = e.commit("Pushed mid-publish", repo=racer)
    fakebin = os.path.join(e.tmp, name + "-bin")
    os.makedirs(fakebin)
    with open(os.path.join(fakebin, "git"), "w") as fh:
        fh.write('#!/bin/sh\nfor a in "$@"; do\n'
                 '  if [ "$a" = %s ] && [ ! -e "%s/.raced" ]; then\n'
                 '    : > "%s/.raced"\n'
                 '    "%s" -C "%s" push -q origin HEAD:main || exit 99\n'
                 '    break\n  fi\ndone\nexec "%s" "$@"\n'
                 % (trigger, racer, racer, real, racer, real))
    os.chmod(os.path.join(fakebin, "git"), 0o755)
    return sha, fakebin + os.pathsep + e.env["PATH"]


def refuse(e, name, verb, text):
    """A `git` shim that fails every `git <verb>` the way GitHub fails it -
    `text` on stderr, exit 128 - and hands everything else to the real git.
    file:// repositories cannot refuse credentials, so this is how the
    fixtures meet a token that may not push, read, or touch workflow files.
    Returns the PATH that puts the shim first."""
    real = shutil.which("git")
    fakebin = os.path.join(e.tmp, name + "-bin")
    os.makedirs(fakebin)
    msg = os.path.join(fakebin, "stderr.txt")
    with open(msg, "w") as fh:
        fh.write(text)
    with open(os.path.join(fakebin, "git"), "w") as fh:
        fh.write('#!/bin/sh\nfor a in "$@"; do\n'
                 '  if [ "$a" = %s ]; then cat "%s" >&2; exit 128; fi\n'
                 'done\nexec "%s" "$@"\n' % (verb, msg, real))
    os.chmod(os.path.join(fakebin, "git"), 0o755)
    return fakebin + os.pathsep + e.env["PATH"]


def build_suite(e):
    s = e.suite
    e.sh(["git", "init", "-q", "-b", "main", s])
    e.write("README.md", "suite\n")
    e.write("sodiumxt/README.md", "sodium v1\n")
    e.write("onionxt/README.md", "onion v1\n")
    # nostrxt is in the suite but its repository does not exist yet - the
    # state enetxt and NostrXT were in on 2026-09-22.
    e.write("nostrxt/README.md", "nostr v1\n")
    c1 = e.commit("Assemble the suite")
    e.write("README.md", "suite, root only\n")
    c2 = e.commit("Root-only change")
    e.git(s, "checkout", "-q", "-b", "feature")
    e.write("sodiumxt/src/a.txt", "a\n")
    f1 = e.commit("sodiumxt: add a")
    e.write("onionxt/src/x.txt", "x\n")
    f2 = e.commit("onionxt: add x")
    e.git(s, "checkout", "-q", "main")
    e.git(s, "merge", "-q", "--no-ff", "--no-gpg-sign", "feature", "-m",
          "Merge pull request #5 from SethMorrowSoftware/feature\n\n"
          "Add a to sodiumxt and x to onionxt")
    merge = e.git(s, "rev-parse", "HEAD")
    e.write("sodiumxt/src/a.txt", "a, tightened\n")
    c4 = e.commit("Tighten a (#6)")
    return dict(c1=c1, c2=c2, f1=f1, f2=f2, merge=merge, c4=c4)


def main():
    tmp = tempfile.mkdtemp(prefix="publish-members-fixtures-")
    try:
        return scenario(Env(tmp))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def scenario(e):
    c = build_suite(e)
    os.makedirs(e.mirrors)
    sod = e.bare("sodiumxt")
    oni = e.bare("onionxt")
    # onionxt's repository has a pre-suite history of its own.
    pre = os.path.join(e.tmp, "pre")
    e.sh(["git", "init", "-q", "-b", "main", pre])
    e.write("old.txt", "pre-suite\n", repo=pre)
    old = e.commit("Pre-suite history", repo=pre)
    e.git(pre, "push", "-q", "file://" + oni, "main")

    # --- status and the adoption gate -------------------------------------
    rc, out = e.tool("status", "--members", "sodiumxt", "onionxt", "nostrxt")
    check("status: the never-published and the missing are reported, not refused",
          rc == 0 and out.count("not adopted") == 2 and "unreachable" in out
          and "replays 3 commit(s) into the empty repository" in out, out)
    rc, out = e.tool("publish", "--members", "sodiumxt")
    check("publish without --adopt never writes a repository the suite has "
          "not written before", rc == 0 and e.head(sod) is None, out)

    # --- adopt an empty repository ----------------------------------------
    rc, out = e.tool("publish", "--members", "sodiumxt", "--adopt", "sodiumxt")
    head1 = e.head(sod)
    marks = e.trailers(sod)
    check("adopt: the empty repository receives the three states main held "
          "that changed sodiumxt/, newest first",
          rc == 0 and marks == [c["c4"], c["merge"], c["c1"]], (rc, out, marks))
    check("adopt: every published commit holds exactly the suite's sodiumxt/ tree",
          all(e.tree("main~%d" % i, bare=sod) == e.tree(s, path="sodiumxt")
              for i, s in enumerate([c["c4"], c["merge"], c["c1"]])))
    msg = e.git(sod, "log", "-1", "--format=%B", "main~1")
    check("a merge publishes as its pull request's title, linked into the suite, "
          "listing only that pull request's commits to this member",
          msg.startswith("Add a to sodiumxt and x to onionxt (%s#5)" % SUITE_REPO)
          and "sodiumxt: add a (%s@%s)" % (SUITE_REPO, c["f1"][:12]) in msg
          and "onionxt: add x" not in msg, msg)
    subj = e.git(sod, "log", "-1", "--format=%s", "main")
    check("a squash-merge's (#N) names the suite, not this repository",
          subj == "Tighten a (%s#6)" % SUITE_REPO, subj)
    author = e.git(sod, "log", "-1", "--format=%an <%ae> %ad", "main")
    check("the suite commit's authorship is kept",
          author == e.git(e.suite, "log", "-1", "--format=%an <%ae> %ad", c["c4"]),
          author)

    rc, out = e.tool("publish", "--members", "sodiumxt")
    check("a second run is a no-op: up to date, nothing pushed",
          rc == 0 and "up to date" in out and e.head(sod) == head1, out)

    again = os.path.join(e.tmp, "mirrors-again")
    os.makedirs(again)
    sod2 = e.bare("sodiumxt", base=again)
    e.tool("publish", "--members", "sodiumxt", "--adopt", "sodiumxt",
           mirrors=again)
    check("publishing is a pure function of the suite: a second empty "
          "repository gets byte-identical commits", e.head(sod2) == head1,
          (e.head(sod2), head1))

    # --- adopt over a pre-suite history -------------------------------------
    rc, out = e.tool("publish", "--members", "onionxt", "--adopt", "onionxt")
    first = e.git(oni, "rev-list", "--reverse", "--first-parent", "main").split()
    check("adopt over a pre-suite history keeps it: the first published commit "
          "sits on the repository's old head, and the tree is the suite's",
          rc == 0 and first[0] == old and e.git(oni, "rev-parse", first[1] + "^")
          == old and e.tree("main", bare=oni) == e.tree(c["c4"], path="onionxt"),
          (rc, out))
    check("the first published commit says where the pre-suite history ends",
          "The first commit the xTalk suite" in
          e.git(oni, "log", "-1", "--format=%B", first[1]))

    same = os.path.join(e.tmp, "mirrors-same")
    os.makedirs(same)
    sm = e.bare("sodiumxt", base=same)
    held = e.git(e.suite, "commit-tree", "--no-gpg-sign",
                 e.tree(c["c4"], path="sodiumxt"), "-m", "Synced by hand")
    e.git(e.suite, "push", "-q", "file://" + sm, held + ":refs/heads/main")
    rc, out = e.tool("publish", "--members", "sodiumxt", "--adopt",
                     "sodiumxt", mirrors=same)
    check("adopting a repository that already holds the suite's tree lands ONE "
          "commit carrying the watermark, not a rewind and replay",
          rc == 0 and e.git(sm, "rev-list", "--count", "main") == "2"
          and e.git(sm, "rev-parse", "main^") == held
          and e.trailers(sm)[0] == c["c4"]
          and e.tree("main", bare=sm) == e.tree(c["c4"], path="sodiumxt"),
          (rc, out, e.trailers(sm)))
    rc, out = e.tool("publish", "--members", "sodiumxt", mirrors=same)
    check("... after which it is an adopted repository like any other",
          rc == 0 and "up to date" in out, out)

    # --- extend -----------------------------------------------------------
    e.write("sodiumxt/src/b.txt", "b\n")
    c5 = e.commit("sodiumxt: add b")
    e.write("README.md", "root again\n")
    c6 = e.commit("Root-only again")
    rc, out = e.tool("publish", "--members", "sodiumxt", "--dry-run")
    check("--dry-run plans and pushes nothing",
          rc == 0 and "would publish" in out and e.head(sod) == head1, out)
    rc, out = e.tool("publish", "--members", "sodiumxt")
    head2 = e.head(sod)
    check("an adopted repository is extended by a fast-forward of exactly the "
          "commits that changed the member",
          rc == 0 and e.git(sod, "rev-parse", head2 + "^") == head1
          and e.trailers(sod)[0] == c5 and e.tree("main", bare=sod)
          == e.tree(c6, path="sodiumxt"), (rc, out))

    rc, out = e.tool("publish", "--members", "sodiumxt", "--commit", c["c4"])
    check("an older target than the repository holds is a no-op, not a rewind",
          rc == 0 and "ahead" in out and e.head(sod) == head2, out)
    rc, out = e.tool("publish", "--members", "sodiumxt", "--commit", c["f1"])
    check("a commit that is not on main's first-parent line is refused",
          rc != 0 and "first-parent" in out and e.head(sod) == head2, out)

    # --- divergence, porting, publishing over the port ---------------------
    s1 = e.stray(sod, "src/c.txt", "c from outside\n", "Fix from an outside contributor")
    rc, out = e.tool("publish", "--members", "sodiumxt")
    check("a commit pushed to the member repository directly is REFUSED, "
          "named, with the port command, and left untouched",
          rc == 1 and "REFUSED" in out and s1[:12] in out
          and "publish-members.py port sodiumxt" in out and e.head(sod) == s1, out)

    rc, out = e.tool("port", "sodiumxt")
    ported = e.git(e.suite, "log", "-1", "--format=%(trailers:key=Mirror-Commit,valueonly)")
    check("port applies it under sodiumxt/, keeps its author, and stamps it "
          "with a Mirror-Commit trailer naming the repository and commit",
          rc == 0
          and os.path.isfile(os.path.join(e.suite, "sodiumxt", "src", "c.txt"))
          and ported == "SethMorrowSoftware/SodiumXT@" + s1
          and e.git(e.suite, "log", "-1", "--format=%s") ==
          "Fix from an outside contributor", (rc, out, ported))
    rc, out = e.tool("port", "sodiumxt")
    check("porting again applies nothing twice",
          rc == 0 and "1 already ported" in out, out)

    rc, out = e.tool("publish", "--members", "sodiumxt")
    head3 = e.head(sod)
    tip = e.git(e.suite, "rev-parse", "main")
    check("once ported, the next publish lands as ONE commit over the outside "
          "commit, holding the suite's tree",
          rc == 0 and e.git(sod, "rev-parse", head3 + "^") == s1
          and e.tree("main", bare=sod) == e.tree(tip, path="sodiumxt")
          and "ported to the suite as" in e.git(sod, "log", "-1", "--format=%B", "main"),
          (rc, out))

    s2 = e.stray(sod, "README.md", "rewritten outside\n", "Web edit")
    rc, out = e.tool("publish", "--members", "sodiumxt", "--accept-divergence", "sodiumxt")
    check("--accept-divergence publishes the suite's tree over an unported "
          "commit and keeps that commit in history",
          rc == 0 and e.git(sod, "rev-parse", "main^") == s2
          and e.tree("main", bare=sod) == e.tree(tip, path="sodiumxt"), (rc, out))

    # --- refusals that must name their cause ------------------------------
    rc, out = e.tool("publish", "--members", "torrentxt", "--adopt", "torrentxt")
    check("a member absent from the suite at the target is refused",
          rc == 1 and "does not exist at" in out, out)

    hand = os.path.join(e.tmp, "mirrors-hand")
    os.makedirs(hand)
    h = e.bare("sodiumxt", base=hand)
    work = os.path.join(e.tmp, "hand-work")
    e.sh(["git", "init", "-q", "-b", "main", work])
    e.write("junk.txt", "not the suite's tree\n", repo=work)
    e.commit("Hand-written\n\nSuite-Commit: %s" % c["c1"], repo=work)
    e.git(work, "push", "-q", "file://" + h, "main")
    rc, out = e.tool("publish", "--members", "sodiumxt", mirrors=hand)
    check("a watermark commit that does not hold the suite's tree is refused",
          rc == 1 and "does not hold" in out, out)
    rc, out = e.tool("publish", "--members", "sodiumxt", "--accept-divergence",
                     "sodiumxt", mirrors=hand)
    check("... and --accept-divergence repairs it with the suite's tree",
          rc == 0 and e.tree("main", bare=h) == e.tree(tip, path="sodiumxt"), out)

    ghost = os.path.join(e.tmp, "mirrors-ghost")
    os.makedirs(ghost)
    g = e.bare("sodiumxt", base=ghost)
    e.write("junk.txt", "again\n", repo=work)
    e.commit("Ghost\n\nSuite-Commit: %s" % ("0123456789abcdef" * 3)[:40], repo=work)
    e.git(work, "push", "-q", "-f", "file://" + g, "main")
    rc, out = e.tool("publish", "--members", "sodiumxt", mirrors=ghost)
    check("a watermark naming a suite commit this history lacks is refused",
          rc == 1 and "does not have" in out, out)

    # A pull request opened on the member repository from an older publish,
    # which then merged the default branch into itself: its OWN commit is
    # the only thing to port. What came in with the merge is the publisher's
    # commits (the suite has them) and the web edit the owner accepted away
    # above (porting it would bring back what was deliberately discarded).
    prw = os.path.join(e.tmp, "pr-work")
    e.sh(["git", "clone", "-q", "file://" + sod, prw])
    e.git(prw, "checkout", "-q", "-b", "pr", head2)
    e.write("src/pr.txt", "from a pull request\n", repo=prw)
    pr_own = e.commit("Add pr.txt", repo=prw)
    e.git(prw, "merge", "-q", "--no-ff", "--no-gpg-sign", "origin/main",
          "-m", "Merge branch main into pr")
    e.git(prw, "push", "-q", "origin", "HEAD:refs/pull/9/head")
    before_readme = open(os.path.join(e.suite, "sodiumxt", "README.md")).read()
    rc, out = e.tool("port", "sodiumxt", "--ref", "pull/9/head")
    ported9 = e.git(e.suite, "log", "-1",
                    "--format=%(trailers:key=Mirror-Commit,valueonly)")
    check("porting a pull request that merged the default branch ports only "
          "its own commit - no publisher commit, no accepted-away web edit",
          rc == 0 and "1 commit(s) not on" in out
          and ported9 == "SethMorrowSoftware/SodiumXT@" + pr_own
          and os.path.isfile(os.path.join(e.suite, "sodiumxt", "src", "pr.txt"))
          and open(os.path.join(e.suite, "sodiumxt", "README.md")).read()
          == before_readme, (rc, out, ported9))

    e.write("sodiumxt/src/d.txt", "d\n")
    e.commit("sodiumxt: add d")
    hook = os.path.join(sod, "hooks", "pre-receive")
    with open(hook, "w") as fh:
        fh.write("#!/bin/sh\necho 'protected branch' >&2\nexit 1\n")
    os.chmod(hook, 0o755)
    before = e.head(sod)
    rc, out = e.tool("publish", "--members", "sodiumxt")
    check("a push the repository rejects is refused by its cause - here a "
          "protected branch - and moves nothing",
          rc == 1 and "branch protection" in out and e.head(sod) == before, out)
    os.remove(hook)

    # THE RACE, which is the only place a force-push would do harm: the
    # publisher builds on the head it just fetched, so a forced push and a
    # plain one are the same push - UNTIL somebody pushes to the repository
    # between that fetch and the publisher's push. A `git` shim on PATH
    # injects exactly that: on the publisher's push it first pushes a
    # racer's commit, then hands over to the real git. The publisher must be
    # refused and the racer's commit must still be the branch head.
    raced, path = race(e, sod, "push", "racer")
    rc, out = e.tool("publish", "--members", "sodiumxt", env={"PATH": path})
    check("a repository that moves mid-publish refuses the push and keeps "
          "the commit that moved it - nothing is ever force-pushed",
          rc == 1 and "moved while this ran" in out and e.head(sod) == raced,
          (rc, out))

    # The other window: a push landing between the publisher's look at the
    # repository (ls-remote) and its fetch. The publisher must judge the
    # head it FETCHED - so the newcomer is seen, as a commit the suite never
    # wrote - rather than replay onto the head it saw first and meet a
    # confusing refused push.
    fr = os.path.join(e.tmp, "mirrors-fetchrace")
    os.makedirs(fr)
    frm = e.bare("sodiumxt", base=fr)
    e.tool("publish", "--members", "sodiumxt", "--adopt", "sodiumxt",
           mirrors=fr)
    e.write("sodiumxt/src/e.txt", "e\n")
    e.commit("sodiumxt: add e")
    raced2, path = race(e, frm, "fetch", "racer2")
    rc, out = e.tool("publish", "--members", "sodiumxt", mirrors=fr,
                     env={"PATH": path})
    check("a push between the publisher's look and its fetch is judged as "
          "what it is - a commit the suite never wrote - on the head fetched",
          rc == 1 and "never wrote and never ported" in out
          and raced2[:12] in out and e.head(frm) == raced2, (rc, out))

    # --- the credentials, which a plan that only reads cannot test -------
    # 2026-09-23: a plan run read every repository (public: no token
    # needed), looked healthy, and the adoption after it was refused eleven
    # times by a token that could push nowhere - under a message blaming a
    # race. These are that day's refusals, in GitHub's own words.
    ck = os.path.join(e.tmp, "mirrors-creds")
    os.makedirs(ck)
    ckm = e.bare("sodiumxt", base=ck)
    rc, out = e.tool("status", "--members", "sodiumxt", "--check-push",
                     mirrors=ck)
    check("--check-push over credentials that may push leaves the plan as "
          "it was (an empty repository included)",
          rc == 0 and "not adopted" in out and e.head(ckm) is None, out)
    e.tool("publish", "--members", "sodiumxt", "--adopt", "sodiumxt",
           mirrors=ck)
    e.write("sodiumxt/src/f.txt", "f\n")
    e.commit("sodiumxt: add f")
    before = e.head(ckm)
    path = refuse(e, "denied", "push",
                  "remote: Permission to SethMorrowSoftware/SodiumXT.git denied "
                  "to SethMorrowSoftware.\nfatal: unable to access "
                  "'https://github.com/SethMorrowSoftware/SodiumXT.git/': The "
                  "requested URL returned error: 403\n")
    rc, out = e.tool("status", "--members", "sodiumxt", "--check-push",
                     mirrors=ck, env={"PATH": path})
    check("a plan run with --check-push refuses a member its credentials may "
          "not push to, and names the token's settings - before anything is "
          "adopted", rc == 1 and "dry-run push" in out
          and "may not push to" in out and "Contents and Workflows" in out
          and e.head(ckm) == before, out)
    rc, out = e.tool("publish", "--members", "sodiumxt", mirrors=ck,
                     env={"PATH": path})
    check("a real push refused for want of permission says so, and not that "
          "the repository moved", rc == 1 and "may not push to" in out
          and "moved while this ran" not in out and e.head(ckm) == before, out)
    path = refuse(e, "noworkflow", "push",
                  "To https://github.com/SethMorrowSoftware/SodiumXT.git\n"
                  "!\trefs/heads/main:refs/heads/main\t[remote rejected] "
                  "(refusing to allow a Personal Access Token to create or "
                  "update workflow `.github/workflows/gates.yml` without "
                  "`workflow` scope)\nDone\n")
    rc, out = e.tool("publish", "--members", "sodiumxt", mirrors=ck,
                     env={"PATH": path})
    check("a push refused over workflow files names the Workflows permission",
          rc == 1 and "Workflows: Read and write" in out
          and e.head(ckm) == before, out)
    path = refuse(e, "noread", "ls-remote",
                  "remote: Write access to repository not granted.\nfatal: "
                  "unable to access 'https://github.com/SethMorrowSoftware/"
                  "SodiumXT.git/': The requested URL returned error: 403\n")
    rc, out = e.tool("status", "--members", "sodiumxt", mirrors=ck,
                     env={"PATH": path})
    check("a read refused to credentials that were offered is a refusal that "
          "names the token, not 'unreachable'", rc == 1
          and "may not read" in out and "unreachable" not in out, out)
    rc, out = e.tool("publish", "--members", "sodiumxt", "--check-push",
                     mirrors=ck)
    check("... and once the credentials may push, --check-push publishes as "
          "before", rc == 0 and "published" in out and e.head(ckm) != before
          and e.trailers(ckm)[0] == e.git(e.suite, "rev-parse", "main"),
          (rc, out))

    # A Re-run replays a run's event with its inputs, so a run that did not
    # adopt never will; in Actions the tool says how to start one that does.
    gh = os.path.join(e.tmp, "mirrors-gh")
    os.makedirs(gh)
    e.bare("sodiumxt", base=gh)
    summ = os.path.join(e.tmp, "step-summary.md")
    rc, out = e.tool("publish", "--members", "sodiumxt", "--dry-run",
                     mirrors=gh, env={"GITHUB_ACTIONS": "true",
                                      "GITHUB_STEP_SUMMARY": summ})
    told = open(summ).read() if os.path.exists(summ) else ""
    check("in Actions, a member waiting to be adopted gets the step that "
          "adopts it, in the Run workflow form's words, in the log and the "
          "summary", rc == 0 and "::notice::" in out
          and "Members to ADOPT set to `sodiumxt`" in out
          and "Members to ADOPT set to `sodiumxt`" in told, (out, told))

    shallow = os.path.join(e.tmp, "shallow")
    e.sh(["git", "clone", "-q", "--depth", "2", "file://" + e.suite, shallow])
    rc, out = e.tool("publish", "--members", "sodiumxt", "--main", "origin/main",
                     suite=shallow)
    check("a shallow suite checkout is refused before anything is read",
          rc != 0 and "shallow" in out, out)

    bad = [r for r in RESULTS if not r]
    if bad:
        print("test-publish-members: %d FAILURE(S) of %d case(s)"
              % (len(bad), len(RESULTS)))
        return 1
    print("test-publish-members: OK (%d case(s): adopt, extend, no-op, "
          "determinism, divergence, port, accept, and every refusal fire the "
          "way the workflow runs the tool)" % len(RESULTS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
