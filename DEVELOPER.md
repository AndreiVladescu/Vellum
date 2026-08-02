# Developer guide

How to build, test and ship both halves of Vellum — the Flutter app and the Rust
server — on Linux, Windows and macOS.

If you only want to *use* Vellum, [README.md](README.md) is shorter and enough.
If you only want to *run the server*, [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
covers Docker, systemd, TLS and backups; this guide covers building it.

> **A note on the Windows sections.** Every command here is what
> [`.github/workflows/release.yml`](.github/workflows/release.yml) runs on a
> `windows-latest` runner for each tagged release, so it is exercised on every
> release — but this repository is developed on Linux, and the Windows steps have
> not been walked through by hand on a desktop. Where something is derived from
> the project's files rather than observed running, it says so.

---

## Contents

- [What you need](#what-you-need)
- [First build, ten minutes](#first-build-ten-minutes)
- [Building the app](#building-the-app)
  - [Linux](#app-linux) · [Windows](#app-windows) · [macOS](#app-macos) · [Android](#app-android)
- [Building the server](#building-the-server)
  - [Linux and macOS](#server-linux-and-macos) · [Windows](#server-windows) · [Docker](#server-docker) · [Static and cross builds](#static-and-cross-builds)
- [Deploying](#deploying)
- [The development loop](#the-development-loop)
- [Changing the schema](#changing-the-schema)
- [Cutting a release](#cutting-a-release)
- [Troubleshooting](#troubleshooting)

---

## What you need

You do not need both toolchains. The app and the server are independent: the app
is a complete product on its own, and the server is optional.

| To build | You need | Version |
|---|---|---|
| The app (any platform) | Flutter SDK | Dart **3.12.2** or newer (`environment: sdk: ^3.12.2`) |
| The app on Linux | clang, cmake, ninja, pkg-config, GTK 3, liblzma, libsecret | distribution packages |
| The app on Windows | Visual Studio 2022, *Desktop development with C++* | 2022 |
| The app on macOS | Xcode | from the App Store |
| The app for Android | JDK **17** and the Android SDK | Temurin 17 is what CI uses |
| The server | Rust, stable | via [rustup](https://rustup.rs) |
| The server on Windows | The same Visual Studio C++ workload | 2022 |
| The server as a container | Docker | any recent version |

**Both first builds need internet access**, and not only for packages:

- `pdfium_dart` runs a build hook that downloads a prebuilt PDFium from
  `github.com/bblanchon/pdfium-binaries`.
- `sqlite3` builds or fetches its own native library into `app/.dart_tool/lib/`.

A network that blocks GitHub releases will fail the build in a way that looks
like a compiler error. See [Troubleshooting](#troubleshooting).

---

## First build, ten minutes

```sh
git clone https://github.com/AndreiVladescu/Vellum.git
cd Vellum

# The app
cd app
flutter pub get
flutter run -d linux          # or: -d windows / -d macos

# The server, in another terminal
cd ../server
cargo run                     # http://localhost:3000
```

The first compile of either is slow — several minutes for Flutter's native
runner, and a few for the server's dependency tree. Everything after that is
incremental.

`flutter doctor` is the single most useful command when something is wrong. Only
the section for the platform you are building for has to be green; Android, web
and iOS warnings are irrelevant unless you want those targets.

---

## Building the app

### Common to every platform

```sh
cd app
flutter pub get                                            # dependencies
dart run build_runner build --delete-conflicting-outputs   # drift codegen
flutter gen-l10n                                           # localisation codegen
```

Both codegen outputs are **committed** so they are reviewable, and CI fails if
either is stale — so run them after touching `lib/data/database.dart` or the ARB
files. See [Changing the schema](#changing-the-schema).

`flutter run` is development mode: hot reload, assertions on, slow. For anything
you intend to keep, build in release.

<a name="app-linux"></a>
### Linux

**Install the toolchain** (Debian/Ubuntu; adapt for other distributions):

```sh
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
                 libsecret-1-dev
```

`libsecret-1-dev` is for `flutter_secure_storage`, which is where the server
token is kept. Leave it out and the build succeeds but signing in to a server
fails at runtime.

**Build:**

```sh
cd app
flutter build linux --release
```

**Output:** `app/build/linux/x64/release/bundle/` — run `./vellum` inside it.

**Keep the bundle whole.** The executable needs the `lib/` and `data/` folders
beside it; shipping the binary alone ships something that cannot start.

**Packaging it.** Three scripts in `app/linux/packaging/` turn that bundle into
something installable. Run them after `flutter build linux --release`; all three
write to `app/dist/`.

```sh
linux/packaging/build-appimage.sh   # Vellum-1.0.0-x86_64.AppImage
linux/packaging/build-deb.sh        # vellum_1.0.0_amd64.deb  (needs dpkg-deb)
linux/packaging/install.sh          # install this build for the current user
```

`install.sh` also ships inside the release tarball, which is how end users
install it: `--system` or `--prefix=DIR` to place it elsewhere, `--uninstall`
to reverse it.

All three rely on the same property, which is worth knowing before you change
them: the executable is linked with `RUNPATH=$ORIGIN/lib`, and the engine finds
`data/` relative to `/proc/self/exe`. Both resolve through a **symlink** to the
real file, so a link in `~/.local/bin` or `/usr/bin` is enough — no wrapper
script and no `LD_LIBRARY_PATH`. That is why the bundle can live in
`/usr/lib/vellum` and still be launched as plain `vellum`.

The AppImage additionally bundles `libsecret` next to the engine, where that
same `RUNPATH` picks it up: `flutter_secure_storage` links it hard, and not
every distribution installs it. The `.deb` declares it as a dependency instead,
so apt refuses to install onto a machine that cannot run it.

<a name="app-windows"></a>
### Windows

**1. Install Visual Studio 2022.** Not VS Code — the full Visual Studio, which
can be the free Community edition. In the installer, tick the
**"Desktop development with C++"** workload. This is what provides MSVC, the
Windows SDK and CMake; Flutter cannot build a Windows app without it.

**2. Install Flutter.** Follow
<https://docs.flutter.dev/get-started/install/windows/desktop>. In short: unzip
the SDK somewhere without spaces in the path (`C:\src\flutter` is the
convention — **not** `C:\Program Files\`, which needs elevation), then add
`C:\src\flutter\bin` to your `PATH` via *Settings → Edit environment variables
for your account*.

Open a **new** PowerShell window afterwards — `PATH` changes don't reach terminals
that were already running — and check:

```powershell
flutter --version
flutter doctor
```

`flutter doctor` must show a green tick for *Visual Studio - develop Windows
apps*. If it reports the workload as missing, reopen the Visual Studio Installer,
choose *Modify*, and confirm the C++ workload is actually ticked.

**3. Build:**

```powershell
cd Vellum\app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build windows --release
```

**Output:** `app\build\windows\x64\runner\Release\` — `vellum.exe` is inside it.

**Keep that folder whole too.** Alongside `vellum.exe` are `flutter_windows.dll`,
the plugin DLLs, `pdfium.dll` and a `data\` directory; the exe on its own will
not start. To hand it to someone else, zip the whole `Release` folder — which is
exactly what the release workflow does:

```powershell
Compress-Archive -Path build\windows\x64\runner\Release\* `
                 -DestinationPath dist\vellum-windows-x64.zip
```

**Running it from source instead**, for a debug session:

```powershell
flutter run -d windows
```

**What is different about Vellum on Windows.** Three plugins are Android-only, so
three features are absent rather than broken (verified from
`.flutter-plugins-dependencies`, which lists the platforms each plugin registers
for):

| Feature | On Windows |
|---|---|
| Barcode **camera** scanning (`mobile_scanner`) | Not available — the scan screen still accepts a typed ISBN, which is the desktop path anyway |
| Home-screen widget (`home_widget`) | Not available |
| Background scheduled backups (`workmanager`) | Not available; backups still run from Preferences, and on a schedule while the app is open |

Everything else — the readers, importers, sync, backups, physical rooms — is the
same code as on Linux.

**Where Windows keeps your data** (derived from `windows/runner/Runner.rc`, whose
`CompanyName` is `com.avladescu` and `ProductName` is `Vellum`, and from how
`path_provider_windows` builds the support directory):

| What | Where |
|---|---|
| Database | `%USERPROFILE%\Documents\vellum.sqlite` |
| Books, covers, settings | `%APPDATA%\com.avladescu\Vellum\` |

Note that this is *not* the same shape as Linux and macOS, which both use
`com.avladescu.vellum` as a single directory name.

**Unsigned builds.** Nothing here signs the executable — that needs a code
signing certificate, which costs money and belongs to a person rather than a
repository. Windows SmartScreen will warn on first launch: *More info → Run
anyway*.

<a name="app-macos"></a>
### macOS

```sh
sudo xcodebuild -runFirstLaunch     # after installing Xcode
cd app
flutter build macos --release
```

**Output:** `app/build/macos/Build/Products/Release/vellum.app`.

Also unsigned, so Gatekeeper refuses the first launch: right-click → *Open*, or
`xattr -d com.apple.quarantine vellum.app`.

<a name="app-android"></a>
### Android

**Toolchain:** JDK 17 (CI uses Temurin) and the Android SDK, which Android Studio
installs. `flutter doctor --android-licenses` accepts the SDK licences.

**Signing.** Release builds want a keystore. Copy
[`app/android/key.properties.example`](app/android/key.properties.example) to
`app/android/key.properties` (gitignored) and fill it in — that file documents
the one-time `keytool` command. Without it, release builds fall back to the debug
key, so a fresh checkout still produces something installable; it just isn't
distributable.

```sh
cd app
flutter build appbundle --release             # for Play, delivers per-ABI (~30 MB)
flutter build apk --release --split-per-abi   # sideloadable APKs, one per ABI
```

**Output:** `app/build/app/outputs/bundle/release/*.aab` and
`app/build/app/outputs/flutter-apk/*.apk`.

Prefer the app bundle for the store. A single fat APK carries every ABI —
arm64, armeabi-v7a, x86_64, plus the PDFium and SQLite natives — and comes to
about 87 MB.

**From Android Studio instead of the terminal:** open the `app/` directory (not
the repository root), let it sync Gradle, then *Build → Flutter → Build APK* or
*Build App Bundle*. The run configuration dropdown selects the device; the build
mode is set in *Run → Edit Configurations → Build flavour*, or just use the
terminal commands above, which are what CI runs.

---

## Building the server

The server is a single binary with no runtime dependencies. It creates and
migrates its own SQLite database on first start.

<a name="server-linux-and-macos"></a>
### Linux and macOS

```sh
cd server
cargo run                        # debug, on :3000
cargo build --release            # target/release/vellum-server
```

No database setup is needed to build. Some queries are compile-checked against
the schema using the committed `server/.sqlx/` data rather than a live database —
see [Changing the schema](#changing-the-schema).

**Optional external tools.** PDF cover rendering and text extraction are a
best-effort shell-out to whatever the host has: `pdftoppm`/`pdftocairo`
(poppler), `mutool` (mupdf), `gs` (ghostscript), `pdftotext`. None is required —
without them a PDF simply gets no generated cover and no text index. On Debian:

```sh
sudo apt install poppler-utils
```

<a name="server-windows"></a>
### Windows

**1. Install the C++ build tools.** Rust's default Windows toolchain is
`x86_64-pc-windows-msvc`, which links with MSVC. If you already installed Visual
Studio 2022 with *Desktop development with C++* for the app, you are done. If you
only want the server, the standalone
[Build Tools for Visual Studio](https://visualstudio.microsoft.com/downloads/)
with the same workload is enough.

**2. Install Rust** from <https://rustup.rs> — run `rustup-init.exe` and accept
the defaults. Then, in a new PowerShell window:

```powershell
rustc --version
```

**3. Build:**

```powershell
cd Vellum\server
cargo build --release
```

**Output:** `server\target\release\vellum-server.exe`.

**4. Run it:**

```powershell
$env:VELLUM_DB = "C:\ProgramData\Vellum\vellum.db"
$env:VELLUM_DATA_DIR = "C:\ProgramData\Vellum\data"
.\target\release\vellum-server.exe
```

It listens on `http://localhost:3000`; open that in a browser for the console.
The first account you register becomes the master account.

Every setting is an environment variable, listed in
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md#configuration) — and
`vellum-server.exe --help` prints the same list, so the binary is the authority.

**Windows-specific caveats:**

- **PDF tooling is usually absent.** The shell-outs above (`pdftoppm`, `mutool`,
  `gs`) are not on a stock Windows machine, so generated PDF covers and the
  optional content search will find nothing to call. Install
  [poppler for Windows](https://github.com/oschwartz10612/poppler-windows/releases)
  and put its `bin` on `PATH` if you want them. Everything else works regardless.
- **Firewall.** The first time it binds a port, Windows Defender Firewall asks
  whether to allow it. Allow it on private networks if you want another device to
  sync; deny it if you only want localhost.
- **Running as a service.** There is no Windows service wrapper in this
  repository — `packaging/vellum-server.service` is a systemd unit and does not
  apply. The usual options are
  [NSSM](https://nssm.cc/) or `New-Service`; treat this as untested here.
- The release workflow builds `x86_64-pc-windows-msvc` on every tag, so a
  prebuilt `vellum-server-x86_64-pc-windows-msvc.tar.gz` is attached to each
  GitHub release if you would rather not build it.

<a name="server-docker"></a>
### Docker

The [`Dockerfile`](Dockerfile) at the repository root builds the server. It is
deliberately a slim Debian image rather than `scratch`: the PDF fallbacks above
need a userland, and `poppler-utils` is what makes them work.

```sh
docker build -t vellum-server .
docker run -d --name vellum -p 3000:3000 -v vellum-data:/var/lib/vellum \
  vellum-server
```

Or with Compose, including automatic TLS via Caddy — see
[`docker-compose.yml`](docker-compose.yml) and
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md#docker).

The image is built *and run* in CI, and its `/health` endpoint probed, so a
change that produces a container which cannot serve is caught there rather than
at someone's `docker compose up`.

### Static and cross builds

For a binary that runs on any Linux distribution regardless of its glibc:

```sh
cargo install cross --locked
cd server
cross build --release --locked --target x86_64-unknown-linux-musl
# or aarch64-unknown-linux-musl for a Raspberry Pi and friends
```

This is what the release workflow does for the two Linux targets.

---

## Deploying

Running the server properly — TLS, reverse proxies, systemd, backups, upgrades —
is [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). The short version of the options:

| You want | Read |
|---|---|
| A container, HTTPS handled for you | [Docker Compose with automatic TLS](docs/DEPLOYMENT.md#docker-compose-with-automatic-tls) |
| A box on your LAN, phone syncing to it | [LAN-only, self-signed TLS](docs/DEPLOYMENT.md#lan-only-self-signed-tls) |
| A Linux service that starts at boot | [systemd](docs/DEPLOYMENT.md#systemd), using `packaging/vellum-server.service` |
| Windows | Build as above and run it; there is no service wrapper here |

**The app needs no deployment.** It is a local-first desktop and mobile
application: copy the built bundle to the machine and run it. There is no
installer in this repository — the release artefacts are a `.tar.gz`, a `.zip`
and an `.aab`/`.apk`.

---

## The development loop

```sh
cd app
flutter analyze                    # lint and static analysis, must be clean
flutter test                       # ~850 tests
flutter test test/settle_test.dart          # one file
flutter test --plain-name "name of test"    # one test

cd ../server
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs all of the
above plus:

- **codegen freshness** — regenerates drift and l10n output and fails on a diff;
- **`./tool/check_l10n.sh`** — no new hardcoded user-facing strings in files
  already migrated;
- **`flutter build linux --debug`** — `analyze` and `test` compile no native
  code, so without this a broken plugin or toolchain would land green;
- **`flutter build appbundle --release`** — same idea for Android;
- **`cargo sqlx prepare --check`** — the compile-checked queries match the
  migrations;
- **`cargo audit`** — a new RustSec advisory fails the build;
- **`scripts/e2e_sync.sh`** — a real server and a real client over the wire;
- **the Docker image**, built and then run and probed.

If you want to reproduce the cross-stack test locally:

```sh
bash scripts/e2e_sync.sh
```

---

## Changing the schema

**The schema is defined twice and kept in sync by hand.** This is the single
easiest thing to get wrong in this repository.

1. **App** — drift tables in `app/lib/data/database.dart`. After editing:
   ```sh
   cd app
   dart run build_runner build --delete-conflicting-outputs
   ```
   Bump `schemaVersion`, add a drift migration step in `onUpgrade`, and dump a
   schema snapshot so `test/migration_test.dart` can replay the upgrade:
   ```sh
   dart run drift_dev schema dump lib/data/database.dart test/drift_schemas
   dart run drift_dev schema generate test/drift_schemas \
        test/generated/drift_schema_versions
   ```
   **Do not pass `--data-classes` or `--companions`.** The verifier only asks a
   snapshot to create its tables and then diffs `sqlite_schema`; those flags add
   a data class and a companion per table per version — tens of thousands of
   lines of dead code — and rewrite every existing snapshot in the process,
   burying the one real change.
2. **Server** — a new SQL file in `server/migrations/`. **Never edit a migration
   that has already been applied**: sqlx checksums them, and an edited one makes
   every existing server refuse to start. Always add a new file.
3. If the table syncs, `server/tests/schema_parity.rs` pins it. A few `book`
   columns are app-local by design and must *not* be added server-side — see
   [CLAUDE.md](CLAUDE.md) for which and why.

**One SQLite trap, learned the hard way:** never write
`ALTER TABLE ... ADD COLUMN ... DEFAULT (expr)`. SQLite rejects a non-constant
default, but *only when the table already has rows* — so it passes every test
against a fresh database and fails on the first real server. Use a constant
default plus a backfilling `UPDATE`. `server/tests/migrations_with_data.rs`
guards both halves: it migrates a *populated* database, and it scans the
migration sources for the pattern.

After editing a compile-checked query (`sqlx::query!` and friends), regenerate
the offline data:

```sh
cd server
export DATABASE_URL="sqlite://$PWD/prepare.db?mode=rwc"
sqlx database create && sqlx migrate run
cargo sqlx prepare -- --lib
rm -f prepare.db*
```

---

## Changing the app icon

One image feeds every launcher slot on every platform:

```sh
python3 design/prepare_source.py path/to/artwork.png   # once per new artwork
python3 design/generate_icons.py                        # writes every slot
```

`prepare_source.py` finds the tile in the artwork, crops it square and makes the
rounded corners transparent, writing `design/logo-source.png` — the single
source of truth. `generate_icons.py` fans that out: Android's legacy and
adaptive icons (including the Android 13+ monochrome layer), the macOS icon set,
the Windows `.ico`, the in-app asset, the Linux hicolor theme, and the server
console's favicon. Needs Pillow and NumPy.

On Linux the *window* icon is resolved from the icon theme, not the bundle, so
after regenerating:

```sh
cd app && sh linux/install-dev.sh debug
```

Without that the desktop keeps showing whatever was installed last, and the app
looks unchanged however many times you rebuild it.

## Cutting a release

Push a `v*` tag. [`release.yml`](.github/workflows/release.yml) builds
everything and attaches it to a GitHub Release with checksums:

| Job | Produces |
|---|---|
| `server` | `vellum-server` for `x86_64`/`aarch64` musl Linux, `x86_64` Windows MSVC, `aarch64` macOS |
| `desktop` | `vellum-linux-x64.tar.gz`, `vellum-windows-x64.zip`, `vellum-macos.zip` |
| `android` | `app-release.aab` and per-ABI APKs |

```sh
git tag v1.0.0
git push origin v1.0.0
```

`workflow_dispatch` is kept on the same workflow so a release can be rehearsed
without tagging. Desktop artefacts are unsigned; the release notes say so.

---

## Troubleshooting

**`flutter: command not found` / not recognised** — Flutter isn't on `PATH`.
Reopen the terminal after installing; on Windows, `PATH` changes only reach
newly-opened windows.

**The Windows build fails mentioning MSBuild, `cl.exe` or the Windows SDK** —
the Visual Studio C++ workload is missing or incomplete. Reopen the Visual Studio
Installer → *Modify* → tick *Desktop development with C++*. `flutter doctor -v`
prints which Visual Studio it found.

**The Linux build fails mentioning GTK, ninja or clang** — install the packages
from [the Linux section](#app-linux).

**The build fails downloading `pdfium`** — `pdfium_dart`'s build hook fetches a
prebuilt PDFium from GitHub releases. On a network that blocks it (a corporate
proxy, an offline machine) the failure surfaces as a native build error. Set the
usual `HTTPS_PROXY` for your environment, or build on a machine that can reach
GitHub and copy the result.

**The build fails after pulling a newer version** — stale build cache:

```sh
cd app
flutter clean && flutter pub get
```

For the server, `cargo clean` — though this is rarely the answer, and it costs a
full rebuild.

**`git diff --exit-code -- lib/data/database.g.dart` fails in CI** — you edited
`database.dart` without regenerating. Run build_runner and commit the output.

**The server refuses to start with `Cannot add a column with non-constant
default`** — a migration broke the SQLite rule described in
[Changing the schema](#changing-the-schema). It only reproduces against a
database that already has rows.

**`flutter doctor` complains about Android, Chrome or Xcode** — ignore it unless
you are building for that platform.
