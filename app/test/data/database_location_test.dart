import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';

/// The catalogue lives beside the things it describes.
///
/// `driftDatabase` defaults to the *documents* directory, which on Linux is the
/// user's own `~/Documents` — so the database used to sit among their papers
/// while the covers, book files and settings it refers to lived under
/// `~/.local/share`. Moving it is only safe if an existing database comes with
/// it, which is what these pin: the catalogue is the one thing whose loss
/// cannot be recovered from the files on disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory documents;
  late Directory support;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vellum_db_location');
    documents = Directory(p.join(root.path, 'Documents'))..createSync();
    support = Directory(p.join(root.path, 'support'))..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationDocumentsDirectory' => documents.path,
        'getApplicationSupportDirectory' => support.path,
        _ => root.path,
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    root.deleteSync(recursive: true);
  });

  File legacy(String suffix) =>
      File(p.join(documents.path, 'vellum.sqlite$suffix'));
  File moved(String suffix) =>
      File(p.join(support.path, 'vellum.sqlite$suffix'));

  test('a database left in the documents directory is moved across', () async {
    legacy('').writeAsStringSync('the catalogue');

    await VellumDatabase.relocateLegacyDatabaseForTesting(support);

    expect(moved('').existsSync(), isTrue);
    expect(moved('').readAsStringSync(), 'the catalogue');
    expect(legacy('').existsSync(), isFalse, reason: 'moved, not copied');
  });

  test('the write-ahead log and shared memory move too', () async {
    legacy('').writeAsStringSync('db');
    legacy('-wal').writeAsStringSync('uncommitted');
    legacy('-shm').writeAsStringSync('shm');

    await VellumDatabase.relocateLegacyDatabaseForTesting(support);

    // A stale -wal left behind is how a "successful" move quietly loses the
    // last transactions written before it.
    expect(moved('-wal').readAsStringSync(), 'uncommitted');
    expect(moved('-shm').existsSync(), isTrue);
    expect(legacy('-wal').existsSync(), isFalse);
  });

  test('an existing database is never overwritten by an older one', () async {
    legacy('').writeAsStringSync('old');
    moved('').writeAsStringSync('current');

    await VellumDatabase.relocateLegacyDatabaseForTesting(support);

    expect(moved('').readAsStringSync(), 'current',
        reason: 'the destination wins; a move must not undo newer work');
    expect(legacy('').existsSync(), isTrue, reason: 'and the old one is left');
  });

  test('nothing to move is not an error', () async {
    await VellumDatabase.relocateLegacyDatabaseForTesting(support);
    expect(moved('').existsSync(), isFalse);
  });

  test('a fresh install creates the support directory', () async {
    final fresh = Directory(p.join(root.path, 'not-yet'));
    legacy('').writeAsStringSync('db');

    await VellumDatabase.relocateLegacyDatabaseForTesting(fresh);

    expect(File(p.join(fresh.path, 'vellum.sqlite')).existsSync(), isTrue);
  });
}
