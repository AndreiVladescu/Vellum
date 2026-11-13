// Not a test: the seeding step of the profiling run (tool/perf_run.sh, see
// docs/PERFORMANCE.md). A `flutter test`-hosted CLI for the same reason as
// seed_library_tool.dart — `database.dart` needs the engine's `dart:ui`.
//
// Skipped unless PERF_SEED_OUT is set:
//
//   PERF_SEED_OUT=/some/dir PERF_BOOKS=4000 flutter test test/tool/perf_seed_tool.dart
//
// Writes the library *as the app keeps it* — `vellum.sqlite`, `covers/`,
// `files/` — into `$PERF_SEED_OUT/data/app.vellum.Vellum/`, which is where the
// Linux app looks when started with `XDG_DATA_HOME=$PERF_SEED_OUT/data`, and the
// covers' and files' shared sources into `$PERF_SEED_OUT/seed-sources/`. The
// shape is taken from the `PERF_*` variables (`ProfilingLibrary.fromEnvironment`)
// and recorded in `$PERF_SEED_OUT/seed.json`.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/seed_profiling.dart';

void main() {
  final out = Platform.environment['PERF_SEED_OUT'];
  test(
    'seed the profiling library',
    () async {
      final root = Directory(out!)..createSync(recursive: true);
      final dataDir = Directory(p.join(root.path, 'data', 'app.vellum.Vellum'));
      if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
      dataDir.createSync(recursive: true);
      final spec = ProfilingLibrary.fromEnvironment(Platform.environment);

      final db = VellumDatabase(
        NativeDatabase(File(p.join(dataDir.path, 'vellum.sqlite'))),
      );
      final sw = Stopwatch()..start();
      await seedProfilingLibrary(
        db,
        dataDir,
        spec: spec,
        epub: File('assets/samples/the-time-machine.epub').readAsBytesSync(),
        sourcesDir: Directory(p.join(root.path, 'seed-sources')),
        // ignore: avoid_print
        log: (m) => print('  seed: $m'),
      );
      final schemaVersion = db.schemaVersion;
      await db.close();
      File(p.join(root.path, 'seed.json')).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          ...spec.toJson(),
          'seededAt': DateTime.now().toIso8601String(),
          'schemaVersion': schemaVersion,
          'millis': sw.elapsedMilliseconds,
        }),
      );
      // ignore: avoid_print
      print('Seeded ${spec.books} books into ${dataDir.path} '
          'in ${sw.elapsedMilliseconds} ms');
    },
    skip: out == null ? 'set PERF_SEED_OUT to run' : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
