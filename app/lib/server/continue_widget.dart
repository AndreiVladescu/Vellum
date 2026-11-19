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

import '../data/database.dart';
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

/// The book the widget should show: the most recently read one that is still
/// on the go. A book marked Finished or Abandoned drops out whatever its
/// progress says, so the next candidate (or the empty state) takes over.
Book? pickContinueBook(Iterable<Book> books) {
  Book? candidate;
  for (final book in books) {
    final progress = book.readingProgress;
    if (progress == null || progress >= 0.98) continue;
    if (!_onTheGo(book)) continue;
    // A position with no timestamp (restored from a backup, or published by
    // another device) is still a book on the go: it ranks below any that has
    // one, rather than dropping out and leaving the widget saying "nothing".
    if (candidate == null || _readAt(book).isAfter(_readAt(candidate))) {
      candidate = book;
    }
  }
  return candidate;
}

DateTime _readAt(Book book) =>
    book.lastReadAt ?? DateTime.fromMillisecondsSinceEpoch(0);

/// What the widget would show for [book], as a comparable value: the widget is
/// only pushed again when this changes, so a page turn that does not move the
/// percentage costs nothing.
Object? continueWidgetKey(Book? book) => book == null
    ? null
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
ContinueWidgetData snapshotFor(L10n l10n, Book? book, {String? coverPath}) {
  if (book == null) return ContinueWidgetData.empty;
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
Future<void> updateContinueWidget(LibraryRepository repository) async {
  if (!Platform.isAndroid) return;
  try {
    final view = await repository.queries.watchLibrary().first;
    await _pushContinueWidget(
      repository,
      pickContinueBook([for (final e in view.entries) e.book]),
    );
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
  Book? pending;
  return repository.queries.watchLibrary().listen((view) {
    final candidate = pickContinueBook([for (final e in view.entries) e.book]);
    final key = continueWidgetKey(candidate);
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
  Book? candidate,
) async {
  try {
    final cover = candidate == null ? null : repository.coverFileOf(candidate);
    // No widget tree here to ask (this also runs from the background sync), so
    // the platform's language, like the status-bar notifications.
    final data = snapshotFor(
      platformL10n(),
      candidate,
      coverPath: cover != null && cover.existsSync() ? cover.path : null,
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
