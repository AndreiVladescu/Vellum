/// Feeding the continue-reading home-screen widget (plan 5 #40).
///
/// The app **pushes a snapshot**; the widget never reads the database. A
/// launcher process opening the app's SQLite file would be a second writer to a
/// store the app assumes it owns alone, and a locked or half-written database is
/// a far worse failure than a widget showing yesterday's book.
///
/// So the contract is three strings and a file path, written whenever the app
/// knows the answer changed. Stale is the intended failure mode.
library;

import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../audio/attach_audio.dart' show formatAudioTime;
import '../audio/continue_listening.dart';
import '../data/database.dart';
import '../data/library_queries.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/platform_l10n.dart';

/// What the widget shows.
class ContinueWidgetData {
  const ContinueWidgetData({
    required this.title,
    required this.subtitle,
    this.coverPath,
  });

  final String title;

  /// The progress line — "42% · page 214".
  final String subtitle;

  /// Absolute path to the cover, or null. Absolute because the widget process
  /// has no idea where the app's data directory is.
  final String? coverPath;

  /// The empty state, pushed when there is nothing on the go — so the widget
  /// says so rather than keeping a book you finished last month.
  static const empty = ContinueWidgetData(title: '', subtitle: '');

  bool get isEmpty => title.isEmpty;
}

bool _onTheGo(Book book) {
  final status = ReadingStatus.parse(book.status);
  return status != ReadingStatus.finished &&
      status != ReadingStatus.abandoned;
}

/// What the widget shows: a book, and whether it is the listening position
/// (rather than the reading one) that is being continued.
typedef ContinuePick = ({Book book, bool listening, int? audioMs});

/// The book the widget should show: whichever of reading or listening happened
/// most recently, among books still on the go. One book, not one of each: the
/// widget has a single slot, and the launcher is where "carry on" should be one
/// tap, not a choice. A book marked Finished or Abandoned drops out whatever
/// its progress says, so the next candidate (or the empty state) takes over.
///
/// [audioMs] maps a book id to its audio length; a book not in it has no audio
/// and is never a listening candidate. A book that qualifies both ways is
/// shown for whichever is later.
ContinuePick? pickContinue(
  Iterable<Book> books, {
  Map<String, int> audioMs = const {},
}) {
  ContinuePick? best;
  DateTime? bestAt;
  for (final book in books) {
    final length = audioMs[book.id];
    final listens = isListeningOnTheGo(book, length);
    final reads = _readingOnTheGo(book);
    if (!listens && !reads) continue;
    final listenAt = listens ? book.lastListenedAt! : null;
    final readAt = reads ? _readAt(book) : null;
    final listening = listens && (readAt == null || listenAt!.isAfter(readAt));
    final at = listening ? listenAt! : readAt!;
    // A reading position with no timestamp (restored from a backup, or
    // published by another device) is still a book on the go: it ranks below
    // any that has one, rather than dropping out and leaving the widget saying
    // "nothing".
    if (best == null || at.isAfter(bestAt!)) {
      best = (book: book, listening: listening, audioMs: length);
      bestAt = at;
    }
  }
  return best;
}

bool _readingOnTheGo(Book book) {
  final progress = book.readingProgress;
  return progress != null && progress < 0.98 && _onTheGo(book);
}

/// [pickContinue]'s book alone.
Book? pickContinueBook(
  Iterable<Book> books, {
  Map<String, int> audioMs = const {},
}) =>
    pickContinue(books, audioMs: audioMs)?.book;

DateTime _readAt(Book book) =>
    book.lastReadAt ?? DateTime.fromMillisecondsSinceEpoch(0);

/// What the widget would show for [book], as a comparable value: the widget is
/// only pushed again when this changes, so a page turn that does not move the
/// percentage costs nothing.
Object? continueWidgetKey(
  Book? book, {
  bool listening = false,
  int? audioMs,
}) =>
    book == null
        ? null
        : listening
            // The minute, not the second: the player writes every 15 s.
            ? (
                book.id,
                book.title,
                book.coverPath,
                true,
                ((book.listenPosition ?? 0) / 60).floor(),
                audioMs,
                book.status,
              )
            : (
                book.id,
                book.title,
                book.coverPath,
                ((book.readingProgress ?? 0) * 100).round(),
                book.lastReadPage,
                book.status,
              );

