import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../snack_bars.dart';
import 'attach_audio.dart';
import 'audio_download_view.dart';
import 'audio_downloads.dart';
import 'audio_engine.dart';
import 'audio_formats.dart';
import 'audiobook_player.dart';
import 'playback_host.dart';
import 'playback_options.dart';
import 'player_sheets.dart';

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

/// The audiobook player: play and pause, ±30 s, the chapter list and skipping
/// between chapters, speed, the sleep timer, and the position remembered
/// locally and on the reading-progress channel.
///
/// A view of the [AudiobookPlayer] the [PlaybackHost] holds, not its owner:
/// leaving the page leaves the book playing, and opening it again finds it
/// where it was.
class PlayerPage extends StatefulWidget {
  PlayerPage({
    super.key,
    required this.bookId,
    required this.repository,
    PlaybackHost? host,
    AudioDownloads? downloads,
  })  : host = host ?? PlaybackHost.instance,
        downloads = downloads ?? AudioDownloads.instance;

  final String bookId;
  final LibraryRepository repository;

  /// What is playing; the app's own unless a test passes one.
  final PlaybackHost host;

  /// Fetches audio that is not on this device yet.
  final AudioDownloads downloads;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  AudiobookPlayer? _player;
  bool _started = false;
  Book? _book;
  Object? _error;
  bool _loading = true;
  bool _endPromptShown = false;

  /// Where the slider is being dragged to, so it follows the finger rather
  /// than snapping back to the playing position until it is let go.
  double? _dragMs;

