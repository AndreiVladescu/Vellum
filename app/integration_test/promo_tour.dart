// The promo tour: the app driven through the scenes the README, the store
// listing and the promo clip show, with deliberate pauses, against the demo
// library (tool/demo_library.sh).
//
// Not part of `flutter test`. tool/promo_capture.sh runs it through
//
//   flutter drive --profile --driver test_driver/promo_driver.dart \
//       --target integration_test/promo_tour.dart
//
// against a fresh copy of the demo library, and records the window while it
// plays. The tour itself:
//
//   * takes a PNG of every scene with the app's own renderer (a
//     RepaintBoundary around the app, so no screen grabber is involved and the
//     picture is exactly the window's content at its device pixel ratio), into
//     $PROMO_OUT/shots/;
//   * writes $PROMO_OUT/scenes.json — for each scene, the wall-clock span
//     (epoch ms) of the part worth keeping in the clip, which the capture
//     script cuts out of the recording and joins. The screenshots are taken
//     *outside* those spans, so a hitch while one is encoded never shows.
//
// Environment:
//   PROMO_OUT      where shots/ and scenes.json go (default build/promo)
//   PROMO_WINDOW   the window size to wait for, e.g. 1600x1000 (the capture
//                  script resizes the window from outside, as perf_run.sh does)
//   PROMO_RECORD=1 wait for $PROMO_OUT/recording to exist before the first
//                  scene, so the recording is running when the tour starts
//   PROMO_ONLY     comma-separated scene names, to rehearse a few
//
// SAFETY: it opens the app's real data directory, so it refuses to run unless
// XDG_DATA_HOME is a demo directory holding a library the demo seeder built,
// and VELLUM_NO_KEYRING=1 keeps it away from the OS keyring (which XDG_*
// does not isolate). It never signs in to a server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/audio/player_page.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/seed_demo.dart';
import 'package:vellum/main.dart';
import 'package:vellum/physical/environment_editor_page.dart';
import 'package:vellum/reader/epub_reader_page.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/settings/book_face.dart';
import 'package:vellum/shelf/shelf_view.dart';
import 'package:vellum/stats/insights_page.dart';
import 'package:vellum/stats/year_review_page.dart';

