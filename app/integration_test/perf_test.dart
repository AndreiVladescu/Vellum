// The profiling run's GUI half (docs/PERFORMANCE.md, "The profiling run").
//
// Not part of `flutter test`: it drives the real app, in profile mode, against
// a seeded library, and is started by tool/perf_run.sh through
//
//   flutter drive --profile --driver test_driver/perf_driver.dart \
//       --target integration_test/perf_test.dart
//
// Each scenario is timed three ways: wall-clock milliseconds for "how long
// until it is there", the engine's own frame timings (`FrameRecorder`) for "how
// smooth was it", and — through `traceAction` — a full timeline per scenario,
// which the driver summarises and can keep for opening in DevTools/Perfetto.
// After each one it records memory: resident set and the image cache.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/book_detail/book_detail_page.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/seed_profiling.dart';
import 'package:vellum/main.dart';
import 'package:vellum/physical/environment_editor_page.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/sync_service.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/settings/book_face.dart';
import 'package:vellum/settings/preferences_page.dart';
import 'package:vellum/settings/spine_art.dart';
import 'package:vellum/shelf/book_list_view.dart';
import 'package:vellum/shelf/shelf_view.dart';
import 'package:vellum/stats/insights_page.dart';
import 'package:vellum/stats/month_review_page.dart';

import 'perf_support.dart';

