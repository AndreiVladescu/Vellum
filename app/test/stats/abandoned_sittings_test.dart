// A sitting left open by a killed app (SessionRecorder.closeAbandoned): found
// by the app-local `open` flag, closed at its last touch, marked for push.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/stats/session_recorder.dart';

void main() {
  late VellumDatabase db;
  late DateTime now;

  setUp(() async {
    db = VellumDatabase(NativeDatabase.memory());
    now = DateTime(2026, 11, 20, 20);
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b', title: 'Dune'));
  });
  tearDown(() => db.close());

  Future<ReadingSession> only() => db.select(db.readingSessions).getSingle();

  test('a killed reading sitting is closed at its last touch and marked', () async {
    final recorder = SessionRecorder(db);
    await recorder.begin('b', page: 3, now: now);
    await recorder.touch(
        page: 9, now: now.add(const Duration(minutes: 20)));
    // Mid-sitting: open, and not yet publishable.
    expect((await only()).open, isTrue);
    expect((await only()).needsPush, isFalse);

    // The app is killed here; the next start sweeps.
    expect(await SessionRecorder.closeAbandoned(db), 1);
    final row = await only();
    expect(row.open, isFalse);
    expect(row.needsPush, isTrue);
    expect(row.endedAt, now.add(const Duration(minutes: 20)));
    expect(row.endPage, 9);
  });

  test('a killed listening sitting is closed the same way', () async {
    final recorder = SessionRecorder(db);
    await recorder.begin('b',
        kind: SessionRecorder.listen, second: 100, now: now);
    await recorder.touch(
        second: 1300, now: now.add(const Duration(minutes: 20)));
    expect(await SessionRecorder.closeAbandoned(db), 1);
    final row = await only();
    expect(row.kind, 'listen');
    expect(row.open, isFalse);
    expect(row.needsPush, isTrue);
    expect(row.endSecond, 1300);
    expect(row.endedAt, now.add(const Duration(minutes: 20)));
  });

  test('a killed sitting below the minimum length is dropped', () async {
    final recorder = SessionRecorder(db);
    await recorder.begin('b', page: 3, now: now);
    await recorder.touch(page: 3, now: now.add(const Duration(seconds: 2)));
    expect(await SessionRecorder.closeAbandoned(db), 0);
    expect(await db.select(db.readingSessions).get(), isEmpty);

    await recorder.end(); // the recorder's own id is gone; must not throw
    final listener = SessionRecorder(db);
    await listener.begin('b',
        kind: SessionRecorder.listen, second: 0, now: now);
    await listener.touch(second: 3, now: now.add(const Duration(seconds: 3)));
    expect(await SessionRecorder.closeAbandoned(db), 0);
    expect(await db.select(db.readingSessions).get(), isEmpty);
  });

  test('a normally closed sitting is untouched by the sweep', () async {
    final recorder = SessionRecorder(db);
    await recorder.begin('b', page: 3, now: now);
    await recorder.end(page: 9, now: now.add(const Duration(minutes: 10)));
    final before = await only();
    expect(before.open, isFalse);
    expect(before.needsPush, isTrue);

    // Pushed since; the sweep must not mark it for push again.
    await (db.update(db.readingSessions))
        .write(const ReadingSessionsCompanion(needsPush: Value(false)));
    expect(await SessionRecorder.closeAbandoned(db), 0);
    final after = await only();
    expect(after.needsPush, isFalse);
    expect(after.endedAt, before.endedAt);
    expect(after.endPage, 9);
  });

  test('a pulled sitting is never open', () async {
    // The sync pull inserts through the companion without naming `open`.
    await db.into(db.readingSessions).insert(ReadingSessionsCompanion.insert(
          id: 'pulled',
          bookId: 'b',
          startedAt: now,
          endedAt: now.add(const Duration(hours: 1)),
          needsPush: const Value(false),
        ));
    expect((await only()).open, isFalse);
    expect(await SessionRecorder.closeAbandoned(db), 0);
    expect((await only()).needsPush, isFalse);
  });

  test('resuming a coalesced sitting reopens it, and ending closes it',
      () async {
    final recorder = SessionRecorder(db);
    await recorder.begin('b', page: 1, now: now);
    await recorder.end(page: 5, now: now.add(const Duration(minutes: 5)));
    await recorder.begin('b',
        page: 5, now: now.add(const Duration(minutes: 6)));
    expect((await only()).open, isTrue);
    await recorder.end(page: 8, now: now.add(const Duration(minutes: 9)));
    expect((await only()).open, isFalse);
  });
}
