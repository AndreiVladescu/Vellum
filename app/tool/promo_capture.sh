#!/usr/bin/env bash
#
# Promo screenshots and clip: plays integration_test/promo_tour.dart against a
# fresh copy of the demo library (tool/demo_library.sh) and films it.
#
#   tool/promo_capture.sh                  # on the current X display ($DISPLAY)
#   tool/promo_capture.sh --headless       # in a private Xvfb (drafts only)
#   tool/promo_capture.sh --no-video       # screenshots only
#   tool/promo_capture.sh --only shelf,room  # rehearse some scenes
#   PROMO_WINDOW=1280x800 tool/promo_capture.sh
#   PROMO_CLIP=shelf,scroll,book,reader,pages,room tool/promo_capture.sh
#                                          # only these scenes in the clip
#   tool/promo_capture.sh --recut <capture dir>   # cut its clip again (say
#                                          # with another PROMO_CLIP or
#                                          # PROMO_LAG_MS) without refilming
#
# WHAT COMES OUT — in $VELLUM_DEMO_HOME/captures/<date>-<commit>/ (default
# ~/.cache/vellum-demo), never in the repository:
#
#   shots/NN-<scene>.png   one per scene, rendered by the app itself at the
#                          window's size and device pixel ratio
#   vellum-promo.mp4       the clip: each scene's moving part, joined (H.264)
#   vellum-promo.webm      the same, smaller, for the README (VP9, loops)
#   vellum-promo.gif       the same as a GIF, for places a video cannot go
#   raw.mkv                the whole recording, uncut
#   scenes.json, tour.log
#
# THE DISPLAY
#
# The recording is ffmpeg's x11grab of the app's window, so it needs an X
# server: an X11 session, or --headless. (On a Wayland session the app runs
# under XWayland, and grabbing XWayland's root records black.) The window is
# resized to PROMO_WINDOW (default 1600x1000) from outside with wmctrl, which
# needs a window manager; --headless starts metacity in its Xvfb for that.
# Xvfb's GL is software, so frame pacing there is rough: --headless is for
# judging composition, the real captures are made on a real display. Keep the
# screen awake and unlocked — a compositor starves a window it cannot show.
#
# SAFETY: the app runs with XDG_DATA_HOME and XDG_CONFIG_HOME pointed at the
# capture's own copy of the demo library and VELLUM_NO_KEYRING=1 (so the real
# app's keyring, and its server token, are never touched); the tour refuses any
# library the demo seeder did not make, and never signs in to a server. Nothing
# is left running when the script ends.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR=$PWD

FLUTTER=${FLUTTER:-flutter}
DEMO_HOME=${VELLUM_DEMO_HOME:-$HOME/.cache/vellum-demo}
WINDOW=${PROMO_WINDOW:-1600x1000}
FPS=${PROMO_FPS:-30}

headless=
video=1
only=
recut=
while [ $# -gt 0 ]; do
  case "$1" in
    --headless) headless=1 ;;
    --no-video) video= ;;
    --only) only=$2; shift ;;
    --recut) recut=$2; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

say() { printf '\n== %s\n' "$*"; }

