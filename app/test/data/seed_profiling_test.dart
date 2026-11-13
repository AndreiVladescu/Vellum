// The profiling run's seeder (docs/PERFORMANCE.md, "The profiling run") only
// runs before a release, by hand — so a schema change that breaks it would
// otherwise be found by whoever next needs it. A small library, every table.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/seed_profiling.dart';
import 'package:vellum/shelf/spine_style.dart';

void main() {
  test('seeds a small profiling library into every table it covers', () async {
    final root = Directory.systemTemp.createTempSync('vellum_seed_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final dataDir = Directory(p.join(root.path, 'data'))..createSync();
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await seedProfilingLibrary(
      db,
      dataDir,
      spec: const ProfilingLibrary(
        books: 120,
        sessions: 200,
        annotations: 40,
        looseCopies: 20,
        loans: 8,
        placed: 30,
        jpegSources: 2,
        pngSources: 1,
      ),
      epub: Uint8List.fromList(List.filled(64, 7)),
      sourcesDir: Directory(p.join(root.path, 'sources')),
      now: DateTime(2026, 11, 13, 20),
    );

    Future<int> count(String sql) async =>
        (await db.customSelect('SELECT COUNT(*) AS n FROM $sql').getSingle())
            .read<int>('n');
    expect(await count('books'), 120);
    expect(await count('reading_sessions'), 200);
    expect(await count('annotations'), 40);
    expect(await count('loans'), 8);
    expect(await count('book_placements'), 30);
    expect(await count('physical_shelves'), greaterThan(0));
    expect(await count("books WHERE status = 'finished'"), greaterThan(0));
    // "This week" on the insights page has something in it.
    final sessions = await db.select(db.readingSessions).get();
    expect(
      sessions.where((s) => s.startedAt.isAfter(DateTime(2026, 11, 7))),
      isNotEmpty,
    );

    // Every cover and file the rows name is on disk, through its link.
    final covered = await (db.select(db.books)
          ..where((b) => b.coverPath.isNotNull()))
        .get();
    expect(covered, isNotEmpty);
    for (final b in covered) {
      expect(File(p.join(dataDir.path, b.coverPath!)).existsSync(), isTrue);
      // As the colour backfill would have left it, so the app's startup
      // sweep has nothing to do and every run starts from the same rows.
      expect(SpineStyle.fromJson(b.spineStyle, title: b.title).coverColor,
          isNotNull);
    }
    for (final f in await db.select(db.bookFiles).get()) {
      expect(File(p.join(dataDir.path, f.path)).existsSync(), isTrue);
    }
  });
}
