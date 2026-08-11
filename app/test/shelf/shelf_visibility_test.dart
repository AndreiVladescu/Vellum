import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/shelf_service.dart';

/// Personal shelves, and which of other people's this device shows.
///
/// Two separate ideas that are easy to confuse. **Personal** is the owner's
/// statement — this shelf is mine, don't show it to the people I share with —
/// and it travels with the shelf. **Accepted** is the reader's statement — I
/// don't want this person's shelf in my chip row — and it never leaves the
/// device, because pushing it would let one reader's "no thanks" hide a shelf
/// for everyone.
///
/// The third state is the part worth pinning. `accepted == null` means "no
/// answer yet", which follows the preference; without it, "the default is off"
/// and "I said no to this one" would be the same value, and turning the default
/// back on would wipe out every individual no.
void main() {
  Shelf shelf({
    String id = 's1',
    String? ownerId,
    bool isPersonal = false,
    bool? accepted,
  }) =>
      Shelf(
        id: id,
        name: 'Cookbooks',
        sortOrder: 0,
        updatedAt: DateTime(2026, 8, 1),
        needsPush: false,
        isPersonal: isPersonal,
        ownerId: ownerId,
        accepted: accepted,
      );

  group('whose shelf is it', () {
    test('a shelf made here belongs to nobody in particular', () {
      expect(shelfMadeByAnother(shelf(), 'me'), isFalse);
    });

    test('my own shelf from the server is still mine', () {
      expect(shelfMadeByAnother(shelf(ownerId: 'me'), 'me'), isFalse);
    });

    test("somebody else's is theirs", () {
      expect(shelfMadeByAnother(shelf(ownerId: 'them'), 'me'), isTrue);
    });

    test('with no idea who I am, nothing is somebody else\'s', () {
      // An offline library, or a session saved before the id was recorded.
      // Hiding shelves on a guess is the one outcome worth ruling out.
      expect(shelfMadeByAnother(shelf(ownerId: 'them'), ''), isFalse);
    });
  });

  group('what gets shown', () {
    bool shown(Shelf s, {String me = 'me', bool byDefault = true}) =>
        shelfIsShown(s, myUserId: me, acceptByDefault: byDefault);

    test('my own shelves always show, even with the default off', () {
      expect(shown(shelf(ownerId: 'me'), byDefault: false), isTrue);
    });

    test('my own personal shelf shows to me', () {
      // "Personal" is about other people, not about hiding it from yourself.
      expect(shown(shelf(ownerId: 'me', isPersonal: true)), isTrue);
    });

    test('an undecided shelf follows the preference', () {
      expect(shown(shelf(ownerId: 'them'), byDefault: true), isTrue);
      expect(shown(shelf(ownerId: 'them'), byDefault: false), isFalse);
    });

    test('a decided shelf ignores the preference, both ways', () {
      expect(shown(shelf(ownerId: 'them', accepted: true), byDefault: false),
          isTrue, reason: 'I asked for this one');
      expect(shown(shelf(ownerId: 'them', accepted: false), byDefault: true),
          isFalse, reason: 'and I said no to this one');
    });
  });

  group('the service', () {
    late VellumDatabase db;
    late ShelfService shelves;

    setUp(() {
      db = VellumDatabase(NativeDatabase.memory());
      shelves = ShelfService(db);
    });
    tearDown(() => db.close());

    test('a new shelf is shared unless asked otherwise', () async {
      final id = await shelves.createShelf('Cookbooks');
      final row = await (db.select(db.shelves)..where((s) => s.id.equals(id)))
          .getSingle();
      expect(row.isPersonal, isFalse);
      expect(row.accepted, isNull, reason: 'my own shelf needs no answer');
    });

    test('a personal shelf is created personal and pushes as such', () async {
      final id = await shelves.createShelf('Reread', personal: true);
      final row = await (db.select(db.shelves)..where((s) => s.id.equals(id)))
          .getSingle();
      expect(row.isPersonal, isTrue);
      expect(row.needsPush, isTrue, reason: 'the server has to be told');
    });

    test('changing the kind dirties the shelf', () async {
      final id = await shelves.createShelf('Cookbooks');
      await (db.update(db.shelves)..where((s) => s.id.equals(id)))
          .write(const ShelvesCompanion(needsPush: Value(false)));

      await shelves.setShelfPersonal(id, true);
      final row = await (db.select(db.shelves)..where((s) => s.id.equals(id)))
          .getSingle();
      expect(row.isPersonal, isTrue);
      expect(row.needsPush, isTrue,
          reason: 'withdrawing a shelf is only real once the server knows');
    });

    test('accepting is local, so it must not dirty the shelf', () async {
      // The whole reason `accepted` is app-local: if this pushed, one reader
      // hiding a shelf would hide it for everyone it was shared with.
      final id = await shelves.createShelf('Theirs');
      await (db.update(db.shelves)..where((s) => s.id.equals(id)))
          .write(const ShelvesCompanion(needsPush: Value(false)));

      await shelves.setShelfAccepted(id, false);
      final row = await (db.select(db.shelves)..where((s) => s.id.equals(id)))
          .getSingle();
      expect(row.accepted, isFalse);
      expect(row.needsPush, isFalse, reason: 'nothing to tell the server');
    });

    test('a decision can be taken back to undecided', () async {
      final id = await shelves.createShelf('Theirs');
      await shelves.setShelfAccepted(id, false);
      await shelves.setShelfAccepted(id, null);
      final row = await (db.select(db.shelves)..where((s) => s.id.equals(id)))
          .getSingle();
      expect(row.accepted, isNull);
    });

    test('the bulk form answers every shelf named and no others', () async {
      final a = await shelves.createShelf('A');
      final b = await shelves.createShelf('B');
      final c = await shelves.createShelf('C');

      await shelves.setAllAccepted([a, b], false);
      final rows = {
        for (final s in await db.select(db.shelves).get()) s.id: s.accepted,
      };
      expect(rows[a], isFalse);
      expect(rows[b], isFalse);
      expect(rows[c], isNull, reason: 'untouched');
    });

    test('bulk with nothing to do is a no-op, not a full-table write', () async {
      final a = await shelves.createShelf('A');
      await shelves.setAllAccepted(const [], false);
      final row = await (db.select(db.shelves)..where((s) => s.id.equals(a)))
          .getSingle();
      expect(row.accepted, isNull);
    });
  });
}