late IntegrationTestWidgetsFlutterBinding _binding;
final _metrics = <String, Object>{};
final _frames = FrameRecorder();
final _images = ImageCacheSampler();

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at the display's pace, as a user gets them — not the test
  // binding's "only when asked" frames, which would time nothing real.
  _binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('profiling run', (tester) async {
    _metrics['platform'] = Platform.operatingSystem;
    _metrics['rss_mb_at_test_start'] = rssMb();

    // ---- Boot, as main() does: the four loads, then the app.
    final boot = Stopwatch()..start();
    final repository = await LibraryRepository.open(VellumDatabase());
    await guardProfilingLibrary(repository.db);
    _metrics['seeded_in_app'] = await seedIfEmpty(
      repository.db,
      repository.dataDir,
    );
    if (_metrics['seeded_in_app'] == true) boot.reset();
    final profile = await UserProfileStore.load(dataDir: repository.dataDir);
    final settings = await AppSettingsStore.load();
    await applyProfilingPreferences(settings);
    final connection = await ServerConnection.load();
    _metrics['boot_loads_ms'] = boot.elapsedMilliseconds;
    boot.stop();
    _metrics['library'] = await _libraryShape(repository.db);

    final view = tester.view;
    // One layout for every run, whatever size the window manager first gave
    // the window: how many spines a frame draws depends on it. The run
    // resizes the window from outside (wmctrl) to PERF_WINDOW; this waits for
    // that to land. (Overriding `tester.view.physicalSize` instead lays out at
    // the new size but no longer rasterises the frames — no good for timing.)
    final wanted = Platform.environment['PERF_WINDOW'];
    if (wanted != null) {
      final sw = Stopwatch()..start();
      while ('${view.physicalSize.width.round()}x'
                  '${view.physicalSize.height.round()}' !=
              wanted &&
          sw.elapsed < const Duration(seconds: 15)) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    _metrics['window'] =
        '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}'
        '@${view.devicePixelRatio}';

    // From here on the clock counts on from the four loads, skipping the
    // wait for the window above.
    final loads = _metrics['boot_loads_ms']! as int;
    final shown = Stopwatch()..start();
    await tester.pumpWidget(
      VellumApp(
        repository: repository,
        profile: profile,
        settings: settings,
        connection: connection,
      ),
    );
    final firstFrame = loads + shown.elapsedMilliseconds;
    await _until(tester, () => find.byType(BookSpine).evaluate().isNotEmpty);
    await SchedulerBinding.instance.endOfFrame;
    _record('startup', {
      'first_frame_ms': firstFrame,
      'first_shelf_frame_ms': loads + shown.elapsedMilliseconds,
    });
    await _settle(tester);

    // ---- The shelf, spine view: thumbnails absent, then present, then all
    // decoded already. The run's data directory is a fresh copy, so the
    // first pass really is the first look at these covers.
    if (_want('shelf')) {
      await _scrollShelf(tester, 'shelf_spines_cold');
      await _waitForThumbnails(repository.dataDir);
      _clearImageCache();
      await _scrollShelf(tester, 'shelf_spines_warm');
      await _scrollShelf(tester, 'shelf_spines_hot');
      // The other spine artwork: generated spines in each cover's colour.
      await settings.setSpineArt(SpineArt.dominantColor);
      await _settle(tester);
      await _scrollShelf(tester, 'shelf_spines_colour');
      await settings.setSpineArt(SpineArt.coverSlice);
      await _settle(tester);
    }

    // ---- Face-out covers and the list.
    if (_want('covers')) {
      await settings.setBookFace(BookFace.cover);
      await _settle(tester);
      await _scrollShelf(tester, 'shelf_covers_cold');
      await _waitForThumbnails(repository.dataDir);
      _clearImageCache();
      await _scrollShelf(tester, 'shelf_covers_warm');
      await settings.setBookFace(BookFace.list);
      await _settle(tester);
      await _scrollShelf(
        tester,
        'shelf_list',
        finder: find.descendant(
          of: find.byType(BookListView),
          matching: find.byType(Scrollable),
        ),
      );
      await settings.setBookFace(BookFace.spine);
      await _settle(tester);
    }

    // ---- Opening a book from the shelf, with the pull-out animation.
    if (_want('detail')) {
      await _jumpShelfTo(tester, 0);
      final spine = find.byWidgetPredicate(
        (w) => w is BookSpine && w.coverFile != null,
      );
      await _timed(tester, 'book_detail_open', () async {
        await tester.tap(spine.first);
        await _until(
          tester,
          () => find.byType(BookDetailPage).evaluate().isNotEmpty,
        );
      });
      await _pop(tester);
    }

    // ---- Search: typed a character at a time, as a person does.
    if (_want('search')) await _search(tester);

    // ---- Reading insights, its range control, and the month page.
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    if (_want('insights')) {
      await _timed(tester, 'insights_open', () async {
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  InsightsPage(repository: repository, settings: settings),
            ),
          ),
        );
        await _until(
          tester,
          () =>
              find.byType(InsightsPage).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(InsightsPage),
                    matching: find.byType(ChoiceChip),
                  )
                  .evaluate()
                  .isNotEmpty,
        );
      });
      await _scrollToEnd(
        tester,
        'insights_scroll',
        find
            .descendant(
              of: find.byType(InsightsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _jumpTo(
        tester,
        find
            .descendant(
              of: find.byType(InsightsPage),
              matching: find.byType(Scrollable),
            )
            .first,
        0,
      );
      final chips = find.descendant(
        of: find.byType(InsightsPage),
        matching: find.byType(ChoiceChip),
      );
      final perChip = <int>[];
      await _traced(
        'insights_range',
        () async {
          for (final index in [1, 2, 3, 0]) {
            final sw = Stopwatch()..start();
            await tester.tap(chips.at(index));
            await SchedulerBinding.instance.endOfFrame;
            await SchedulerBinding.instance.endOfFrame;
            perChip.add(sw.elapsedMilliseconds);
          }
        },
        extra: () => {
          'switch_ms': perChip,
          'switch_ms_max': perChip.reduce(math.max),
        },
      );
      await _timed(tester, 'month_open', () async {
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  MonthReviewPage(repository: repository, settings: settings),
            ),
          ),
        );
        await _until(
          tester,
          () =>
              find.byType(MonthReviewPage).evaluate().isNotEmpty &&
              find
                  .descendant(
                    of: find.byType(MonthReviewPage),
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty,
        );
      });
      final perMonth = <int>[];
      await _traced('month_navigate', () async {
        for (var m = 0; m < 4; m++) {
          final sw = Stopwatch()..start();
          await tester.tap(find.byIcon(Icons.chevron_left).first);
          await SchedulerBinding.instance.endOfFrame;
          await _settle(tester, quiet: 3);
          perMonth.add(sw.elapsedMilliseconds);
        }
      }, extra: () => {'step_ms': perMonth});
      await _pop(tester);
      await _pop(tester);
    }

    // ---- The physical room: open, pan, zoom.
    if (_want('room')) {
      await _timed(tester, 'room_open', () async {
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => EnvironmentEditorPage(
                repository: repository,
                settings: settings,
                environmentId: profilingRoomId,
                environmentName: profilingRoomName,
              ),
            ),
          ),
        );
        await _until(
          tester,
          () => find.byType(EnvironmentEditorPage).evaluate().isNotEmpty,
        );
      });
      await _settle(tester);
      final room = tester.getCenter(find.byType(EnvironmentEditorPage));
      await _traced('room_pan', () async {
        final g = await tester.startGesture(room);
        for (var i = 0; i < 120; i++) {
          await g.moveBy(Offset(i < 60 ? -6 : 6, i < 60 ? 2 : -2));
          await SchedulerBinding.instance.endOfFrame;
        }
        await g.up();
      });
      await _traced('room_zoom', () async {
        if (Platform.isAndroid) {
          await _pinch(tester, room);
        } else {
          final mouse = TestPointer(9, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(mouse.addPointer(location: room));
          await tester.sendEventToBinding(mouse.hover(room));
          for (var i = 0; i < 80; i++) {
            await tester.sendEventToBinding(
              mouse.scroll(Offset(0, i < 40 ? -30 : 30)),
            );
            await SchedulerBinding.instance.endOfFrame;
          }
          await tester.sendEventToBinding(mouse.removePointer());
        }
      });
      await _pop(tester);
    }

    // ---- Preferences.
    if (_want('prefs')) {
      final sync = SyncService(repository, profile: profile);
      await _timed(tester, 'preferences_open', () async {
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => PreferencesPage(
                settings: settings,
                repository: repository,
                connection: connection,
                sync: sync,
              ),
            ),
          ),
        );
        await _until(
          tester,
          () => find.byType(PreferencesPage).evaluate().isNotEmpty,
        );
      });
      await _scrollToEnd(
        tester,
        'preferences_scroll',
        find
            .descendant(
              of: find.byType(PreferencesPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _pop(tester);
    }

    _metrics['rss_mb_max'] = ProcessInfo.maxRss / (1 << 20);
    _binding.reportData = {...?_binding.reportData, 'metrics': _metrics};
  }, timeout: Timeout.none);
}

