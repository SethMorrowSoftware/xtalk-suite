#!/usr/bin/env bash
# android-run.sh - run one Android executable on a device or emulator.
#
#   XTALK_ANDROID_SERIAL=emulator-5554 bash tools/android-run.sh <executable> [args...]
#
# tools/build-android.sh calls it for each of a member's tests. It pushes
# the executable, and every .so beside it (the member's library, which the
# tests link, and datachannelxt's seams library), to a folder of its own under
# /data/local/tmp, runs it there with that folder as its library path and
# its temporary folder, prints what it printed, and exits with ITS exit
# status.
#
# Two details, each there for a reason (tools/test-android-run.py holds both
# against a fake adb; the release workflow's emulator lanes are where a real
# one is observed):
#
#   * The exit status comes back in a marker line, not from `adb shell`.
#     adb carries a command's exit status only through its shell protocol,
#     which arrived with Android 7.0; before it, adbd reports 0 whatever the
#     command returned (DOCUMENTED; the 2026-11-18 run read every status from
#     the marker on a real API 21 device, all of them 0, so what adb itself
#     returns for a failing test there is still not observed). The release lane
#     boots an API 21 emulator, the floor these libraries are built for, so
#     trusting adb's status would pass every failing test on exactly the
#     oldest system. No marker at all (the device went away, the shell died)
#     is a failure.
#   * /data/local/tmp, because it is the folder the shell user may both
#     write to and execute from. There is no /tmp on Android; the tests'
#     own temporary paths follow TMPDIR (and say /data/local/tmp themselves
#     where they name a folder outright).
set -euo pipefail

if [ $# -lt 1 ]; then
  sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
: "${XTALK_ANDROID_SERIAL:?android-run: set XTALK_ANDROID_SERIAL to the adb serial to run on}"
ADB="${ADB:-adb}"
exe="$1"
shift
if [ ! -f "$exe" ]; then
  echo "android-run: $exe is not a file" >&2
  exit 2
fi

name="$(basename "$exe")"
# A folder per executable, emptied first: a library left by an earlier run
# must never be the one a test loads.
dir="/data/local/tmp/xtalk-$name"
adb_do() { "$ADB" -s "$XTALK_ANDROID_SERIAL" "$@"; }

adb_do shell "rm -rf '$dir' && mkdir -p '$dir'" > /dev/null
adb_do push "$exe" "$dir/$name" > /dev/null
for lib in "$(dirname "$exe")"/*.so; do
  [ -f "$lib" ] || continue
  adb_do push "$lib" "$dir/$(basename "$lib")" > /dev/null
done

# Each argument single-quoted for the device's shell.
quoted=""
for arg in "$@"; do
  quoted="$quoted '$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")'"
done

marker="XTALK_ANDROID_EXIT"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
adb_do shell "cd '$dir' && chmod 755 '$name' && TMPDIR='$dir' LD_LIBRARY_PATH='$dir' ./'$name'$quoted; echo $marker=\$?" \
  | tr -d '\r' | tee "$log" | grep -v "^$marker=" || true

status="$(sed -n "s/^$marker=//p" "$log" | tail -1)"
adb_do shell "rm -rf '$dir'" > /dev/null 2>&1 || true
if [ -z "$status" ]; then
  echo "android-run: $name: the device returned no exit status (did it go away?)" >&2
  exit 1
fi
if [ "$status" != "0" ]; then
  echo "android-run: $name exited $status on $XTALK_ANDROID_SERIAL" >&2
  exit "$status"
fi
