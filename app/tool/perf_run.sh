#!/usr/bin/env bash
#
# The profiling run: what is slow, measured the same way every time.
# docs/PERFORMANCE.md, "The profiling run", says what each number means.
#
#   tool/perf_run.sh                       # Linux desktop: GUI scenarios + cold starts
#   tool/perf_run.sh --android             # the same on the one connected device
#   tool/perf_run.sh --only gui|startup    # one half
#   tool/perf_run.sh --label before-fix    # name the run (kept in its directory name)
#   tool/perf_run.sh --headless            # Linux, in a nested X server (Xephyr)
#   tool/perf_run.sh diff <run A> <run B>  # compare two runs' summary.json
#
# WHAT IT DOES
#
#   1. Seeds a large library once and caches it: thousands of books, most with
#      covers (some the large PNG page renders old PDF imports left), half with
#      files, years of reading sessions, highlights, loans, a furnished room.
#      The shape comes from PERF_BOOKS, PERF_SESSIONS, ... (seed_profiling.dart).
#   2. Copies it into a fresh run directory, so every run starts from the same
#      library with no cover thumbnails made yet.
#   3. Runs integration_test/perf_test.dart under `flutter drive --profile`:
#      shelf first paint and scrolling (spines cold/warm/hot, covers, list),
#      opening a book, search typing, Reading insights + its range control +
#      the month page, the physical room's pan and zoom, Preferences — frame
#      times, jank, image cache and resident memory for each.
#   4. Builds integration_test/startup_probe.dart as the app and cold-starts it
#      PERF_STARTS times (the first is a warm-up and is not counted).
#   5. Writes summary.json and summary.md next to the raw results, and prints
#      the summary.
#
# WHERE THINGS GO — all outside the repository:
#
#   $VELLUM_PERF_HOME (default ~/.cache/vellum-perf)
#     seed-<key>/          the cached seeded library, keyed by its shape
#     runs/<date>-<commit>[-label]/
#       summary.md, summary.json, gui/, startup/, xdg/ (that run's library)
#     runs/latest          a link to the newest run
#
# THE DISPLAY MUST BE AWAKE
#
# A desktop compositor stops drawing a window it cannot show: with the monitor
# asleep or the screen locked, frames arrive about once a second and every GUI
# number is meaningless. The run checks for that before it starts and the
# report flags any scenario that got far fewer frames than its duration allows.
# --headless avoids the question by running in Xephyr — but Xephyr's GL is
# software (llvmpipe), so its *raster* times are the CPU's, not the GPU's:
# fine for comparing two builds, wrong for quoting as "the app's" raster cost.
# Build times, wall times and memory are unaffected.
#
# SAFETY
#
# The app is pointed at the run's own directory with XDG_DATA_HOME and
# XDG_CONFIG_HOME, so the real library under ~/.local/share is never opened —
# and both entry points refuse to start unless XDG_DATA_HOME is a profiling
# directory, so running them by hand cannot touch it either. Nothing is left
# running: the app is stopped on exit, however the script ends.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR=$PWD

FLUTTER=${FLUTTER:-flutter}
DART=${DART:-$(dirname "$(command -v "$FLUTTER")")/dart}
PERF_HOME=${VELLUM_PERF_HOME:-$HOME/.cache/vellum-perf}
STARTS=${PERF_STARTS:-6}
PACKAGE=app.vellum.Vellum

if [ "${1:-}" = diff ]; then
  shift
  exec "$DART" tool/perf_report.dart diff "$@"
fi

target=linux
only=all
label=
headless=
while [ $# -gt 0 ]; do
  case "$1" in
    --android) target=android ;;
    --headless) headless=1 ;;
    --only) only=$2; shift ;;
    --label) label=-$2; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

say() { printf '\n== %s\n' "$*"; }