// ---------------------------------------------------------------------------

/// The scenario groups this run asks for: all of them, or the comma-separated
/// list in PERF_ONLY (shelf, covers, detail, search, insights, room, prefs) —
/// for iterating on one fix without sitting through the rest.
bool _want(String group) {
  final only = Platform.environment['PERF_ONLY'] ?? '';
  return only.isEmpty || only.split(',').contains(group);
}

void _record(String scenario, Map<String, Object> values) {
  _metrics[scenario] = {
    ...values,
    'rss_mb': (rssMb() * 10).roundToDouble() / 10,
    ...imageCacheNow(),
  };
  // Reported as it goes, so a scenario that fails still leaves the ones
  // before it (the driver writes the report on failure too).
  _binding.reportData = {...?_binding.reportData, 'metrics': _metrics};
}

/// Runs [action] under the timeline, the frame recorder and the image-cache
/// sampler, and records all three as [key].
Future<void> _traced(
  String key,
  Future<void> Function() action, {
  Map<String, Object> Function()? extra,
}) async {
  final sw = Stopwatch();
  late Map<String, Object> frames;
  await _binding.traceAction(() async {
    _frames.start();
    _images.start();
    sw.start();
    await action();
    sw.stop();
    frames = await _frames.stop();
  }, reportKey: key);
  _record(key, {
    'wall_ms': sw.elapsedMilliseconds,
    ...frames,
    ..._images.stop(),
    ...?extra?.call(),
  });
}

