# Publishing to F-Droid

> **Parked (2026-08-11).** Vellum is not being submitted anywhere for now. The
> repository is committed as the **full** flavour, which carries Google ML Kit,
> so it is *not* in a submittable state — `tool/flavour.sh free` is one command
> away when that changes. Everything below is kept because it is the map of
> what the work would be, and it stays accurate about what is and isn't
> possible.

Where Vellum stands with the F-Droid ecosystem, what is ready, and what is in
the way. The short version: the app **can** be built as free software with one
command; **IzzyOnDroid could list that build as it is**; and **f-droid.org
cannot build it at all** — for one reason, PDFium, which is a project rather
than a task.

---

## The two flavours

Vellum builds two ways from one source tree, switched by `app/tool/flavour.sh`:

```sh
cd app
tool/flavour.sh status   # which one is this tree set to?
tool/flavour.sh free     # the default, and what is committed
tool/flavour.sh full     # adds Google ML Kit for on-device translation
```

**`full` is the committed state today** (see the note at the top), so a fresh
clone builds with ML Kit. Submitting anywhere means committing `free` first;
CI's `tool/flavour.sh check` only asserts that the tree is *consistently* one
or the other, since either is a legitimate thing to commit.

| | free | full |
|---|---|---|
| On-device translation | — (LibreTranslate, or a translator installed on the machine) | Google ML Kit |
| Proprietary dependencies | none | `google_mlkit_translation`, `google_mlkit_language_id` |
| arm64 APK | **37.9 MB** | 59.9 MB |

### Why it has to be a build flavour

A runtime setting cannot do this. A dependency that is *listed* is a dependency
that *ships*: the ML Kit AARs put `libtranslate_jni.so` (16.4 MB) and
`liblanguage_id_l2c_jni.so` (1.0 MB) into every APK whether or not a single
line of code calls them, and both stores' scanners look at what is in the APK,
not at what runs. Nor can the library be fetched later — it is native code
linked at build time, Android cannot add native code to an installed app, and
F-Droid forbids downloading non-free code at runtime in any case. Only ML Kit's
~30 MB *language models* download on demand, and they need the library present.

So: a different APK. That is the ordinary answer, and the one most listed apps
with an optional proprietary bit use.

### What the switch touches

Four things, all in the repository and all visible in a diff — nothing is
generated and nothing is deleted:

| | |
|---|---|
| `pubspec.yaml` | the two `google_mlkit_*` lines |
| `lib/reader/translate/on_device.dart` | one `export` line, choosing the stub or the real one |
| `analysis_options.yaml` | whether the analyser reads `translate/proprietary/` |
| `test/reader/proprietary/` | whether that half's one test is collected |

The ML Kit code itself lives in `app/lib/reader/translate/proprietary/` in
**both** flavours. The free build simply never references it, so it is never
compiled.

### And a second gate in the full build

Shipping a proprietary library and running it are two decisions. The full
flavour makes only the first: on-device translation stays **off** until it is
switched on in the reader's settings (`Translate on this device`). Until then
the full build behaves exactly like the free one.

---

## What else changed to get here

**The barcode scanner is now free software, in both flavours.** `mobile_scanner`
decodes with ML Kit's barcode library — another 4.9 MB blob (`libbarhopper_v3.so`)
that dragged in Play Services and Firebase. It is replaced by `flutter_zxing`,
which builds zxing-cpp (Apache-2.0) from source with the rest of the app.
Scanning ISBNs and shelf labels works exactly as before, so unlike the
translator this needed no flavour split — there was nothing to choose between.

Removing the two together also took out every Firebase and Play-Services
component, including `transport-backend-cct`, Google's telemetry transport.
The free APK's only remaining marker of any of it is none:

```
$ unzip -l app-arm64-v8a-release.apk | grep -icE 'mlkit|gms|play-services|firebase'
0
```

---

## Why f-droid.org still cannot build it

F-Droid builds every app from source on its own infrastructure and admits no
prebuilt binaries. Vellum has exactly one left.

### PDFium arrives as a prebuilt binary

`pdfrx` → `pdfium_dart` downloads a compiled library during the build:

```
pdfium_dart-0.2.5/hook/build.dart:47
  'https://github.com/bblanchon/pdfium-binaries/releases/download/…'
```

