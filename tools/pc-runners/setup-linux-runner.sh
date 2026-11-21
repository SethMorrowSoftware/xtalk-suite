#!/usr/bin/env bash
# tools/pc-runners/setup-linux-runner.sh - make the maintainer's Linux PC a
# GitHub Actions runner for this repository's own branches, without getting
# in the way of the person using it (docs/PC-RUNNERS.md).
#
#   sudo bash setup-linux-runner.sh OWNER/REPO REGISTRATION-TOKEN [INSTANCE]
#
# REGISTRATION-TOKEN comes from the repository's Settings > Actions > Runners
# > New self-hosted runner page (the --token value; it lapses after an hour).
# INSTANCE (default 1) lets one PC hold more than one runner for the same
# repository; every runner on the PC shares ONE CPU and memory budget (the
# ghrunner slice below), so a second one adds parallelism, not load.
# Running it again for the same OWNER/REPO and INSTANCE replaces that runner.
#
# What it sets up, and why:
#   - a system account `ghrunner` with no password and no sudo. Jobs are code
#     from a branch; they never get root on this computer.
#   - the toolchain the routed lanes ask for (PACKAGES), installed here as
#     root ONCE, and tools/pc-runners/sudo as the jobs' `sudo`, which answers
#     those lanes' install lines by checking the package is already present.
#   - the runner as a systemd service in ghrunner.slice: Nice 15, the batch
#     CPU scheduler and the idle I/O class, at most CPU_QUOTA of the CPUs and
#     MEMORY_MAX of the memory. A service has no display, so nothing a job
#     does can open a window on the desktop.
#   - two job hooks: one that refuses to start a job when the disk has less
#     than MIN_FREE_GB free (a red job beats a full disk), one that deletes
#     the job's checkout when it ends.
set -euo pipefail

# The packages the PC-routed lanes install (tools/check-pc-runner-lanes.py
# holds every routed lane's `sudo apt-get install` to this list), plus what
# GitHub's ubuntu-24.04 image has that those lanes use without installing.
PACKAGES=(
  build-essential gcc g++ make cmake ninja-build pkg-config autoconf automake libtool patch
  gcc-multilib g++-multilib
  libssl-dev libssl-dev:i386 zlib1g-dev zlib1g-dev:i386
  libboost-dev libtorrent-rasterbar-dev
  python3 python3-pip python3-venv python3-yaml
  git curl ca-certificates jq unzip zip xz-utils file gh
)
CPU_QUOTA=${CPU_QUOTA:-800%}      # 8 of this PC's 20 threads, for all its runners together
MEMORY_MAX=${MEMORY_MAX:-12G}
MIN_FREE_GB=${MIN_FREE_GB:-5}
HOME_DIR=/var/lib/ghrunner
LABELS=seth-pc

