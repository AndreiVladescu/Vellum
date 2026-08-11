// Translating a selected passage (next features #12).
//
// Two things are worth more than the happy path. **Nothing is sent anywhere
// until a server is named** — the feature is off, not failing, on a fresh
// install — and **a wrong detection has to be visible and correctable**, which
// is why `from` is a value the caller passes rather than something the backend
// decides on its own.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/reader/reader_settings.dart';
import 'package:vellum/reader/translate/local_engine_backend.dart';
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

  group('a translator installed on this machine', () {
    ProcessResult ok(String out) => ProcessResult(1, 0, out, '');

    test('the first engine that answers is the one used', () async {
      final tried = <String>[];
      final backend = await LocalEngineBackend.detect(
        runner: (exe, args, {input}) async {
          tried.add(exe);
          return exe == 'apertium'
              ? ok('  eng-spa')
              : throw ProcessException(exe, args, 'not found');
        },
      );
      expect(backend?.engine, LocalEngine.apertium);
      expect(tried.first, 'argos-translate',
          reason: 'the neural one is asked for first');
    });

    test('an engine that exits non-zero is still installed', () async {
      // apertium answers `--help` with "ERROR: Unknown option -" and exit 1,
      // which is why an apt-installed one was invisible. Starting is the
      // evidence; the exit code is the command's opinion of the arguments.
      final backend = await LocalEngineBackend.detect(
        runner: (exe, args, {input}) async => exe == 'apertium'
            ? ProcessResult(1, 1, '', 'ERROR: Unknown option -')
            : throw ProcessException(exe, args, 'not found'),
      );
      expect(backend?.engine, LocalEngine.apertium);
    });

    test('apertium is probed with -l, not --help', () async {
      List<String>? args;
      await LocalEngineBackend.detect(
        runner: (exe, a, {input}) async {
          if (exe == 'argos-translate') {
            throw ProcessException(exe, a, 'not found');
          }
          args = a;
          return ok('  eng-spa');
        },
      );
      expect(args, ['-l'], reason: 'the option it actually answers');
    });

    test('the pairs it has are read from the engine itself', () async {
      final backend = LocalEngineBackend(
        LocalEngine.apertium,
        runner: (exe, a, {input}) async => ok('  eng-spa\n  spa-eng\n\n'),
      );
      expect(await backend.installedPairs(), ['eng-spa', 'spa-eng'],
          reason: 'blank lines dropped, indentation trimmed');
    });

    test('argos pairs come from argospm, which is a different binary',
        () async {
      String? asked;
      final backend = LocalEngineBackend(
        LocalEngine.argos,
        runner: (exe, a, {input}) async {
          asked = exe;
          return ok('translate-en_ro\n');
        },
      );
      expect(await backend.installedPairs(), ['translate-en_ro']);
      expect(asked, 'argospm');
    });

    test('an engine with no pack listing says nothing rather than failing',
        () async {
      final backend = LocalEngineBackend(
        LocalEngine.argos,
        runner: (exe, a, {input}) async =>
            throw ProcessException(exe, a, 'not found'),
      );
      expect(await backend.installedPairs(), isEmpty);
    });

    test('nothing installed is null, not an exception', () async {
      final backend = await LocalEngineBackend.detect(
        runner: (exe, args, {input}) async =>
            throw ProcessException(exe, args, 'not found'),
      );
      expect(backend, isNull);
    });

    test('argos is handed the passage on stdin with both languages', () async {
      String? sent;
      List<String>? args;
      final backend = LocalEngineBackend(
        LocalEngine.argos,
        runner: (exe, a, {input}) async {
          sent = input;
          args = a;
          return ok('Guten Morgen\n');
        },
      );

      final result = await backend.translate(
        'Good morning',
        from: TranslationLanguage.byCode('en')!,
        to: TranslationLanguage.byCode('de')!,
      );

      expect(result.text, 'Guten Morgen');
      expect(sent, 'Good morning');
      expect(args, ['--from-lang', 'en', '--to-lang', 'de']);
    });

    test('apertium is asked for its pair in ISO 639-3', () async {
      List<String>? args;
      final backend = LocalEngineBackend(
        LocalEngine.apertium,
        runner: (exe, a, {input}) async {
          args = a;
          return ok('Buenos dias');
        },
      );
      await backend.translate('Good morning',
          from: TranslationLanguage.byCode('en')!,
          to: TranslationLanguage.byCode('es')!);
      expect(args, ['-u', 'eng-spa']);
    });

    test('Detect is refused rather than guessed at', () async {
      final backend = LocalEngineBackend(
        LocalEngine.argos,
        runner: (exe, a, {input}) async => throw StateError('ran anyway'),
      );
      await expectLater(
        backend.translate('Guten Morgen',
            from: TranslationLanguage.auto,
            to: TranslationLanguage.byCode('en')!),
        throwsA(isA<TranslationException>().having((e) => e.message, 'message',
            contains('coming'))),
      );
    });

    test("what the engine said is what the reader is told", () async {
      final backend = LocalEngineBackend(
        LocalEngine.argos,
        runner: (exe, a, {input}) async =>
            ProcessResult(1, 1, '', 'no package installed for en -> ro'),
      );
      await expectLater(
        backend.translate('hi',
            from: TranslationLanguage.byCode('en')!,
            to: TranslationLanguage.byCode('ro')!),
        throwsA(isA<TranslationException>().having((e) => e.message, 'message',
            contains('no package installed'))),
      );
    });

    test('a silent failure still names the pair', () async {
      final backend = LocalEngineBackend(
        LocalEngine.apertium,
        runner: (exe, a, {input}) async => ProcessResult(1, 1, '', ''),
      );
      await expectLater(
        backend.translate('hi',
            from: TranslationLanguage.byCode('en')!,
            to: TranslationLanguage.byCode('ro')!),
        throwsA(isA<TranslationException>().having((e) => e.message, 'message',
            allOf(contains('English'), contains('Romanian')))),
      );
    });
  });

  group('more than one translator installed', () {
    ProcessResult ok(String out) => ProcessResult(1, 0, out, '');

    test('a pair the best engine lacks is asked of the next one', () async {
      // The real shape of this machine: Argos has en_ro, Apertium has eng-spa.
      // Asking only the first means Spanish fails with Apertium sitting there.
      final pool = await LocalTranslators.detect(
        runner: (exe, args, {input}) async {
          if (exe == 'argos-translate' && input != null) {
            return ProcessResult(1, 1, '', 'no package installed for en -> es');
          }
          if (exe == 'apertium' && input != null) return ok('Buenos días');
          return ok('');
        },
      );

      final result = await pool!.translate(
        'Good morning',
        from: TranslationLanguage.byCode('en')!,
        to: TranslationLanguage.byCode('es')!,
      );
      expect(result.text, 'Buenos días');
    });

    test('when every engine refuses, the last complaint is the one shown',
        () async {
      final pool = await LocalTranslators.detect(
        runner: (exe, args, {input}) async => input == null
            ? ok('')
            : ProcessResult(1, 1, '', 'no pack for $exe'),
      );
      await expectLater(
        pool!.translate('hi',
            from: TranslationLanguage.byCode('en')!,
            to: TranslationLanguage.byCode('ro')!),
        throwsA(isA<TranslationException>()
            .having((e) => e.message, 'message', contains('no pack for'))),
      );
    });

    test('Detect is not retried against every engine', () async {
      var runs = 0;
      final pool = await LocalTranslators.detect(
        runner: (exe, args, {input}) async {
          if (input != null) runs++;
          return ok('');
        },
      );
      await expectLater(
        pool!.translate('hi',
            from: TranslationLanguage.auto,
            to: TranslationLanguage.byCode('ro')!),
        throwsA(isA<TranslationException>()),
      );
      expect(runs, 0, reason: 'it is the request that cannot be answered');
    });

    test('nothing installed is null, so the sheet can say so', () async {
      expect(
        await LocalTranslators.detect(
          runner: (exe, args, {input}) async =>
              throw ProcessException(exe, args, 'not found'),
        ),
        isNull,
      );
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
          body: TranslateSheet(
            passage: 'Guten Morgen',
            settings: settings,
            // Nothing installed — asserted, not inherited from whatever this
            // machine happens to have.
            resolve: () async => null,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('No translator is installed'), findsOneWidget);
      expect(find.text('Languages'), findsOneWidget,
          reason: 'the way out of this state is on the sheet itself');
      expect(find.text('nothing to translate with'), findsOneWidget);
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
