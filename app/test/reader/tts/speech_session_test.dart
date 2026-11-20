// Read aloud and the rest of the device's audio: pause for a call, carry on
// after a short one, pause when headphones come out, and never be audible at
// the same time as the audiobook player. A fake session and a fake rival stand
// in for the platform.
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/tts/speech_session.dart';
import 'package:vellum/reader/tts/tts_controller.dart';
import 'package:vellum/reader/tts/tts_engine.dart';
import 'package:vellum/reader/tts/tts_text.dart';

class _Engine implements TtsEngine {
  Completer<bool>? _current;
  @override
  String? lastError;
  @override
  Future<bool> speak(String text) {
    _current?.complete(false);
    return (_current = Completer<bool>()).future;
  }

  @override
  Future<void> stop() async {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete(false);
  }

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<TtsVoice>> voices() async => const [];
  @override
  Future<void> setRate(double multiplier) async {}
  @override
  Future<void> setLanguage(String language) async {}
  @override
  Future<void> setVoice(TtsVoice? voice) async {}
  @override
  Future<void> dispose() async {}
}

class _Source implements TtsSource {
  @override
  int get sectionCount => 1;
  @override
  Future<List<TtsChunk>> chunksOf(int section) async =>
      speechChunks('One. Two. Three.');
  @override
  void onSpeaking(int section, int index, TtsChunk chunk) {}
  @override
  void onSectionSkipped(int section) {}
  @override
  void onFinished() {}
  @override
  void onError(String message) {}
}

class _FakeAudio implements SpeechAudioSession {
  final interruption = StreamController<AudioInterruptionEvent>.broadcast();
  final noisy = StreamController<void>.broadcast();
  final log = <String>[];
  bool grant = true;

  @override
  Stream<AudioInterruptionEvent> get interruptions => interruption.stream;
  @override
  Stream<void> get becomingNoisy => noisy.stream;
  @override
  Future<bool> activate() async {
    log.add('activate');
    return grant;
  }

  @override
  Future<void> deactivate() async => log.add('deactivate');
}

class _FakeRival implements SpeechRival {
  @override
  bool playing = false;
  int pauses = 0;
  final _listeners = <VoidCallback>[];

  @override
  Future<void> pause() async {
    pauses++;
    playing = false;
  }

  @override
  VoidCallback addStartListener(VoidCallback onStart) {
    _listeners.add(onStart);
    return () => _listeners.remove(onStart);
  }

  /// The audiobook starts.
  void start() {
    playing = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeAudio audio;
  late _FakeRival rival;
  late TtsController controller;
  late SpeechSession session;

  setUp(() {
    audio = _FakeAudio();
    rival = _FakeRival();
    controller = TtsController(engine: _Engine(), source: _Source());
    session = SpeechSession(controller: controller, audio: audio, rival: rival);
  });
  tearDown(() {
    session.dispose();
    controller.dispose();
  });

  Future<void> begin(AudioInterruptionType type) async {
    audio.interruption.add(AudioInterruptionEvent(true, type));
    await settle();
  }

  Future<void> end(AudioInterruptionType type) async {
    audio.interruption.add(AudioInterruptionEvent(false, type));
    await settle();
    await settle();
  }

  test('speaking takes the audio, stopping gives it back', () async {
    await controller.play(0);
    await settle();
    expect(audio.log, ['activate']);
    await controller.stop();
    await settle();
    expect(audio.log, ['activate', 'deactivate']);
  });

  test('a call pauses, and a short one resumes afterwards', () async {
    await controller.play(0);
    await settle();
    await begin(AudioInterruptionType.pause);
    expect(controller.state, TtsState.paused);
    expect(audio.log, ['activate'], reason: 'focus is kept for the return');

    await end(AudioInterruptionType.pause);
    expect(controller.state, TtsState.playing);
  });

  test(
    'another app taking the audio for good pauses and never resumes',
    () async {
      await controller.play(0);
      await settle();
      await begin(AudioInterruptionType.unknown);
      expect(controller.state, TtsState.paused);
      await end(AudioInterruptionType.unknown);
      expect(controller.state, TtsState.paused);
    },
  );

  test(
    'a pause the reader chose is not undone when an interruption ends',
    () async {
      await controller.play(0);
      await settle();
      await controller.pause();
      await settle();
      await begin(AudioInterruptionType.pause); // nothing playing to interrupt
      await end(AudioInterruptionType.pause);
      expect(controller.state, TtsState.paused);
    },
  );

  test('the reader taking over during an interruption wins', () async {
    await controller.play(0);
    await settle();
    await begin(AudioInterruptionType.pause);
    await controller.resume(); // pressed play themselves
    await settle();
    await controller.pause(); // and paused again
    await settle();
    await end(AudioInterruptionType.pause);
    expect(controller.state, TtsState.paused);
  });

  test('unplugging the headphones pauses and stays paused', () async {
    await controller.play(0);
    await settle();
    audio.noisy.add(null);
    await settle();
    expect(controller.state, TtsState.paused);
    await end(AudioInterruptionType.pause);
    expect(controller.state, TtsState.paused);
  });

  test(
    'a refused focus request waits instead of speaking over a call',
    () async {
      audio.grant = false;
      await controller.play(0);
      await settle();
      await settle();
      expect(controller.state, TtsState.paused);
    },
  );

  test('reading pauses a playing audiobook', () async {
    rival.playing = true;
    await controller.play(0);
    await settle();
    expect(rival.pauses, 1);
    expect(rival.playing, isFalse);
  });

  test(
    'the audiobook starting pauses the reading and keeps its focus',
    () async {
      await controller.play(0);
      await settle();
      audio.log.clear();
      rival.start();
      await settle();
      expect(controller.state, TtsState.paused);
      expect(audio.log, isEmpty, reason: 'the audiobook now holds the session');
    },
  );

  test('a session that is disposed stops listening', () async {
    await controller.play(0);
    await settle();
    session.dispose();
    await begin(AudioInterruptionType.pause);
    expect(controller.state, TtsState.playing);
  });
}
