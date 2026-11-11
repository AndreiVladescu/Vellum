/// The text behind "Copy diagnostics": inputs in, string out.
///
/// Pure on purpose, so the format and the privacy promise are testable without
/// a widget or a database. The promise: counts and versions only. There is no
/// field here that could carry a title, an author, a file name, a path, the
/// server address or an account, and the one free-text part — recent error
/// messages — has home and data directories scrubbed out and a header asking
/// the reader to look it over before posting.
library;

import 'error_log.dart';

class DiagnosticsInput {
  const DiagnosticsInput({
    required this.appVersion,
    required this.flavour,
    required this.mode,
    required this.platform,
    required this.osVersion,
    required this.locale,
    this.screen,
    this.textScale,
    required this.schemaVersion,
    required this.books,
    required this.filesByFormat,
    required this.shelves,
    required this.copies,
    required this.annotations,
    required this.readingSessions,
    required this.serverConfigured,
    this.serverVersion,
    this.syncProtocol,
    this.serverFeatures,
    this.errors = const [],
    this.homeDir,
    this.dataDir,
    required this.generatedAt,
  });

  final String appVersion;
  final String flavour;
  final String mode;
  final String platform;
  final String osVersion;
  final String locale;
  final String? screen;
  final double? textScale;
  final int schemaVersion;
  final int books;
  final Map<String, int> filesByFormat;
  final int shelves;
  final int copies;
  final int annotations;
  final int readingSessions;
  final bool serverConfigured;

  /// Only known if the app has already asked the server; null otherwise.
  final String? serverVersion;
  final int? syncProtocol;
  final List<String>? serverFeatures;
  final List<LoggedError> errors;
  final String? homeDir;
  final String? dataDir;
  final DateTime generatedAt;
}

/// Replaces [dataDir] and [homeDir] in [text] with placeholders. The data
/// directory goes first because it usually lives inside the home directory and
/// would otherwise be reported as `<home>/…`. Both slash styles are matched.
String scrubPaths(String text, {String? homeDir, String? dataDir}) {
  var out = text;
  for (final (dir, label) in [(dataDir, '<data>'), (homeDir, '<home>')]) {
    if (dir == null) continue;
    final trimmed = dir.replaceAll(RegExp(r'[\\/]+$'), '');
    // A bare "/" or "C:" would blank half the report.
    if (trimmed.length < 3) continue;
    for (final variant in {
      trimmed,
      trimmed.replaceAll('\\', '/'),
      trimmed.replaceAll('/', '\\'),
    }) {
      out = out.replaceAll(variant, label);
    }
  }
  return out;
}

const _maxMessage = 300;

String buildDiagnosticsReport(DiagnosticsInput i) {
  String scrub(String s) =>
      scrubPaths(s, homeDir: i.homeDir, dataDir: i.dataDir);

  final formats = i.filesByFormat.keys.toList()..sort();
  final files = formats.isEmpty
      ? 'none'
      : formats.map((f) => '$f ${i.filesByFormat[f]}').join(', ');

  final b = StringBuffer()
    ..writeln('Vellum diagnostics')
    ..writeln(
      'Read this before posting it: it has no book titles, authors, '
      'file names or server address, but the error messages below are '
      'free text. Remove anything you would rather keep private.',
    )
    ..writeln()
    ..writeln('Generated: ${i.generatedAt.toUtc().toIso8601String()}')
    ..writeln()
    ..writeln('[App]')
    ..writeln('Version: ${i.appVersion}')
    ..writeln('Flavour: ${i.flavour}')
    ..writeln('Mode: ${i.mode}')
    ..writeln()
    ..writeln('[Device]')
    ..writeln('Platform: ${i.platform} ${i.osVersion}')
    ..writeln('Locale: ${i.locale}');
  if (i.screen != null) b.writeln('Screen: ${i.screen}');
  if (i.textScale != null) b.writeln('Text scale: ${i.textScale}');

  b
    ..writeln()
    ..writeln('[Library]')
    ..writeln('Database schema: ${i.schemaVersion}')
    ..writeln('Books: ${i.books}')
    ..writeln('Files: $files')
    ..writeln('Shelves: ${i.shelves}')
    ..writeln('Physical copies: ${i.copies}')
    ..writeln('Annotations: ${i.annotations}')
    ..writeln('Reading sessions: ${i.readingSessions}')
    ..writeln()
    ..writeln('[Server]')
    ..writeln('Configured: ${i.serverConfigured ? 'yes' : 'no'}');
  if (i.serverConfigured) {
    if (i.serverVersion == null) {
      b.writeln('Capabilities: not fetched this session');
    } else {
      b
        ..writeln('Server version: ${i.serverVersion}')
        ..writeln('Sync protocol: ${i.syncProtocol}')
        ..writeln('Features: ${(i.serverFeatures ?? const []).join(', ')}');
    }
  }

  b
    ..writeln()
    ..writeln('[Recent errors] (${i.errors.length}, oldest first)');
  if (i.errors.isEmpty) b.writeln('None since the app started.');
  for (final e in i.errors) {
    var message = scrub(e.message).replaceAll(RegExp(r'\s*\n\s*'), ' ');
    if (message.length > _maxMessage) {
      message = '${message.substring(0, _maxMessage)}…';
    }
    b.writeln('${e.time.toUtc().toIso8601String()} ${e.type}: $message');
    for (final f in e.frames) {
      b.writeln('    ${scrub(f)}');
    }
  }
  return b.toString();
}
