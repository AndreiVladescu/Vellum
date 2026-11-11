/// Gathers the inputs for the diagnostics report from the running app.
///
/// Everything here is a count or a version; see `diagnostics_report.dart` for
/// what is deliberately left out.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_version.dart';
import '../data/library_repository.dart';
import '../reader/translate/on_device.dart' show buildFlavour;
import '../server/connection_store.dart';
import 'diagnostics_report.dart';
import 'error_log.dart';

Future<DiagnosticsInput> collectDiagnostics(
  BuildContext context, {
  required LibraryRepository repository,
  required ServerConnection connection,
}) async {
  // Read first: the context must not be used after an await.
  final size = MediaQuery.maybeSizeOf(context);
  final scale = MediaQuery.maybeTextScalerOf(context)?.scale(1);
  final db = repository.db;
  Future<int> count(String sql) async {
    final row = await db.customSelect(sql).getSingle();
    return row.data.values.first as int;
  }

  // Only the two formats the app knows by name; anything else is "other", so
  // an odd extension can never smuggle a file name into the report.
  final formats = <String, int>{};
  final rows = await db
      .customSelect(
        'SELECT format, COUNT(*) AS n FROM book_files GROUP BY format',
      )
      .get();
  for (final r in rows) {
    final f = (r.data['format'] as String? ?? '').toLowerCase();
    final key = (f == 'pdf' || f == 'epub') ? f : 'other';
    formats[key] = (formats[key] ?? 0) + (r.data['n'] as int);
  }

  final caps = connection.capabilities;
  final env = Platform.environment;

  return DiagnosticsInput(
    appVersion: await appVersion(),
    flavour: buildFlavour,
    mode: kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    platform: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    locale: WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
    screen: size == null
        ? null
        : '${size.width.round()}x${size.height.round()}',
    textScale: scale,
    schemaVersion: db.schemaVersion,
    books: await count('SELECT COUNT(*) FROM books WHERE deleted_at IS NULL'),
    filesByFormat: formats,
    shelves: await count('SELECT COUNT(*) FROM shelves'),
    copies: await count('SELECT COUNT(*) FROM physical_copies'),
    annotations: await count('SELECT COUNT(*) FROM annotations'),
    readingSessions: await count('SELECT COUNT(*) FROM reading_sessions'),
    serverConfigured: connection.isConnected,
    serverVersion: caps?.serverVersion,
    syncProtocol: caps?.syncProtocol,
    serverFeatures: caps?.features,
    errors: ErrorLog.instance.entries,
    homeDir: env['HOME'] ?? env['USERPROFILE'],
    dataDir: repository.dataDir.path,
    generatedAt: DateTime.now(),
  );
}