# ---- 1. The seeded library, made once per shape -----------------------------
schema=$(grep -oE 'schemaVersion => [0-9]+' lib/data/database.dart | grep -oE '[0-9]+')
shape="books=${PERF_BOOKS:-} covers=${PERF_COVER_SHARE:-} png=${PERF_PNG_COVER_SHARE:-} \
files=${PERF_FILE_SHARE:-} sessions=${PERF_SESSIONS:-} annotations=${PERF_ANNOTATIONS:-} \
copies=${PERF_COPIES:-} loans=${PERF_LOANS:-} placed=${PERF_PLACED:-} seed=${PERF_SEED:-} \
schema=$schema"
key=$( (echo "$shape"; cat lib/data/seed_profiling.dart lib/data/seed_library.dart) \
  | sha1sum | cut -c1-10)
SEED=$PERF_HOME/seed-$key

if [ "$target" = linux ] && [ ! -f "$SEED/seed.json" ]; then
  say "seeding a profiling library ($shape) into $SEED"
  PERF_SEED_OUT=$SEED "$FLUTTER" test test/tool/perf_seed_tool.dart
fi

# ---- 2. A run directory of its own ------------------------------------------
commit=$(git rev-parse --short HEAD)
dirty=$(git status --porcelain --untracked-files=no | grep -q . && echo -dirty || true)
RUN=$PERF_HOME/runs/$(date +%Y%m%d-%H%M%S)-$commit$dirty$label
mkdir -p "$RUN"
ln -sfn "$RUN" "$PERF_HOME/runs/latest"
{
  echo "{\"commit\": \"$commit$dirty\", \"target\": \"$target${headless:+-headless}\","
  echo " \"date\": \"$(date -Iseconds)\", \"host\": \"$(uname -srm)\","
  echo " \"cpus\": $(nproc), \"load\": \"$(cut -d' ' -f1-3 /proc/loadavg)\","
  echo " \"flutter\": \"$("$FLUTTER" --version 2>/dev/null | head -1)\"}"
} > "$RUN/meta.json"

BUNDLE=$APP_DIR/build/linux/x64/profile/bundle/vellum
cleanup() {
  # Whatever happened, leave nothing running.
  pkill -f "$BUNDLE" 2>/dev/null || true
  if [ -n "${XEPHYR_PID:-}" ]; then kill "$XEPHYR_PID" 2>/dev/null || true; fi
  if [ "$target" = android ]; then adb shell am force-stop "$PACKAGE" 2>/dev/null || true; fi
}
trap cleanup EXIT

if [ "$target" = linux ]; then
  mkdir -p "$RUN/xdg/config"
  cp -a "$SEED/data" "$RUN/xdg/data"
  cp "$SEED/seed.json" "$RUN/seed.json"
  export XDG_DATA_HOME=$RUN/xdg/data
  export XDG_CONFIG_HOME=$RUN/xdg/config
  # Shared between runs on purpose: the GPU driver keeps its shader cache here,
  # and a cold shader cache in one run but not the next is noise, not signal.
  export XDG_CACHE_HOME=$PERF_HOME/xdg-cache
  # The engine writes timeline arguments with printf, which follows LC_NUMERIC:
  # under a decimal-comma locale ("0,5") the timeline no longer parses.
  export LC_NUMERIC=C
  DEVICE=linux
  if [ -n "$headless" ]; then
    # A display number nobody holds, and a screen the window fills exactly
    # (no window manager in there to resize it).
    n=77; while [ -e "/tmp/.X11-unix/X$n" ]; do n=$((n + 1)); done
    Xephyr ":$n" -screen 1280x720 -ac -br -noreset > "$RUN/xephyr.log" 2>&1 &
    XEPHYR_PID=$!
    for _ in $(seq 1 50); do [ -e "/tmp/.X11-unix/X$n" ] && break; sleep 0.1; done
    export DISPLAY=":$n" GDK_BACKEND=x11 PERF_WINDOW=1280x720
    echo "headless: Xephyr on $DISPLAY (software GL — see the note at the top)"
  elif command -v xset > /dev/null && xset q 2>/dev/null | grep -q 'Monitor is Off'; then
    echo "the monitor is asleep, so the compositor will starve the window of frames;" >&2
    echo "wake the screen (and unlock it) or use --headless" >&2
    exit 75
  fi
