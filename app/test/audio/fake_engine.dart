import 'dart:async';

import 'package:vellum/audio/audio_engine.dart';

/// Records what the player asked for; positions are whatever it was told.
class FakeEngine implements AudioEngine {
  final opened = <(String, Duration)>[];
  bool isPlaying = false;
  double speed = 1.0;
  double volume = 1.0;
  final volumes = <double>[];
  Duration _position = Duration.zero;
  final _positions = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  Duration? reportDuration;

  /// Some backends forget the speed when a new file is opened.
  bool resetsSpeedOnOpen = false;

  @override
  Future<Duration?> open(String path, {Duration at = Duration.zero}) async {
    opened.add((path, at));
    _position = at;
    if (resetsSpeedOnOpen) speed = 1.0;
    return reportDuration;
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async => _position = position;
  @override
  Future<void> setSpeed(double value) async => speed = value;
  @override
  Future<void> setVolume(double value) async {
    volume = value;
    volumes.add(value);
  }

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Duration get position => _position;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<void> get completed => _completed.stream;

  void finishPart() => _completed.add(null);
  void tick(Duration at) {
    _position = at;
    _positions.add(at);
  }

  /// The system paused or resumed playback without being asked (a call, the
  /// headphones coming out).
  void interrupt({required bool playing}) {
    isPlaying = playing;
    _playing.add(playing);
  }

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _completed.close();
    await _playing.close();
  }
}