# The clip: each scene's span cut out of the recording and joined, then the
# README's smaller copies. PROMO_CLIP picks the scenes; PROMO_LAG_MS shifts
# every span later by how far the window's picture trails the app's clock —
# a frame or two on a real GPU, over a second under Xvfb's software GL.
make_clip() {
  local run=$1 t0 filter
  say "cutting the clip (lag ${LAG_MS} ms)"
  t0=$(ffprobe -v error -show_entries format=start_time -of csv=p=0 "$run/raw.mkv")
  filter=$(jq -r --argjson t0 "$t0" --argjson lag "$LAG_MS" --arg keep "${PROMO_CLIP:-}" '
    def at(ms): ((ms + $lag) / 1000 - $t0) * 1000 | round / 1000;
    [.scenes[] | select($keep == "" or (.name as $n | $keep | split(",") | index($n)))] as $s
    | ([range(0; $s | length) as $i
        | "[0:v]trim=start=\(at($s[$i].start)):end=\(at($s[$i].end)),setpts=PTS-STARTPTS[v\($i)]"]
       | join(";"))
      + ";" + ([range(0; $s | length) as $i | "[v\($i)]"] | join(""))
      + "concat=n=\($s | length):v=1:a=0[cut]"' "$run/scenes.json")
  ffmpeg -loglevel error -y -i "$run/raw.mkv" -filter_complex "$filter;[cut]fps=$FPS[v]" \
    -map '[v]' -c:v libx264 -preset slow -crf 23 -maxrate 2800k -bufsize 5600k \
    -pix_fmt yuv420p -movflags +faststart "$run/vellum-promo.mp4"
  ffmpeg -loglevel error -y -i "$run/vellum-promo.mp4" \
    -vf "scale=960:-2:flags=lanczos,fps=24" -c:v libvpx-vp9 -b:v 0 -crf 40 \
    -row-mt 1 -an "$run/vellum-promo.webm"
  ffmpeg -loglevel error -y -i "$run/vellum-promo.mp4" -filter_complex \
    "fps=12,scale=720:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    -loop 0 "$run/vellum-promo.gif"
  for f in mp4 webm gif; do
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$run/vellum-promo.$f")
    echo "  vellum-promo.$f  $(du -h "$run/vellum-promo.$f" | cut -f1)  ${d%.*} s"
  done
}
for tool in jq wmctrl xwininfo; do
  command -v "$tool" > /dev/null || { echo "$tool is needed" >&2; exit 69; }
done
[ -z "$video" ] || command -v ffmpeg > /dev/null || { echo "ffmpeg is needed" >&2; exit 69; }
LAG_MS=${PROMO_LAG_MS:-${headless:+1400}}
LAG_MS=${LAG_MS:-0}

if [ -n "$recut" ]; then
  [ -s "$recut/raw.mkv" ] && [ -f "$recut/scenes.json" ] \
    || { echo "$recut has no raw.mkv and scenes.json to cut" >&2; exit 66; }
  make_clip "$recut"
  exit 0
fi

if [ ! -f "$DEMO_HOME/data/app.vellum.Vellum/demo-library.json" ]; then
  say "no demo library yet; building it"
  tool/demo_library.sh
fi

# ---- A capture directory, and a copy of the library to play with -------------
commit=$(git rev-parse --short HEAD)
RUN=$DEMO_HOME/captures/$(date +%Y%m%d-%H%M%S)-$commit
OUT=$RUN/out
mkdir -p "$RUN/xdg/config" "$OUT"
cp -a "$DEMO_HOME/data" "$RUN/xdg/data"
export XDG_DATA_HOME=$RUN/xdg/data
export XDG_CONFIG_HOME=$RUN/xdg/config
# The files are isolated by the two above; the OS keyring is not. This keeps
# the app away from it, so the real app's server token is never read (or, on a
# sign-out, deleted). The tour refuses to start without it.
export VELLUM_NO_KEYRING=1
export XDG_CACHE_HOME=$DEMO_HOME/xdg-cache
export LC_NUMERIC=C

BUNDLE=$APP_DIR/build/linux/x64/profile/bundle/vellum
cleanup() {
  [ -n "${FFMPEG_PID:-}" ] && kill -INT "$FFMPEG_PID" 2>/dev/null || true
  pkill -f "^$BUNDLE" 2>/dev/null || true
  [ -n "${WATCH_PID:-}" ] && kill "$WATCH_PID" 2>/dev/null || true
  [ -n "${WM_PID:-}" ] && kill "$WM_PID" 2>/dev/null || true
  [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" 2>/dev/null || true
  return 0
}
trap cleanup EXIT

if [ -n "$headless" ]; then
  XVFB=${XVFB:-Xvfb}
  command -v "$XVFB" > /dev/null || { echo "Xvfb not found (set XVFB=/path/to/Xvfb)" >&2; exit 69; }
  n=81; while [ -e "/tmp/.X11-unix/X$n" ]; do n=$((n + 1)); done
  # Room for the window and its title bar.
  w=${WINDOW%x*}; h=${WINDOW#*x}
  "$XVFB" ":$n" -screen 0 "$((w + 80))x$((h + 120))x24" -nolisten tcp \
    > "$RUN/xvfb.log" 2>&1 &
  XVFB_PID=$!
  for _ in $(seq 1 50); do [ -e "/tmp/.X11-unix/X$n" ] && break; sleep 0.1; done
  export DISPLAY=":$n" GDK_BACKEND=x11
  # No session bus: the app's media controls and notifications would otherwise
  # reach the desktop this runs beside. And no sound out of the player.
  export DBUS_SESSION_BUS_ADDRESS=unix:path=$RUN/no-such-bus
  export PULSE_SERVER=unix:$RUN/no-such-pulse PIPEWIRE_REMOTE=$RUN/no-such-pipewire
  metacity --display=":$n" --replace > "$RUN/wm.log" 2>&1 &
  WM_PID=$!
  sleep 1
  echo "headless: Xvfb on $DISPLAY with metacity (software GL — drafts only)"
elif [ -z "${DISPLAY:-}" ]; then
  echo "no DISPLAY: run on an X11 session or pass --headless" >&2
  exit 75
elif command -v xset > /dev/null && xset q 2>/dev/null | grep -q 'Monitor is Off'; then
  echo "the monitor is asleep; wake the screen (and unlock it) first" >&2
  exit 75
fi

# ---- The window: one size, found by the app's process id ---------------------
window_id() {
  local pid
  pid=$(pgrep -f "^$BUNDLE" | head -1 || true)
  [ -n "$pid" ] && wmctrl -lp | awk -v p="$pid" '$3==p {print $1; exit}'
}
(
  for _ in $(seq 1 900); do
    win=$(window_id || true)
    if [ -n "${win:-}" ]; then
      wmctrl -i -r "$win" -b remove,maximized_vert,maximized_horz
      wmctrl -i -r "$win" -e "0,0,0,${WINDOW%x*},${WINDOW#*x}"
      exit 0
    fi
    sleep 0.5
  done
) &
WATCH_PID=$!

# ---- The recording: started when the tour says it is ready -------------------
if [ -n "$video" ]; then
  (
    while [ ! -e "$OUT/ready" ]; do
      [ -e "$OUT/done" ] && exit 0
      sleep 0.2
    done
    win=$(window_id)
    geo=$(xwininfo -id "$win")
    x=$(awk '/Absolute upper-left X/ {print $4}' <<< "$geo")
    y=$(awk '/Absolute upper-left Y/ {print $4}' <<< "$geo")
    w=$(awk '/Width:/ {print $2}' <<< "$geo")
    h=$(awk '/Height:/ {print $2}' <<< "$geo")
    echo "recording ${w}x${h}+${x},${y} at $FPS fps" > "$RUN/record.txt"
    # Wall-clock timestamps, kept (-copyts), so the recording's own clock is
    # the one the tour's scene times are written in.
    ffmpeg -loglevel error -nostdin -f x11grab -use_wallclock_as_timestamps 1 \
      -framerate "$FPS" -video_size "${w}x${h}" -draw_mouse 0 \
      -i "$DISPLAY+$x,$y" -c:v libx264 -preset ultrafast -crf 12 \
      -pix_fmt yuv420p -copyts "$RUN/raw.mkv" 2> "$RUN/ffmpeg.log" &
    echo $! > "$RUN/ffmpeg.pid"
    for _ in $(seq 1 50); do
      [ -s "$RUN/raw.mkv" ] && break
      sleep 0.1
    done
    touch "$OUT/recording"
  ) &
fi

# ---- The tour ---------------------------------------------------------------
say "the tour ($WINDOW) — a window opens for a minute or two"
set +e
PROMO_OUT=$OUT PROMO_WINDOW=$WINDOW PROMO_RECORD=${video:+1} PROMO_ONLY=$only \
  "$FLUTTER" drive --profile -d linux \
  --driver test_driver/promo_driver.dart \
  --target integration_test/promo_tour.dart > "$RUN/tour.log" 2>&1
status=$?
set -e
grep -E 'PROMO_|All tests passed|Some tests failed|Exception' "$RUN/tour.log" || true
if [ -f "$RUN/ffmpeg.pid" ]; then
  FFMPEG_PID=$(cat "$RUN/ffmpeg.pid")
  kill -INT "$FFMPEG_PID" 2>/dev/null || true
  while kill -0 "$FFMPEG_PID" 2>/dev/null; do sleep 0.2; done
  FFMPEG_PID=
fi
[ "$status" -eq 0 ] && [ -f "$OUT/scenes.json" ] \
  || { echo "the tour did not finish; see $RUN/tour.log" >&2; exit 1; }
mv "$OUT/shots" "$RUN/shots"
cp "$OUT/scenes.json" "$RUN/scenes.json"

if [ -n "$video" ] && [ -s "$RUN/raw.mkv" ]; then
  make_clip "$RUN"
fi

say "done: $RUN"
ls "$RUN/shots"
