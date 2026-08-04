import 'dart:convert';
import 'dart:io';

import 'translation_backend.dart';

/// Runs a command and hands back what it said. Injectable so the tests can
/// drive every branch without installing a translator.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? input,
});

Future<ProcessResult> _run(
  String executable,
  List<String> arguments, {
  String? input,
}) async {
  final process = await Process.start(executable, arguments);
  if (input != null) {
    process.stdin.write(input);
    await process.stdin.flush();
  }
  await process.stdin.close();
  final out = await process.stdout.transform(utf8.decoder).join();
  final err = await process.stderr.transform(utf8.decoder).join();
  return ProcessResult(process.pid, await process.exitCode, out, err);
}

/// A translator installed on this machine, driven as a command.
///
/// **No server, and nothing on a network.** The desktop has no equivalent of
/// ML Kit, and embedding an engine is a native build for every platform
/// (docs/NEXT_FEATURES.md #12). Until that exists, the way to translate a
/// passage on a desktop without sending it anywhere is a translator installed
/// on the same machine — which several distributions package, and which runs
/// as a process rather than as a service listening on a port.
///
/// Two are understood, in order of quality:
///
/// - **Argos Translate** (`argos-translate`), neural, the engine behind
///   LibreTranslate — the same translations, without the server around it.
///   Its language packs come from an open index and are managed with
///   `argospm`.
/// - **Apertium** (`apertium`), rule-based and older, but packaged by Debian,
///   Ubuntu and Fedora and installable in one line.
enum LocalEngine {
  argos('Argos Translate', 'argos-translate'),
  apertium('Apertium', 'apertium');

  const LocalEngine(this.label, this.executable);

  final String label;
  final String executable;

  /// What to type to get it. Shown verbatim, because a half-remembered
  /// instruction is worse than none.
  String get installHint => switch (this) {
        LocalEngine.argos =>
          'pipx install argostranslate  (then: argospm update && '
              'argospm install translate-en_de)',
        LocalEngine.apertium => 'sudo apt install apertium apertium-en-es',
      };
}

/// Translation by a locally installed engine.
class LocalEngineBackend implements TranslationBackend {
  LocalEngineBackend(this.engine, {ProcessRunner? runner})
      : _runner = runner ?? _run;

  final LocalEngine engine;
  final ProcessRunner _runner;

  @override
  String get name => '${engine.label}, on this machine';

  /// The first engine that answers, or null when none is installed.
  ///
  /// Asked by running the thing rather than by looking for a file: a translator
  /// on the PATH is the question, and `which` answers a different one on a
  /// machine with shell aliases or a pipx shim.
  static Future<LocalEngineBackend?> detect({ProcessRunner? runner}) async {
    final run = runner ?? _run;
    for (final engine in LocalEngine.values) {
      try {
        final result = await run(engine.executable, const ['--help']);
        if (result.exitCode == 0) {
          return LocalEngineBackend(engine, runner: runner);
        }
      } on ProcessException {
        // Not installed. Try the next one.
      } catch (_) {
        // Anything else (a shim that misbehaves) is also "not usable".
      }
    }
    return null;
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
    if (from == TranslationLanguage.auto) {
      // Neither command detects a language, and guessing wrong here produces
      // confident nonsense. Better to ask.
      throw const TranslationException(
        'Pick the language it is coming *from* — a translator on this machine '
        'cannot work it out on its own.',
      );
    }
    if (from == to) return Translation(text: text);

    final (executable, arguments) = switch (engine) {
      LocalEngine.argos => (
          engine.executable,
          ['--from-lang', from.code, '--to-lang', to.code],
        ),
      // Apertium names a pair as `eng-spa`, in ISO 639-3.
      LocalEngine.apertium => (
          engine.executable,
          ['-u', '${_iso3(from.code)}-${_iso3(to.code)}'],
        ),
    };

    final ProcessResult result;
    try {
      result = await _runner(executable, arguments, input: text);
    } on ProcessException catch (e) {
      throw TranslationException('${engine.label} could not be run — ${e.message}');
    }

    if (result.exitCode != 0) {
      final said = (result.stderr as String).trim();
      throw TranslationException(
        said.isEmpty
            ? '${engine.label} could not translate ${from.name} to ${to.name}. '
                'Its language pack for that pair may not be installed.'
            : said,
      );
    }
    final out = (result.stdout as String).trim();
    if (out.isEmpty) {
      throw TranslationException('${engine.label} returned nothing.');
    }
    return Translation(text: out);
  }

  /// ISO 639-1 → 639-3, which is what Apertium's pair names use. Only the
  /// languages this app offers; anything else is passed through and lets
  /// Apertium give its own error.
  static String _iso3(String code) => const {
        'ar': 'ara', 'cs': 'ces', 'de': 'deu', 'el': 'ell', 'en': 'eng',
        'es': 'spa', 'fa': 'pes', 'fr': 'fra', 'he': 'heb', 'hi': 'hin',
        'hu': 'hun', 'it': 'ita', 'ja': 'jpn', 'ko': 'kor', 'nl': 'nld',
        'pl': 'pol', 'pt': 'por', 'ro': 'ron', 'ru': 'rus', 'sv': 'swe',
        'tr': 'tur', 'uk': 'ukr', 'zh': 'zho',
      }[code] ??
      code;
}
