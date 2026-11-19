import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../snack_bars.dart';
import 'attach_audio.dart';
import 'audio_engine.dart';
import 'audio_formats.dart';
import 'audiobook_player.dart';

/// The book page's way into the player: nothing for a book without audio,
/// "Listen" for one not started, "Resume listening · 1:02:33" otherwise.
class ListenButton extends StatelessWidget {
  const ListenButton({super.key, required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookFile>>(
      stream: repository.watchFilesOf(book.id),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <BookFile>[];
        if (!files.any((f) => isAudioFormat(f.format))) {
          return const SizedBox.shrink();
        }
        final l10n = L10n.of(context);
        final at = book.listenPosition;
        return FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlayerPage(bookId: book.id, repository: repository),
          )),
          icon: const Icon(Icons.headphones),
          label: Text(at == null || at < 1
              ? l10n.listenListen
              : l10n.listenResume(
                  formatAudioTime(Duration(milliseconds: (at * 1000).round())))),
        );
      },
    );
  }
}

/// A basic audiobook player (v1.5.0): play and pause, ±30 s, the chapter list
/// and skipping between chapters, and the position remembered locally and on
/// the reading-progress channel. Speed, the sleep timer and background
/// playback come in v1.5.1, on top of [AudiobookPlayer] rather than this page.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.bookId,
    required this.repository,
    this.engine,
  });

  final String bookId;
  final LibraryRepository repository;

  /// Replaces the real backend; for tests.
  final AudioEngine Function()? engine;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final AudiobookPlayer _player = AudiobookPlayer(
    repository: widget.repository,
    bookId: widget.bookId,
    engine: widget.engine,
  );
  Book? _book;
  Object? _error;
  bool _loading = true;
  bool _endPromptShown = false;

  /// Where the slider is being dragged to, so it follows the finger rather
  /// than snapping back to the playing position until it is let go.
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
    _load();
  }

  Future<void> _load() async {
    try {
      _book = await _readBook();
      await _player.load();
      if (mounted) await _maybeOfferJump();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// One read, not a stream: the page only needs the row as it opens.
  Future<Book?> _readBook() {
    final db = widget.repository.db;
    return (db.select(db.books)..where((b) => b.id.equals(widget.bookId)))
        .getSingleOrNull();
  }

  /// "You were at 5:12:33 on Pixel 8 — go there?" Offered, never adopted.
  Future<void> _maybeOfferJump() async {
    final book = await _readBook();
    if (book == null) return;
    final positions = widget.repository.readingPositions;
    final offer = positions.listenOfferFor(
      book: book,
      remotes: await positions.remotePositions(widget.bookId),
      totalSeconds: _player.total.inMilliseconds / 1000,
    );
    if (offer == null || !mounted) return;
    final time =
        formatAudioTime(Duration(milliseconds: (offer.seconds * 1000).round()));
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = L10n.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.readResumeTitle),
          content: Text(l10n.listenResumeBody(
              time, offer.deviceLabel ?? l10n.listenAnotherDevice)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.listenStayHere),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.listenGoTo(time)),
            ),
          ],
        );
      },
    );
    if (go == true) {
      await _player.seek(Duration(milliseconds: (offer.seconds * 1000).round()));
    }
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_player.ended && !_endPromptShown) {
      _endPromptShown = true;
      final l10n = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
        content: Text(l10n.playerEndedPrompt),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l10n.playerMarkFinished,
          onPressed: () => widget.repository.readingStatus
              .setStatus(widget.bookId, ReadingStatus.finished),
        ),
      ));
    }
    if (!_player.ended) _endPromptShown = false;
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _player.dispose(); // saves the position on the way out
    super.dispose();
  }

  String _chapterTitle(L10n l10n, int index) {
    final title = _player.chapters[index].title?.trim();
    return title == null || title.isEmpty ? l10n.playerChapterNumber(index + 1) : title;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_book?.title ?? '')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(l10n)
              : _playerView(context, l10n),
    );
  }

  Widget _errorView(L10n l10n) {
    final error = _error;
    final text = error is AudioUnavailable && Platform.isLinux
        ? l10n.playerNeedsLibmpv
        : l10n.playerUnavailable(error is AudioUnavailable ? error.detail : '$error');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _playerView(BuildContext context, L10n l10n) {
    final theme = Theme.of(context);
    final position = _player.position;
    final total = _player.total;
    final current = _player.currentChapter;
    final cover = _book == null ? null : widget.repository.coverFileOf(_book!);
    final maxMs = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              if (cover != null && cover.existsSync())
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(cover, height: 96, fit: BoxFit.cover),
                  ),
                ),
              Expanded(
                child: Text(
                  current >= 0 ? _chapterTitle(l10n, current) : '',
                  style: theme.textTheme.titleMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Slider(
            value: (_dragMs ?? position.inMilliseconds.toDouble()).clamp(0, maxMs),
            max: maxMs,
            onChanged: (v) => setState(() => _dragMs = v),
            onChangeEnd: (v) {
              setState(() => _dragMs = null);
              _player.seek(Duration(milliseconds: v.round()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatAudioTime(position), style: theme.textTheme.bodySmall),
              Text(formatAudioTime(total), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: l10n.playerPreviousChapter,
              icon: const Icon(Icons.skip_previous),
              onPressed: current > 0 ? () => _player.jumpToChapter(current - 1) : null,
            ),
            IconButton(
              tooltip: l10n.playerBack30,
              icon: const Icon(Icons.replay_30),
              onPressed: () => _player.skip(const Duration(seconds: -30)),
            ),
            IconButton.filled(
              iconSize: 40,
              tooltip: _player.playing ? l10n.playerPause : l10n.playerPlay,
              icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
              onPressed: _player.playing ? _player.pause : _player.play,
            ),
            IconButton(
              tooltip: l10n.playerForward30,
              icon: const Icon(Icons.forward_30),
              onPressed: () => _player.skip(const Duration(seconds: 30)),
            ),
            IconButton(
              tooltip: l10n.playerNextChapter,
              icon: const Icon(Icons.skip_next),
              onPressed: current + 1 < _player.chapters.length
                  ? () => _player.jumpToChapter(current + 1)
                  : null,
            ),
          ],
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.playerChapters, style: theme.textTheme.titleSmall),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _player.chapters.length,
            itemBuilder: (context, i) {
              final chapter = _player.chapters[i];
              return ListTile(
                selected: i == current,
                title: Text(_chapterTitle(l10n, i)),
                trailing: Text(
                    formatAudioTime(Duration(milliseconds: chapter.startMs))),
                onTap: () => _player.jumpToChapter(i),
              );
            },
          ),
        ),
      ],
    );
  }
}
