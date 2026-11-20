# Translating Vellum

Every message the app shows lives in one file, `app/lib/l10n/app_en.arb`. A
language is one more file next to it. You do not need to touch any Dart code, and
you do not need to know Flutter: a text editor and the commands below are
enough.

Shipped so far: English (the template) and Romanian (`app_ro.arb`, with its
glossary in [translations/ro-glossary.md](translations/ro-glossary.md)). Use the
Romanian files as a worked example.

## What stays English

A few things stay English on purpose: the diagnostics report (it is pasted into
bug reports the maintainer has to read), the system prompt sent to an AI model,
brand and engine names, format identifiers, log lines, and the technical detail
of an error (the part after "Could not reach the server:"). Messages that come
from the server itself are shown as the server wrote them. The CSV/JSON column
names in the import help (`title`, `books`) are what the importer reads, so they
stay as they are in every language.

## Add a language

1. **Copy the template** and name the copy after the language code:

   ```sh
   cd app/lib/l10n
   cp app_en.arb app_fr.arb      # fr = French; use es, de, pt_BR, ...
   ```

2. In `app_fr.arb` change `"@@locale": "en"` to `"@@locale": "fr"`.

3. **Start a glossary** before you translate a single message:
   `docs/translations/fr-glossary.md`. List the 60–100 words that recur (book
   spine, shelf, library, loan, highlight, reading session, sync, …), the word
   you chose for each and why, plus your house style (formal or informal
   address, quotation marks, dash, how percentages and units are written). The
   Romanian glossary is the template. It is what keeps 1,900 messages saying one
   thing for one idea, and it is what a reviewer reads first.

4. **Translate the values.** Leave the keys, the `{placeholders}` and the ICU
   syntax alone. Delete the `"@key": { ... }` description blocks from your copy
   — they only exist in the English template, which is where you read them: each
   says where the message appears and what its placeholders hold. Read the
   description; many messages are short labels whose meaning depends on where
   they sit.

   One message is special: `languageName` is your language's name *in your
   language* ("Français", "Română"). It is what the language picker shows, so a
   reader always finds their own language whatever the app is set to.

5. **Android and Linux** have a few strings outside the ARB, because the system
   reads them before the app starts:

   - `app/android/app/src/main/res/values/strings.xml` (launcher shortcuts, the
     home-screen widget): copy it to `values-fr/strings.xml` and translate the
     text between the tags. Short shortcut labels must stay at or under about
     10 characters.
   - The desktop entry is written by the scripts in `app/linux/` (`install-dev.sh`
     and `packaging/*.sh`): add a `Name[fr]=` and `Comment[fr]=` line next to the
     `Name=` and `Comment=` lines in each.

6. **Check** (see below), and open a pull request with the ARB, the glossary and
   any Android/Linux files.

## Placeholders

A value in braces is filled in by the app. Keep it exactly as it is spelled,
and move it wherever your language's word order needs it:

```json
"bookAdded": "“{title}” added to your shelf"
```

Romanian: `"Ai adăugat „{title}” pe raft"`. Never translate the name inside the
braces.

Numbers, dates, percentages and file sizes arrive already formatted for your
language (`1.234`, `20.11.2026`, `42 %`, `3,2 MB` in Romanian), so you never
write a decimal point or a date pattern yourself. If you see a hand-written
English format in the app, that is a bug to report, not something to work
around in the translation.

## Plurals

Anything that counts is an ICU plural. English needs two forms (`=1` and
`other`); your language may need more. The forms are `zero`, `one`, `two`,
`few`, `many` and `other`; `other` is always required. Which numbers fall into
which form is fixed per language by the Unicode CLDR — look yours up at
<https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html>
before you start, and write only the forms your language has.

```json
"syncIssues": "{count, plural, =1{1 issue} other{{count} issues}}"
```

Romanian has three forms, and `few` covers 0 and 2–19 (and 101–119, …), while
`other` takes "de" ("20 de probleme"):

```json
"syncIssues": "{count, plural, one{1 problemă} few{{count} probleme} other{{count} de probleme}}"
```

Polish would write
`{count, plural, one{{count} problem} few{{count} problemy} many{{count} problemów} other{{count} problemu}}`.

An explicit `=0{…}` (or `=1`, `=2`) always wins over the CLDR form for that exact
number, so you can keep a special "Nothing yet" case. A plural is allowed even
where the English has none: if English writes `{count} books` but your language
needs agreement, write a plural.

Some messages use `select` to pick a word by a value, e.g. `{unit, select,
chapter{chapter} other{page}}`. Translate the words inside the braces; leave the
value names (`chapter`, `other`) as they are. Every case must stay.

## Run the checks

From `app/` (the Flutter SDK's `bin/` on your PATH):

```sh
flutter gen-l10n                       # regenerates lib/l10n/gen/ from the ARBs
cat lib/l10n/untranslated.json         # {} when every language is complete
flutter test test/l10n_ro_test.dart    # parity, placeholders, selects, Android strings
flutter analyze
```

`gen-l10n` fails on broken ICU syntax and tells you the key. `untranslated.json`
lists, per language, the keys that exist in English but not in your file; a
missing message is shown in English, so the app still works, but the file
should end up `{}`.

`test/l10n_ro_test.dart` runs over **every** translation in `lib/l10n/`, not
only Romanian: it fails if your file lacks a message, has one English does not,
drops or renames a placeholder, loses a `select` case, or writes a plural with
no `other`. Its Romanian-specific tests (plural examples, diacritics) are a
model for a few of your own: copy them into `test/l10n_fr_test.dart` with your
language's forms.

Then check the layout. Translations are often 20–30% longer than English;
`test/widgets/large_text_test.dart` renders the shelf, the drawer, the book page,
Insights, Loans, Library statistics, Preferences and the reader's chrome on a
411×891 phone at 1.3× and 2.0× text, once per language listed in its `_locales`.
Add your locale there and run it:

```sh
flutter test test/widgets/large_text_test.dart
```

A failure names the widget that overflowed. Report it (or fix the layout with
`Wrap`, `Flexible` or an ellipsis); never shorten a translation into something
nobody would say just to make it fit.

## Preview it

Run the app and pick your language in **Preferences → Appearance → Language**.
The choice is stored on the device and takes effect immediately; "System
default" follows the device language again.

```sh
cd app
flutter run -d linux
```

You can also start it in a language without touching the setting:
`LANGUAGE=fr LC_ALL=fr_FR.UTF-8 flutter run -d linux` (with the Preferences
choice on "System default"). On Android, set the device language and relaunch to
see the shortcuts and the home-screen widget.

## Adding a new message (for developers)

Add the key to `app_en.arb` with a `@key` entry (a `description`, and a `type`
for every placeholder; give counts `"format": "decimalPattern"` so they are
grouped per locale), run `flutter gen-l10n`, and read it with
`L10n.of(context).theKey`. Add the Romanian too, or the parity test fails. Name
keys `<screen or feature><What it is>` in camelCase (`detailRevertTitle`,
`scanIsbnLabel`), one message per sentence, never built by joining translated
pieces. For text that lives on an enum or in a service with no `BuildContext`,
add a `labelOf(L10n l10n)` extension in `app/lib/l10n/labels.dart` and call it
from the widget; for code with no widget tree at all (notifications, the
background isolate) use `platformL10n()`. Format a date, number, percentage or
size with the helpers in `app/lib/l10n/formats.dart` (`l10n.formatDate(d)`,
`l10n.formatPercent(0.42)`, `l10n.formatFileSize(bytes)`), never by hand.
