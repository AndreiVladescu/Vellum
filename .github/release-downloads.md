
---

## Downloads

| | |
|---|---|
| **Linux** | `Vellum-*-x86_64.AppImage` — download, `chmod +x`, run |
| **Linux (Debian/Ubuntu)** | `vellum_*_amd64.deb` — `sudo apt install ./vellum_*.deb` |
| **Linux (other)** | `vellum-linux-x64.tar.gz` — extract, then `./install.sh` |
| **Windows** | `vellum-windows-x64.zip` |
| **macOS** | `vellum-macos.zip` (Apple Silicon) |
| **Android** | `app-release.aab` (Play), or the per-ABI `.apk` to sideload |
| **Server** | `vellum-server-<target>` for four targets, or `docker build .` |

The AppImage is a single file and needs no installation. The `.deb` and the
tarball's `install.sh` both put the app out of the way and leave one `vellum`
command on your PATH — you never move `lib/` or `data/` yourself.
`./install.sh --uninstall` reverses it.

**The desktop builds are unsigned.** macOS will refuse the first launch:
right-click the app and choose Open, or
`xattr -d com.apple.quarantine vellum.app`. Windows SmartScreen will warn;
choose *More info → Run anyway*. Check the `SHA256SUMS` beside each artefact if
you want to verify what you downloaded.