late IntegrationTestWidgetsFlutterBinding _binding;
final _shotKey = GlobalKey();
final _scenes = <Map<String, Object>>[];
late Directory _out;

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at the display's pace — this is being filmed.
  _binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('promo tour', (tester) async {
    final env = Platform.environment;
    _out = Directory(env['PROMO_OUT'] ?? 'build/promo');
    Directory(p.join(_out.path, 'shots')).createSync(recursive: true);

    final repository = await LibraryRepository.open(VellumDatabase());
    final demo = _guardDemoLibrary(repository.dataDir);
    final ids = (demo['books'] as Map).cast<String, String>();
    final profile = await UserProfileStore.load(dataDir: repository.dataDir);
    final settings = await AppSettingsStore.load();
    final connection = await ServerConnection.load();
    // The paged reader is what the clip turns pages in.
    await (await SharedPreferences.getInstance())
        .setString('reader.epubLayout', 'paged');

    await _waitForWindow(tester, env['PROMO_WINDOW']);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: VellumApp(
          repository: repository,
          profile: profile,
          settings: settings,
          connection: connection,
        ),
      ),
    );
    await _until(tester, () => find.byType(BookSpine).evaluate().isNotEmpty);
    // Every cover thumbnail made before anything is filmed, so no spine pops
    // in mid-shot.
    await _waitForThumbnails(repository.dataDir);
    await _settle(tester);
    await _pause(1500);

    if (env['PROMO_RECORD'] == '1') {
      File(p.join(_out.path, 'ready')).writeAsStringSync('${DateTime.now()}');
      final sw = Stopwatch()..start();
      while (!File(p.join(_out.path, 'recording')).existsSync() &&
          sw.elapsed < const Duration(seconds: 30)) {
        await _pause(100);
      }
      await _pause(500);
    }

    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    Future<void> push(Widget page) async {
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => page)));
      await _settle(tester);
    }

    Future<void> popToShelf() async {
      navigator.popUntil((r) => r.isFirst);
      await _settle(tester);
    }

    // ---- 1. The shelf, spine-out.
    await _scene(tester, 'shelf', hold: 1300, () async {});

    // ---- 2. The same books face-out.
    await _scene(tester, 'covers', hold: 1100, () async {
      await settings.setBookFace(BookFace.cover);
      await _settle(tester);
    }, after: () async {
      await settings.setBookFace(BookFace.spine);
      await _settle(tester);
    });

    // ---- 3. A slow scroll down the shelf, coming to rest on The Hound of
    // the Baskervilles (a series, a rating, and a copy out on loan).
    const featured = 'the-hound-of-the-baskervilles';
    await _scene(tester, 'scroll', hold: 300, () async {
      final position = _shelfPosition(tester);
      await position.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 2100),
        curve: Curves.easeInOutCubic,
      );
      await _settle(tester, quiet: 2);
      final spine = _spineOf(ids[featured]!);
      if (spine.evaluate().isNotEmpty) {
        await Scrollable.ensureVisible(
          spine.evaluate().first,
          alignment: 0.5,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });

    // ---- 4. The book: on a wide window it opens beside the shelf.
    await _scene(tester, 'book', hold: 1500, () async {
      final spine = _spineOf(ids[featured]!);
      await _until(tester, () => spine.evaluate().isNotEmpty);
      await tester.tap(spine.first);
      await _settle(tester);
    });

    // ---- 5. Reading: Middlemarch in the paged reader, open on the page
    // with today's highlight, then a few pages turned.
    await _scene(tester, 'reader', hold: 1100, () async {
      final book = await repository.watchBook(ids['middlemarch']!).first;
      final file = (await repository.watchFilesOf(book!.id).first)
          .firstWhere((f) => f.format == 'epub');
      await push(EpubReaderPage(
        book: book,
        file: repository.fileOf(file),
        bookFile: file,
        repository: repository,
      ));
      await _until(
          tester, () => find.byType(EpubReaderPage).evaluate().isNotEmpty);
      await _settle(tester);
    });
    await _scene(tester, 'pages', hold: 300, () async {
      for (var i = 0; i < 3; i++) {
        // The physical key named outright: the simulator looks it up by
        // debug name, and a profile build has no debug names.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight);
        await _settle(tester, quiet: 3);
        await _pause(450);
      }
    }, after: popToShelf);

    // ---- 6. The audiobook player, part-way through A Christmas Carol.
    await _scene(tester, 'player', hold: 1100, () async {
      await push(PlayerPage(
        bookId: ids['a-christmas-carol']!,
        repository: repository,
      ));
    }, after: popToShelf);

    // ---- 7. Reading insights, and a slow look down the page.
    await _scene(tester, 'insights', hold: 1000, () async {
      await push(InsightsPage(repository: repository, settings: settings));
      await _until(
        tester,
        () => find
            .descendant(
                of: find.byType(InsightsPage),
                matching: find.byType(ChoiceChip))
            .evaluate()
            .isNotEmpty,
      );
      await _settle(tester);
    });
    await _scene(tester, 'insights-more', hold: 400, () async {
      final scroll = tester
          .state<ScrollableState>(find
              .descendant(
                  of: find.byType(InsightsPage),
                  matching: find.byType(Scrollable))
              .first)
          .position;
      await scroll.animateTo(
        (scroll.maxScrollExtent * 0.45).clamp(0.0, 900.0),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
      );
    }, after: popToShelf);

    // ---- 8. The year in review.
    await _scene(tester, 'year', hold: 1300, () async {
      await push(YearReviewPage(repository: repository, settings: settings));
      await _settle(tester);
    }, after: popToShelf);

    // ---- 9. The room: open, pan along the bookcases, zoom in and out.
    await _scene(tester, 'room', hold: 600, () async {
      final room = await (repository.db.select(repository.db.physicalEnvironments)
            ..where((e) => e.name.equals(demoRoomName)))
          .getSingle();
      await push(EnvironmentEditorPage(
        repository: repository,
        settings: settings,
        environmentId: room.id,
        environmentName: room.name,
      ));
      await _pause(300);
      // The room opens at 300 px/m with the world's origin 40 px in from the
      // canvas's bottom-left corner (EnvironmentEditorPage), so the bookcases
      // start small in that corner: drag them to the middle, then zoom in
      // around them until they fill most of the window.
      final segments =
          await (repository.db.select(repository.db.physicalShelves)
                ..where((s) => s.environmentId.equals(room.id)))
              .get();
      var bounds = Rect.fromPoints(
          Offset(segments.first.x1, segments.first.y1),
          Offset(segments.first.x2, segments.first.y2));
      for (final s in segments) {
        bounds = bounds.expandToInclude(
            Rect.fromPoints(Offset(s.x1, s.y1), Offset(s.x2, s.y2)));
      }
      final page = tester.getRect(find.byType(EnvironmentEditorPage));
      final bar = tester.getRect(find
          .descendant(
              of: find.byType(EnvironmentEditorPage),
              matching: find.byType(AppBar))
          .first);
      final canvas =
          Rect.fromLTRB(page.left, bar.bottom, page.right, page.bottom);
      const startScale = 300.0;
      final cases = Offset(canvas.left + 40 + bounds.center.dx * startScale,
          canvas.bottom - 90 - bounds.center.dy * startScale);
      final centre = canvas.center;
      final fill = math.min(0.82 * canvas.width / bounds.width,
          0.78 * canvas.height / bounds.height);
      // x1.1 a wheel click.
      final clicks =
          (math.log(fill / startScale) / math.log(1.1)).floor().clamp(0, 30);
      final drag = await tester.startGesture(cases);
      const steps = 36;
      for (var i = 0; i < steps; i++) {
        final t = Curves.easeInOut.transform((i + 1) / steps) -
            Curves.easeInOut.transform(i / steps);
        await drag.moveBy((centre - cases) * t);
        await SchedulerBinding.instance.endOfFrame;
      }
      await drag.up();
      await _pause(500);
      final mouse = TestPointer(9, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.addPointer(location: centre));
      await tester.sendEventToBinding(mouse.hover(centre));
      Future<void> zoom(int clicks, {required bool zoomIn}) async {
        for (var i = 0; i < clicks; i++) {
          await tester.sendEventToBinding(
              mouse.scroll(Offset(0, zoomIn ? -20 : 20)));
          // A wheel click every few frames: a smooth glide, not a jump.
          for (var f = 0; f < 3; f++) {
            await SchedulerBinding.instance.endOfFrame;
          }
        }
      }
      // In until the bookcases fill the window, a little closer, and back.
      await zoom(clicks, zoomIn: true);
      await _pause(250);
      await zoom(3, zoomIn: true);
      await _pause(250);
      await zoom(3, zoomIn: false);
      await tester.sendEventToBinding(mouse.removePointer());
      await _settle(tester);
    }, after: popToShelf);

    // ---- 10. Dark theme, back on the shelf.
    await _scene(tester, 'dark', hold: 1300, () async {
      final position = _shelfPosition(tester);
      position.jumpTo(0);
      await settings.setThemeMode(ThemeMode.dark);
      await _settle(tester);
    });

    File(p.join(_out.path, 'scenes.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'window': '${tester.view.physicalSize.width.round()}x'
            '${tester.view.physicalSize.height.round()}',
        'devicePixelRatio': tester.view.devicePixelRatio,
        'scenes': _scenes,
      }),
    );
    File(p.join(_out.path, 'done')).writeAsStringSync('${DateTime.now()}');
  }, timeout: Timeout.none);
}