/// Like [_traced], for "open something": `wall_ms` is until [action] says it
/// is there, `settled_ms` until frames stop being scheduled.
Future<void> _timed(
  WidgetTester tester,
  String key,
  Future<void> Function() action,
) async {
  var shown = 0;
  var settled = 0;
  final sw = Stopwatch();
  await _traced(key, () async {
    sw.start();
    await action();
    shown = sw.elapsedMilliseconds;
    settled = shown + await _settle(tester);
  }, extra: () => {'shown_ms': shown, 'settled_ms': settled});
}

/// Pumps real frames until [done], or fails after [timeout].
Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('waited ${timeout.inSeconds}s', timeout);
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// Waits until no frame has been asked for in [quiet] consecutive checks
/// 16 ms apart — `pumpAndSettle` for a live binding, without its habit of
/// timing out on an indeterminate progress indicator. Gives up after 10 s.
///
/// Returns the milliseconds until the quiet stretch began: when the last
/// frame was asked for, not when this noticed.
Future<int> _settle(WidgetTester tester, {int quiet = 6}) async {
  final sw = Stopwatch()..start();
  var still = 0;
  var lastBusy = 0;
  while (still < quiet && sw.elapsed < const Duration(seconds: 10)) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (SchedulerBinding.instance.hasScheduledFrame) {
      still = 0;
      lastBusy = sw.elapsedMilliseconds;
    } else {
      still++;
    }
  }
  return lastBusy;
}

Future<void> _pop(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await _settle(tester);
}

Finder get _shelfScrollable => find
    .descendant(of: find.byType(ShelfView), matching: find.byType(Scrollable))
    .first;

Future<void> _jumpTo(WidgetTester tester, Finder scrollable, double to) async {
  tester.state<ScrollableState>(scrollable).position.jumpTo(to);
  await _settle(tester);
}

Future<void> _jumpShelfTo(WidgetTester tester, double to) =>
    _jumpTo(tester, _shelfScrollable, to);

/// Scrolls the shelf down 12,000 px in 6 s at a steady 2,000 px/s — a brisk
/// flick-and-follow through a hundred-odd rows, every frame bringing new rows
/// (and new covers) into view.
Future<void> _scrollShelf(
  WidgetTester tester,
  String key, {
  Finder? finder,
}) async {
  final scrollable = finder?.first ?? _shelfScrollable;
  await _jumpTo(tester, scrollable, 0);
  final position = tester.state<ScrollableState>(scrollable).position;
  final target = math.min(12000.0, position.maxScrollExtent);
  await _traced(key, () async {
    await position.animateTo(
      target,
      duration: Duration(milliseconds: (target / 2).round()),
      curve: Curves.linear,
    );
  }, extra: () => {'distance_px': target.round()});
  await _settle(tester);
}

/// Scrolls a page from top to bottom in about two seconds, chasing the
/// extent as lazily built children make it grow.
Future<void> _scrollToEnd(
  WidgetTester tester,
  String key,
  Finder scrollable,
) async {
  await _jumpTo(tester, scrollable, 0);
  final position = tester.state<ScrollableState>(scrollable).position;
  await _traced(key, () async {
    for (var leg = 0; leg < 4; leg++) {
      final target = position.maxScrollExtent;
      if (target - position.pixels < 1) break;
      await position.animateTo(
        target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.linear,
      );
    }
  }, extra: () => {'extent_px': position.maxScrollExtent.round()});
}

