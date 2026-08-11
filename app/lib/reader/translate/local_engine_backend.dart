import 'dart:convert';
import 'dart:io';

import 'translation_backend.dart';

/// Whether a translator *could* be installed on this platform at all.
///
/// These engines are command-line programs, which a phone has no way to run —
/// so this is the desktop half of "can this device translate without a
/// server?". It used to be the other way round: ML Kit answered for phones and
/// this answered for desktops. ML Kit is gone, so a phone's answer is a
/// LibreTranslate address or nothing.
bool get localEngineSupportedHere =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

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

  /// What to run to find out whether it is here.
  ///
  /// Not `--help` for both: **apertium exits 1 on an unknown option**, and
  /// `--help` is one — it prints `ERROR: Unknown option -` and returns a
  /// failure, which is why an apt-installed apertium was invisible to this
  /// until now. `-l` is a real command it answers with a zero exit, and the
  /// answer is the list of pairs it has.
  List<String> get probe => switch (this) {
        LocalEngine.argos => const ['--help'],
        LocalEngine.apertium => const ['-l'],
      };

  /// The command that lists the language pairs this engine can do.
  List<String> get listCommand => switch (this) {
        // `argospm` is a separate binary that ships with argostranslate.
        LocalEngine.argos => const ['list'],
        LocalEngine.apertium => const ['-l'],
      };

  /// The binary that answers [listCommand].
  String get listExecutable => switch (this) {
        LocalEngine.argos => 'argospm',
        LocalEngine.apertium => executable,
      };

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

  /// Every engine installed here, best first.
  ///
  /// More than one is normal — Argos from pip and Apertium from apt do not
  /// know about each other — and they rarely have the same pairs. Asking only
  /// the first is how a machine with `apertium eng-spa` fails to translate
  /// Spanish because Argos, which is better but has only `en_ro`, answered the
  /// door.
  static Future<List<LocalEngineBackend>> detectAll({ProcessRunner? runner}) async {
    final run = runner ?? _run;
    final found = <LocalEngineBackend>[];
    for (final engine in LocalEngine.values) {
      try {
        await run(engine.executable, engine.probe);
        found.add(LocalEngineBackend(engine, runner: runner));
      } on ProcessException {
        // Not installed.
      } catch (_) {
        // Present but unusable.
      }
    }
    return found;
  }

  /// The first engine that answers, or null when none is installed.
  ///
  /// Asked by running the thing rather than by looking for a file: a translator
  /// on the PATH is the question, and `which` answers a different one on a
  /// machine with shell aliases or a pipx shim.
  ///
  /// **Starting is the evidence, not the exit code.** A command that runs and
  /// then complains is installed; only a `ProcessException` — no such binary —
  /// means it is not. Requiring a zero exit is what hid an apt-installed
  /// apertium, which fails `--help` by design.
  static Future<LocalEngineBackend?> detect({ProcessRunner? runner}) async {
    final run = runner ?? _run;
    for (final engine in LocalEngine.values) {
      try {
        await run(engine.executable, engine.probe);
        return LocalEngineBackend(engine, runner: runner);
      } on ProcessException {
        // Not installed. Try the next one.
      } catch (_) {
        // Anything else (a shim that misbehaves) is also "not usable".
      }
    }
    return null;
  }

  /// The language pairs this engine can actually do, as it reports them.
  ///
  /// Worth asking rather than assuming: an engine is installed long before its
  /// packs are, and "Apertium is here" while German→English silently fails is
  /// the confusing half of the story. Returns an empty list when the listing
  /// command is missing or says nothing.
  Future<List<String>> installedPairs() async {
    try {
      final result = await _runner(engine.listExecutable, engine.listCommand);
      if (result.exitCode != 0) return const [];
      return [
        for (final line in (result.stdout as String).split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    } on ProcessException {
      return const [];
    } catch (_) {
      return const [];
    }
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


/// Every local translator on the machine, tried in turn.
///
/// The pairs an engine has are not the pairs you want, and the two engines are
/// installed by different package managers with different coverage. So a
/// failure from the best one is a reason to ask the next, not a reason to stop:
/// what the reader wants is the passage translated, not a particular program
/// run.
class LocalTranslators implements TranslationBackend {
  const LocalTranslators(this.engines);

  final List<LocalEngineBackend> engines;

  /// Null when nothing is installed, so the caller can say so rather than
  /// holding an object that can only fail.
  static Future<LocalTranslators?> detect({ProcessRunner? runner}) async {
    final engines = await LocalEngineBackend.detectAll(runner: runner);
    return engines.isEmpty ? null : LocalTranslators(engines);
  }

  @override
  String get name => engines.length == 1
      ? engines.single.name
      : '${engines.first.engine.label} and ${engines.length - 1} other'
          '${engines.length == 2 ? '' : 's'}, on this machine';

  @override
  Future<Translation> translate(
    String text, {
    required TranslationLanguage from,
    required TranslationLanguage to,
  }) async {
    TranslationException? last;
    for (final engine in engines) {
      try {
        return await engine.translate(text, from: from, to: to);
      } on TranslationException catch (e) {
        // "Pick the language it is coming from" is about the request, not this
        // engine — asking another one would produce the same answer.
        if (from == TranslationLanguage.auto) rethrow;
        last = e;
      }
    }
    throw last ??
        const TranslationException('No translator is installed on this machine.');
  }
}