// ---------------------------------------------------------------------------

/// The demo marker, or an error: XDG_DATA_HOME must be a demo directory and
/// the library in it must be one the demo seeder made.
Map<String, dynamic> _guardDemoLibrary(Directory dataDir) {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    final dataHome = Platform.environment['XDG_DATA_HOME'] ?? '';
    if (!dataHome.contains('vellum-demo')) {
      throw StateError('Refusing to run the promo tour: XDG_DATA_HOME '
          '($dataHome) is not a demo directory. Use tool/promo_capture.sh.');
    }
    // The files are isolated, the OS keyring is not: without the switch the
    // tour could read, or on a sign-out delete, the real app's server token.
    if (!ServerConnection.keyringDisabled) {
      throw StateError('Refusing to run the promo tour: VELLUM_NO_KEYRING is '
          "not set, so it would share the real app's keyring. Use "
          'tool/promo_capture.sh.');
    }
  }
  final marker = File(p.join(dataDir.path, demoMarkerFile));
  if (!marker.existsSync()) {
    throw StateError('Refusing to run the promo tour: ${dataDir.path} is not '
        'a demo library (no $demoMarkerFile). Run tool/demo_library.sh.');
  }
  return jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
}

/// Runs one scene: [action] (the part that moves), then [hold] ms of stillness
/// — together the span the clip keeps — then the screenshot, then [after]
/// (tidying up off camera).
Future<void> _scene(
  WidgetTester tester,
  String name,
  Future<void> Function() action, {
  required int hold,
  Future<void> Function()? after,
}) async {
  final only = Platform.environment['PROMO_ONLY'] ?? '';
  final wanted = only.isEmpty || only.split(',').contains(name);
  if (!wanted) {
    // Still walked through (later scenes start where this one leaves off),
    // just not filmed.
    await action();
    await after?.call();
    return;
  }
  final start = DateTime.now().millisecondsSinceEpoch;
  await action();
  await _settle(tester);
  await _pause(hold);
  final end = DateTime.now().millisecondsSinceEpoch;
  final shot = '${(_scenes.length + 1).toString().padLeft(2, '0')}-$name.png';
  await _screenshot(p.join(_out.path, 'shots', shot));
  _scenes.add({'name': name, 'start': start, 'end': end, 'shot': shot});
  // ignore: avoid_print
  print('PROMO_SCENE $name ${end - start} ms');
  await after?.call();
}

