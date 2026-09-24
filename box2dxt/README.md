# Box2Dxt

[![build](https://github.com/SethMorrowSoftware/xtalk-suite/actions/workflows/native-box2dxt.yml/badge.svg)](https://github.com/SethMorrowSoftware/xtalk-suite/actions/workflows/native-box2dxt.yml)

**Real 2D physics for OpenXTalk and the xTalk family.** Box2Dxt packages the
[Box2D v3.1.0](https://box2d.org) engine as a drop-in extension for
**OpenXTalk (OXT)**, compatible with **LiveCode 9.6.3+**. You write plain xTalk;
your controls fall, roll, bounce, hinge and collide.

```livecodescript
on openCard
   b2kQuickStart                          -- world + gravity + walls + go
   b2kSpawnBall 200, 80, 50               -- create + drop a ball
   b2kSpawnBox 260, 80, 60, 40, "orange"  -- (read `the result` for the ref)
end openCard
on mouseDown ; get b2kGrab(the mouseH, the mouseV) ; end mouseDown
on mouseUp   ; b2kRelease ; end mouseUp
```

## How it's put together

```
Box2D v3.1.0 (fetched by CMake)
  -> C shim        src/box2d_lc.c                  -> libbox2dxt.{so,dylib,dll}
  -> LCB binding   src/box2dxt.lcb                 -> raw b2* API (metres, radians)
  -> the Kit       src/box2dxt-kit.livecodescript  -> friendly b2k* API
                   (pixels, degrees, control-backed bodies, render loop)
  -> examples/*.livecodescript                     -> self-contained demo stacks
```

- **The Kit (`b2k...`)** is what most users call: pixels, degrees, bodies bound
  to LiveCode controls and a loop that moves them, plus a game layer (keyboard
  input, sprites, a platformer controller, a scrolling camera, sound).
- **The extension (`b2...`)** is the Box2D v3.1 surface (376 handlers: bodies,
  shapes, joints, chains, sensors, queries, ray casts, events) in metres/radians.
- **Safety by design:** every handle is validated and generation-tagged in the
  C shim. Stale or invalid handles are harmless no-ops, never crashes.

## Quick start

1. **Install the extension:** open [`src/box2dxt.lcb`](src/box2dxt.lcb) in OXT's
   Extension Builder, click **Package**, and install the resulting `box2dxt.lce`.
   The native library is bundled inside (`src/code/<arch>-<platform>/`) and loads
   automatically: no separate download, no rename, no `sudo`, no `/usr/lib`.
2. **Sanity check:** `put b2Version()` in the Message Box should print `4`.
3. **Run a demo:** paste all of
   [`examples/box2dxt-demo.livecodescript`](examples/box2dxt-demo.livecodescript)
   into a stack script and reopen the card.

The step-by-step version (with troubleshooting) is
[docs/getting-started.md](docs/getting-started.md).

## Examples

Each is one file that embeds a copy of the Kit: paste it into a stack script.

- [**Demo**](examples/box2dxt-demo.livecodescript) - six interactive scenes,
  from a Newton's cradle to a drivable car and a ray-cast lidar.
- [**Contraption builder**](examples/box2dxt-contraption-builder.livecodescript) -
  the flagship physics sandbox: fans, magnets, lasers, bombs, motors, save/load.
- [**Platformer**](examples/box2dxt-platformer.livecodescript) - the Game Kit
  pushed hard: seven scrolling levels (Green Hills to the vertical Stone Keep),
  a full player controller (run, double-jump, wall-jump, dash, duck, climb,
  swim, drop-through, platform carry), a bestiary (bats, a mimic, piranhas, a
  ghost, a kickable snail shell, rising serpents, crushers, spinners), joints,
  coin tiers, gems and a hidden star, five-heart health, a title screen with
  character select, transition cards, an art HUD and synthesized audio.
- [**Slingshot**](examples/box2dxt-slingshot.livecodescript) - catapult
  cannonballs into toppling towers (three levels, aim preview, zero assets).
- [**Self-test harness**](examples/box2dxt-selftest.livecodescript) - proves the
  whole Kit on *your* machine in one click; run it first on any new platform.
- [**Game Kit spike**](examples/box2dxt-spike-gamekit.livecodescript) - the
  hardware-acceptance checks (keyboard, sprites, camera, performance).

## Documentation

**Most people want the Kit:** start at [getting-started.md](docs/getting-started.md),
then [kit-guide.md](docs/kit-guide.md), the longest doc and the one most need.

| Doc | What's in it |
|-----|--------------|
| **The Kit** | |
| [Getting started](docs/getting-started.md) | Zero to a draggable scene, plus troubleshooting. Assumes no physics knowledge. |
| [Kit guide](docs/kit-guide.md) | The friendly `b2k...` layer taught start to finish: bodies, joints, events, sensors, input, sprites, the player controller, the camera, sound, a whole-game pattern. |
| [Kit reference](docs/kit-reference.md) | The `b2k...` handlers as quick-lookup tables: all 313, the internal helpers gathered at the end (complete since 2026-09-24; `tools/check-reference-docs.py` holds it). |
| **The raw binding** | |
| [API reference](docs/api-reference.md) | The low-level `b2...` extension surface: all 376 public handlers, including every per-joint accessor (complete since 2026-09-24; `tools/check-reference-docs.py` holds it). |
| [Architecture](docs/architecture.md) | The three layers, handles, units, the ABI, and how to extend the binding. |
| [Building](docs/building.md) | Compile the native library yourself, package a release zip. Most users can skip it: the per-platform binaries are committed. |
| **Maintainers** | |
| [CLAUDE.md](CLAUDE.md) | Maintainer memory: the rules, the numbered OXT gotchas, the performance playbook, the engine evidence ledger. |
| [CHANGELOG.md](CHANGELOG.md) | Release history. |

Suite-wide documents live in the xTalk suite's
[docs index](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md).

## Building from source

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBOX2DXT_BUILD_TESTS=ON
cmake --build build --config Release
ctest --test-dir build --output-on-failure
```

CMake fetches Box2D v3.1.0 automatically. The suite's CI builds and
smoke-tests Linux (x86-64 and i686, manylinux2014), macOS (universal) and
Windows (x64 and x86) on every push; see [docs/building.md](docs/building.md).
The committed Linux and Windows libraries come from the suite's
`release-binaries.yml` dispatch (Linux 2026-08-27, Windows DLLs 2026-09-12):
the x86-64 Linux one keeps the glibc 2.17 floor, but the 32-bit `x86-linux` one
(built on a stock Ubuntu 24.04 runner) requires glibc 2.34. The `universal-mac`
dylib is byte-identical to what both release dispatches built (2026-08-27 and
2026-09-12: the installer reported it unchanged, so git shows no commit for
it); no Mac has loaded it.

## Contributing

The Kit is the single source of truth: after editing
`src/box2dxt-kit.livecodescript`, run `python3 tools/sync-embedded-kit.py` and
commit the re-synced examples in the same change. `bash tools/run-gates.sh`
runs this member's gates, the same script CI runs: the script checker,
embedded-Kit drift (`sync-embedded-kit.py --check`), the FFI signature gate
(`check-lcb-signatures.py`), the reference-page gate (`check-reference-docs.py`:
every public handler named in `docs/`), `package-extension.py --check` (no
empty platform slot) and the `src/code/MANIFEST.sha256` check. `audit-platformer.py` runs
beside them but is **advisory** (it prints findings and never exits non-zero).
Maintainer rules: [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE). Box2D itself is also MIT, (c) Erin Catto.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

Box2Dxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`box2dxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/Box2Dxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `box2dxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port box2dxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