else
  serial=${ANDROID_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')}
  [ -n "$serial" ] || { echo "no Android device connected" >&2; exit 69; }
  DEVICE=$serial
  adb -s "$serial" shell getprop ro.product.model > "$RUN/device.txt"
fi

# ---- 3. The GUI scenarios -----------------------------------------------------
if [ "$only" != startup ]; then
  say "GUI scenarios on $DEVICE (a window will open for a few minutes)"
  if [ "$target" = linux ] && [ -z "$headless" ] && command -v wmctrl > /dev/null; then
    # One window size for every run (the test waits for it): how much of the
    # shelf a frame draws depends on it, and a window manager that maximises
    # one launch and not the next would otherwise decide the numbers. Found by
    # the app's process id, never by title — an editor can be called Vellum too.
    export PERF_WINDOW=${PERF_WINDOW:-1280x800}
    (
      for _ in $(seq 1 600); do
        pid=$(pgrep -f "^$BUNDLE" | head -1 || true)
        win=${pid:+$(wmctrl -lp | awk -v p="$pid" '$3==p {print $1; exit}')}
        if [ -n "${win:-}" ]; then
          wmctrl -i -r "$win" -b remove,maximized_vert,maximized_horz
          wmctrl -i -r "$win" -e "0,-1,-1,${PERF_WINDOW%x*},${PERF_WINDOW#*x}"
          exit 0
        fi
        sleep 0.5
      done
    ) &
  fi
  PERF_OUT=$RUN/gui "$FLUTTER" drive --profile -d "$DEVICE" \
    --driver test_driver/perf_driver.dart \
    --target integration_test/perf_test.dart \
    2>&1 | tee "$RUN/gui.log" | grep -E 'All tests passed|Some tests failed|Exception|Error' || true
  [ -f "$RUN/gui/metrics.json" ] || { echo "the GUI run reported nothing; see $RUN/gui.log" >&2; exit 1; }
fi

# ---- 4. Cold starts -----------------------------------------------------------
if [ "$only" != gui ]; then
  mkdir -p "$RUN/startup"
  : > "$RUN/startup.jsonl"
  if [ "$target" = linux ]; then
    say "building the start-up probe"
    "$FLUTTER" build linux --profile -t integration_test/startup_probe.dart > "$RUN/startup/build.log" 2>&1
    for i in $(seq 0 "$STARTS"); do
      VELLUM_PERF_LAUNCHED_AT=$(date +%s%6N) timeout 90 "$BUNDLE" \
        > "$RUN/startup/run-$i.log" 2>&1 || true
      line=$(grep -m1 '^VELLUM_PERF_STARTUP ' "$RUN/startup/run-$i.log" | cut -d' ' -f2- || true)
      if [ -z "$line" ]; then echo "  start $i: no result (see startup/run-$i.log)"; continue; fi
      echo "  start $i: $line"
      [ "$i" -gt 0 ] && echo "$line" >> "$RUN/startup.jsonl"
    done
  else
    say "building and installing the start-up probe"
    "$FLUTTER" build apk --profile -t integration_test/startup_probe.dart > "$RUN/startup/build.log" 2>&1
    adb -s "$serial" install -r build/app/outputs/flutter-apk/app-profile.apk > /dev/null
    for i in $(seq 0 "$STARTS"); do
      adb -s "$serial" shell am force-stop "$PACKAGE"
      sleep 1
      adb -s "$serial" logcat -c
      total=$(adb -s "$serial" shell am start -W -n "$PACKAGE/.MainActivity" \
        | awk -F': ' '/TotalTime/ {print $2}' | tr -d '\r')
      line=
      for _ in $(seq 1 60); do
        line=$(adb -s "$serial" logcat -d -s flutter:I | grep -m1 -o 'VELLUM_PERF_STARTUP .*' | cut -d' ' -f2- || true)
        [ -n "$line" ] && break
        sleep 0.5
      done
      if [ -z "$line" ]; then echo "  start $i: no result"; continue; fi
      line="${line%\}}, \"am_total_ms\": ${total:-null}}"
      echo "  start $i: $line"
      [ "$i" -gt 0 ] && echo "$line" >> "$RUN/startup.jsonl"
    done
  fi
fi

# ---- 5. The report ------------------------------------------------------------
say "summary ($RUN)"
"$DART" tool/perf_report.dart summarize "$RUN"