Future<void> _screenshot(String path) async {
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final view = _binding.platformDispatcher.views.first;
  final ui.Image image =
      await boundary.toImage(pixelRatio: view.devicePixelRatio);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

/// Waits for the window to reach [wanted] ("1600x1000"), which the capture
/// script sets from outside; carries on after 20 s with whatever it got.
Future<void> _waitForWindow(WidgetTester tester, String? wanted) async {
  if (wanted == null) return;
  final sw = Stopwatch()..start();
  String now() => '${tester.view.physicalSize.width.round()}x'
      '${tester.view.physicalSize.height.round()}';
  while (now() != wanted && sw.elapsed < const Duration(seconds: 20)) {
    await tester.pump();
    await _pause(50);
  }
  // ignore: avoid_print
  print('PROMO_WINDOW ${now()} (wanted $wanted)');
}

Finder _spineOf(String bookId) =>
    find.byWidgetPredicate((w) => w is BookSpine && w.book.id == bookId);

ScrollPosition _shelfPosition(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(
            of: find.byType(ShelfView), matching: find.byType(Scrollable))
        .first)
    .position;

Future<void> _pause(int ms) =>
    Future<void>.delayed(Duration(milliseconds: ms));

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
    await _pause(5);
  }
}

/// `pumpAndSettle` for a live binding: waits until no frame has been asked
/// for in [quiet] checks 16 ms apart, giving up after 8 s (a spinner never
/// settles).
Future<void> _settle(WidgetTester tester, {int quiet = 6}) async {
  final sw = Stopwatch()..start();
  var still = 0;
  while (still < quiet && sw.elapsed < const Duration(seconds: 8)) {
    await _pause(16);
    still = SchedulerBinding.instance.hasScheduledFrame ? 0 : still + 1;
  }
}

/// Waits for the background thumbnailers: the thumbnail count holds still for
/// a second and a half.
Future<void> _waitForThumbnails(Directory dataDir) async {
  final dir = Directory(p.join(dataDir.path, 'covers', 'thumbs'));
  final sw = Stopwatch()..start();
  var last = -1;
  var stable = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 60)) {
    final n = dir.existsSync() ? dir.listSync().length : 0;
    if (n != last) {
      last = n;
      stable = Stopwatch()..start();
    } else if (stable.elapsed > const Duration(milliseconds: 1500)) {
      break;
    }
    await _pause(100);
  }
}
