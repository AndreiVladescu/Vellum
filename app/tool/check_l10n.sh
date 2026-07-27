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