There is no environment variable or local-path escape hatch in that hook; it
downloads unconditionally, and pre-seeding the file would not satisfy F-Droid
anyway, whose requirement is that the binary be *built* from source in the
recipe.

PDFium itself is open source (BSD), so this is not a licence problem — it is a
build problem, and a large one: PDFium is a Chromium-derived C++ project whose
from-source build needs `depot_tools`, `gn` and `ninja` and takes hours. It is
also load-bearing here: the PDF reader, text extraction and content search all
sit on it.

**This is the only thing between Vellum and f-droid.org.** There are four ways
out, in ascending order of work:

1. **Ask F-Droid whether a Maven-hosted PDFium AAR counts.** They accept Maven
   dependencies of free-licensed libraries (they do not rebuild AndroidX
   either), and `io.legere:pdfiumandroid` is Apache-2.0 with the `.so` inside
   the AAR. Whether their reviewers read that as "prebuilt binary" or "ordinary
   dependency" is their judgement call — one forum post, and a yes makes this a
   dependency swap.
2. **A `nopdf` flavour.** The flavour machinery already exists, and the reader
   is already forked at `read_button.dart` — EPUB goes to `EpubReaderPage`,
   which is pure Dart. A build without `pdfrx` keeps the library, sync, loans
   and EPUB reading, and hands PDFs to whatever viewer the phone has. It loses
   in-app PDF reading, PDF covers and PDF content indexing.
3. **Replace the engine with MuPDF.** AGPL-3.0, so compatible with this
   project, and it builds with a plain makefile rather than a Chromium
   toolchain — but nothing binds it to Flutter, so it means writing FFI for
   rendering, text extraction, search and highlight coordinates. Weeks.
4. **Build PDFium from source in the recipe.** Mechanically possible — the hook
   skips its download when the file is already there — but it needs `gn`,
   `ninja` and every DEP as F-Droid `srclibs`, and their maintainers would
   likely decline first.

Android's platform `PdfRenderer` is not a substitute: it renders pages to
bitmaps and gives no text at all until API 35.

---

## The route that works today: IzzyOnDroid

[IzzyOnDroid](https://apt.izzysoft.de/fdroid/) is an F-Droid-compatible
repository that most F-Droid clients can add in two taps. It differs in the one
way that matters: **it publishes the APKs you build and release yourself**
rather than building from source, so a prebuilt PDFium is not disqualifying.

| Requirement | Status |
|---|---|
| FOSS licence | AGPL-3.0 ✅ |
| Public source repository | ✅ |
| GitHub Releases carrying an APK | ✅ (per-ABI since v1.0.0) |
| Fastlane metadata in the repo | ✅ |
| Phone screenshots | ✅ five, in `fastlane/metadata/android/en-US/images/phoneScreenshots/` |
| No proprietary dependencies | ✅ in the free flavour — **submit that one** |
| APK signed with a stable release key | ⚠️ see below |

### The signing prerequisite

IzzyOnDroid pins the signing certificate of the first APK it accepts and
refuses later ones signed with a different key. v1.1.0's Android artefacts were
**debug-signed** (`CN=Android Debug` in the signing block), and submitting that
would pin Vellum to a throwaway certificate for good.

So the order is: set the signing secrets (see
[DEVELOPER.md](../DEVELOPER.md#app-android)), cut a release whose APKs are
signed with the real key, *then* submit. `release.yml` refuses to publish a tag
whose APK is debug-signed, so this cannot be got wrong silently.

### Submitting

Open an issue on [IzzyOnDroid/repo](https://gitlab.com/IzzyOnDroid/repo)
requesting inclusion, pointing at the repository and the release. They read the
fastlane metadata from the default branch. Note in the issue that the release
APK is the **free** flavour, so no anti-features apply.

---

## If f-droid.org proper is wanted later

1. **Build PDFium from source** in the F-Droid recipe, or replace the PDF stack.
   This is the whole problem; nothing else is worth doing until it has an
   answer.
2. Submit `metadata/app.vellum.Vellum.yml` to
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata) with the build recipe.
   The recipe must run `tool/flavour.sh free` in a `prebuild` step, or the
   tree's committed flavour must be switched to free first — otherwise it
   would build ML Kit into an F-Droid release.

Step 2 is ordinary work. Step 1 is a project.