/// Builds the snapshot for [book].
///
/// A book at 98% or more is treated as finished and doesn't count as "on the
/// go", matching the shelf's own continue-reading strip (plan 5 #25) — the two
/// disagreeing about what you're reading would be worse than either being wrong.
///
/// With [listening] the line is the listening position instead: how far through
/// the audio ([audioMs] is its length) and where you are in it.
ContinueWidgetData snapshotFor(
  L10n l10n,
  Book? book, {
  String? coverPath,
  bool listening = false,
  int? audioMs,
}) {
  if (book == null) return ContinueWidgetData.empty;
  if (listening) {
    if (!isListeningOnTheGo(book, audioMs)) return ContinueWidgetData.empty;
    final time = formatAudioTime(
        Duration(milliseconds: (book.listenPosition! * 1000).round()));
    final fraction = listenFraction(book, audioMs);
    return ContinueWidgetData(
      title: book.title,
      subtitle: fraction == null
          ? time
          : l10n.continueWidgetListening((fraction * 100).round(), time),
      coverPath: coverPath,
    );
  }
  final progress = book.readingProgress;
  if (progress == null || progress >= 0.98 || !_onTheGo(book)) {
    return ContinueWidgetData.empty;
  }

  final percent = (progress * 100).round();
  final page = book.lastReadPage;
  return ContinueWidgetData(
    title: book.title,
    subtitle:
        page == null ? '$percent%' : l10n.continueWidgetPage(percent, page),
    coverPath: coverPath,
  );
}

/// Pushes the current continue-reading book to the widget.
///
/// Best-effort and silent: no widget on the home screen, an older Android, or a
/// platform without the plugin are all non-events. A local-first app must never
/// nag about a nicety failing.
ContinuePick? _pickFrom(LibraryView view) => pickContinue(
      [for (final e in view.entries) e.book],
      audioMs: {
        for (final e in view.entries)
          if (e.audioMs != null) e.book.id: e.audioMs!,
      },
    );

Future<void> updateContinueWidget(LibraryRepository repository) async {
  if (!Platform.isAndroid) return;
  try {
    final view = await repository.queries.watchLibrary().first;
    await _pushContinueWidget(repository, _pickFrom(view));
  } catch (_) {
    // See below.
  }
}

/// Keeps the widget in step with the library for as long as the app runs:
/// pushed once the database has answered (app start), and again whenever the
/// book it would show — or how far into it you are — changes. Reading, a sync
/// that brings a position in, marking a book finished and a restored backup
/// all land in the same place this way, instead of each remembering to call
/// [updateContinueWidget].
///
/// Cancel the returned subscription when done. A no-op off Android.
StreamSubscription<void>? watchContinueWidget(LibraryRepository repository) {
  if (!Platform.isAndroid) return null;
  Object? last;
  var first = true;
  Timer? settle;
  ContinuePick? pending;
  return repository.queries.watchLibrary().listen((view) {
    final candidate = _pickFrom(view);
    final key = continueWidgetKey(
      candidate?.book,
      listening: candidate?.listening ?? false,
      audioMs: candidate?.audioMs,
    );
    // The first answer is always pushed: what the widget holds (a reinstall
    // clears it) says nothing about what the library holds.
    if (!first && key == last) return;
    first = false;
    last = key;
    pending = candidate;
    // A page turn writes the position every time; coalesce the burst.
    settle?.cancel();
    settle = Timer(const Duration(seconds: 1), () {
      unawaited(_pushContinueWidget(repository, pending));
    });
  });
}

Future<void> _pushContinueWidget(
  LibraryRepository repository,
  ContinuePick? pick,
) async {
  try {
    final candidate = pick?.book;
    final cover = candidate == null ? null : repository.coverFileOf(candidate);
    // No widget tree here to ask (this also runs from the background sync), so
    // the platform's language, like the status-bar notifications.
    final data = snapshotFor(
      platformL10n(),
      candidate,
      coverPath: cover != null && cover.existsSync() ? cover.path : null,
      listening: pick?.listening ?? false,
      audioMs: pick?.audioMs,
    );

    await HomeWidget.saveWidgetData<String>('continue_title', data.title);
    await HomeWidget.saveWidgetData<String>('continue_subtitle', data.subtitle);
    await HomeWidget.saveWidgetData<String>('continue_cover', data.coverPath);
    await HomeWidget.updateWidget(name: 'ContinueReadingWidget');
  } catch (_) {
    // See the doc comment: a widget that didn't update is not worth telling
    // anyone about.
  }
}
