import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import 'tts_controller.dart';

/// The slice of the OS audio session that reading aloud needs, so the policy
/// below can be tested with a fake one. The real one is [PluginAudioSession].
abstract class SpeechAudioSession {
  /// Another app (a call, a player) taking the audio, and giving it back.
  Stream<AudioInterruptionEvent> get interruptions;

  /// The headphones were unplugged.
  Stream<void> get becomingNoisy;

  /// Configures the session as speech and asks for the audio. False when the
  /// system refused (a call is in progress, say).
  Future<bool> activate();

  /// Gives the audio back, so other apps can resume.
  Future<void> deactivate();
}

/// Something else that makes sound and must not talk over the voice: the
/// audiobook player. Only one of the two is audible at a time.
abstract class SpeechRival {
  bool get playing;

  /// Pauses the rival.
  Future<void> pause();

  /// Calls [onStart] each time the rival starts playing. Returns the remover.
  VoidCallback addStartListener(VoidCallback onStart);
}

/// Real session, from the `audio_session` package the audiobook player already
/// uses. Android and macOS only (as in `configureAudioSession`): elsewhere
/// there is no such session and [forPlatform] gives null.
class PluginAudioSession implements SpeechAudioSession {
  PluginAudioSession._();

  static SpeechAudioSession? forPlatform() =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS
          ? PluginAudioSession._()
          : null;

  Future<AudioSession>? _session;

  Future<AudioSession> _get() => _session ??= () async {
        final session = await AudioSession.instance;
        // The same profile the audiobook player picks: spoken word.
        await session.configure(const AudioSessionConfiguration.speech());
        return session;
      }();

  @override
  Stream<AudioInterruptionEvent> get interruptions async* {
    yield* (await _get()).interruptionEventStream;
  }

  @override
  Stream<void> get becomingNoisy async* {
    yield* (await _get()).becomingNoisyEventStream;
  }

  @override
  Future<bool> activate() async {
    try {
      return await (await _get()).setActive(true);
    } catch (_) {
      // No session to ask: carry on without one rather than not speak.
      return true;
    }
  }

  @override
  Future<void> deactivate() async {
    try {
      await (await _get()).setActive(false);
    } catch (_) {}
  }
}

/// What reading aloud does about the rest of the device's audio (roadmap
/// v1.4.3 follow-up). `flutter_tts` takes audio focus when it speaks but never
/// reports losing it, so the controller would carry on through a phone call.
///
/// - **Interruption** (a call, another app's playback): pause. When a
///   *transient* one ends, carry on if it was this that paused it and the
///   reader has not touched the controls since. A permanent loss never resumes.
/// - **Headphones unplugged**: pause, and stay paused.
/// - **The audiobook player**: starting to read pauses it, and it starting
///   pauses the reading, so the two are never audible together. The audio
///   session is shared by the whole app, so neither takes the other's focus
///   away by releasing it — [_release] leaves it alone while the rival plays.
///
/// Everything is attached on the first time the voice plays, so a reader that
/// never reads aloud costs nothing and tests need no platform.
class SpeechSession {
  SpeechSession({
    required this.controller,
    this.audio,
    this.rival,
  }) {
    controller.addListener(_onState);
  }

  final TtsController controller;
  final SpeechAudioSession? audio;
  final SpeechRival? rival;

  TtsState _last = TtsState.stopped;
  bool _attached = false;
  bool _disposed = false;

  /// This session paused the voice for an interruption, and has not been
  /// overruled by the reader since.
  bool _pausedByUs = false;

  /// And whether that interruption is one that ends (a transient loss).
  bool _resumable = false;

  /// A resume this session started, so it is not mistaken for the reader's.
  bool _resuming = false;

  final _subs = <StreamSubscription<void>>[];
  VoidCallback? _removeRival;

  void _onState() {
    if (_disposed) return;
    final state = controller.state;
    final was = _last;
    _last = state;
    if (state == was) return;
    switch (state) {
      case TtsState.playing:
        if (!_resuming) _pausedByUs = false;
        _attach();
        if (!_resuming) unawaited(_acquire());
      case TtsState.paused:
        // Held through an interruption, whose end will want it back; given up
        // when the reader paused.
        if (!_pausedByUs) unawaited(_release());
      case TtsState.stopped:
        _pausedByUs = false;
        unawaited(_release());
    }
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    final audio = this.audio;
    if (audio != null) {
      _subs.add(audio.interruptions.listen(_onInterruption, onError: (_) {}));
      _subs.add(audio.becomingNoisy.listen((_) => _onNoisy(), onError: (_) {}));
    }
    final rival = this.rival;
    if (rival != null) _removeRival = rival.addStartListener(_onRivalStart);
  }

  /// Takes the audio for speaking: quiets the audiobook, then asks the system.
  Future<bool> _acquire() async {
    final rival = this.rival;
    if (rival != null && rival.playing) await rival.pause();
    final granted = await audio?.activate() ?? true;
    if (!granted && !_disposed && controller.playing) {
      // The system said no (a call is in progress): wait rather than talk.
      _pausedByUs = false;
      await controller.pause();
    }
    return granted;
  }

  Future<void> _release() async {
    // The audiobook may have taken the session over; releasing it now would
    // pull its audio focus out from under it.
    if (rival?.playing ?? false) return;
    await audio?.deactivate();
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (_disposed) return;
    if (event.begin) {
      if (!controller.playing) return;
      _pausedByUs = true;
      _resumable = event.type != AudioInterruptionType.unknown;
      unawaited(controller.pause());
      return;
    }
    if (!_pausedByUs) return;
    // A later permanent loss cannot be undone by an earlier transient end.
    if (!_resumable || controller.state != TtsState.paused) {
      _pausedByUs = false;
      return;
    }
    unawaited(_resumeAfterInterruption());
  }

  Future<void> _resumeAfterInterruption() async {
    _resuming = true;
    try {
      final granted = await audio?.activate() ?? true;
      if (_disposed || !_pausedByUs || controller.state != TtsState.paused) {
        return;
      }
      if (granted) {
        _pausedByUs = false;
        await controller.resume();
      }
    } finally {
      _resuming = false;
    }
  }

  void _onNoisy() {
    if (_disposed || !controller.playing) return;
    _pausedByUs = false;
    unawaited(controller.pause());
  }

  void _onRivalStart() {
    if (_disposed || !controller.playing) return;
    _pausedByUs = false;
    unawaited(controller.pause());
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_onState);
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _removeRival?.call();
    _removeRival = null;
    if (_last != TtsState.stopped) unawaited(_release());
  }
}
