import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../data/sync_clock.dart';
import 'audio_engine.dart';
import 'audiobook_import.dart';
import 'playback_options.dart';

/// One chapter, placed on the whole book's timeline.
class BookChapter {
  const BookChapter({required this.title, required this.startMs, required this.part});
  final String? title;

  /// From the start of part 1.
  final int startMs;

  /// Index into [AudiobookPlayer.parts].
  final int part;
}

/// Turns "seconds into the book" into (part, offset) and back, from the
/// parts' durations (docs/AUDIOBOOKS.md §4). The only place that arithmetic
/// lives.
class PartTimeline {
  PartTimeline(List<int> durationsMs) : _durations = List.of(durationsMs);

  final List<int> _durations;

  int get length => _durations.length;
  int durationOf(int part) => _durations[part];
  void setDuration(int part, int ms) => _durations[part] = ms;

  int get totalMs => _durations.fold(0, (a, b) => a + b);

  int startOf(int part) {
    var sum = 0;
    for (var i = 0; i < part; i++) {
      sum += _durations[i];
    }
    return sum;
  }

  /// The part holding [bookMs] and the offset into it. A position past the
  /// end lands at the end of the last part.
  (int part, int offsetMs) locate(int bookMs) {
    var start = 0;
    final at = bookMs < 0 ? 0 : bookMs;
    for (var i = 0; i < _durations.length; i++) {
      final end = start + _durations[i];
      // A part whose length is not known yet (0) still owns its own start,
      // or it could never be opened — and opening it is what measures it.
      final unknownHere = _durations[i] == 0 && at == start;
      if (at < end || unknownHere || i == _durations.length - 1) {
        final offset = at - start;
        return (i, offset > _durations[i] ? _durations[i] : offset);
      }
      start = end;
    }
    return (0, 0);
  }
}

/// Plays one book's audio parts as one timeline, and remembers where you are.
///
/// Owned by the `PlaybackHost` (v1.5.1), not by the player page, so playback
/// carries on when the page is left; the media session of the background
/// service drives it through the same methods as the page's buttons. It is a
/// plain [ChangeNotifier] with no widget in it, which is also what the session
/// recorder of v1.5.3 will hang off.
///
/// The position is saved to `books.listenPosition` on pause, on every seek and
/// chapter skip, every [saveEvery] while playing, and on [dispose]; each save
/// sets `needsProgressPush`, which is what puts it on the reading-progress
/// channel. `readingProgress` is never written here.
class AudiobookPlayer extends ChangeNotifier {
  AudiobookPlayer({
    required this.repository,
    required this.bookId,
    AudioEngine Function()? engine,
    this.saveEvery = const Duration(seconds: 15),
    SpeedStore? speedStore,
  })  : _engineFactory = engine ?? JustAudioEngine.new,
        _speedStore = speedStore ?? PrefsSpeedStore();

  final LibraryRepository repository;
  final String bookId;
  final Duration saveEvery;
  final AudioEngine Function() _engineFactory;
  final SpeedStore _speedStore;

  /// How often the sleep timer looks at the clock. Short, so the fade is a
  /// smooth ramp and "end of chapter" stops within a quarter second.
  static const sleepTick = Duration(milliseconds: 250);

  AudioEngine? _engine;
  StreamSubscription<bool>? _playingSub;
  Timer? _sleepTimer;
  Duration? _sleepLeft;
  bool _sleepAtChapterEnd = false;

  /// Where the chapter the timer is waiting for ends, on the book's timeline.
  int _sleepTargetMs = 0;
  double _speed = 1.0;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completedSub;
  Timer? _saveTimer;

  List<BookFile> parts = const [];
  List<BookChapter> chapters = const [];
  late PartTimeline _timeline;
  int _part = 0;
  int _offsetMs = 0;
  bool _playing = false;
  bool _ended = false;
  bool _startedOnce = false;
  bool _disposed = false;

  bool get playing => _playing;

