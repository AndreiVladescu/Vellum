#!/usr/bin/env bash
#
# Switch Vellum between its two flavours.
#
#   tool/flavour.sh free    # the default: every dependency is free software
#   tool/flavour.sh full    # adds Google ML Kit for on-device translation
#   tool/flavour.sh status  # say which one the tree is currently set to
#
# WHY THIS EXISTS
#
# On-device translation is Google's ML Kit: a closed-source library that puts
# about 17 MB of `.so` files into the APK and pulls in Play Services. F-Droid
# refuses proprietary dependencies outright and IzzyOnDroid flags them, so an
# app that wants to be listed cannot simply ship it.
#
# It cannot be a *setting*, either. A dependency that is listed is a dependency
# that ships, whether or not any code calls it, so a runtime switch would leave
# every blob exactly where it was and change nothing a scanner looks at. The
# only thing that removes it is not building with it — hence a flavour.
#
# WHAT IT TOUCHES
#
# Two files, both in the repository, both readable in a diff:
#
#   pubspec.yaml                         the two google_mlkit_* dependencies
#   lib/reader/translate/on_device.dart  which implementation is exported
#   analysis_options.yaml                whether the analyser reads that code
#   test/reader/proprietary/…            whether its one test is collected
#
# Nothing is deleted or generated: the ML Kit code lives in
# lib/reader/translate/proprietary/ in both flavours, and is simply not
# referenced (and so not compiled) by the free one. Switching back is this
# script with the other argument.
#
# The full build then asks a second time, at runtime: on-device translation
# stays off until it is switched on in the reader's settings. Shipping a
# proprietary library and running it are two decisions, and this only makes the
# first one.
set -euo pipefail

cd "$(dirname "$0")/.."

SWITCH=lib/reader/translate/on_device.dart
STUB_LINE="export 'on_device_stub.dart';"
REAL_LINE="export 'proprietary/on_device.dart';"

# The dependency block, written on one line each so the toggle is a grep away.
MLKIT_TRANSLATION="  google_mlkit_translation: ^0.14.0"
MLKIT_LANGUAGE_ID="  google_mlkit_language_id: ^0.14.0"

# `flutter test` collects every *_test.dart under test/, so the proprietary
# half's one test is parked under a name it does not match.
FULL_TEST=test/reader/proprietary/language_packs_test.dart
PARKED_TEST=test/reader/proprietary/language_packs_test.dart.full

current() {
  if grep -qF "$REAL_LINE" "$SWITCH"; then echo full; else echo free; fi
}

case "${1:-status}" in
  status)
    echo "flavour: $(current)"
    if grep -q '^  google_mlkit' pubspec.yaml; then
      echo "pubspec: ML Kit present"
    else
      echo "pubspec: no proprietary dependencies"
    fi
    if grep -q '^analyzer:' analysis_options.yaml; then
      echo "analyser: proprietary/ excluded"
    else
      echo "analyser: reading everything"
    fi
    ;;

  free)
    # The export first: a pubspec without ML Kit and a switch still pointing at
    # it is the one state that does not compile.
    sed -i "s|^$REAL_LINE\$|$STUB_LINE|" "$SWITCH"
    sed -i '/^  google_mlkit_translation:/d; /^  google_mlkit_language_id:/d' pubspec.yaml
    # The proprietary sources stay on disk and stop being analysable, since
    # their imports are no longer dependencies. Nothing compiles them — they
    # are unreferenced — but `flutter analyze` reads every file it can see.
    sed -i 's|^# analyzer:|analyzer:|; s|^#   exclude:|  exclude:|; s|^#     - lib/reader/translate/proprietary|    - lib/reader/translate/proprietary|' analysis_options.yaml
    [ -f "$FULL_TEST" ] && mv "$FULL_TEST" "$PARKED_TEST"
    flutter pub get >/dev/null
    echo "flavour: free — no proprietary dependencies"
    ;;

  full)
    if ! grep -q '^  google_mlkit_translation:' pubspec.yaml; then
      # Placed after mobile-facing packages, where they were before; the anchor
      # is a dependency that is in both flavours.
      sed -i "s|^  flutter_local_notifications:.*|&\n$MLKIT_TRANSLATION\n$MLKIT_LANGUAGE_ID|" pubspec.yaml
    fi
    sed -i "s|^$STUB_LINE\$|$REAL_LINE|" "$SWITCH"
    # Analyse it again: in this flavour it is code that ships.
    sed -i 's|^analyzer:|# analyzer:|; s|^  exclude:|#   exclude:|; s|^    - lib/reader/translate/proprietary|#     - lib/reader/translate/proprietary|' analysis_options.yaml
    [ -f "$PARKED_TEST" ] && mv "$PARKED_TEST" "$FULL_TEST"
    flutter pub get >/dev/null
    echo "flavour: full — Google ML Kit is in this build (proprietary)"
    echo "note: it still does nothing until the reader's settings turn it on."
    ;;

  check)
    # Used by CI. Asserts the four switched things agree with each other,
    # rather than asserting a particular flavour — either flavour is a valid
    # thing to commit, but a half-switched tree is not, and it fails in ways
    # (an unresolved import, a test that will not compile) that are much
    # easier to read here than in a build log.
    fail=0
    if grep -q '^  google_mlkit' pubspec.yaml; then
      grep -qF "$REAL_LINE" "$SWITCH" || { echo "pubspec has ML Kit but $SWITCH exports the stub"; fail=1; }
      grep -q '^analyzer:' analysis_options.yaml && { echo "pubspec has ML Kit but proprietary/ is excluded from analysis"; fail=1; }
      [ -f "$FULL_TEST" ] || { echo "pubspec has ML Kit but its test is parked"; fail=1; }
    else
      grep -qF "$STUB_LINE" "$SWITCH" || { echo "no ML Kit in pubspec but $SWITCH exports it"; fail=1; }
      grep -q '^analyzer:' analysis_options.yaml || { echo "no ML Kit in pubspec but proprietary/ would be analysed"; fail=1; }
      [ -f "$PARKED_TEST" ] || { echo "no ML Kit in pubspec but its test would be collected"; fail=1; }
    fi
    if [ "$fail" -eq 0 ]; then echo "flavour: $(current), consistently"; fi
    exit "$fail"
    ;;

  *)
    echo "usage: $0 [free|full|status|check]" >&2
    exit 2
    ;;
esac