die() { echo "setup-linux-runner: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run it with sudo"
[ $# -ge 2 ] || die "usage: sudo bash $0 OWNER/REPO REGISTRATION-TOKEN [INSTANCE]"
REPO=$1 TOKEN=$2 INSTANCE=${3:-1}
[[ $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "OWNER/REPO looks wrong: $REPO"
[[ $INSTANCE =~ ^[0-9]+$ ]] || die "INSTANCE must be a number"
HERE=$(cd "$(dirname "$0")" && pwd)
[ -f "$HERE/sudo" ] || die "tools/pc-runners/sudo must sit beside this script"

free_gb=$(df -BG --output=avail /var/lib | tail -1 | tr -dc 0-9)
[ "$free_gb" -ge $((MIN_FREE_GB + 3)) ] ||
  die "only ${free_gb} GB free on /var/lib; free some space first (wanted $((MIN_FREE_GB + 3)) GB)"

echo "== toolchain"
dpkg --print-foreign-architectures | grep -qx i386 || dpkg --add-architecture i386
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends "${PACKAGES[@]}"

# ASan and TSan in GCC 13 crash at start-up with the kernel's 32 random mmap
# bits; GitHub's lanes lower it per job with sudo sysctl, which the stand-in
# sudo accepts only when it is already true.
echo "vm.mmap_rnd_bits = 28" > /etc/sysctl.d/60-ghrunner-sanitizers.conf
sysctl -q -w vm.mmap_rnd_bits=28

echo "== account"
if ! id ghrunner > /dev/null 2>&1; then
  useradd --system --create-home --home-dir "$HOME_DIR" --shell /bin/bash ghrunner
fi
passwd -l ghrunner > /dev/null
chmod 750 "$HOME_DIR"
install -d -o ghrunner -g ghrunner "$HOME_DIR/bin" "$HOME_DIR/hooks"
install -m 755 -o root -g root "$HERE/sudo" "$HOME_DIR/bin/sudo"

cat > "$HOME_DIR/hooks/job-started.sh" <<EOF
#!/usr/bin/env bash
free=\$(df -BG --output=avail "$HOME_DIR" | tail -1 | tr -dc 0-9)
if [ "\$free" -lt $MIN_FREE_GB ]; then
  echo "::error::The PC runner has only \${free} GB of disk free (it needs $MIN_FREE_GB); not starting, so the PC's disk is never filled."
  exit 1
fi
EOF
cat > "$HOME_DIR/hooks/job-completed.sh" <<'EOF'
#!/usr/bin/env bash
# The checkout and build tree go when the job ends: the PC's disk is shared
# with the person using it.
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "$GITHUB_WORKSPACE" ]; then
  rm -rf "${GITHUB_WORKSPACE:?}"/* "${GITHUB_WORKSPACE:?}"/.[!.]* 2> /dev/null || true
fi
EOF
chmod 755 "$HOME_DIR/hooks/"*.sh

echo "== the slice every runner on this PC shares"
cat > /etc/systemd/system/ghrunner.slice <<EOF
[Unit]
Description=GitHub Actions runners (low priority, shared budget)

[Slice]
CPUQuota=$CPU_QUOTA
CPUWeight=20
IOWeight=20
MemoryHigh=$MEMORY_MAX
MemoryMax=$MEMORY_MAX
EOF

echo "== runner"
release=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)
version=$(printf '%s' "$release" | jq -r .tag_name | sed 's/^v//')
asset="actions-runner-linux-x64-$version.tar.gz"
digest=$(printf '%s' "$release" | jq -r --arg n "$asset" '.assets[] | select(.name == $n) | .digest // empty')
[[ $digest == sha256:* ]] || die "the runner release did not publish a sha256 digest for $asset"
dir="$HOME_DIR/${REPO//\//-}-$INSTANCE"
name="$(hostname)-${REPO#*/}-$INSTANCE"

if [ -f "$dir/.service" ]; then
  echo "replacing the runner in $dir"
  (cd "$dir" && ./svc.sh stop && ./svc.sh uninstall) || true
fi
rm -rf "$dir"
install -d -o ghrunner -g ghrunner "$dir"
curl -fsSL -o "$dir/$asset" "https://github.com/actions/runner/releases/download/v$version/$asset"
echo "${digest#sha256:}  $dir/$asset" | sha256sum -c -
tar -xzf "$dir/$asset" -C "$dir"
rm "$dir/$asset"
chown -R ghrunner:ghrunner "$dir"
"$dir/bin/installdependencies.sh" > /dev/null

sudo -u ghrunner -H bash -c "cd '$dir' && ./config.sh --unattended --replace \
  --url 'https://github.com/$REPO' --token '$TOKEN' \
  --name '$name' --labels '$LABELS' --work _work"

# The jobs' environment: the stand-in sudo first, and the two hooks
printf '%s\n' "$HOME_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" > "$dir/.path"
cat >> "$dir/.env" <<EOF
ACTIONS_RUNNER_HOOK_JOB_STARTED=$HOME_DIR/hooks/job-started.sh
ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$HOME_DIR/hooks/job-completed.sh
EOF
chown ghrunner:ghrunner "$dir/.path" "$dir/.env"

(cd "$dir" && ./svc.sh install ghrunner)
unit=$(cat "$dir/.service")
install -d "/etc/systemd/system/$unit.d"
cat > "/etc/systemd/system/$unit.d/low-priority.conf" <<'EOF'
[Service]
Slice=ghrunner.slice
Nice=15
CPUSchedulingPolicy=batch
IOSchedulingClass=idle
EOF
systemctl daemon-reload
systemctl enable --now "$unit"
systemctl restart "$unit"
echo
echo "Done: $name is registered with $REPO under the labels self-hosted, Linux, X64, $LABELS."
echo "It takes jobs only once the repository variable PC_RUNNERS_LINUX is 'on'."
echo "Pause it:  sudo systemctl stop $unit    Resume: sudo systemctl start $unit"