  /// The playback speed, 1.0 being normal.
  double get speed => _speed;

  /// Whether a sleep timer is running, of either kind.
  bool get sleepActive => _sleepLeft != null || _sleepAtChapterEnd;

  /// True when the timer waits for the chapter to end rather than a clock.
  bool get sleepAtChapterEnd => _sleepAtChapterEnd;

  /// Time left on a timed sleep timer, in listening time (it does not run
  /// while paused), or null for none and for "end of chapter".
  Duration? get sleepRemaining => _sleepLeft;

  /// True once the last part has played to its end.
  bool get ended => _ended;
  int get currentPart => _part;
  Duration get position => Duration(milliseconds: _timeline.startOf(_part) + _offsetMs);
  Duration get total => Duration(milliseconds: _timeline.totalMs);

  /// The chapter playing now, as an index into [chapters], or -1.
  int get currentChapter {
    final at = position.inMilliseconds;
    var found = -1;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].startMs <= at) found = i;
    }
    return found;
  }

  /// Reads the parts, their chapters and the saved position, and opens the
  /// part that position falls in — paused. Throws [AudioUnavailable] when this
  /// device cannot play audio, and [StateError] for a book without audio.
  Future<void> load() async {
    final importer = AudiobookImporter(repository);
    parts = await importer.audioFilesOf(bookId);
    if (parts.isEmpty) throw StateError('no audio parts');
    _timeline = PartTimeline([for (final f in parts) f.durationMs ?? 0]);
    _rebuildChapters(await importer.chaptersOf(parts));
    final book = await (repository.db.select(repository.db.books)
          ..where((b) => b.id.equals(bookId)))
        .getSingleOrNull();
    final savedMs = ((book?.listenPosition ?? 0) * 1000).round();
    _engine = _engineFactory();
    _speed = normaliseSpeed(await _speedStore.read(bookId) ?? 1.0);
    if (_speed != 1.0) await _engine!.setSpeed(_speed);
    _playingSub = _engine!.playingStream.listen(_onEnginePlaying);
    _positionSub = _engine!.positionStream.listen((p) {
      _offsetMs = p.inMilliseconds;
      if (!_disposed) notifyListeners();
    });
    _completedSub = _engine!.completed.listen((_) => _onPartCompleted());
    final (part, offset) = _timeline.locate(savedMs);
    await _openPart(part, offset);
  }

  Map<String, List<AudioChapter>> _chaptersByFile = const {};

  void _rebuildChapters(Map<String, List<AudioChapter>> byFile) {
    _chaptersByFile = byFile;
    final out = <BookChapter>[];
    for (var i = 0; i < parts.length; i++) {
      final start = _timeline.startOf(i);
      final own = byFile[parts[i].id] ?? const <AudioChapter>[];
      if (own.isEmpty) {
        out.add(BookChapter(title: parts[i].label, startMs: start, part: i));
      }
      for (final c in own) {
        out.add(BookChapter(title: c.title, startMs: start + c.startMs, part: i));
      }
    }
    chapters = out;
  }

  Future<void> _openPart(int part, int offsetMs) async {
    _part = part;
    _offsetMs = offsetMs;
    final file = repository.fileOf(parts[part]);
    final measured = await _engine!.open(file.path, at: Duration(milliseconds: offsetMs));
    // A new source can reset the backend's speed (media_kit does on some
    // versions); saying it again is free.
    if (_speed != 1.0) await _engine!.setSpeed(_speed);
    // A part pulled or imported without a duration (a VBR mp3 with no
    // header) is measured by the player once, and the measurement kept: it
    // is synced, so every device sums the same numbers from then on.
    if (parts[part].durationMs == null && measured != null && measured > Duration.zero) {
      await _storeMeasuredDuration(part, measured.inMilliseconds);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _storeMeasuredDuration(int part, int ms) async {
    final db = repository.db;
    final file = parts[part];
    await db.transaction(() async {
      await (db.update(db.bookFiles)..where((f) => f.id.equals(file.id)))
          .write(BookFilesCompanion(durationMs: Value(ms)));
      await stampSyncClock(db, SyncedRow.book, bookId);
    });
    parts = [
      for (var i = 0; i < parts.length; i++)
        i == part ? parts[i].copyWith(durationMs: Value(ms)) : parts[i],
    ];
    _timeline.setDuration(part, ms);
    _rebuildChapters(_chaptersByFile);
  }

  Future<void> play() async {
    final engine = _engine;
    if (engine == null || _playing) return;
    if (_ended) {
      _ended = false;
      await _openPart(0, 0);
    }
    if (!_startedOnce) {
      _startedOnce = true;
      // The one automatic status change: the first play makes an unread book
      // "reading", exactly as opening it in a reader does.
      await repository.readingStatus.noteOpened(bookId);
    }
    _playing = true;
    await engine.play();
    _startSaving();
    notifyListeners();
  }

  void _startSaving() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(saveEvery, (_) => save());
  }

  /// The backend started or stopped on its own: audio focus was taken (a call,
  /// another app) or given back, or the headphones came out. The controller
  /// follows, saving the position when it was paused, so what the page and the
  /// notification show is what is true.
  void _onEnginePlaying(bool playing) {
    if (_disposed || playing == _playing) return;
    if (playing && _ended) return;
    _playing = playing;
    if (playing) {
      _startSaving();
    } else {
      _saveTimer?.cancel();
      unawaited(save());
    }
    notifyListeners();
  }

  /// Sets the speed (pitch is kept) and remembers it for this book.
  Future<void> setSpeed(double value) async {
    _speed = normaliseSpeed(value);
    await _engine?.setSpeed(_speed);
    await _speedStore.write(bookId, _speed);
    if (!_disposed) notifyListeners();
  }

  /// Stops playback after [after] of listening, fading out over the last
  /// [sleepFade]. Replaces any timer already running.
  void sleepFor(Duration after) {
    _sleepAtChapterEnd = false;
    _sleepLeft = after;
    _armSleep();
    notifyListeners();
  }

  /// Stops playback where the chapter now playing ends, fading out over the
  /// last [sleepFade] of it. Skipping to another chapter moves the stop to
  /// that chapter's end.
  void sleepAtEndOfChapter() {
    _sleepLeft = null;
    _sleepAtChapterEnd = true;
    _sleepTargetMs = _chapterEndMs(position.inMilliseconds);
    _armSleep();
    notifyListeners();
  }

  void cancelSleep() {
    if (!sleepActive) return;
    _clearSleep();
    unawaited(_engine?.setVolume(1.0));
    notifyListeners();
  }

  void _armSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer.periodic(sleepTick, (_) => _sleepTicked());
  }

  void _clearSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepLeft = null;
    _sleepAtChapterEnd = false;
  }

  /// Where the chapter containing [bookMs] ends, on the book's timeline.
  int _chapterEndMs(int bookMs) {
    var end = _timeline.totalMs;
    for (final c in chapters) {
      if (c.startMs > bookMs && c.startMs < end) end = c.startMs;
    }
    return end;
  }

  void _sleepTicked() {
    final engine = _engine;
    if (engine == null || !_playing) return; // a pause freezes the countdown
    Duration remaining;
    if (_sleepAtChapterEnd) {
      final nowMs = _timeline.startOf(_part) + engine.position.inMilliseconds;
      final end = _chapterEndMs(nowMs);
      if (end != _sleepTargetMs) {
        // Either playback ran over the end of the chapter between two ticks,
        // which is what the timer waits for, or the listener moved to another
        // chapter, which moves the wait to that chapter's end.
        final ranOver =
            nowMs >= _sleepTargetMs && nowMs - _sleepTargetMs <= 2000;
        if (ranOver) {
          unawaited(_stopForSleep());
          return;
        }
        _sleepTargetMs = end;
      }
      final leftMs = _sleepTargetMs - nowMs;
      // Book time to listening time: at 2x the rest of a chapter takes half
      // as long, and the fade should be ten real seconds.
      remaining = Duration(microseconds: (leftMs * 1000 / _speed).round());
    } else {
      remaining = _sleepLeft! - sleepTick;
      _sleepLeft = remaining;
    }
    if (remaining <= Duration.zero) {
      unawaited(_stopForSleep());
      return;
    }
    unawaited(engine.setVolume(sleepVolume(remaining)));
    if (!_sleepAtChapterEnd) notifyListeners();
  }

  Future<void> _stopForSleep() async {
    _clearSleep();
    await pause(); // saves the position
    await _engine?.setVolume(1.0);
  }

  Future<void> pause() async {
    final engine = _engine;
    if (engine == null) return;
    _playing = false;
    _saveTimer?.cancel();
    await engine.pause();
    await save();
    notifyListeners();
  }

  /// Moves to [target] on the whole book's timeline, crossing into another
  /// part when it has to.
  Future<void> seek(Duration target) async {
    final engine = _engine;
    if (engine == null) return;
    final (part, offset) = _timeline.locate(target.inMilliseconds);
    _ended = false;
    if (part == _part) {
      _offsetMs = offset;
      await engine.seek(Duration(milliseconds: offset));
    } else {
      await _openPart(part, offset);
      if (_playing) await engine.play();
    }
    await save();
    notifyListeners();
  }

  /// Back or forward by [delta] (the ±30 s buttons).
  Future<void> skip(Duration delta) {
    final target = position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > total ? total : target);
    return seek(clamped);
  }

  Future<void> jumpToChapter(int index) =>
      seek(Duration(milliseconds: chapters[index].startMs));

  /// The next chapter, for the notification's skip button. Nothing at the
  /// last one.
  Future<void> nextChapter() async {
    final next = currentChapter + 1;
    if (next < chapters.length) await jumpToChapter(next);
  }

  /// Like a CD player's back button: more than [restartAfter] into the chapter
  /// it restarts it, sooner than that it goes to the one before.
  Future<void> previousChapter(
      {Duration restartAfter = const Duration(seconds: 3)}) async {
    final current = currentChapter;
    if (current < 0) return seek(Duration.zero);
    final into = position.inMilliseconds - chapters[current].startMs;
    if (into > restartAfter.inMilliseconds || current == 0) {
      return jumpToChapter(current);
    }
    await jumpToChapter(current - 1);
  }

  Future<void> _onPartCompleted() async {
    if (_part + 1 < parts.length && _sleepAtChapterEnd) {
      // The chapter ended with the part: line up the next one, paused.
      _playing = false;
      _saveTimer?.cancel();
      await _openPart(_part + 1, 0);
      await _stopForSleep();
      return;
    }
    if (_part + 1 < parts.length) {
      await _openPart(_part + 1, 0);
      if (_playing) await _engine!.play();
      await save();
      return;
    }
    // The end of the book. The page offers "Mark as finished"; nothing here
    // decides it.
    _playing = false;
    _ended = true;
    _clearSleep();
    unawaited(_engine?.setVolume(1.0));
    _saveTimer?.cancel();
    _offsetMs = _timeline.durationOf(_part);
    await save();
    if (!_disposed) notifyListeners();
  }

  /// Writes the current position (seconds from the start of part 1).
  Future<void> save() async {
    if (_engine == null) return;
    await repository.readingPositions
        .saveListenPosition(bookId, position.inMilliseconds / 1000);
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _sleepTimer?.cancel();
    final engine = _engine;
    unawaited(() async {
      try {
        if (engine != null) {
          await save();
          await _positionSub?.cancel();
          await _playingSub?.cancel();
          await _completedSub?.cancel();
          await engine.dispose();
        }
      } catch (_) {
        // Closing down: a failed last save is retried by nothing, and the
        // previous one (at most [saveEvery] old) stands.
      }
    }());
    super.dispose();
  }
}
