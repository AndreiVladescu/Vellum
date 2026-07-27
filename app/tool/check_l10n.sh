#!/usr/bin/env bash
# Guards the localization retrofit (plan 5 #38).
#
# Migration is incremental — one feature area per commit — so a repo-wide "no
# raw strings" rule would be noise for the ninety per cent that hasn't moved
# yet. Instead this checks only the files already migrated, listed below. Adding
# a file to that list is the last step of migrating it, and from then on a new
# hardcoded string in it fails CI.
#
# The check is a grep, not a parser: it looks for a `Text('…')` (or a
# label/hint/tooltip taking a literal) whose content contains a letter. That
# misses clever cases and flags a few innocent ones — which is why the escape
# hatch is a trailing `// i18n-ignore` comment, and why the list is opt-in
# rather than the default.
set -euo pipefail
cd "$(dirname "$0")/.."

MIGRATED=(
  lib/main.dart
  lib/add_book/add_book_page.dart
)

fail=0
for file in "${MIGRATED[@]}"; do
  [ -f "$file" ] || { echo "check_l10n: $file is listed but missing"; fail=1; continue; }

  # A user-facing literal: Text('…'), or one of the common string parameters,
  # where the literal contains at least one letter (so ':' , '·' and '' pass).
  hits=$(grep -nE \
    "(Text\(|label: |labelText: |hintText: |tooltip: |title: |subtitle: )'[^']*[A-Za-z][^']*'" \
    "$file" | grep -v 'i18n-ignore' || true)

  # Hand-built plurals, anywhere in the file — not just on a `Text(` line.
  # This is the pattern plan 5 #38 exists to remove (`'$n issue${n == 1 ? '' :
  # 's'}'`), and it slipped through the check above because the literal sat on
  # its own continuation line rather than next to the `Text(`. A same-line grep
  # is a weak guard for a codebase that writes most user-facing copy across
  # several lines; this catches the specific shape that matters.
  # The shape, precisely: a ternary choosing between two *very short* quoted
  # strings — `? '' : 's'`. That is the suffix hack and essentially nothing
  # else, so it doesn't fire on `if (paths.length == 1)`, which is control flow.
  # `//` lines are skipped: the comments explaining this rule contain the very
  # pattern they warn about, and a guard that flags its own documentation is one
  # people switch off.
  plurals=$(grep -nE "\? *'[a-z]{0,2}' *: *'[a-z]{0,2}'" "$file" \
    | grep -vE "i18n-ignore|^[0-9]+: *(//|///|\*)" || true)
  if [ -n "$plurals" ]; then
    echo "check_l10n: hand-built plural in $file"
    echo "  Use an ICU plural in lib/l10n/app_en.arb — no other language"
    echo "  survives 'thing' + 's'."
    echo "$plurals" | sed 's/^/    /'
    fail=1
  fi

  if [ -n "$hits" ]; then
    echo "check_l10n: hardcoded user-facing strings in $file"
    echo "  Move them to lib/l10n/app_en.arb and use L10n.of(context)."
    echo "  If the string is genuinely not user-facing, append // i18n-ignore."
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "check_l10n: ${#MIGRATED[@]} migrated file(s) clean"
