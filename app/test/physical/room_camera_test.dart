// The room pans by moving one transformed layer, not by rebuilding every
// placed book (docs/PERFORMANCE.md). These drive the real editor page to make
// sure the gestures that share the canvas with the camera still do their jobs:
// panning, a wheel zoom, selecting a book, dragging it, and dragging a shelf.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/physical/environment_editor_page.dart';
import 'package:vellum/physical/placement_toolbar.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/shelf/shelf_view.dart' show SpineFace;

void main() {
  late Directory dir;
  late LibraryRepository repo;
  late AppSettingsStore settings;
  late String envId;
  late String shelfId;

  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_room_cam'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// A room with one 2 m shelf at 1 m, and two books standing on its left end.
  Future<void> load(WidgetTester tester) async {
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettingsStore.load();
      envId = await repo.layout.createEnvironment('Study');
      await repo.layout.addShelf(envId, x1: 0, y1: 1.0, x2: 2.0, y2: 1.0);
      shelfId = (await repo.layout.watchShelves(envId).first).single.id;
      for (final (i, title) in ['Book Zero', 'Book One'].indexed) {
        final bookId = await repo.createCustomBook(title: title, author: 'A');
        await repo.layout.placeBook(envId, bookId, x: 0.1 * i, y: 1.0);
      }
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: EnvironmentEditorPage(
        repository: repo,
        settings: settings,
        environmentId: envId,
        environmentName: 'Study',
      ),
    ));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.runAsync(() => repo.db.close());
  }

  Finder spine(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(SpineFace));

  testWidgets('a pan moves the books without rebuilding them', (tester) async {
    await load(tester);
    final before = tester.getTopLeft(spine('Book Zero'));
    final widget = tester.widget(spine('Book Zero'));

    // Empty wall, well above the shelf: a press there pans.
    final wall = before + const Offset(300, -60);
    final g = await tester.startGesture(wall);
    await g.moveBy(const Offset(-30, 0)); // past the slop: the pan starts
    await tester.pump();
    final started = tester.getTopLeft(spine('Book Zero'));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(-10, 4));
      await tester.pump();
    }
    expect(
      tester.getTopLeft(spine('Book Zero')),
      offsetMoreOrLessEquals(started + const Offset(-50, 20)),
    );
    // The very same widget: the pan rebuilt nothing below the camera layer.
    expect(identical(tester.widget(spine('Book Zero')), widget), isTrue);
    await g.up();
    await tester.pump();
    // A pan is not a tap: nothing got selected on the way.
    expect(find.byType(SelectionBar), findsNothing);
    await unmount(tester);
  });

  testWidgets('a wheel zoom grows the books about the pointer', (tester) async {
    await load(tester);
    final before = tester.getSize(spine('Book Zero'));
    final at = tester.getCenter(spine('Book Zero')) + const Offset(200, -40);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -30)));
    await tester.pump();
    final after = tester.getSize(spine('Book Zero'));
    expect(after.height, closeTo(before.height * 1.1, 0.01));
    expect(after.width, closeTo(before.width * 1.1, 0.01));
    await unmount(tester);
  });

  testWidgets('a tap selects a book, and the selected book drags along the '
      'shelf', (tester) async {
    await load(tester);
    // The outline round a selected book: its visual is reused between
    // rebuilds, so it must still notice that it was selected.
    final outline = find.descendant(
      of: find
          .ancestor(of: spine('Book Zero'), matching: find.byType(Stack))
          .first,
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null,
      ),
    );
    expect(outline, findsNothing);
    await tester.tapAt(tester.getCenter(spine('Book Zero')));
    await tester.pump();
    expect(find.byType(SelectionBar), findsOneWidget);
    expect(outline, findsOneWidget);

    final placed = await tester.runAsync(
      () => repo.layout.watchPlacedBooks(envId).first,
    );
    final zero = placed!.firstWhere((pb) => pb.book.title == 'Book Zero');

    // A mouse, as on the desktop: its slop is 2 px, so the drag starts on
    // the (4 px wide) book rather than a finger-width beyond it.
    final g = await tester.startGesture(
      tester.getTopLeft(spine('Book Zero')) + const Offset(0.5, 30),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(2.5, 0)); // past the 2 px slop, still on it
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(25, 0));
      await tester.pump();
    }
    await g.up();
    await settle(tester);

    final moved = (await tester.runAsync(
      () => repo.layout.watchPlacedBooks(envId).first,
    ))!
        .firstWhere((pb) => pb.placement.id == zero.placement.id);
    // ~300 px at 300 px/m, less the slop: well along the shelf, still on it.
    expect(moved.placement.x, greaterThan(zero.placement.x + 0.5));
    expect(moved.placement.y, closeTo(1.0, 1e-6));
    await unmount(tester);
  });

  testWidgets('an unanchored shelf drags, with its books riding on it',
      (tester) async {
    await load(tester);
    await tester.runAsync(
      () => repo.layout.setAnchored(envId, [shelfId], anchored: false),
    );
    await settle(tester);
    final zeroBefore = tester.getTopLeft(spine('Book Zero'));
    // The plank, 1.5 m along — clear of both books.
    final plank = tester.getBottomLeft(spine('Book Zero')) +
        const Offset(450, 2);
    final g = await tester.startGesture(plank, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, -3)); // a mouse's slop is 2 px
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, -15));
      await tester.pump();
    }
    // The books ride the plank live, before anything is saved.
    expect(
      tester.getTopLeft(spine('Book Zero')).dy,
      lessThan(zeroBefore.dy - 50),
    );
    await g.up();
    await settle(tester);

    final shelf = (await tester.runAsync(
      () => repo.layout.watchShelves(envId).first,
    ))!
        .single;
    expect(shelf.y1, greaterThan(1.15));
    final zero = (await tester.runAsync(
      () => repo.layout.watchPlacedBooks(envId).first,
    ))!
        .firstWhere((pb) => pb.book.title == 'Book Zero');
    expect(zero.placement.y, closeTo(shelf.y1, 1e-6));
    await unmount(tester);
  });
}
