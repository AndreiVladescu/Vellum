import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/tts/tts_controller.dart';
import 'package:vellum/reader/tts/tts_engine.dart';
import 'package:vellum/reader/tts/tts_text.dart';

class FakeEngine implements TtsEngine {
  final spoken = <String>[];
  Completer<bool>? _current;
  bool fail = false;

  @override
  String? lastError;

  /// Ends the sentence being spoken, as the engine does when it is done.
  void finish() {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete(true);
  }

  @override
  Future<bool> speak(String text) {
    final old = _current;
    if (old != null && !old.isCompleted) old.complete(false);
    spoken.add(text);
    if (fail) {
      lastError = 'boom';
      return Future.value(false);
    }
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

class FakeSource implements TtsSource {
  FakeSource(this.sections);
  final List<String> sections;
  final heard = <String>[];
  final skipped = <int>[];
  var finished = 0;
  String? error;

  @override
  int get sectionCount => sections.length;
  @override
  Future<List<TtsChunk>> chunksOf(int section) async =>
      speechChunks(sections[section]);
  @override
  void onSpeaking(int section, int index, TtsChunk chunk) =>
      heard.add('$section:${chunk.text}');
  @override
  void onSectionSkipped(int section) => skipped.add(section);
  @override
  void onFinished() => finished++;
  @override
  void onError(String message) => error = message;
}

void main() {
  late FakeEngine engine;
  late FakeSource source;
  late TtsController controller;

  setUp(() {
    engine = FakeEngine();
    source = FakeSource(['A one. A two.', '', 'B one. B two.']);
    controller = TtsController(engine: engine, source: source);
  });
  tearDown(() => controller.dispose());

  Future<void> settle() => pumpEventQueue();

  test('starts at the sentence containing the offset', () async {
    await controller.play(0, offset: 7);
    await settle();
    expect(engine.spoken, ['A two.']);
    expect(controller.playing, isTrue);
  });

  test('reads on sentence by sentence, then rolls into the next chapter',
      () async {
    await controller.play(0);
    await settle();
    engine.finish();
    await settle();
    engine.finish();
    await settle();
    // Section 1 is empty and is passed over.
    expect(engine.spoken, ['A one.', 'A two.', 'B one.']);
    expect(source.skipped, [1]);
    expect(controller.section, 2);
    engine.finish();
    await settle();
    engine.finish();
    await settle();
    expect(source.finished, 1);
    expect(controller.state, TtsState.stopped);
  });

  test('pause stops speaking; resume repeats the interrupted sentence',
      () async {
    await controller.play(0);
    await settle();
    await controller.pause();
    await settle();
    expect(controller.state, TtsState.paused);
    expect(engine.spoken, ['A one.']);
    await controller.resume();
    await settle();
    expect(engine.spoken, ['A one.', 'A one.']);
    engine.finish();
    await settle();
    expect(engine.spoken.last, 'A two.');
  });

  test('skip moves by a sentence, forward and back, while playing', () async {
    await controller.play(0);
    await settle();
    await controller.skip(1);
    await settle();
    expect(engine.spoken.last, 'A two.');
    await controller.skip(-1);
    await settle();
    expect(engine.spoken.last, 'A one.');
    // Forward over the end of a chapter and the empty one after it.
    await controller.skip(2);
    await settle();
    expect(engine.spoken.last, 'B one.');
    expect(controller.section, 2);
    // And back again across the same gap.
    await controller.skip(-1);
    await settle();
    expect(engine.spoken.last, 'A two.');
    expect(controller.section, 0);
  });

  test('skip while paused moves the view but stays silent', () async {
    await controller.play(0);
    await settle();
    await controller.pause();
    final before = engine.spoken.length;
    await controller.skip(1);
    await settle();
    expect(engine.spoken.length, before);
    expect(controller.state, TtsState.paused);
    expect(source.heard.last, '0:A two.');
  });

  test('stop silences and forgets; a stale sentence end changes nothing',
      () async {
    await controller.play(0);
    await settle();
    await controller.stop();
    engine.finish();
    await settle();
    expect(controller.state, TtsState.stopped);
    expect(engine.spoken, ['A one.']);
  });

  test('an engine failure stops reading and says why', () async {
    engine.fail = true;
    await controller.play(0);
    await settle();
    expect(controller.state, TtsState.stopped);
    expect(source.error, 'boom');
  });

  test('a book with no text anywhere ends without speaking', () async {
    final quiet =
        TtsController(engine: engine, source: FakeSource(['', '  ']));
    await quiet.play(0);
    await settle();
    expect(engine.spoken, isEmpty);
    expect(quiet.state, TtsState.stopped);
    quiet.dispose();
  });
}
