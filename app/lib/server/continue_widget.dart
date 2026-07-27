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

import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

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

/// Builds the snapshot for [book].
///
/// A book at 98% or more is treated as finished and doesn't count as "on the
/// go", matching the shelf's own continue-reading strip (plan 5 #25) — the two
/// disagreeing about what you're reading would be worse than either being wrong.
ContinueWidgetData snapshotFor(Book? book, {String? coverPath}) {
  if (book == null) return ContinueWidgetData.empty;
  final progress = book.readingProgress;
  if (progress == null || progress >= 0.98) return ContinueWidgetData.empty;

  final percent = (progress * 100).round();
  final page = book.lastReadPage;
  return ContinueWidgetData(
    title: book.title,
    subtitle: page == null ? '$percent%' : '$percent% · page $page',
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
    final entries = view.entries;
    Book? candidate;
    for (final entry in entries) {
      final book = entry.book;
      final progress = book.readingProgress;
      if (progress == null || progress >= 0.98) continue;
      if (book.lastReadAt == null) continue;
      if (candidate == null ||
          book.lastReadAt!.isAfter(candidate.lastReadAt!)) {
        candidate = book;
      }
    }

    final cover = candidate == null ? null : repository.coverFileOf(candidate);
    final data = snapshotFor(
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
