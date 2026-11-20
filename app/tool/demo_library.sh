#!/usr/bin/env bash
#
# The demo library: a believable, entirely public-domain Vellum library for the
# README, the store listing and the promo screenshots/clip.
#
#   tool/demo_library.sh                 # download what is missing, then build
#   tool/demo_library.sh --lang ro       # the same, with the UI set to Romanian
#   tool/demo_library.sh --download-only # just fill the cache
#   tool/demo_library.sh --run           # build, then open the app on it
#
# WHAT IT MAKES
#
#   About eighty Standard Ebooks EPUBs (series, genres, descriptions), three
#   PDFs typeset from Standard Ebooks texts, a LibriVox audiobook part-way
#   through, shelves, reading states and ratings, highlights and notes, a year
#   and a half of reading sittings, a reading goal, physical copies with loans
#   (one overdue) and a furnished room. See lib/data/seed_demo.dart for the
#   story it tells and tool/demo_library/manifest.json for every source.
#
# WHERE THINGS GO — all outside the repository:
#
#   $VELLUM_DEMO_HOME (default ~/.cache/vellum-demo)
#     sources/            downloads, kept between runs (the cache)
#     data/               XDG_DATA_HOME for the app: data/app.vellum.Vellum/…
#     config/             XDG_CONFIG_HOME
#
# Rerunning deletes data/ and rebuilds it from sources/, so the library is
# always the same one (dates move with today, so "this week" is never empty).
#
# LICENCES
#
# Only standardebooks.org (CC0 productions of public-domain texts) and
# librivox.org / archive.org (public-domain recordings) are downloaded from.
# The manifest records each file's URL and licence; it is the list to cite.
#
# SAFETY
#
# The data directory must have "vellum-demo" in its path, and an existing one
# is only replaced when it carries the demo marker (data/.vellum-demo) — so
# pointing VELLUM_DEMO_HOME at a real library refuses instead of erasing it.
# VELLUM_NO_KEYRING=1 is set for everything this runs (and printed in the
# command to open the app): XDG_DATA_HOME isolates the files, not the OS
# keyring, which holds the real app's server token. The demo never signs in to
# a server.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR=$PWD
MANIFEST=$APP_DIR/tool/demo_library/manifest.json

FLUTTER=${FLUTTER:-flutter}
DEMO_HOME=${VELLUM_DEMO_HOME:-$HOME/.cache/vellum-demo}
SOURCES=$DEMO_HOME/sources
DATA=$DEMO_HOME/data
CONFIG=$DEMO_HOME/config
UA="vellum-demo-library/1.0"

lang=
download_only=
run=
while [ $# -gt 0 ]; do
  case "$1" in
    --lang) lang=$2; shift ;;
    --download-only) download_only=1 ;;
    --run) run=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

say() { printf '\n== %s\n' "$*"; }
command -v jq > /dev/null || { echo "jq is needed to read the manifest" >&2; exit 69; }

case "$DEMO_HOME" in
  *vellum-demo*) ;;
  *) echo "refusing: VELLUM_DEMO_HOME ($DEMO_HOME) must contain 'vellum-demo'" >&2; exit 77 ;;
esac

# ---- 1. Downloads, once ------------------------------------------------------
# Polite: one file at a time, a pause between requests, nothing fetched twice.
fetch() { # url dest
  local url=$1 dest=$2
  [ -s "$dest" ] && return 0
  mkdir -p "$(dirname "$dest")"
  echo "  get $(basename "$dest")"
  curl -fsSL --retry 3 --retry-delay 5 -A "$UA" -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
  sleep 0.5
}

say "sources ($SOURCES)"
while IFS=$'\t' read -r file url; do
  fetch "$url" "$SOURCES/epub/$file"
  # An EPUB is a zip; an HTML error page that slipped through is not.
  if ! unzip -tqq "$SOURCES/epub/$file" > /dev/null 2>&1; then
    echo "  $file is not a valid EPUB; deleting it — rerun to fetch it again" >&2
    rm -f "$SOURCES/epub/$file"
    exit 1
  fi
done < <(jq -r '.books[] | [.file, .url] | @tsv' "$MANIFEST")
while IFS=$'\t' read -r id file url; do
  fetch "$url" "$SOURCES/audio/$id/$file"
done < <(jq -r '.audio[] | .id as $id | .files[] | [$id, .file, .url] | @tsv' "$MANIFEST")
echo "  $(find "$SOURCES" -type f | wc -l) files, $(du -sh "$SOURCES" | cut -f1)"
[ -n "$download_only" ] && exit 0

# ---- 2. The library ----------------------------------------------------------
if [ -e "$DATA" ] && [ ! -e "$DATA/.vellum-demo" ]; then
  echo "refusing: $DATA exists and is not a demo library (no .vellum-demo marker)" >&2
  exit 77
fi
rm -rf "$DATA" "$CONFIG"
mkdir -p "$DATA" "$CONFIG"
touch "$DATA/.vellum-demo"

say "building the library in $DATA"
started=$(date +%s)
# The generated localizations are not checked in; a fresh checkout has none.
[ -f lib/l10n/gen/app_localizations.dart ] || "$FLUTTER" gen-l10n > /dev/null
# The seeder never needs the keyring; the switch makes sure nothing it calls
# could reach the real one (the seeder refuses to run without it).
export VELLUM_NO_KEYRING=1
DEMO_OUT=$DATA DEMO_SOURCES=$SOURCES DEMO_MANIFEST=$MANIFEST DEMO_LANG=$lang \
  "$FLUTTER" test test/tool/demo_seed_tool.dart --reporter expanded 2>&1 \
  | grep -E '^ *(demo:|Seeded)|Error|Exception|FAIL|failed' || true
[ -f "$DATA/app.vellum.Vellum/demo-library.json" ] \
  || { echo "the seeder did not finish; rerun with the flutter test command above to see why" >&2; exit 1; }
echo "  built in $(( $(date +%s) - started )) s"

if [ -n "$run" ]; then
  say "opening the app on the demo library"
  XDG_DATA_HOME=$DATA XDG_CONFIG_HOME=$CONFIG VELLUM_NO_KEYRING=1 "$FLUTTER" run -d linux
else
  echo
  echo "Open it with:"
  echo "  XDG_DATA_HOME=$DATA XDG_CONFIG_HOME=$CONFIG VELLUM_NO_KEYRING=1 flutter run -d linux"
fi
