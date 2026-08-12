import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/translate/proprietary/on_device_backend.dart';
import 'package:vellum/reader/translate/translation_backend.dart';

/// The ML Kit language-pack list — a **full-flavour test**.
///
/// Named `.dart.full` so `flutter test` does not collect it: in the free
/// flavour the file it imports is not compiled and `google_mlkit_translation`
/// is not a dependency, so collecting it would fail the whole run.
/// `tool/flavour.sh full` renames it to `_test.dart`, and `free` renames it
/// back. It is the one test that belongs to the proprietary half.
void main() {
  group('language packs', () {
    test('only languages the device can actually translate are offered', () {
      // Every offered language must map to a model; the list is the app's own
      // narrowed to what ML Kit has, so nothing is shown that fails on press.
      for (final language in LanguagePacks.offered) {
        expect(TranslationLanguage.byCode(language.code), isNotNull);
      }
      expect(LanguagePacks.offered, isNotEmpty);
      expect(LanguagePacks.offered.contains(TranslationLanguage.auto), false,
          reason: '"Detect" is not something you download');
    });
  });
}
