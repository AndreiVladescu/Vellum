import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_tts/flutter_tts.dart';

/// A voice an engine offers. [name] and [locale] are what the engine itself
/// calls it; both are needed to select one (Android has many voices a language).
class TtsVoice {
  const TtsVoice(this.name, this.locale);

  final String name;
  final String locale;

  /// The stored form: one string, because the preference is one value.
  String get id => '$name|$locale';

  static TtsVoice? parse(String? id) {
    if (id == null) return null;
    final at = id.lastIndexOf('|');
    if (at <= 0) return null;
    return TtsVoice(id.substring(0, at), id.substring(at + 1));
  }

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// What the reader needs from a text-to-speech engine, and no more.
///
/// An interface so the controller is tested against a fake (the real thing
/// needs a device with a speech service), and so Linux — which the
/// `flutter_tts` plugin does not support — can have an engine of its own.
abstract class TtsEngine {
  /// Whether this machine can speak at all. False when there is no engine
  /// installed (a phone with no speech service; a Linux box without
  /// speech-dispatcher); the reader then explains instead of offering the
  /// action.
  Future<bool> isAvailable();

  /// The voices to choose from; empty when the platform offers no choice.
  Future<List<TtsVoice>> voices();

  /// [multiplier] is 1.0 for the engine's normal speed, 0.5 half of it, 2.0
  /// twice it. Each platform's own scale is the engine's business.
  Future<void> setRate(double multiplier);

  /// A BCP-47 tag such as `en-US`, or a bare language such as `fr`. Ignored
  /// when the engine has no voice for it.
  Future<void> setLanguage(String language);

  /// Null goes back to the engine's own choice (for the language).
  Future<void> setVoice(TtsVoice? voice);

  /// Says [text]. Completes with true once it has been spoken in full; with
  /// false if [stop] cut it short or the engine failed — [lastError] says which.
  Future<bool> speak(String text);

  /// Cuts off whatever is being said. Safe to call when nothing is.
  Future<void> stop();

  /// Set when the last [speak] failed, null otherwise.
  String? get lastError;

  Future<void> dispose();
}

/// The engine for this platform, wrapped so nothing outside this file knows
/// which plugin or program it is.
TtsEngine createTtsEngine() =>
    Platform.isLinux ? SpeechDispatcherEngine() : PluginTtsEngine();

/// Android (the system `TextToSpeech` service, so no engine ships with the
/// app), Windows (SAPI), macOS and iOS (`AVSpeechSynthesizer`), through the
/// `flutter_tts` plugin.
class PluginTtsEngine implements TtsEngine {
  PluginTtsEngine() {
    _tts.setCompletionHandler(() => _finish(true));
    _tts.setCancelHandler(() => _finish(false));
    _tts.setErrorHandler((message) {
      _error = '$message';
      _finish(false);
    });
  }

  final _tts = FlutterTts();
  Completer<bool>? _pending;
  String? _error;

  @override
  String? get lastError => _error;

  void _finish(bool spoken) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(spoken);
  }

