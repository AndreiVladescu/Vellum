import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// What the player needs from a playback backend: one file at a time.
///
/// One file at a time on purpose (docs/AUDIOBOOKS.md §7a): `just_audio`'s
/// playlist seek is broken on the media_kit backend, and a single code path
/// on every platform keeps "seconds into the book" → (part, offset) in one
/// place, [AudiobookPlayer]. Also the seam tests replace with a fake, and the
/// one v1.5.1 wraps for background playback and speed.
abstract class AudioEngine {
  /// Opens [path] positioned at [at], paused. Returns the file's duration as
  /// the backend measures it, when it can.
  Future<Duration?> open(String path, {Duration at = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Playback speed, 1.0 being normal. The pitch is kept: the backends
  /// time-stretch rather than resample.
  Future<void> setSpeed(double speed);

  /// Output volume, 0.0 to 1.0. The sleep timer's fade-out.
  Future<void> setVolume(double volume);

  /// Whether the backend is playing. Changes by itself when the system takes
  /// audio focus away (a call, another app) or the headphones are pulled out,
  /// which is how the player learns it was paused from outside.
  Stream<bool> get playingStream;

  /// The position within the open file.
  Duration get position;
  Stream<Duration> get positionStream;

  /// Fires when the open file plays to its end.
  Stream<void> get completed;
  Future<void> dispose();
}

/// Thrown when this device has no way to play audio — on Linux, no libmpv.
class AudioUnavailable implements Exception {
  AudioUnavailable(this.detail);
  final String detail;
  @override
  String toString() => 'AudioUnavailable: $detail';
}

bool _backendReady = false;

/// Registers the media_kit backend on Linux and Windows, once, lazily: only
/// when a player is first made, so startup never pays for it and a machine
/// without libmpv starts normally. Throws [AudioUnavailable] when libmpv
/// cannot be loaded.
void ensureAudioBackend() {
  if (_backendReady) return;
  try {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  } catch (e) {
    throw AudioUnavailable('$e');
  }
  _backendReady = true;
}

bool _sessionConfigured = false;

/// Tells the OS this is spoken-word media: Android then pauses for a call or
/// another app's playback and resumes after a short interruption, ducks for a
/// navigation prompt, and pauses when the headphones are unplugged
/// ("becoming noisy"). `just_audio` listens to the session and acts on all of
/// that itself, so the one thing to do here is choose the profile. Only where
/// `audio_session` has an implementation, and never fatal.
Future<void> configureAudioSession() async {
  if (_sessionConfigured || !(Platform.isAndroid || Platform.isMacOS)) return;
  _sessionConfigured = true;
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  } catch (_) {
    // Playback works with the defaults; only the speech profile is lost.
  }
}

/// The real engine: `just_audio` (ExoPlayer on Android, AVPlayer on macOS,
/// libmpv through media_kit on Linux and Windows).
class JustAudioEngine implements AudioEngine {
  JustAudioEngine() {
    ensureAudioBackend();
    unawaited(configureAudioSession());
    _player = AudioPlayer();
    _sub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _completed.add(null);
    });
  }

  late final AudioPlayer _player;
  late final StreamSubscription<ProcessingState> _sub;
  final _completed = StreamController<void>.broadcast();

  @override
  Future<Duration?> open(String path, {Duration at = Duration.zero}) =>
      _player.setFilePath(path, initialPosition: at);

  @override
  Future<void> play() async {
    // Not awaited: just_audio's play() completes when playback *stops*.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Duration get position => _player.position;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    await _completed.close();
    await _player.dispose();
  }
}
