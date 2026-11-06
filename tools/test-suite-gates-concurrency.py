#!/usr/bin/env python3
"""test-suite-gates-concurrency.py - which suite-gates runs cancel which.

suite-gates.yml's `concurrency:` decides, for every run, which earlier run it
cancels: two runs cancel each other exactly when their group names match
(`cancel-in-progress: true`). The rule since 2026-11-06 (the comment above the
block says why):

  - a pull request's newer commit cancels that pull request's older run,
    and never another pull request's or main's;
  - a newer push to main cancels the older main run (publish-members.yml
    publishes the first-parent line up to the green run's commit, so the
    older commit is published with the newer one);
  - a dispatch is never cancelled, and never cancels anything.

The group is a GitHub Actions expression. This test reads it from the
workflow as written and evaluates it for each kind of event with a small
evaluator for the forms it uses (&&, ||, ==, format(), github.* and string
literals, with Actions' short-circuit values: `a && b` is a when a is falsy,
`a || b` is a when a is truthy), so a rewritten expression is held by what it
EVALUATES to, not by its spelling. A fixture first proves the evaluator
answers the old (pre-2026-11-06) expression the old way, so a blind
evaluator cannot pass the new one.

USAGE
    python3 tools/test-suite-gates-concurrency.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "suite-gates.yml")

# The expression before 2026-11-06: main never cancelled.
OLD = ("suite-gates-${{ github.event_name == 'pull_request' && "
       "format('pr-{0}', github.event.pull_request.number) || "
       "format('run-{0}', github.run_id) }}")


def read_concurrency(text):
    m = re.search(r"^concurrency:\n  group: (.+)\n  cancel-in-progress: (\w+)\n", text, re.M)
    if not m:
        sys.exit("FAIL: no top-level concurrency block with group and cancel-in-progress")
    return m.group(1).strip(), m.group(2)


TOKEN = re.compile(r"\s*(?:(\|\||&&|==|!=|\(|\)|,)|'((?:[^']|'')*)'|([A-Za-z_][\w.-]*))")


def tokens(expr):
    pos, out = 0, []
    while pos < len(expr):
        m = TOKEN.match(expr, pos)
        if not m or m.end() == pos:
            if expr[pos:].strip() == "":
                break
            raise ValueError("cannot read %r" % expr[pos:])
        op, lit, name = m.groups()
        out.append(("op", op) if op else ("str", lit.replace("''", "'")) if lit is not None
                   else ("name", name))
        pos = m.end()
    return out


def evaluate(expr, ctx):
    toks = tokens(expr)
    i = 0

    def peek():
        return toks[i] if i < len(toks) else (None, None)

    def take():
        nonlocal i
        i += 1
        return toks[i - 1]

    def primary():
        kind, val = take()
        if kind == "str":
            return val
        if kind == "op" and val == "(":
            v = orexpr()
            assert take() == ("op", ")")
            return v
        if kind == "name":
            if peek() == ("op", "("):
                take()
                args = [orexpr()]
                while peek() == ("op", ","):
                    take()
                    args.append(orexpr())
                assert take() == ("op", ")")
                if val != "format":
                    raise ValueError("unknown function " + val)
                fmt, rest = args[0], args[1:]
                return re.sub(r"\{(\d+)\}", lambda m: str(rest[int(m.group(1))]), fmt)
            cur = ctx
            for part in val.split("."):
                cur = cur.get(part) if isinstance(cur, dict) else None
            return cur
        raise ValueError("unexpected %r" % (val,))

    def compare():
        left = primary()
        while peek() in (("op", "=="), ("op", "!=")):
            op = take()[1]
            right = primary()
            left = (left == right) if op == "==" else (left != right)
        return left

    def andexpr():
        left = compare()
        while peek() == ("op", "&&"):
            take()
            right = compare()
            left = right if left else left
        return left

    def orexpr():
        left = andexpr()
        while peek() == ("op", "||"):
            take()
            right = andexpr()
            left = left if left else right
        return left

    v = orexpr()
    if i != len(toks):
        raise ValueError("trailing tokens in %r" % expr)
    return v


def group(template, ctx):
    return re.sub(r"\$\{\{(.*?)\}\}", lambda m: str(evaluate(m.group(1), ctx)), template)


def pr(number, run):
    return {"github": {"event_name": "pull_request", "ref": "refs/pull/%d/merge" % number,
                       "run_id": run, "event": {"pull_request": {"number": number}}}}


def push(run):
    return {"github": {"event_name": "push", "ref": "refs/heads/main", "run_id": run,
                       "event": {}}}


def dispatch(run, ref="refs/heads/main"):
    return {"github": {"event_name": "workflow_dispatch", "ref": ref, "run_id": run,
                       "event": {}}}


def main():
    failures = []

    def check(cond, what):
        if not cond:
            failures.append(what)

    # Fixture: the evaluator reads the old expression as it behaved.
    check(group(OLD, pr(7, 1)) == group(OLD, pr(7, 2)), "fixture: old, same PR shares a group")
    check(group(OLD, push(1)) != group(OLD, push(2)), "fixture: old, main runs never shared one")
    check(group(OLD, dispatch(1)) == "suite-gates-run-1", "fixture: old, dispatch by run id")

    with open(WORKFLOW, encoding="utf-8") as f:
        template, cancel = read_concurrency(f.read())
    check(cancel == "true", "cancel-in-progress is %s, expected true" % cancel)

    g = lambda ctx: group(template, ctx)  # noqa: E731
    check(g(pr(7, 1)) == g(pr(7, 2)), "a PR's newer commit must cancel its older run")
    check(g(pr(7, 1)) != g(pr(8, 2)), "one PR must never cancel another")
    check(g(push(1)) == g(push(2)), "a newer push to main must cancel the older main run")
    check(g(push(1)) != g(pr(7, 2)), "a PR must never cancel main, nor main a PR")
    check(g(dispatch(1)) != g(dispatch(2)), "dispatches must never cancel each other")
    check(g(dispatch(1)) != g(push(2)), "main must never cancel a dispatch on main")
    check(g(dispatch(5, "refs/heads/feature")) != g(pr(5, 6)), "a dispatch must never meet a PR")
    for ctx in (pr(7, 1), push(1), dispatch(1)):
        name = g(ctx)
        check(name.startswith("suite-gates-") and "None" not in name and "False" not in name,
              "group name %r for %s" % (name, ctx["github"]["event_name"]))

    if failures:
        for f in failures:
            print("FAIL: " + f)
        return 1
    print("OK: suite-gates concurrency (PR, main, dispatch) and its evaluator fixture")
    return 0


if __name__ == "__main__":
    sys.exit(main())