  @override
  Future<bool> isAvailable() async {
    try {
      if (Platform.isAndroid) {
        // No speech service installed: the plugin initialises against nothing
        // and every call fails later and less clearly than this does now.
        final engines = await _tts.getEngines;
        return engines is List && engines.isNotEmpty;
      }
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<TtsVoice>> voices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final voices = <TtsVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name'];
        final locale = entry['locale'];
        if (name is String && locale is String) {
          voices.add(TtsVoice(name, locale));
        }
      }
      voices.sort((a, b) {
        final byLocale = a.locale.compareTo(b.locale);
        return byLocale != 0 ? byLocale : a.name.compareTo(b.name);
      });
      return voices;
    } catch (_) {
      return const [];
    }
  }

  /// The plugin's rate is 0–1 and means a different speed on each platform, so
  /// the multiplier is mapped per platform, measured against what each calls
  /// normal: Android doubles the number it is given (0.5 is normal), Windows
  /// adds 0.5 to it (0.5 is normal), and Apple's default utterance rate is 0.5.
  /// Apple's scale is not linear — 1.0 is far faster than twice normal — so
  /// the faster half is flattened.
  static double pluginRate(double multiplier, {required bool apple}) {
    final m = multiplier.clamp(0.5, 2.0);
    if (apple) {
      return m <= 1 ? 0.25 + (m - 0.5) * 0.5 : 0.5 + (m - 1) * 0.2;
    }
    if (Platform.isWindows) return (m - 0.5).clamp(0.0, 1.0);
    return (m / 2).clamp(0.0, 1.0);
  }

  @override
  Future<void> setRate(double multiplier) => _tts.setSpeechRate(
      pluginRate(multiplier, apple: Platform.isIOS || Platform.isMacOS));

  @override
  Future<void> setLanguage(String language) async {
    try {
      await _tts.setLanguage(language);
    } catch (_) {
      // A language the engine does not have: it keeps speaking in its own.
    }
  }

  @override
  Future<void> setVoice(TtsVoice? voice) async {
    try {
      if (voice == null) {
        await _tts.clearVoice();
      } else {
        await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      }
    } catch (_) {}
  }

  @override
  Future<bool> speak(String text) async {
    await stop();
    _error = null;
    final done = _pending = Completer<bool>();
    try {
      // `focus` asks Android for audio focus, so a call or another player
      // ducks this rather than talking over it.
      final result = await _tts.speak(text, focus: true);
      // The plugin answers 1 when the utterance was accepted. Anything else
      // means nothing will ever call back, so don't wait for it.
      if (result != null && result != 1) {
        _error = 'speak returned $result';
        _finish(false);
      }
    } catch (e) {
      _error = '$e';
      _finish(false);
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    // The plugin does not reliably call the cancel handler on every platform,
    // so whoever is waiting is told here instead.
    _finish(false);
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() => stop();
}

/// Linux: the `spd-say` client of speech-dispatcher, the speech service the
/// desktop's screen readers use. The `flutter_tts` plugin has no Linux
/// implementation, and a command-line client adds no dependency to the app —
/// it is simply used if it is there.
///
/// Each sentence is one `spd-say --wait` run, which returns when the sentence
/// has been spoken. Stopping kills the client and then cancels what the server
/// had already queued.
class SpeechDispatcherEngine implements TtsEngine {
  double _multiplier = 1;
  String? _language;
  Process? _running;
  String? _error;
  bool? _available;

  @override
  String? get lastError => _error;

  @override
  Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      final result = await Process.run('spd-say', ['--version']);
      return _available = result.exitCode == 0;
    } on ProcessException {
      return _available = false;
    }
  }

  /// speech-dispatcher's own scale is −100 to 100, with 0 normal.
  static int dispatcherRate(double multiplier) {
    final m = multiplier.clamp(0.5, 2.0);
    return ((m >= 1 ? (m - 1) * 100 : (m - 1) * 200)).round();
  }

  /// A bare `en-US` becomes `en`: speech-dispatcher takes ISO 639 languages.
  static String? dispatcherLanguage(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    return tag.split(RegExp(r'[-_]')).first.toLowerCase();
  }

  @override
  Future<List<TtsVoice>> voices() async => const [];

  @override
  Future<void> setRate(double multiplier) async => _multiplier = multiplier;

  @override
  Future<void> setLanguage(String language) async => _language = language;

  @override
  Future<void> setVoice(TtsVoice? voice) async {}

  @override
  Future<bool> speak(String text) async {
    await stop();
    _error = null;
    final language = dispatcherLanguage(_language);
    try {
      final process = await Process.start('spd-say', [
        '--wait',
        '-r',
        '${dispatcherRate(_multiplier)}',
        if (language != null) ...['-l', language],
        // Everything after this is text, even a sentence starting with a dash.
        '--',
        text,
      ]);
      _running = process;
      // Drained so a chatty client can never block on a full pipe.
      unawaited(process.stdout.drain<void>());
      final stderr = StringBuffer();
      final errors = process.stderr
          .transform(const SystemEncoding().decoder)
          .forEach(stderr.write);
      final code = await process.exitCode;
      await errors;
      if (!identical(_running, process)) return false; // stopped meanwhile
      _running = null;
      if (code != 0) {
        _error = stderr.toString().trim().isEmpty
            ? 'spd-say exited with $code'
            : stderr.toString().trim();
        return false;
      }
      return true;
    } on ProcessException catch (e) {
      _error = e.message;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final process = _running;
    if (process == null) return;
    _running = null;
    process.kill();
    try {
      // The client is gone; the server may still be speaking what it was sent.
      await Process.run('spd-say', ['-C']);
    } on ProcessException {
      // Nothing to cancel with.
    }
  }

  @override
  Future<void> dispose() => stop();
}
