#!/usr/bin/env bash
#
# Drive the Android emulator headless, without ever leaving one running.
#
#   tool/emulator.sh boot <avd>              boot headless, wait until usable
#   tool/emulator.sh install [apk]           adb install -r (builds a debug APK
#                                            first when no path is given)
#   tool/emulator.sh shot <file.png>         screenshot of the running emulator
#   tool/emulator.sh run <avd> -- <cmd...>   boot, run <cmd>, ALWAYS shut down
#   tool/emulator.sh stop                    shut the emulator down
#   tool/emulator.sh status                  list running emulators / qemu
#
# AVDs on this machine: vellum_test (Pixel 6), vellum_tablet (Pixel Tablet),
# both Android 14 Google APIs x86_64. Inside `run`, the command can call
# `tool/emulator.sh install`, `shot`, `adb ...` freely; the emulator is gone
# when it exits, pass or fail.
#
# ONE EMULATOR AT A TIME. Another agent or session may be using it, so `boot`
# refuses while any emulator is attached and waits (EMU_WAIT seconds, default
# 300) for it to go away before giving up with exit 3. It never kills an
# emulator it did not start.
#
# Needs the Android SDK (ANDROID_HOME, default ~/Android/Sdk) and /dev/kvm.

set -euo pipefail

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
export PATH="$SDK/platform-tools:$SDK/emulator:$HOME/Documents/tools/flutter/bin:$PATH"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMU_WAIT="${EMU_WAIT:-300}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
LOG_DIR="${TMPDIR:-/tmp}"

die() { echo "emulator.sh: $*" >&2; exit "${2:-1}"; }

running_emulators() { adb devices 2>/dev/null | awk '/^emulator-/ && $2 == "device" {print $1}'; }

wait_until_free() {
  local waited=0
  while [ -n "$(running_emulators)" ] || pgrep -x 'qemu-system-x86' >/dev/null; do
    if [ "$waited" -ge "$EMU_WAIT" ]; then
      die "an emulator is already running ($(running_emulators | tr '\n' ' ')) and did not exit within ${EMU_WAIT}s; not touching it" 3
    fi
    [ "$waited" -eq 0 ] && echo "emulator busy; waiting up to ${EMU_WAIT}s..." >&2
    sleep 5
    waited=$((waited + 5))
  done
}

cmd_boot() {
  local avd="${1:-}"
  [ -n "$avd" ] || die "usage: boot <avd>"
  [ -e /dev/kvm ] || die "/dev/kvm is missing; see docs/ROADMAP.md (kvm_amd)"
  emulator -list-avds | grep -qx "$avd" || die "no AVD named '$avd' (have: $(emulator -list-avds | tr '\n' ' '))"
  wait_until_free
  adb start-server >/dev/null 2>&1 || true
  echo "booting $avd headless..."
  nohup emulator -avd "$avd" -no-window -no-audio -no-snapshot-save -no-boot-anim \
    -gpu swiftshader_indirect >"$LOG_DIR/emulator-$avd.log" 2>&1 &
  local pid=$! waited=0
  adb wait-for-device
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    kill -0 "$pid" 2>/dev/null || die "emulator exited while booting; see $LOG_DIR/emulator-$avd.log"
    if [ "$waited" -ge "$BOOT_TIMEOUT" ]; then
      cmd_stop
      die "boot did not finish within ${BOOT_TIMEOUT}s; see $LOG_DIR/emulator-$avd.log" 4
    fi
    sleep 3
    waited=$((waited + 3))
  done
  adb shell input keyevent 82 >/dev/null 2>&1 || true   # dismiss keyguard
  echo "$avd is up (${waited}s)"
}

cmd_install() {
  local apk="${1:-}"
  if [ -z "$apk" ]; then
    (cd "$APP_DIR" && flutter build apk --debug) || die "flutter build failed"
    apk="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
  fi
  [ -f "$apk" ] || die "no such APK: $apk"
  [ -n "$(running_emulators)" ] || die "no emulator running; boot one first"
  adb install -r "$apk"
}

cmd_shot() {
  local out="${1:-}"
  [ -n "$out" ] || die "usage: shot <file.png>"
  [ -n "$(running_emulators)" ] || die "no emulator running"
  adb exec-out screencap -p >"$out"
  echo "$out"
}

cmd_stop() {
  local e
  for e in $(running_emulators); do
    adb -s "$e" emu kill >/dev/null 2>&1 || true
  done
  local i
  for i in $(seq 1 30); do
    pgrep -x 'qemu-system-x86' >/dev/null || return 0
    sleep 1
  done
  die "qemu is still running after adb emu kill" 5
}

cmd_run() {
  local avd="${1:-}"
  [ -n "$avd" ] || die "usage: run <avd> -- <command...>"
  shift
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || die "usage: run <avd> -- <command...>"
  # Never stop an emulator we did not start: wait for the slot first, and
  # only then arm the trap (a busy refusal must not kill the other user's).
  wait_until_free
  trap 'cmd_stop || true' EXIT INT TERM
  cmd_boot "$avd"
  "$@"
}

case "${1:-}" in
  boot)    shift; cmd_boot "$@" ;;
  install) shift; cmd_install "$@" ;;
  shot)    shift; cmd_shot "$@" ;;
  stop)    cmd_stop ;;
  run)     shift; cmd_run "$@" ;;
  status)  echo "adb: $(running_emulators | tr '\n' ' ')"; pgrep -ax 'qemu-system-x86' || echo "no qemu" ;;
  *)       sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
