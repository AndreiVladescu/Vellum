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
    #
    # Every failure prints the four observed values and the one command that
    # fixes them. A check that says only what it disliked sends whoever reads
    # the log hunting through a shell script.
    has_mlkit=no;  grep -q '^  google_mlkit' pubspec.yaml && has_mlkit=yes
    exports=stub;  grep -qF "$REAL_LINE" "$SWITCH" && exports=proprietary
    excluded=no;   grep -q '^analyzer:' analysis_options.yaml && excluded=yes
    test_state=parked; [ -f "$FULL_TEST" ] && test_state=collected

    if [ "$has_mlkit" = yes ]; then
      want_exports=proprietary; want_excluded=no;  want_test=collected; want=full
    else
      want_exports=stub;        want_excluded=yes; want_test=parked;    want=free
    fi

    if [ "$exports" = "$want_exports" ] &&
       [ "$excluded" = "$want_excluded" ] &&
       [ "$test_state" = "$want_test" ]; then
      echo "flavour: $want, consistently"
      exit 0
    fi

    echo "flavour: half-switched — this tree is neither flavour." >&2
    echo >&2
    printf '  %-28s %s (this is what decides the flavour)\n' \
      "pubspec ML Kit:" "$has_mlkit" >&2
    printf '  %-28s %s (wanted %s)\n' \
      "$SWITCH exports:" "$exports" "$want_exports" >&2
    printf '  %-28s %s (wanted %s)\n' \
      "proprietary/ excluded:" "$excluded" "$want_excluded" >&2
    printf '  %-28s %s (wanted %s)\n' \
      "its test:" "$test_state" "$want_test" >&2
    echo >&2
    echo "The pubspec decides which flavour this is meant to be, so: run" >&2
    echo "  cd app && tool/flavour.sh $want" >&2
    echo "and commit what it changes. See docs/FDROID.md." >&2

    # Which files were actually read. This exists because the check once failed
    # on CI reporting a state that no commit, branch or pull-request merge in
    # the repository could produce — so the next time it happens, the log says
    # *which* bytes it was looking at rather than leaving it to be deduced.
    echo >&2
    echo "read from $(pwd):" >&2
    for f in pubspec.yaml analysis_options.yaml "$SWITCH"; do
      if [ -f "$f" ]; then
        echo "  $f  sha256=$(sha256sum "$f" | cut -c1-16)" >&2
      else
        echo "  $f  MISSING" >&2
      fi
    done
    # Whether these bytes are the *committed* ones. This is the question the
    # hashes above could not answer: a failure on a clean tree means the commit
    # really is half-switched, and a failure on a dirty one means something on
    # the machine edited a file after checkout — two completely different bugs
    # that had until now produced an identical log.
    if command -v git >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "  HEAD: $(git log -1 --format='%h %s' 2>/dev/null)" >&2
      changed=$(git status --porcelain -- \
        pubspec.yaml analysis_options.yaml "$SWITCH" test/reader/proprietary 2>/dev/null)
      if [ -n "$changed" ]; then
        echo "  MODIFIED SINCE CHECKOUT — these are not the committed bytes:" >&2
        echo "$changed" | sed 's|^|    |' >&2
        git diff -- analysis_options.yaml | sed 's|^|    |' >&2
      else
        echo "  working tree is clean, so the commit itself is half-switched" >&2
      fi
    else
      echo "  (not a git checkout — cannot say whether these bytes are committed)" >&2
    fi

    # The file itself, because a hash only tells you that it is not one of the
    # two you expected. It is thirty lines; the log can afford them.
    echo >&2
    echo "analysis_options.yaml, as read:" >&2
    sed -n '1,30p' analysis_options.yaml | cat -n | sed 's|^|  |' >&2
    exit 1
    ;;

  *)
    echo "usage: $0 [free|full|status|check]" >&2
    exit 2
    ;;
esac
