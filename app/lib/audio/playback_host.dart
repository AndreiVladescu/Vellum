import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'audio_engine.dart';
import 'audiobook_player.dart';
import 'background_playback.dart';
import 'playback_options.dart';

/// What the app is playing right now, which is not the same thing as the
/// player page being open.
///
/// In v1.5.0 the page owned the [AudiobookPlayer] and closing the page ended
/// playback. Now the host owns it: the page, the mini bar on the shell and the
/// system's media session are three views of the same player, and any of them
/// can come and go. One book at a time; opening another saves and replaces the
/// first.
class PlaybackHost extends ChangeNotifier {
  PlaybackHost({
    BackgroundPlayback? background,
    this.engine,
    this.speedStore,
  }) : background = background ?? BackgroundPlayback();

  /// The app's one host.
  static final PlaybackHost instance = PlaybackHost();

  final BackgroundPlayback background;

  /// Replace the real backend and the speed preferences; for tests.
  final AudioEngine Function()? engine;
  final SpeedStore? speedStore;

  AudiobookPlayer? _player;
  LibraryRepository? _repository;
  Book? _book;
  Future<AudiobookPlayer>? _opening;

  /// The player, or null when nothing is loaded.
  AudiobookPlayer? get player => _player;
  Book? get book => _book;
  LibraryRepository? get repository => _repository;
  String? get bookId => _player?.bookId;

  /// Makes [bookId] the book being played, unless it already is, in which
  /// case the running player is returned untouched — which is how reopening
  /// the page, or tapping the mini bar, finds playback exactly where it was.
  ///
  /// [channelName] and [untitledChapter] are strings for the system's
  /// notification, which the host cannot look up itself: it has no
  /// `BuildContext`. `reused` says the book was already loaded. Throws what
  /// [AudiobookPlayer.load] throws.
  Future<({AudiobookPlayer player, bool reused})> open(
    LibraryRepository repository,
    String bookId, {
    required String channelName,
    required String Function(int number) untitledChapter,
  }) async {
    // A second tap while the first is loading waits for it.
    final pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final current = _player;
    if (current != null && current.bookId == bookId) {
      return (player: current, reused: true);
    }
    final loading = _replace(repository, bookId, channelName, untitledChapter);
    _opening = loading;
    try {
      return (player: await loading, reused: false);
    } finally {
      _opening = null;
    }
  }

  Future<AudiobookPlayer> _replace(
    LibraryRepository repository,
    String bookId,
    String channelName,
    String Function(int number) untitledChapter,
  ) async {
    final player = AudiobookPlayer(
      repository: repository,
      bookId: bookId,
      engine: engine,
      speedStore: speedStore,
    );
    try {
      await player.load(); // throws before anything is replaced
    } catch (_) {
      player.dispose();
      rethrow;
    }
    await _release();
    final db = repository.db;
    final book = await (db.select(db.books)..where((b) => b.id.equals(bookId)))
        .getSingleOrNull();
    _player = player;
    _repository = repository;
    _book = book;
    var author = '';
    try {
      final authors = await repository.watchAuthorsByBook().first;
      author = (authors[bookId] ?? const <String>[]).join(', ');
    } catch (_) {}
    final cover = book == null ? null : repository.coverFileOf(book);
    // The handover: from here the system's controls drive this player.
    await background.attach(
      player,
      channelName: channelName,
      title: book?.title ?? '',
      author: author.isEmpty ? null : author,
      artUri: cover != null && cover.existsSync() ? cover.uri : null,
      untitledChapter: untitledChapter,
    );
    notifyListeners();
    return player;
  }

  /// Stops and forgets the current book (the mini bar's close button). The
  /// position is saved first.
  Future<void> close() async {
    await _release();
    notifyListeners();
  }

  Future<void> _release() async {
    final player = _player;
    if (player == null) return;
    _player = null;
    _book = null;
    background.detach();
    if (player.playing) await player.pause();
    player.dispose(); // saves the position on the way out
  }
}
