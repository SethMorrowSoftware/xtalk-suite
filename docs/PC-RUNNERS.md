# The maintainer's PCs as CI runners

Since 2026-11-21 the short Linux and Windows lanes of the `native-<member>.yml` workflows can run
on self-hosted GitHub Actions runners on the maintainer's own two PCs, beside GitHub's machines.
OXT-Beyond routes its draft-check jobs the same way (its BUILDING.md, "Continuous integration"). This page is how
that works, what it can and cannot do, and how to turn it on, pause it or take it away.

## Why

On 2026-11-21 the account's GitHub-hosted queue was the bottleneck, not the builds: an extension's
Linux or Windows job did about 1 minute of work after 40 to 60 minutes in the queue, and an
OXT-Beyond Linux build spent about 200 of its 337 minutes waiting. The account runs about 20
GitHub-hosted jobs at once. Each PC runner adds one slot, so the raw gain is small; it counts because
the routed jobs are SHORT and numerous, so a PC slot turns over dozens of them an hour, and every
job it takes is one that no longer holds one of GitHub's machines. Long jobs (the OXT-Beyond engine
builds, coinxt's wallet gates) stay on GitHub's machines on purpose: a single PC slot would become
the new queue. The Mac lanes stay on GitHub's machines because no PC is a Mac.

## What may run there

`tools/test-pc-runner-lanes.py` holds all of this as written, in the suite gates:

- **Only `native-<member>.yml`.** No other workflow names a self-hosted runner: never
  `release-binaries.yml` (rule 5's committed libraries come only from GitHub's machines), never
  `publish-members.yml`, pages or the gates.
- **Only rows marked `pc:`.** `pc: linux` on an `ubuntu-24.04` row without a container (the 32-bit
  rows and the non-manylinux 64-bit rows), `pc: windows` on a `windows-2025` row that needs no
  vcpkg (`acquire: none`), and the static `sanitize` jobs.
- **Only this repository's own runs, and only while switched on.** A routed `runs-on` is one of two
  canonical expressions: a PC only when the repository variable `PC_RUNNERS_LINUX` (or
  `PC_RUNNERS_WINDOWS`) is `on` AND the run is a push, a dispatch, or a pull request whose head is
  this repository. A pull request from a fork always runs on GitHub's machines, so code from outside
  never reaches a PC. Every other case falls back to the label the job had before.
- **Only what the PC can run.** No containers, no Docker, no vcpkg; and every `sudo` line a routed
  Linux row would run is fed to the real stand-in `sudo` (below) over the setup script's package
  list, so a lane that starts installing something new fails the gates before it fails on the PC.

The published member repositories get the same `runs-on` lines through
`tools/sync-member-workflows.py`; no runner is registered there and the variables are unset, so
their lanes run on GitHub's machines as before.

## How a PC runner stays out of the way

The maintainer's rule (2026-11-21): CI must never pin either PC at 100%, and nothing may appear on
the screen. Both caps below are enforced by the operating system, not asked of the jobs.

| | Linux PC (`setup-linux-runner.sh`) | Windows PC (`setup-windows-runner.ps1`) |
|---|---|---|
| Account | system user `ghrunner`, no password, no sudo | `NT AUTHORITY\NETWORK SERVICE` |
| Windows on screen | none: a systemd service has no display | none: a boot task as NETWORK SERVICE runs in session 0 |
| CPU | a HARD cap: `CPUQuota` 800% (8 of 20 threads) for all runners together; Nice 15, batch scheduler | a HARD cap: `runner-cpu-cap.ps1` joins a job object of 25% of the CPU (a core and a half of 6; the PC is older, 2026-11-21) and only then starts the runner, so it and everything it starts are inside; if it cannot join, the runner does not start. Below Normal priority. Not a service: Windows would not let a cap take in a running service (2026-11-21) |
| Disk I/O | idle class | Low I/O priority |
| Memory | `MemoryMax` 12G for all runners together | 8 GB, in the same job object |
| Disk | a job does not start with under 5 GB free; its checkout is deleted when it ends | the same, 4 GB |

**No root for jobs.** The lanes were written for GitHub's machines, where `sudo apt-get install` is
free. On the Linux PC the setup script installs the toolchain once, as root, and the jobs' `sudo`
is `tools/pc-runners/sudo`: it answers `apt-get update`, `apt-get install` of packages already
installed, `dpkg --add-architecture i386` when already added and `sysctl -w vm.mmap_rnd_bits=N` when
already that low, and refuses everything else, loudly, naming the command.

## Turning it on

1. On the Linux PC, with about 15 GB free: `sudo bash tools/pc-runners/setup-linux-runner.sh
   SethMorrowSoftware/xtalk-suite <token>` (the token from the repository's Settings > Actions >
   Runners > New self-hosted runner, `--token` value; it lapses after an hour). A second runner for
   the same repository is the same command with `2` at the end; both share the one CPU and memory
   budget. Repeat with `SethMorrowSoftware/OpenXTalk-Beyond` and that repository's token.
2. On the Windows PC, in an elevated PowerShell: `powershell -ExecutionPolicy Bypass -File
   tools\pc-runners\setup-windows-runner.ps1 -Repo SethMorrowSoftware/xtalk-suite -Token <token>`.
3. In the repository's Settings > Secrets and variables > Actions > Variables, set
   `PC_RUNNERS_LINUX` and/or `PC_RUNNERS_WINDOWS` to `on`.
4. In Settings > Actions > General, keep "Require approval for all external contributors" (or
   stricter) for fork pull requests. The routing already keeps them off the PCs; this is the second
   lock.

## Pausing, and when a PC is off

A job routed to a PC waits for that PC: GitHub does not fall back by itself. Before a PC is turned
off for long, set its variable to anything but `on` (new runs then go to GitHub's machines; a run
already waiting can be re-run). To pause without that: `sudo systemctl stop 'actions.runner.*'` on
Linux, `Stop-ScheduledTask 'GitHub runner (capped)'` on Windows (ending the cap ends the runner), and
start them again the same way. On Windows, `C:\actions-runner\runner-cpu-cap.state` lists what the
cap holds, refreshed every 30 s, and `runner-cpu-cap.log` says when it started or why it would not.

## Taking it away

Set the variables off, then on each PC remove the runner (`./config.sh remove --token <token>` in
its folder, Linux under `/var/lib/ghrunner/`, Windows under `C:\actions-runner\`), and delete the
`pc:` rows and the routed `runs-on` lines here (the test then has nothing to hold).

## Status

Verified statically (the routing test and its fixtures, the stand-in `sudo` run over every routed
lane's install lines); no job has run on either PC yet. Both runners were registered on 2026-11-21.
On Windows the first design (a service, capped afterwards by a SYSTEM task) was refused by Windows
on every process, so the runner ran uncapped and jobs stayed switched off; the cap-starts-the-runner
design replaced it the same day. Observed on that PC (2026-11-21): the cap's log says it joined the
job, and its state file lists Runner.Listener inside it at 25% and 8 GB. No job has run under it yet,
so the cap has not been seen holding a build.
