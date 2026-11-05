# Contributing to the xTalk Suite

Thank you for helping. Bug reports, engine test runs on machines and
platforms we have not covered yet, documentation, examples and code are
all welcome. This is a small volunteer project: please be patient with
reviews, and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Where to contribute

**Here.** This repository is the development repository and the source
of truth for all eleven members. Each member is also published into its
own repository (`docs/MEMBER-REPO-SPLIT.md`); a pull request opened in
a member's repository is welcome too, and is ported back here before it
is published again.

For anything bigger than a small fix, open an
[issue](https://github.com/SethMorrowSoftware/xtalk-suite/issues) first
so we can talk about the idea.

## The one-minute orientation

- **[CLAUDE.md](CLAUDE.md)** at the root is the suite's working guide:
  the rules that hold across every member, the carried blocks, the
  gates and the generators. Each member's own `CLAUDE.md` adds to it
  and wins inside that member. Read both before you change a member.
- **[docs/README.md](docs/README.md)** indexes the suite documents:
  the engine notes (what the OXT engine really does), the engine-pass
  runbook, the work plan (all open work) and the owner decisions.
- **[README.md](README.md)** says what each member is and how far its
  testing has got.

## The rules that matter most

1. **Never call an xTalk handler from a foreign thread.** Events are
   queued and poll-drained on a timer.
2. **Nothing crosses the FFI as an exception.** Every `extern "C"` body
   catches everything and returns an error.
3. **Handles are generation-tagged integers**, so a stale one is a
   harmless no-op.
4. **The static gate is law for script.** Every `.livecodescript` and
   `.lcb` change must pass the member's `tools/check-livecodescript.py`
   (ASCII only, the `k`/`p`/`s`/`t` token-shadow trap, constants before
   use, and the rest).
5. **Edit the master, never a copy.** Carried blocks (the UI kit, the
   demo self-check, the harness scaffold, embedded libraries) have one
   master each; regenerate the copies with the tool CLAUDE.md names.
   `tests/suite-selftest.livecodescript` is generated: rebuild it with
   `python3 tools/build-suite-selftest.py`.
6. **The honesty convention.** Anything not observed on a real engine is
   labelled "verified statically; needs an OXT pass". A label is removed
   only for what a run exercised, and a doc must not understate a dated
   record either.

## Before you open a pull request

```sh
bash tools/build-all.sh --gates      # the compiler-free gates CI runs on every pull request
```

and, for a member you changed, its own `tools/run-gates.sh`. A change to
a native shim also needs the member's smoke test under ASan/UBSan, and a
change to a native library must refresh the committed binary under
`src/code/<arch>-<platform>/` in the same change (or leave it to the
`release-binaries` dispatch, which a maintainer runs).

If you ran something on a real OXT, OpenXTalk, LiveCode or OXT-Beyond
engine, say so in the pull request: which engine and version, which
platform and whether it was 32- or 64-bit, and what passed and failed.
An engine run is the evidence this project values most.

## Compatibility

The extensions are used by stacks people have already written. Do not
rename or remove a public handler, change what one returns for an input
that worked before, or change a package's id
(`org.openxtalk.library.*`, `org.openxtalk.box2dxt`). If a change would
alter what a script sees, make the new behaviour opt-in and say so in
the pull request.

## Licence of contributions

The suite is MIT licensed ([LICENSE](LICENSE)). By opening a pull
request you agree that your contribution is licensed under the MIT
licence. If you bring in third-party code, name its source and licence
in the pull request and add its notice to `LICENSE`.
