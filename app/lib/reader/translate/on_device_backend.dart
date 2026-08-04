import 'dart:io';

import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translation_backend.dart';

/// Translation that happens on the device, with no server anywhere.
///
/// A language is a **pack you download once and keep**: after that the passage
/// never leaves the machine, which is the whole point — what you are reading is
/// more personal than your catalogue, and a translation request is a sentence
/// you stopped on sent to a stranger.
///
/// **Android and iOS only.** ML Kit is a platform service; there is no desktop
/// build of it. [available] is how everything above this decides whether to
/// offer it, and the desktop keeps the optional LibreTranslate address until
/// the engine described in docs/NEXT_FEATURES.md #12 exists.
class OnDeviceBackend implements TranslationBackend {
  OnDeviceBackend({LanguagePacks? packs}) : packs = packs ?? LanguagePacks();

  final LanguagePacks packs;

  /// Whether this backend can exist at all on this platform.
  static bool get available => Platform.isAndroid || Platform.isIOS;

  @override
  String get name => 'this device';

  @override
  Future<Translation> translate(
    String text, {
    required TranslationLanguage from,
    required TranslationLanguage to,
  }) async {
    if (text.trim().isEmpty) {
      throw const TranslationException('There is nothing selected to translate.');
    }
    if (!available) {
      throw const TranslationException(
        'On-device translation is only available on a phone or tablet.',
      );
    }

    // Detect first when asked to, because the translator needs a source: "work
    // it out" is this layer's job, not the translator's.
    var source = from;
    TranslationLanguage? detected;
    if (from == TranslationLanguage.auto) {
      detected = await identify(text);
      if (detected == null) {
        throw const TranslationException(
          'Could not tell what language that is — pick one under From.',
        );
      }
      source = detected;
    }

    if (source == to) {
      // Not an error worth a red message: it is already in that language.
      return Translation(text: text, detected: detected);
    }

    final sourceModel = _model(source);
    final targetModel = _model(to);
    if (sourceModel == null || targetModel == null) {
      throw TranslationException(
        '${sourceModel == null ? source.name : to.name} is not one of the '
        'languages this device can translate.',
      );
    }

    final missing = <TranslationLanguage>[
      if (!await packs.isInstalled(source)) source,
      if (!await packs.isInstalled(to)) to,
    ];
    if (missing.isNotEmpty) {
      throw TranslationException(
        'Download ${missing.map((l) => l.name).join(' and ')} under Languages '
        'to translate this without a server.',
      );
    }

    final translator = OnDeviceTranslator(
      sourceLanguage: sourceModel,
      targetLanguage: targetModel,
    );
    try {
      return Translation(text: await translator.translateText(text), detected: detected);
    } catch (e) {
      throw TranslationException('That could not be translated here — $e');
    } finally {
      await translator.close();
    }
  }

  /// What language a passage looks like, or null when nothing is confident
  /// enough. ML Kit answers `und` for "undetermined", which is a real answer
  /// and not an error.
  Future<TranslationLanguage?> identify(String text) async {
    final identifier = LanguageIdentifier(confidenceThreshold: 0.5);
    try {
      final code = await identifier.identifyLanguage(text);
      return code == 'und' ? null : TranslationLanguage.byCode(code);
    } catch (_) {
      return null;
    } finally {
      await identifier.close();
    }
  }

  static TranslateLanguage? _model(TranslationLanguage language) =>
      BCP47Code.fromRawValue(language.code);
}

/// The downloaded languages, and the toggling of them.
///
/// A pack is a file on the device that ML Kit fetches once (roughly 30 MB per
/// language) and reuses forever. Downloading is the only part that needs a
/// network; everything after it works on a train.
class LanguagePacks {
  LanguagePacks({OnDeviceTranslatorModelManager? manager})
      : _manager = manager ?? OnDeviceTranslatorModelManager();

  final OnDeviceTranslatorModelManager _manager;

  /// The languages that can be downloaded here — the app's own list narrowed to
  /// the ones ML Kit actually has a model for, so nothing is offered that would
  /// fail when pressed.
  static List<TranslationLanguage> get offered => [
        for (final language in TranslationLanguage.all)
          if (BCP47Code.fromRawValue(language.code) != null) language,
      ];

  Future<bool> isInstalled(TranslationLanguage language) async {
    if (!OnDeviceBackend.available) return false;
    try {
      return await _manager.isModelDownloaded(language.code);
    } catch (_) {
      // No ML Kit on this platform, or the service is unavailable: not
      // installed is the honest answer, and the caller shows it as such.
      return false;
    }
  }

  /// Fetches [language]. Wi-Fi only by default, because a pack is tens of
  /// megabytes and nobody means to spend their data allowance on one by
  /// pressing a button in a book.
  Future<void> install(TranslationLanguage language, {bool wifiOnly = true}) async {
    final ok = await _manager.downloadModel(language.code, isWifiRequired: wifiOnly);
    if (!ok) {
      throw TranslationException(
        wifiOnly
            ? 'Could not download ${language.name}. On mobile data, turn off '
                'Wi-Fi only and try again.'
            : 'Could not download ${language.name}.',
      );
    }
  }

  Future<void> remove(TranslationLanguage language) async {
    final ok = await _manager.deleteModel(language.code);
    if (!ok) {
      throw TranslationException('Could not remove ${language.name}.');
    }
  }

  /// Every offered language with whether it is here, in one pass, for the list.
  Future<Map<TranslationLanguage, bool>> installedState() async {
    final state = <TranslationLanguage, bool>{};
    for (final language in offered) {
      state[language] = await isInstalled(language);
    }
    return state;
  }
}
