#!/usr/bin/env bash
# Build Vellum-<version>-x86_64.AppImage from an already-built release bundle.
#
#   flutter build linux --release
#   linux/packaging/build-appimage.sh
#
# An AppImage is one executable file: no extraction, no install, no root, and
# nothing for the user to keep together. That is the whole reason it exists here
# — `vellum`, `lib/` and `data/` are an implementation detail the moment they
# are inside the image.
#
# appimagetool is downloaded on first use unless APPIMAGETOOL points at one.
set -euo pipefail

APP_ID="com.avladescu.vellum"
APP="$(cd "$(dirname "$0")/../.." && pwd)"      # -> app/
BUNDLE="$APP/build/linux/x64/release/bundle"
ICONS="$APP/linux/packaging/icons/hicolor"
OUT="$APP/dist"

VERSION="$(sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' "$APP/pubspec.yaml")"
[ -n "$VERSION" ] || { echo "error: no version in pubspec.yaml" >&2; exit 1; }

[ -x "$BUNDLE/vellum" ] || {
  echo "error: $BUNDLE/vellum not found — run 'flutter build linux --release' first." >&2
  exit 1
}

APPDIR="$(mktemp -d)/Vellum.AppDir"
trap 'rm -rf "$(dirname "$APPDIR")"' EXIT
mkdir -p "$APPDIR/usr/lib/vellum" "$APPDIR/usr/share"

cp -r "$BUNDLE/." "$APPDIR/usr/lib/vellum/"
cp -r "$ICONS" "$APPDIR/usr/share/icons/"

# libsecret is not installed by default on every distribution, and
# flutter_secure_storage links it hard — a missing one is a failure to start,
# not a degraded feature. Bundling it beside the engine works without patching
# anything, because the executable already carries RUNPATH=$ORIGIN/lib.
#
# Only libsecret and its private crypto deps: glib, GTK and the X/Wayland stack
# are deliberately left to the host, which is the usual AppImage bargain —
# bundle what the base system may lack, borrow what it certainly has.
# Read the cache once. `awk ... exit` inside a pipeline closes it early, which
# under `set -o pipefail` fails the whole script with SIGPIPE; `sed -n 1p`
# drains its input instead.
LDCACHE="$(ldconfig -p)"
for soname in libsecret-1.so.0 libgcrypt.so.20 libgpg-error.so.0; do
  path="$(printf '%s\n' "$LDCACHE" \
    | awk -v s="$soname" '$1 == s && /x86-64/ {print $NF}' | sed -n 1p)"
  if [ -n "$path" ] && [ -e "$path" ]; then
    cp -L "$path" "$APPDIR/usr/lib/vellum/lib/"
    echo "bundled $soname"
  else
    echo "warning: $soname not found on this machine — not bundled" >&2
  fi
done

# AppRun is what the image runs. exec, so the app is PID 1 of the payload and
# signals reach it; $APPDIR is set by the runtime.
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/vellum/vellum" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# appimagetool requires the desktop file and icon at the AppDir root. Exec is
# the bare name by convention: the runtime rewrites it, and nothing outside the
# image ever reads this copy.
cat > "$APPDIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Vellum
Comment=Personal library manager
Exec=vellum %f
Icon=$APP_ID
Terminal=false
Categories=Office;Literature;Education;
MimeType=application/pdf;application/epub+zip;
StartupWMClass=$APP_ID
EOF
mkdir -p "$APPDIR/usr/share/applications"
cp "$APPDIR/$APP_ID.desktop" "$APPDIR/usr/share/applications/"
cp "$ICONS/256x256/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"
mkdir -p "$APPDIR/usr/share/metainfo"

TOOL="${APPIMAGETOOL:-}"
if [ -z "$TOOL" ]; then
  TOOL="$OUT/.appimagetool"
  if [ ! -x "$TOOL" ]; then
    mkdir -p "$OUT"
    echo "fetching appimagetool…"
    wget -q -O "$TOOL" \
      https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x "$TOOL"
  fi
fi

mkdir -p "$OUT"
IMAGE="$OUT/Vellum-$VERSION-x86_64.AppImage"
# --appimage-extract-and-run: appimagetool is itself an AppImage, and CI
# containers have no FUSE for it to mount itself with.
ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$IMAGE" >/dev/null 2>&1

chmod +x "$IMAGE"
echo "built $IMAGE ($(du -h "$IMAGE" | cut -f1))"
