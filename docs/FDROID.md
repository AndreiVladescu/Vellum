# Publishing to F-Droid

Where Vellum stands with the F-Droid ecosystem, what is ready, and what is in
the way. The short version: **f-droid.org cannot build Vellum today**, but
**IzzyOnDroid can list it more or less as it is**, and the store metadata both
of them read is now in this repository.

---

## What is already done

`fastlane/metadata/android/en-US/` holds the listing, in the layout F-Droid,
IzzyOnDroid and Google Play all read:

| File | |
|---|---|
| `title.txt` | Vellum |
| `short_description.txt` | 69 characters (limit 80) |
| `full_description.txt` | 2,357 characters (limit 4,000) |
| `changelogs/2.txt` | 454 characters (limit 500) — named for the **versionCode**, not the version name |
| `images/icon.png` | 512×512 |
| `images/featureGraphic.png` | 1024×500 |

A new release needs a new `changelogs/<versionCode>.txt`. `versionCode` is the
number after the `+` in `app/pubspec.yaml` — `version: 1.1.0+2` is versionCode
**2**.

**Still missing: phone screenshots.** `images/phoneScreenshots/1.png` and up,
taken on a phone or emulator. The repository's existing `img/` shots are
desktop-shaped and would look wrong in a phone listing, and there is no honest
way to produce phone screenshots without running the app on one.

---

## Why f-droid.org cannot build it

F-Droid builds every app from source on its own infrastructure, and admits no
proprietary dependencies. Vellum currently fails both tests.

### 1. PDFium arrives as a prebuilt binary — the hard one

`pdfrx` → `pdfium_dart` fetches a compiled library during the build:

```
pdfium_dart/hook/build.dart:48
  'https://github.com/bblanchon/pdfium-binaries/releases/download/…'
```

F-Droid's inclusion policy forbids downloading binaries at build time; the
whole point of the repository is that every APK is built from the source you
can read. PDFium itself is open source (BSD), so this is not a licence problem
— it is a *build* problem, and a large one: PDFium is a Chromium-derived C++
project whose from-source build is a serious undertaking, not a recipe tweak.

There is no way around this that keeps the reader working. Vellum's PDF
rendering, text extraction and content search all sit on PDFium.

### 2. Google ML Kit is proprietary — two places

| Package | Android dependency |
|---|---|
| `google_mlkit_translation` | `com.google.mlkit:translate` |
| `google_mlkit_language_id` | `com.google.mlkit:language-id` |
| `mobile_scanner` | `com.google.mlkit:barcode-scanning` |

These are closed-source Google libraries. F-Droid would refuse them outright;
a lister that tolerates them flags the app `NonFreeDep`.

Both are replaceable in principle — barcode scanning has FOSS implementations
(ZXing), and the desktop translation path already uses locally installed
engines rather than ML Kit (`local_engine_backend.dart`). Doing it would mean a
build flavour that drops on-device translation on Android, which is a real
feature loss rather than a packaging detail.

**Neither of these matters until the PDFium problem is solved**, so there is no
point starting with them.

---

## The route that does work: IzzyOnDroid

[IzzyOnDroid](https://apt.izzysoft.de/fdroid/) is an F-Droid-compatible
repository that most F-Droid clients can add in two taps. It differs in the one
way that matters here: **it publishes the APKs you build and release yourself**
rather than building from source, so a prebuilt PDFium is not disqualifying. It
flags proprietary dependencies as anti-features instead of rejecting them.

What it needs, and where Vellum stands:

| Requirement | Status |
|---|---|
| FOSS licence | AGPL-3.0 ✅ |
| Public source repository | ✅ |
| GitHub Releases carrying an APK | ✅ (per-ABI APKs since v1.0.0) |
| Fastlane metadata in the repo | ✅ (above) |
| Phone screenshots | ❌ still to take |
| **APK signed with a stable release key** | ⚠️ see below |

### The signing prerequisite

IzzyOnDroid pins the signing certificate of the first APK it accepts and
refuses later ones signed with a different key. That makes the current state a
blocker rather than a detail:

**v1.1.0's Android artefacts are debug-signed** — verified by reading the APK
signing block, which contains `CN=Android Debug`. Submitting that would pin
Vellum to the debug certificate permanently.

So the order is: set the four signing secrets (see
[DEVELOPER.md](../DEVELOPER.md#app-android)), cut a release whose APKs are
signed with the real key, *then* submit. `release.yml` now refuses to publish a
tag whose APK is debug-signed, so this cannot be got wrong silently again.

### Submitting

Once there is a properly signed release with screenshots, open an issue on
[IzzyOnDroid/repo](https://gitlab.com/IzzyOnDroid/repo) requesting inclusion,
pointing at the repository and the release. They read the fastlane metadata
from the default branch.

---

## If f-droid.org proper is wanted later

The order of work, hardest first:

1. **Build PDFium from source** in the F-Droid recipe, or replace the PDF stack
   with something F-Droid can build. This is the whole problem; nothing else is
   worth doing until it has an answer.
2. **Drop ML Kit** on that build: a flavour without on-device translation, and
   a ZXing-based scanner.
3. Submit `metadata/app.vellum.Vellum.yml` to
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata) with the build recipe.

Steps 2 and 3 are ordinary work. Step 1 is a project.
