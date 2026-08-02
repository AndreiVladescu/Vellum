#!/usr/bin/env sh
# Install Vellum from an extracted release tarball.
#
# Flutter ships a Linux app as three things that must stay together: the
# `vellum` executable, `lib/` next to it, and `data/` beside that. This script
# puts the set somewhere out of the way and leaves a single `vellum` on your
# PATH, so you never move those folders by hand.
#
# That works because the executable is linked with `RUNPATH=$ORIGIN/lib` and the
# engine finds `data/` relative to /proc/self/exe — both of which resolve
# through a symlink to the *real* file, not to the link. So a symlink in a bin
# directory is enough; no wrapper script, no LD_LIBRARY_PATH.
#
#   ./install.sh                 install for you alone, into ~/.local
#   sudo ./install.sh --system   install for everyone, into /usr/local
#   ./install.sh --prefix=DIR    install somewhere specific
#   ./install.sh --uninstall     remove it again (same flags as you installed)
set -eu

APP_ID="com.avladescu.vellum"
SRC="$(cd "$(dirname "$0")" && pwd)"

PREFIX="$HOME/.local"
UNINSTALL=no

for arg in "$@"; do
  case "$arg" in
    --system) PREFIX=/usr/local ;;
    --prefix=*) PREFIX="${arg#--prefix=}" ;;
    --uninstall) UNINSTALL=yes ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

LIBDIR="$PREFIX/lib/vellum"
BINDIR="$PREFIX/bin"
SHAREDIR="$PREFIX/share"
DESKTOP="$SHAREDIR/applications/$APP_ID.desktop"

refresh() {
  # Best-effort: the desktop picks both up on its own eventually, and neither
  # tool is guaranteed to exist.
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$SHAREDIR/applications" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 &&
    gtk-update-icon-cache -qtf "$SHAREDIR/icons/hicolor" 2>/dev/null || true
}

if [ "$UNINSTALL" = yes ]; then
  rm -rf "$LIBDIR"
  rm -f "$BINDIR/vellum" "$DESKTOP"
  find "$SHAREDIR/icons/hicolor" -name "$APP_ID.*" -delete 2>/dev/null || true
  refresh
  echo "Removed Vellum from $PREFIX."
  echo "Your library was NOT touched — it lives in"
  echo "  ~/.local/share/$APP_ID"
  echo "and stays there in case you reinstall. Delete it by hand if you meant to."
  exit 0
fi

[ -x "$SRC/vellum" ] || {
  echo "error: no 'vellum' executable beside this script." >&2
  echo "       Run install.sh from inside the extracted tarball." >&2
  exit 1
}

# Refuse to install into the directory we are reading from: the rm -rf below
# would delete the source mid-copy.
if [ "$SRC" = "$LIBDIR" ]; then
  echo "error: already installed at $LIBDIR — nothing to copy from." >&2
  exit 1
fi

echo "Installing Vellum to $LIBDIR"
rm -rf "$LIBDIR"
mkdir -p "$LIBDIR" "$BINDIR" "$SHAREDIR/applications"
# Everything except this script and the docs beside it — those are tarball
# furniture, not part of the app.
for item in "$SRC"/*; do
  case "$(basename "$item")" in
    install.sh|README.txt|share) continue ;;
  esac
  cp -r "$item" "$LIBDIR/"
done

ln -sfn "$LIBDIR/vellum" "$BINDIR/vellum"

if [ -d "$SRC/share/icons" ]; then
  mkdir -p "$SHAREDIR"
  cp -r "$SRC/share/icons" "$SHAREDIR/"
fi

# Exec is absolute rather than bare `vellum`: a user install puts the symlink in
# ~/.local/bin, which is not on PATH in every desktop session, and a menu entry
# that only sometimes works is worse than none.
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Vellum
Comment=Personal library manager
Exec=$BINDIR/vellum %f
Icon=$APP_ID
Terminal=false
Categories=Office;Literature;Education;
MimeType=application/pdf;application/epub+zip;
StartupWMClass=$APP_ID
EOF

refresh

echo "Installed."
echo "  run it:   $BINDIR/vellum"
echo "  or find 'Vellum' in your application menu"
case ":$PATH:" in
  *":$BINDIR:"*) echo "  ('vellum' on its own works — $BINDIR is on your PATH)" ;;
  *) echo
     echo "note: $BINDIR is not on your PATH, so plain 'vellum' will not work."
     echo "      Add it with:  echo 'export PATH=\"$BINDIR:\$PATH\"' >> ~/.profile"
     echo "      then log out and back in." ;;
esac
