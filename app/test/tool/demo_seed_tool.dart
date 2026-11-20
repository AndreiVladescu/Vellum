// Not a test: the building step of the demo library (tool/demo_library.sh). A
// `flutter test`-hosted CLI for the same reason as perf_seed_tool.dart —
// `database.dart` needs the engine's `dart:ui`.
//
// Skipped unless DEMO_OUT is set:
//
//   DEMO_OUT=~/.cache/vellum-demo/data DEMO_SOURCES=~/.cache/vellum-demo/sources \
//     DEMO_MANIFEST=tool/demo_library/manifest.json \
//     flutter test test/tool/demo_seed_tool.dart
//
// DEMO_OUT is used as XDG_DATA_HOME: the library is written *as the app keeps
// it* into `$DEMO_OUT/app.vellum.Vellum/` — `vellum.sqlite`, `covers/`,
// `files/`, `shared_preferences.json` — plus `demo-library.json`, the marker
// the promo tour checks for. DEMO_LANG=ro sets the UI language.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/seed_demo.dart';
import 'package:vellum/server/connection_store.dart';

void main() {
  final env = Platform.environment;
  final out = env['DEMO_OUT'];
  test(
    'build the demo library',
    () async {
      final root = Directory(out!);
      // The same guard the shell script applies, for a hand-run: never write
      // into anything but a demo directory, and never over a real library.
      if (!root.absolute.path.contains('vellum-demo')) {
        throw StateError('DEMO_OUT ($out) must contain "vellum-demo"');
      }
      // Nothing here reads the keyring today; the switch makes sure nothing
      // it calls ever could reach the real app's (and its server token).
      if (!ServerConnection.keyringDisabled) {
        throw StateError('VELLUM_NO_KEYRING is not set; run '
            'tool/demo_library.sh, which sets it');
      }
      if (!File(p.join(root.path, '.vellum-demo')).existsSync()) {
        throw StateError('$out has no .vellum-demo marker; '
            'run tool/demo_library.sh, which creates it');
      }
      final dataDir = Directory(p.join(root.path, 'app.vellum.Vellum'));
      if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
      dataDir.createSync(recursive: true);

      final manifest = jsonDecode(
        File(env['DEMO_MANIFEST'] ?? 'tool/demo_library/manifest.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final sources = Directory(
        env['DEMO_SOURCES'] ?? p.join(root.parent.path, 'sources'),
      );

      final db = VellumDatabase(
        NativeDatabase(File(p.join(dataDir.path, 'vellum.sqlite'))),
      );
      final repository = await LibraryRepository.forTesting(db, dataDir);
      final sw = Stopwatch()..start();
      final summary = await seedDemoLibrary(
        repository,
        manifest: manifest,
        sources: sources,
        work: Directory(p.join(sources.parent.path, 'work')),
        // ignore: avoid_print
        log: (m) => print('  demo: $m'),
      );
      final schemaVersion = db.schemaVersion;
      await db.close();

      File(p.join(dataDir.path, 'shared_preferences.json')).writeAsStringSync(
        jsonEncode(demoPreferences(language: env['DEMO_LANG'])),
      );
      File(p.join(dataDir.path, demoMarkerFile)).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          ...summary.toJson(),
          'builtAt': DateTime.now().toIso8601String(),
          'schemaVersion': schemaVersion,
          'millis': sw.elapsedMilliseconds,
        }),
      );
      for (final w in summary.warnings) {
        // ignore: avoid_print
        print('  demo: warning: $w');
      }
      // ignore: avoid_print
      print('Seeded the demo library into ${dataDir.path} in '
          '${sw.elapsedMilliseconds} ms: ${summary.ebooks} EPUBs, '
          '${summary.pdfs} PDFs, ${summary.audiobooks} audiobook, '
          '${summary.wishlist} wishlist, ${summary.finished} finished, '
          '${summary.sessions} sittings, ${summary.annotations} marks, '
          '${summary.copies} copies (${summary.placed} in the room), '
          '${summary.loans} loans');
    },
    skip: out == null ? 'set DEMO_OUT to run' : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
