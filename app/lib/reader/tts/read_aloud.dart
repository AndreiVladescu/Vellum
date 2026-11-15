import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_controller.dart';
import 'tts_engine.dart';

/// Everything a reader needs to read aloud (roadmap v1.4.3): the engine, the
/// remembered speed and voice, and the [TtsController] that moves through the
/// book. One per open reader, disposed with it — which is what stops the
/// speech when the reader closes.
class ReadAloud extends ChangeNotifier with WidgetsBindingObserver {
  ReadAloud({
    required TtsSource source,
    this.bookLanguage,
    TtsEngine? engine,
  }) : engine = engine ?? createTtsEngine() {
    controller = TtsController(engine: this.engine, source: source);
    controller.addListener(notifyListeners);
    WidgetsBinding.instance.addObserver(this);
  }

  final TtsEngine engine;
  late final TtsController controller;
  SharedPreferences? _prefs;

  /// The book's own language (an EPUB's `dc:language`), when it says. Chooses
  /// the voice's language until a voice has been picked by hand.
  String? bookLanguage;

  static const minRate = 0.5;
  static const maxRate = 2.0;
  static const _rateKey = 'reader.tts.rate';
  static const _voiceKey = 'reader.tts.voice';

  /// Null until [init] has asked the engine. While it is, the action is
  /// shown as unavailable rather than guessed at.
  bool? available;

  double _rate = 1.0;
  double get rate => _rate;

  TtsVoice? _voice;
  TtsVoice? get voice => _voice;

  List<TtsVoice> voices = const [];

  /// The language the engine is asked for when no voice has been chosen: the
  /// book's, else the device's.
  String get language {
    final book = bookLanguage?.trim();
    if (book != null && book.isNotEmpty) return book;
    return PlatformDispatcher.instance.locale.toLanguageTag();
  }

  Future<void> init() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    _rate = (prefs.getDouble(_rateKey) ?? 1.0).clamp(minRate, maxRate);
    _voice = TtsVoice.parse(prefs.getString(_voiceKey));
    available = await engine.isAvailable();
    if (available == true) voices = await engine.voices();
    // A remembered voice that this engine no longer has (another device's
    // preference, an uninstalled voice pack) is not applied.
    if (_voice != null && voices.isNotEmpty && !voices.contains(_voice)) {
      _voice = null;
    }
    notifyListeners();
  }

  Future<void> setRate(double value) async {
    _rate = value.clamp(minRate, maxRate);
    notifyListeners();
    await _prefs?.setDouble(_rateKey, _rate);
    await engine.setRate(_rate);
  }

  Future<void> setVoice(TtsVoice? value) async {
    _voice = value;
    notifyListeners();
    final prefs = _prefs;
    if (value == null) {
      await prefs?.remove(_voiceKey);
    } else {
      await prefs?.setString(_voiceKey, value.id);
    }
    await _apply();
  }

  Future<void> _apply() async {
    await engine.setRate(_rate);
    final voice = _voice;
    if (voice != null) {
      await engine.setVoice(voice);
    } else {
      await engine.setVoice(null);
      await engine.setLanguage(language);
    }
  }

  /// Starts reading [section] at [offset]; see [TtsController.play].
  Future<void> start(int section, {int offset = 0}) async {
    if (available != true) return;
    await _apply();
    await controller.play(section, offset: offset);
  }

  Future<void> stop() => controller.stop();

  /// Background playback is not offered, so leaving the app silences it
  /// rather than leaving a voice talking from a screen nobody is looking at.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(notifyListeners);
    controller.dispose();
    engine.dispose();
    super.dispose();
  }
}
