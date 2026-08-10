#!/usr/bin/env sh
# Install a desktop entry + themed icon for Vellum into the current user's
# ~/.local/share, so the Linux desktop (GNOME, Cinnamon, KDE, …) shows the
# Vellum logo in the title bar, window list, Alt-Tab and application menu —
# including when the app is started with `flutter run`.
#
# The window itself asks for the themed icon named after the application ID
# (see linux/runner/my_application.cc); this script is what puts that icon in
# the theme. Re-run it after `flutter build linux` if you move the build.
#
# Usage:  linux/install-dev.sh [debug|release]     (default: debug)
set -eu

MODE="${1:-debug}"
APP_ID="app.vellum.Vellum"

# Resolve paths relative to this script (linux/ -> app/).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
BIN="$APP_DIR/build/linux/x64/$MODE/bundle/vellum"
ICONS_SRC="$SCRIPT_DIR/packaging/icons/hicolor"

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
ICONS_DST="$DATA/icons/hicolor"
APPS_DST="$DATA/applications"

if [ ! -d "$ICONS_SRC" ]; then
  echo "error: $ICONS_SRC not found — run design/generate_icons.py first." >&2
  exit 1
fi
if [ ! -x "$BIN" ]; then
  echo "warning: $BIN not found — build it with 'flutter build linux --$MODE'." >&2
  echo "         Installing anyway; the .desktop Exec will point there." >&2
fi

# Icons: copy every size/scalable slot into the user's hicolor theme.
find "$ICONS_SRC" -type f | while read -r f; do
  rel="${f#"$ICONS_SRC"/}"
  mkdir -p "$ICONS_DST/$(dirname "$rel")"
  cp "$f" "$ICONS_DST/$rel"
done
echo "installed icons -> $ICONS_DST/.../apps/$APP_ID.*"

# Desktop entry. StartupWMClass must match the window's WM_CLASS instance so the
# shell associates the running window (and flutter-run's window) with this entry.
mkdir -p "$APPS_DST"
cat > "$APPS_DST/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Vellum
Comment=Personal library manager
Exec=$BIN
Icon=$APP_ID
Terminal=false
Categories=Office;
StartupWMClass=$APP_ID
EOF
echo "installed desktop entry -> $APPS_DST/$APP_ID.desktop"

# Refresh caches (best-effort; the desktop picks them up regardless).
gtk-update-icon-cache -f -t "$ICONS_DST" >/dev/null 2>&1 || true
update-desktop-database "$APPS_DST" >/dev/null 2>&1 || true

echo "done. If the icon doesn't appear immediately, restart the app (and for"
echo "GNOME Shell, Alt-F2 -> r; Cinnamon usually updates on next launch)."
