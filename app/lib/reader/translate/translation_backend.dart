import 'dart:convert';

import 'package:http/http.dart' as http;

/// A language a passage can be translated from or to.
///
/// `auto` is only ever a *source*: it means "work it out", and the answer comes
/// back on the result so the sheet can show what was guessed and let it be
/// corrected.
class TranslationLanguage {
  const TranslationLanguage(this.code, this.name);

  /// ISO 639-1, which is what every backend here speaks.
  final String code;
  final String name;

  static const auto = TranslationLanguage('auto', 'Detect');

  /// The languages offered in the pickers.
  ///
  /// Deliberately a fixed list rather than whatever a backend reports: the
  /// picker has to work before anything is configured (so you can see what the
  /// feature would do), and a server that speaks fewer of them answers with an
  /// error naming the one it refused, which is a better failure than an empty
  /// dropdown.
  static const all = <TranslationLanguage>[
    TranslationLanguage('en', 'English'),
    TranslationLanguage('ar', 'Arabic'),
    TranslationLanguage('zh', 'Chinese'),
    TranslationLanguage('cs', 'Czech'),
    TranslationLanguage('nl', 'Dutch'),
    TranslationLanguage('fr', 'French'),
    TranslationLanguage('de', 'German'),
    TranslationLanguage('el', 'Greek'),
    TranslationLanguage('he', 'Hebrew'),
    TranslationLanguage('hi', 'Hindi'),
    TranslationLanguage('hu', 'Hungarian'),
    TranslationLanguage('it', 'Italian'),
    TranslationLanguage('ja', 'Japanese'),
    TranslationLanguage('ko', 'Korean'),
    TranslationLanguage('fa', 'Persian'),
    TranslationLanguage('pl', 'Polish'),
    TranslationLanguage('pt', 'Portuguese'),
    TranslationLanguage('ro', 'Romanian'),
    TranslationLanguage('ru', 'Russian'),
    TranslationLanguage('es', 'Spanish'),
    TranslationLanguage('sv', 'Swedish'),
    TranslationLanguage('tr', 'Turkish'),
    TranslationLanguage('uk', 'Ukrainian'),
  ];

  /// The language for [code], or null when it isn't one this app offers.
  static TranslationLanguage? byCode(String? code) {
    if (code == null) return null;
    if (code == auto.code) return auto;
    final lower = code.toLowerCase();
    // Tolerates 'en-GB' and 'pt_BR': the base language is what a translator
    // takes, and a regional tag that isn't recognised is better than nothing.
    final base = lower.split(RegExp(r'[-_]')).first;
    return all.where((l) => l.code == base).firstOrNull;
  }

  @override
  bool operator ==(Object other) =>
      other is TranslationLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// What came back: the text, and which language the backend decided it was.
class Translation {
  const Translation({required this.text, this.detected});

  final String text;

  /// The source language the backend detected, when it was asked to guess.
  /// Null when the source was given explicitly, or when the backend doesn't
  /// report one.
  final TranslationLanguage? detected;
}

/// A backend refused, and this is what to tell the reader.
///
/// Carries a plain sentence rather than a status code: every caller shows it to
/// a person, and "LibreTranslate does not have German→Romanian" is more use
/// than 400.
class TranslationException implements Exception {
  const TranslationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Where translations come from.
///
/// An interface with one implementation today, because the implementation is
/// the part expected to change: an engine packed into the app with downloadable
/// language packs (see docs/NEXT_FEATURES.md #12) is the destination, and it is
/// a native build for five platforms. Everything above this line — the button,
/// the sheet, the pickers, saving a translation as a note — is written against
/// this and does not care which one answers.
abstract class TranslationBackend {
  /// A short name for the sheet: "LibreTranslate", eventually "On this device".
  String get name;

  /// Translates [text]. [from] may be [TranslationLanguage.auto].
  Future<Translation> translate(
    String text, {
    required TranslationLanguage from,
    required TranslationLanguage to,
  });
}

/// A [LibreTranslate](https://libretranslate.com) server.
///
/// The one backend that can exist today without shipping a native engine, and
/// it fits the bargain this app already makes for sync: bring your own server,
/// and nothing is sent anywhere until you name one. Until then the reader has
/// no translate button at all, rather than one that fails.
class LibreTranslateBackend implements TranslationBackend {
  LibreTranslateBackend({
    required this.baseUrl,
    this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;

  /// Public instances ask for one; a server you run yourself usually doesn't.
  final String? apiKey;

  final http.Client _http;

  @override
  String get name => 'LibreTranslate';

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  @override
  Future<Translation> translate(
    String text, {
    required TranslationLanguage from,
    required TranslationLanguage to,
  }) async {
    if (text.trim().isEmpty) {
      throw const TranslationException('There is nothing selected to translate.');
    }
    final http.Response res;
    try {
      res = await _http.post(
        _uri('/translate'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'source': from.code,
          'target': to.code,
          'format': 'text',
          if (apiKey != null && apiKey!.isNotEmpty) 'api_key': apiKey,
        }),
      );
    } catch (e) {
      throw TranslationException('Could not reach $baseUrl — $e');
    }

    if (res.statusCode != 200) {
      throw TranslationException(_errorFrom(res));
    }

    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic> || body['translatedText'] is! String) {
      throw const TranslationException(
        'That server answered something this app does not understand.',
      );
    }
    return Translation(
      text: body['translatedText'] as String,
      // LibreTranslate reports what it detected only when asked to detect.
      detected: from == TranslationLanguage.auto
          ? TranslationLanguage.byCode(
              (body['detectedLanguage'] as Map<String, dynamic>?)?['language']
                  as String?,
            )
          : null,
    );
  }

  /// The server's own words where it gave any, since they name the actual
  /// problem ("es is not supported").
  static String _errorFrom(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic> && body['error'] is String) {
        return body['error'] as String;
      }
    } catch (_) {
      // Not JSON. Fall through to the status code.
    }
    return 'The translation server answered ${res.statusCode}.';
  }
}