Future<void> _pinch(WidgetTester tester, Offset centre) async {
  final a = await tester.startGesture(
    centre - const Offset(40, 0),
    pointer: 21,
  );
  final b = await tester.startGesture(
    centre + const Offset(40, 0),
    pointer: 22,
  );
  for (var i = 0; i < 80; i++) {
    final d = i < 40 ? 3.0 : -3.0;
    await a.moveBy(Offset(-d, 0));
    await b.moveBy(Offset(d, 0));
    await SchedulerBinding.instance.endOfFrame;
  }
  await a.up();
  await b.up();
}

/// Waits for the background thumbnailers to finish: the thumbnail count holds
/// still for a second and a half. Reported, because how long a first look at
/// a library keeps four cores busy is worth knowing too.
Future<void> _waitForThumbnails(Directory dataDir) async {
  final dir = Directory(p.join(dataDir.path, 'covers', 'thumbs'));
  final sw = Stopwatch()..start();
  var last = -1;
  var stable = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 90)) {
    final n = dir.existsSync() ? dir.listSync().length : 0;
    if (n != last) {
      last = n;
      stable = Stopwatch()..start();
    } else if (stable.elapsed > const Duration(milliseconds: 1500)) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final key =
      'thumbnails_${_metrics.keys.where((k) => k.startsWith('thumbnails_')).length}';
  _metrics[key] = {
    'count': last,
    'drained_ms': sw.elapsedMilliseconds - stable.elapsedMilliseconds,
  };
}

void _clearImageCache() {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
}

Future<void> _search(WidgetTester tester) async {
  final field = find.byType(TextField).first;
  final full = _shelfSignature(tester);
  final latencies = <String, int>{};
  await _traced(
    'search_typing',
    () async {
      for (final query in ['silent', 'garden of', 'ada', 'qqqq']) {
        for (var i = 1; i <= query.length; i++) {
          _type(tester, field, query.substring(0, i));
          // About 11 characters a second: brisk typing, and faster than the
          // shelf's 150 ms debounce, so only the last keystroke filters.
          await Future<void>.delayed(const Duration(milliseconds: 90));
        }
        final sw = Stopwatch()..start();
        await _until(tester, () => _shelfSignature(tester) != full);
        await SchedulerBinding.instance.endOfFrame;
        latencies[query] = sw.elapsedMilliseconds;
        _type(tester, field, '');
        await _until(tester, () => _shelfSignature(tester) == full);
        await _settle(tester, quiet: 3);
      }
    },
    extra: () => {
      // From the last keystroke to the frame showing the result, debounce
      // included — 150 ms of it is the debounce by design.
      'results_ms': latencies,
      'results_ms_max': latencies.values.reduce(math.max),
    },
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
}

/// Puts [text] in the search box the way a keystroke does: the controller's
/// value changes, then the field's `onChanged` fires. Straight to the field
/// rather than through `enterText`, because a live run on the desktop talks to
/// the real text-input plugin, which a test cannot type into.
void _type(WidgetTester tester, Finder field, String text) {
  final widget = tester.widget<TextField>(field);
  widget.controller!.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  widget.onChanged!(text);
}

/// What the shelf is showing, by content. A rebuild hands the shelf a new list
/// every time — with the old results, too, while a new query is in flight —
/// so the list's identity says nothing about whether the results arrived.
String _shelfSignature(WidgetTester tester) {
  final shelf = find.byType(ShelfView).evaluate();
  if (shelf.isEmpty) return 'no shelf';
  final List<Book> books = (shelf.first.widget as ShelfView).books;
  return books.isEmpty ? 'empty' : '${books.length}:${books.first.id}';
}

Future<Map<String, Object>> _libraryShape(VellumDatabase db) async {
  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');
  return {
    'books': await count('books'),
    'with_cover':
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM books WHERE cover_path IS NOT NULL',
                )
                .getSingle())
            .read<int>('n'),
    'files': await count('book_files'),
    'sessions': await count('reading_sessions'),
    'annotations': await count('annotations'),
    'copies': await count('physical_copies'),
    'loans': await count('loans'),
    'placements': await count('book_placements'),
  };
}