  // Not initState: opening the book needs the localised strings for the
  // notification, and a State may not read inherited widgets there.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(L10n.of(context));
  }

  Future<void> _load(L10n l10n) async {
    try {
      _book = await _readBook();
      final opened = await widget.host.open(
        widget.repository,
        widget.bookId,
        channelName: l10n.playerChannelName,
        untitledChapter: l10n.playerChapterNumber,
      );
      _player = opened.player..addListener(_onPlayerChanged);
      // Listen on a book whose audio is not here (docs/AUDIOBOOKS.md §6):
      // start fetching it, the part with the position first, so play can
      // begin as soon as that one has arrived. The Wi-Fi rule may hold it
      // back; the panel at the top then asks.
      if (_player!.parts.any((f) => !f.present)) {
        unawaited(widget.downloads.download(
          widget.repository,
          widget.bookId,
          firstFileId: _player!.currentPartFile.id,
        ));
      }
      // Only for a book just opened: one already playing has no use for
      // "go to where you were on another device".
      if (mounted && !opened.reused) await _maybeOfferJump();
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
      totalSeconds: _player!.total.inMilliseconds / 1000,
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
      await _player!.seek(Duration(milliseconds: (offer.seconds * 1000).round()));
    }
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_player!.ended && !_endPromptShown) {
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
    if (!_player!.ended) _endPromptShown = false;
  }

  @override
  void dispose() {
    // Only a view: the host's player goes on playing.
    _player?.removeListener(_onPlayerChanged);
    super.dispose();
  }

  String _chapterTitle(L10n l10n, int index) {
    final title = _player!.chapters[index].title?.trim();
    return title == null || title.isEmpty ? l10n.playerChapterNumber(index + 1) : title;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final player = _player;
    return Scaffold(
      appBar: AppBar(
        title: Text(_book?.title ?? ''),
        actions: [
          if (player != null && player.parts.isNotEmpty)
            _RemoveDownloadMenu(
              bookId: widget.bookId,
              repository: widget.repository,
              downloads: widget.downloads,
              host: widget.host,
            ),
        ],
      ),
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
    final player = _player!;
    final position = player.position;
    final total = player.total;
    final current = player.currentChapter;
    final cover = _book == null ? null : widget.repository.coverFileOf(_book!);
    final maxMs = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AudioDownloadPanel(
            bookId: widget.bookId,
            repository: widget.repository,
            downloads: widget.downloads,
            host: widget.host,
            firstFileId: () => _player?.currentPartFile.id,
          ),
        ),
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
              player.seek(Duration(milliseconds: v.round()));
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
              onPressed: current > 0 ? () => player.jumpToChapter(current - 1) : null,
            ),
            IconButton(
              tooltip: l10n.playerBack30,
              icon: const Icon(Icons.replay_30),
              onPressed: () => player.skip(const Duration(seconds: -30)),
            ),
            // Asked to play while the part downloads: it shows as playing,
            // so a second tap takes the wish back.
            IconButton.filled(
              iconSize: 40,
              tooltip: player.playing || player.playPending
                  ? l10n.playerPause
                  : l10n.playerPlay,
              icon: Icon(player.playing || player.playPending
                  ? Icons.pause
                  : Icons.play_arrow),
              onPressed: player.playing || player.playPending
                  ? player.pause
                  : player.play,
            ),
            IconButton(
              tooltip: l10n.playerForward30,
              icon: const Icon(Icons.forward_30),
              onPressed: () => player.skip(const Duration(seconds: 30)),
            ),
            IconButton(
              tooltip: l10n.playerNextChapter,
              icon: const Icon(Icons.skip_next),
              onPressed: current + 1 < player.chapters.length
                  ? () => player.jumpToChapter(current + 1)
                  : null,
            ),
          ],
        ),
        if (player.waitingForPart || player.partMissing)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (player.waitingForPart)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Flexible(
                  child: Text(
                    player.waitingForPart
                        ? l10n.playerWaitingForPart
                        : l10n.playerPartNotHere,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.speed),
              label: Text(l10n.playerSpeedButton(formatSpeed(player.speed, locale: l10n.localeName))),
              onPressed: () => showSpeedSheet(context, player),
            ),
            TextButton.icon(
              icon: Icon(player.sleepActive ? Icons.bedtime : Icons.bedtime_outlined),
              label: Text(player.sleepActive
                  ? (player.sleepAtChapterEnd
                      ? l10n.playerSleepAtChapterEnd
                      : l10n.playerSleepIn(
                          formatAudioTime(player.sleepRemaining!)))
                  : l10n.playerSleepButton),
              onPressed: () => showSleepSheet(context, player),
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
            itemCount: player.chapters.length,
            itemBuilder: (context, i) {
              final chapter = player.chapters[i];
              return ListTile(
                selected: i == current,
                title: Text(_chapterTitle(l10n, i)),
                trailing: Text(
                    formatAudioTime(Duration(milliseconds: chapter.startMs))),
                onTap: () => player.jumpToChapter(i),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The player's overflow menu: Remove download, once some of the book's
/// audio is on this device. Removing stops the book, so the page closes.
class _RemoveDownloadMenu extends StatefulWidget {
  const _RemoveDownloadMenu({
    required this.bookId,
    required this.repository,
    required this.downloads,
    required this.host,
  });

  final String bookId;
  final LibraryRepository repository;
  final AudioDownloads downloads;
  final PlaybackHost host;

  @override
  State<_RemoveDownloadMenu> createState() => _RemoveDownloadMenuState();
}

class _RemoveDownloadMenuState extends State<_RemoveDownloadMenu> {
  // Once, not per build: the page rebuilds on every position tick.
  late final Stream<List<BookFile>> _files =
      widget.repository.watchFilesOf(widget.bookId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookFile>>(
      stream: _files,
      builder: (context, snapshot) {
        final here = [
          for (final f in snapshot.data ?? const <BookFile>[])
            if (isAudioFormat(f.format) && f.present) f,
        ];
        if (here.isEmpty) return const SizedBox.shrink();
        return PopupMenuButton<void>(
          itemBuilder: (_) => [
            PopupMenuItem<void>(
              onTap: () async {
                final navigator = Navigator.of(context);
                final removed = await confirmRemoveAudioDownload(
                  context,
                  repository: widget.repository,
                  bookId: widget.bookId,
                  size: here.fold<int>(0, (n, f) => n + f.sizeBytes),
                  downloads: widget.downloads,
                  host: widget.host,
                );
                if (removed && navigator.mounted) navigator.pop();
              },
              child: Text(L10n.of(context).audioDownloadRemove),
            ),
          ],
        );
      },
    );
  }
}
