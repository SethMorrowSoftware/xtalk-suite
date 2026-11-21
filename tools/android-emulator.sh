#!/usr/bin/env bash
# android-emulator.sh - boot the Android emulator the suite's Android tests
# run on, and wait until it can run them.
#
#   bash tools/android-emulator.sh start         # boots, waits, prints the serial
#   bash tools/android-emulator.sh start <api>   # the same, for another Android
#   bash tools/android-emulator.sh stop          # ...and waits until it is gone
#
# WHICH ANDROID. API 21 (Android 5.0), x86_64: the oldest Android the
# libraries are built for (tools/build-android.sh's ANDROID_API), on the
# one architecture a CI runner can run at speed (KVM runs an x86_64 guest
# on an x86_64 host; an ARM guest would be emulated instruction by
# instruction). Testing on the FLOOR is the point: a library that imports
# something Android 5.0 lacks loads on every newer Android and fails only
# there. The image is the one OXT-Beyond's own CI boots for its Android 5.0
# probe (android-engine.yml there), and its 64-bit system runs 32-bit x86
# programs too, so one emulator serves the x86_64-android and x86-android
# libraries. Nothing here runs an ARM library: those are built and checked,
# and say so (tools/build-android.sh's last line).
#
# ONE MEMBER HAS A FLOOR OF ITS OWN: torrentxt is built for API 24 (Android
# 7.0; tools/build-android.sh says why beside TORRENTXT_ANDROID_API), so its
# tests cannot load on the API 21 image. `start 24` boots the same kind of
# image for that Android, again the member's FLOOR. The API levels this
# script will boot are exactly the ones build-android.sh --pins names
# (tools/test-build-android.py compares them): any other is refused, so a
# typo cannot test on an Android nothing is built for. One emulator runs at
# a time, under one serial; stop the first before starting the second.
#
# It needs an Android SDK (ANDROID_HOME or ANDROID_SDK_ROOT) with its
# command-line tools, and /dev/kvm. What the SDK lacks of the emulator, the
# platform tools and the image, sdkmanager installs.
#
# start prints `serial <name>` as its last line; give that name to
# tools/build-android.sh as XTALK_ANDROID_SERIAL.
set -euo pipefail

APIS="21 24"
SERIAL="emulator-5554"
BOOT_MINUTES="${XTALK_ANDROID_BOOT_MINUTES:-10}"

case "${1:-}" in
  --apis)
    echo "apis $APIS"
    exit 0 ;;
  start|stop) : ;;
  *)
    sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2 ;;
esac

API="${2:-21}"
case " $APIS " in
  *" $API "*) : ;;
  *)
    echo "android-emulator: '$API' is not an Android this script boots ($APIS)" >&2
    exit 2 ;;
esac
IMAGE="system-images;android-$API;google_apis;x86_64"
AVD="xtalk-api$API"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  echo "android-emulator: no Android SDK (set ANDROID_HOME)" >&2
  exit 1
fi
ADB="$SDK/platform-tools/adb"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/xtalk-avd}"
LOG="$ANDROID_AVD_HOME/emulator.log"

if [ "$1" = "stop" ]; then
  "$ADB" -s "$SERIAL" emu kill > /dev/null 2>&1 || true
  # Gone is "adb no longer lists it", waited for: the next emulator takes the
  # same serial, and one started while this one still holds the port comes
  # up under another name that nothing here would find.
  deadline=$(( $(date +%s) + 120 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! "$ADB" devices 2> /dev/null | grep -q "^$SERIAL[[:space:]]"; then
      exit 0
    fi
    sleep 2
  done
  echo "android-emulator: $SERIAL is still there two minutes after it was told to stop" >&2
  exit 1
fi
if "$ADB" devices 2> /dev/null | grep -q "^$SERIAL[[:space:]]"; then
  echo "android-emulator: an emulator is already running as $SERIAL; stop it first" >&2
  exit 1
fi

# A hosted runner has KVM and gives it to root only; this is the rule
# GitHub documents for its Linux runners.
if [ ! -w /dev/kvm ] && [ -e /dev/kvm ] && command -v sudo > /dev/null; then
  echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
    sudo tee /etc/udev/rules.d/99-kvm4all.rules > /dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger --name-match=kvm
  sleep 1
fi
if [ ! -w /dev/kvm ]; then
  echo "android-emulator: /dev/kvm is not usable here; without it the emulator" >&2
  echo "  is too slow to boot in any time worth waiting for." >&2
  exit 1
fi

sm="$SDK/cmdline-tools/latest/bin/sdkmanager"
avdmanager="$SDK/cmdline-tools/latest/bin/avdmanager"
if [ ! -x "$sm" ] || [ ! -x "$avdmanager" ]; then
  echo "android-emulator: $SDK has no cmdline-tools/latest (sdkmanager, avdmanager)" >&2
  exit 1
fi
mkdir -p "$ANDROID_AVD_HOME"
(yes || true) | "$sm" --licenses > /dev/null 2>&1 || true
"$sm" --install "platform-tools" "emulator" "$IMAGE" > "$ANDROID_AVD_HOME/sdkmanager.log" 2>&1 ||
  { tail -40 "$ANDROID_AVD_HOME/sdkmanager.log" >&2; exit 1; }

echo no | "$avdmanager" create avd -n "$AVD" -k "$IMAGE" -d pixel_5 --force > /dev/null
"$ADB" start-server > /dev/null 2>&1
nohup "$SDK/emulator/emulator" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot \
  -gpu swiftshader_indirect -camera-back none -camera-front none > "$LOG" 2>&1 &

# Booted is `sys.boot_completed` = 1, asked of the device itself: adb lists
# an emulator as "device" well before its system can start a program.
deadline=$(( $(date +%s) + BOOT_MINUTES * 60 ))
booted=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  if ! pgrep -f "emulator.*-avd $AVD|qemu-system" > /dev/null; then
    echo "android-emulator: the emulator stopped while booting; the end of its log:" >&2
    tail -n 40 "$LOG" >&2
    exit 1
  fi
  booted=$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2> /dev/null | tr -d '\r' || true)
  if [ "$booted" = "1" ]; then
    break
  fi
  sleep 5
done
if [ "$booted" != "1" ]; then
  echo "android-emulator: not booted after $BOOT_MINUTES minutes; the end of its log:" >&2
  tail -n 40 "$LOG" >&2
  exit 1
fi

# The image must be the Android it was asked for: a renamed or substituted
# image would move the floor the tests stand on without a word.
api=$("$ADB" -s "$SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')
abis=$("$ADB" -s "$SERIAL" shell getprop ro.product.cpu.abilist | tr -d '\r')
echo "android-emulator: booted API $api, runs $abis"
if [ "$api" != "$API" ]; then
  echo "android-emulator: the image is API $api, not $API" >&2
  exit 1
fi
echo "serial $SERIAL"
