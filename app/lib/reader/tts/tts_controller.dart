import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tts_engine.dart';
import 'tts_text.dart';

/// What a reader gives the controller to read from: the book, cut into
/// sections (an EPUB's chapters, a PDF's pages), and a way to hear where the
/// voice has got to so the page can follow it.
abstract class TtsSource {
  /// How many sections there are; reading ends after the last.
  int get sectionCount;

  /// What to say for [section], in order. Empty when it has nothing to say (a
  /// scanned page) — the controller then tells [onSectionSkipped] and goes on.
  Future<List<TtsChunk>> chunksOf(int section);

  /// The voice has reached [chunk] ([index]th of [section]). Called before it
  /// is spoken, and also on a skip while paused, so the view can move.
  void onSpeaking(int section, int index, TtsChunk chunk);

  /// [section] had nothing to read and was passed over.
  void onSectionSkipped(int section);

  /// Reading ran off the end of the last section.
  void onFinished();

  /// The engine failed; [message] is the engine's own.
  void onError(String message);
}

enum TtsState { stopped, playing, paused }

/// Reads a [TtsSource] aloud, a sentence at a time (roadmap v1.4.3).
///
/// **How it moves.** One loop speaks the chunk at [index], waits for the engine
/// to finish it, and takes the next — rolling into the next section when the
/// last chunk is done. Anything that changes where the voice is (pause, skip,
/// stop) cancels the loop by bumping a token and starts a new one, so a
/// sentence finishing late never moves a position somebody has already changed.
///
/// **Pause is "stop, remembering where".** Engines disagree about pausing
/// (Android's cannot resume mid-sentence), so a pause stops the engine and
/// [resume] says the interrupted sentence again from its start — a repeat of at
/// most a sentence rather than silence or the wrong place.
class TtsController extends ChangeNotifier {
  TtsController({required this.engine, required this.source});

  final TtsEngine engine;
  final TtsSource source;

  TtsState _state = TtsState.stopped;
  TtsState get state => _state;
  bool get playing => _state == TtsState.playing;
  bool get active => _state != TtsState.stopped;

  int _section = 0;
  int get section => _section;

  List<TtsChunk> _chunks = const [];
  int _index = 0;

  /// Where the voice is in its section; null while stopped.
  TtsChunk? get current =>
      active && _index >= 0 && _index < _chunks.length ? _chunks[_index] : null;

  int _token = 0;
  bool _disposed = false;

  /// Starts reading [section] at the sentence containing [offset] (a character
  /// offset into the text the source cut its chunks from; 0 for the start).
  ///
  /// A section with nothing in it, wherever the start is, is skipped like any
  /// other. Returns once reading is under way, not when it is over.
  Future<void> play(int section, {int offset = 0}) async {
    final token = ++_token;
    await engine.stop();
    if (_disposed || token != _token) return;
    _state = TtsState.playing;
    _section = section;
    _chunks = const [];
    _index = 0;
    notifyListeners();
    final chunks = await source.chunksOf(section);
    if (_disposed || token != _token) return;
    _chunks = chunks;
    if (chunks.isEmpty) source.onSectionSkipped(section);
    _index = chunks.isEmpty ? 0 : chunkIndexAt(chunks, offset);
    unawaited(_run(token));
  }

  Future<void> pause() async {
    if (_state != TtsState.playing) return;
    _token++;
    _state = TtsState.paused;
    notifyListeners();
    await engine.stop();
  }

  Future<void> resume() async {
    if (_state != TtsState.paused) return;
    final token = ++_token;
    _state = TtsState.playing;
    notifyListeners();
    unawaited(_run(token));
  }

  Future<void> togglePause() => playing ? pause() : resume();

  Future<void> stop() async {
    if (_state == TtsState.stopped) return;
    _token++;
    _state = TtsState.stopped;
    _chunks = const [];
    notifyListeners();
    await engine.stop();
  }

  /// Moves the voice by [delta] sentences — negative goes back — across section
  /// boundaries. Keeps playing, or stays paused, as it was.
  Future<void> skip(int delta) async {
    if (!active || delta == 0) return;
    final wasPlaying = playing;
    final token = ++_token;
    await engine.stop();
    if (_disposed || token != _token) return;

    var section = _section;
    var chunks = _chunks;
    var index = _index + delta;
    // Walk into neighbouring sections until the target sentence is inside one.
    while (index >= chunks.length || index < 0) {
      if (index >= chunks.length) {
        if (section + 1 >= source.sectionCount) {
          // Past the end of the book: stay on its last sentence.
          index = chunks.isEmpty ? 0 : chunks.length - 1;
          break;
        }
        index -= chunks.length;
        section++;
        chunks = await source.chunksOf(section);
        if (_disposed || token != _token) return;
        if (chunks.isEmpty) {
          source.onSectionSkipped(section);
          index = 0;
        }
      } else {
        if (section == 0) {
          index = 0;
          break;
        }
        section--;
        chunks = await source.chunksOf(section);
        if (_disposed || token != _token) return;
        if (chunks.isEmpty) {
          source.onSectionSkipped(section);
          index = -1;
          continue;
        }
        index += chunks.length;
      }
    }
    _section = section;
    _chunks = chunks;
    _index = chunks.isEmpty ? 0 : index.clamp(0, chunks.length - 1);
    notifyListeners();
    if (wasPlaying) {
      unawaited(_run(token));
    } else if (current != null) {
      source.onSpeaking(_section, _index, current!);
    }
  }

  Future<void> _run(int token) async {
    while (token == _token && !_disposed) {
      if (_index >= _chunks.length) {
        if (!await _nextSection(token)) return;
        continue;
      }
      final chunk = _chunks[_index];
      source.onSpeaking(_section, _index, chunk);
      notifyListeners();
      final spoken = await engine.speak(chunk.text);
      if (token != _token || _disposed) return;
      if (!spoken) {
        final message = engine.lastError ?? 'speech failed';
        _token++;
        _state = TtsState.stopped;
        _chunks = const [];
        notifyListeners();
        source.onError(message);
        return;
      }
      _index++;
    }
  }

  /// Loads the next section with something in it; false when there is none (or
  /// this run was cancelled meanwhile), in which case reading has ended.
  Future<bool> _nextSection(int token) async {
    var next = _section + 1;
    while (next < source.sectionCount) {
      final chunks = await source.chunksOf(next);
      if (token != _token || _disposed) return false;
      if (chunks.isNotEmpty) {
        _section = next;
        _chunks = chunks;
        _index = 0;
        return true;
      }
      source.onSectionSkipped(next);
      next++;
    }
    _token++;
    _state = TtsState.stopped;
    _chunks = const [];
    notifyListeners();
    source.onFinished();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _token++;
    unawaited(engine.stop());
    super.dispose();
  }
}
