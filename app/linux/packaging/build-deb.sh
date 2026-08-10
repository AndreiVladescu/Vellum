#!/usr/bin/env bash
# Build vellum_<version>_amd64.deb from an already-built Linux release bundle.
#
#   flutter build linux --release
#   linux/packaging/build-deb.sh            # -> app/dist/vellum_1.0.0_amd64.deb
#
# Layout follows the FHS: the bundle is architecture-dependent private data, so
# it goes in /usr/lib/vellum, with a symlink on PATH. That symlink is all the
# user ever touches — `$ORIGIN/lib` and the engine's /proc/self/exe lookup both
# resolve to the real file, so `lib/` and `data/` stay where they are put.
#
# Dependencies are declared rather than bundled, which is the whole point of a
# .deb: apt refuses to install onto a machine that cannot run it, instead of
# letting it fail at launch. libsecret in particular is not installed by default
# everywhere, and flutter_secure_storage — where the server token lives — links
# it hard.
set -euo pipefail

APP_ID="app.vellum.Vellum"
APP="$(cd "$(dirname "$0")/../.." && pwd)"      # -> app/
BUNDLE="$APP/build/linux/x64/release/bundle"
ICONS="$APP/linux/packaging/icons/hicolor"

# `version: 1.0.0+1` in pubspec — Debian wants the part before the build number.
VERSION="$(sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' "$APP/pubspec.yaml")"
[ -n "$VERSION" ] || { echo "error: no version in pubspec.yaml" >&2; exit 1; }

[ -x "$BUNDLE/vellum" ] || {
  echo "error: $BUNDLE/vellum not found — run 'flutter build linux --release' first." >&2
  exit 1
}

OUT="$APP/dist"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/usr/lib/vellum" "$ROOT/usr/bin" \
         "$ROOT/usr/share/applications" "$ROOT/usr/share/icons" \
         "$ROOT/usr/share/doc/vellum" "$ROOT/DEBIAN"

cp -r "$BUNDLE/." "$ROOT/usr/lib/vellum/"
ln -s /usr/lib/vellum/vellum "$ROOT/usr/bin/vellum"
cp -r "$ICONS" "$ROOT/usr/share/icons/"

cat > "$ROOT/usr/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Vellum
Comment=Personal library manager
Exec=/usr/bin/vellum %f
Icon=$APP_ID
Terminal=false
Categories=Office;Literature;Education;
MimeType=application/pdf;application/epub+zip;
StartupWMClass=$APP_ID
EOF

cp "$APP/../LICENSE" "$ROOT/usr/share/doc/vellum/copyright"

# Installed-Size is in kibibytes and is what apt reports before downloading.
SIZE="$(du -ks "$ROOT/usr" | cut -f1)"

cat > "$ROOT/DEBIAN/control" <<EOF
Package: vellum
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Maintainer: Andrei Vladescu <avladescu2000@gmail.com>
Depends: libgtk-3-0 (>= 3.22), libsecret-1-0 (>= 0.18.4), libstdc++6, zlib1g
Homepage: https://github.com/AndreiVladescu/Vellum
Description: Personal library manager for digital and physical books
 Vellum shows your library as a visual bookshelf: you browse your books
 spine-out, the way they look on a real shelf, instead of scrolling a grid
 of covers. It reads PDF and EPUB, tracks physical copies and loans, and
 works entirely offline.
 .
 An optional server can sync a library between devices, but the application
 is complete without it and contacts nothing by default.
EOF

# Refresh the icon and desktop caches after install/remove. Both are
# best-effort: a machine without the tools still gets a working application,
# just a stale menu until the next login.
cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database -q /usr/share/applications || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 &&
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
fi
EOF
cat > "$ROOT/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] || [ "$1" = purge ]; then
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database -q /usr/share/applications || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 &&
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
fi
EOF
chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"

mkdir -p "$OUT"
DEB="$OUT/vellum_${VERSION}_amd64.deb"
# --root-owner-group so the contents are owned by root without needing fakeroot
# or building as root.
dpkg-deb --root-owner-group --build "$ROOT" "$DEB" >/dev/null

echo "built $DEB"
dpkg-deb --info "$DEB" | sed -n '2,8p'
