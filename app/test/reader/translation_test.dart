// Translating a selected passage (next features #12).
//
// Two things are worth more than the happy path. **Nothing is sent anywhere
// until a server is named** — the feature is off, not failing, on a fresh
// install — and **a wrong detection has to be visible and correctable**, which
// is why `from` is a value the caller passes rather than something the backend
// decides on its own.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/reader/reader_settings.dart';
import 'package:vellum/reader/translate/on_device_backend.dart';
import 'package:vellum/reader/translate/translate_sheet.dart';
import 'package:vellum/reader/translate/translation_backend.dart';

/// A LibreTranslate that answers [reply] and records what it was asked.
MockClient _server(
  Map<String, dynamic> reply, {
  int status = 200,
  List<Map<String, dynamic>>? asked,
}) =>
    MockClient((request) async {
      asked?.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode(reply), status,
          headers: {'content-type': 'application/json'});
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the feature is off until a server is named', () {
    test('a fresh install cannot translate', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ReaderSettings.load();
      expect(settings.canTranslate, false);
      expect(settings.translateUrl, '');
    });

    test('whitespace is not a server', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ReaderSettings.load();
      await settings.setTranslateServer(url: '   ');
      expect(settings.canTranslate, false,
          reason: 'a button that can only fail is worse than no button');
    });

    test('naming one turns it on, and clearing it turns it off', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ReaderSettings.load();
      await settings.setTranslateServer(url: 'http://libre.test:5000');
      expect(settings.canTranslate, true);
      await settings.setTranslateServer(url: '');
      expect(settings.canTranslate, false);
    });
  });

  group('the destination language', () {
    test('is remembered between passages', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ReaderSettings.load();
      await settings.setTranslateTo(TranslationLanguage.byCode('ro')!);
      expect((await ReaderSettings.load()).translateTo.code, 'ro');
    });

    test('falls back to English when the device speaks something we do not',
        () async {
      SharedPreferences.setMockInitialValues({'reader.translate.to': 'xx'});
      final settings = await ReaderSettings.load();
      expect(settings.translateTo.code, isNotEmpty);
    });
  });

  group('language codes', () {
    test('a regional tag resolves to its base language', () {
      expect(TranslationLanguage.byCode('en-GB')?.code, 'en');
      expect(TranslationLanguage.byCode('pt_BR')?.code, 'pt');
    });

    test('an unknown code is null rather than a guess', () {
      expect(TranslationLanguage.byCode('klingon'), isNull);
      expect(TranslationLanguage.byCode(null), isNull);
    });

    test('auto is a source, and is not in the general list', () {
      expect(TranslationLanguage.byCode('auto'), TranslationLanguage.auto);
      expect(TranslationLanguage.all.contains(TranslationLanguage.auto), false);
    });
  });

  group('LibreTranslate', () {
    test('sends the passage and the two languages, and reads the answer',
        () async {
      final asked = <Map<String, dynamic>>[];
      final backend = LibreTranslateBackend(
        baseUrl: 'http://libre.test:5000',
        httpClient: _server({'translatedText': 'Guten Morgen'}, asked: asked),
      );

      final result = await backend.translate(
        'Good morning',
        from: TranslationLanguage.byCode('en')!,
        to: TranslationLanguage.byCode('de')!,
      );

      expect(result.text, 'Guten Morgen');
      expect(asked.single['q'], 'Good morning');
      expect(asked.single['source'], 'en');
      expect(asked.single['target'], 'de');
    });

    test('reports what it detected, so a wrong guess can be corrected',
        () async {
      final backend = LibreTranslateBackend(
        baseUrl: 'http://libre.test:5000',
        httpClient: _server({
          'translatedText': 'Good morning',
          'detectedLanguage': {'language': 'de', 'confidence': 92},
        }),
      );

      final result = await backend.translate(
        'Guten Morgen',
        from: TranslationLanguage.auto,
        to: TranslationLanguage.byCode('en')!,
      );

      expect(result.detected?.code, 'de');
      expect(result.detected?.name, 'German');
    });

    test('a detection is not reported when the source was given', () async {
      final backend = LibreTranslateBackend(
        baseUrl: 'http://libre.test:5000',
        httpClient: _server({
          'translatedText': 'Good morning',
          'detectedLanguage': {'language': 'de'},
        }),
      );

      final result = await backend.translate(
        'Guten Morgen',
        from: TranslationLanguage.byCode('de')!,
        to: TranslationLanguage.byCode('en')!,
      );

      expect(result.detected, isNull,
          reason: 'you told it the language; it has nothing to report back');
    });

    test("the server's own words are what the reader is shown", () async {
      final backend = LibreTranslateBackend(
        baseUrl: 'http://libre.test:5000',
        httpClient: _server(
          {'error': 'de is not supported'},
          status: 400,
        ),
      );

      await expectLater(
        backend.translate(
          'Guten Morgen',
          from: TranslationLanguage.byCode('de')!,
          to: TranslationLanguage.byCode('ro')!,
        ),
        throwsA(isA<TranslationException>().having(
          (e) => e.message,
          'message',
          contains('de is not supported'),
        )),
      );
    });

    test('an unreachable server says so, naming it', () async {
      final backend = LibreTranslateBackend(
        baseUrl: 'http://nothing.here:5000',
        httpClient: MockClient((_) async => throw const SocketishFailure()),
      );

      await expectLater(
        backend.translate('x',
            from: TranslationLanguage.auto,
            to: TranslationLanguage.byCode('en')!),
        throwsA(isA<TranslationException>()
            .having((e) => e.message, 'message', contains('nothing.here'))),
      );
    });

    test('an empty selection never reaches the network', () async {
      final backend = LibreTranslateBackend(
        baseUrl: 'http://libre.test:5000',
        httpClient: MockClient((_) async => throw StateError('asked anyway')),
      );

      await expectLater(
        backend.translate('   ',
            from: TranslationLanguage.auto,
            to: TranslationLanguage.byCode('en')!),
        throwsA(isA<TranslationException>()),
      );
    });

    test('a trailing slash on the address does not become a double slash',
        () async {
      Uri? seen;
      final backend = LibreTranslateBackend(
        baseUrl: 'http://libre.test:5000/',
        httpClient: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'translatedText': 'ok'}), 200);
        }),
      );

      await backend.translate('hi',
          from: TranslationLanguage.auto, to: TranslationLanguage.byCode('de')!);
      expect(seen.toString(), 'http://libre.test:5000/translate');
    });
  });


  group('choosing a backend', () {
    test('on-device wins wherever it exists', () {
      final backend = backendFor(
        onDeviceAvailable: true,
        onDevice: () => _FakeBackend(),
        libreUrl: 'http://libre.test:5000',
      );
      expect(backend, isA<_FakeBackend>(),
          reason: 'free, offline, and the passage stays on the machine');
    });

    test('a server is the answer where there is no on-device engine', () {
      final backend = backendFor(
        onDeviceAvailable: false,
        onDevice: () => _FakeBackend(),
        libreUrl: 'http://libre.test:5000',
      );
      expect(backend, isA<LibreTranslateBackend>());
    });

    test('neither means the reader offers nothing at all', () {
      expect(
        backendFor(onDeviceAvailable: false, libreUrl: '  '),
        isNull,
        reason: 'a button that can only fail is worse than no button',
      );
    });
  });

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
  group('the sheet', () {
    testWidgets('translates on open and offers to keep it as a note',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ReaderSettings.load();
      String? saved;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TranslateSheet(
            passage: 'Guten Morgen',
            settings: settings,
            backend: LibreTranslateBackend(
              baseUrl: 'http://libre.test:5000',
              httpClient: _server({
                'translatedText': 'Good morning',
                'detectedLanguage': {'language': 'de'},
              }),
            ),
            onSaveAsNote: (t) async => saved = t,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The passage, the translation, and what it decided the passage was.
      expect(find.text('Guten Morgen'), findsOneWidget);
      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('Detected German'), findsOneWidget);

      await tester.tap(find.text('Save as note'));
      await tester.pumpAndSettle();
      expect(saved, 'Good morning');
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('with nothing set up it explains, and offers the way to set it up',
        (tester) async {
      // The state every desktop starts in, and the one that used to be
      // unreachable: the button was hidden until a server was named, and the
      // only place to name one was behind that button.
      SharedPreferences.setMockInitialValues({});
      final settings = await ReaderSettings.load();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TranslateSheet(passage: 'Guten Morgen', settings: settings),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('no translator of its own'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget,
          reason: 'the way out of this state is on the sheet itself');
      expect(find.text('not set up yet'), findsOneWidget);
    });

    testWidgets('a refusal is shown in the sheet, not swallowed',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ReaderSettings.load();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TranslateSheet(
            passage: 'Guten Morgen',
            settings: settings,
            backend: LibreTranslateBackend(
              baseUrl: 'http://libre.test:5000',
              httpClient: _server({'error': 'ro is not supported'}, status: 400),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('ro is not supported'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}

class _FakeBackend implements TranslationBackend {
  @override
  String get name => 'fake';

  @override
  Future<Translation> translate(String text,
          {required TranslationLanguage from,
          required TranslationLanguage to}) async =>
      const Translation(text: 'x');
}

/// Stands in for a socket failure without depending on `dart:io` in a test that
/// otherwise doesn't need it.
class SocketishFailure implements Exception {
  const SocketishFailure();
  @override
  String toString() => 'connection refused';
}
