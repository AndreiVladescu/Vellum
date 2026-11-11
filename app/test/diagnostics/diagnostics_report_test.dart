// "Copy diagnostics": the report text, the scrubbing, the error ring buffer,
// and the promise that nothing about a book can reach the report.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/diagnostics/diagnostics_collector.dart';
import 'package:vellum/diagnostics/diagnostics_report.dart';
import 'package:vellum/diagnostics/error_log.dart';
import 'package:vellum/server/connection_store.dart';

DiagnosticsInput sample({
  List<LoggedError> errors = const [],
  bool server = false,
  String? home,
  String? data,
}) => DiagnosticsInput(
  appVersion: '1.1.12 (12)',
  flavour: 'free',
  mode: 'release',
  platform: 'linux',
  osVersion: 'Linux 6.8',
  locale: 'en-US',
  screen: '1280x800',
  textScale: 1.0,
  schemaVersion: 38,
  books: 3,
  filesByFormat: const {'pdf': 2, 'epub': 1},
  shelves: 2,
  copies: 1,
  annotations: 5,
  readingSessions: 4,
  serverConfigured: server,
  errors: errors,
  homeDir: home,
  dataDir: data,
  generatedAt: DateTime.utc(2026, 11, 11, 12),
);

void main() {
  test('the report has every section, with the warning first', () {
    final text = buildDiagnosticsReport(sample());
    expect(text.split('\n').first, 'Vellum diagnostics');
    expect(text, contains('Read this before posting it'));
    expect(text, contains('Version: 1.1.12 (12)'));
    expect(text, contains('Flavour: free'));
    expect(text, contains('Mode: release'));
    expect(text, contains('Platform: linux Linux 6.8'));
    expect(text, contains('Locale: en-US'));
    expect(text, contains('Screen: 1280x800'));
    expect(text, contains('Database schema: 38'));
    expect(text, contains('Books: 3'));
    expect(text, contains('Files: epub 1, pdf 2'));
    expect(text, contains('Reading sessions: 4'));
    expect(text, contains('Configured: no'));
    expect(text, contains('None since the app started.'));
  });

  test('a configured server shows capabilities only when known', () {
    expect(
      buildDiagnosticsReport(sample(server: true)),
      contains('not fetched this session'),
    );
    final known = buildDiagnosticsReport(
      DiagnosticsInput(
        appVersion: 'x',
        flavour: 'full',
        mode: 'debug',
        platform: 'linux',
        osVersion: '',
        locale: 'en',
        schemaVersion: 1,
        books: 0,
        filesByFormat: const {},
        shelves: 0,
        copies: 0,
        annotations: 0,
        readingSessions: 0,
        serverConfigured: true,
        serverVersion: '0.9.1',
        syncProtocol: 3,
        serverFeatures: const ['live_events', 'batch'],
        generatedAt: DateTime.utc(2026),
      ),
    );
    expect(known, contains('Server version: 0.9.1'));
    expect(known, contains('Features: live_events, batch'));
  });

  test('scrubbing removes the data and home directories', () {
    final err = LoggedError(
      time: DateTime.utc(2026),
      type: 'FileSystemException',
      message: 'Cannot open /home/ann/Vellum/books/x.pdf and /home/ann/.cache',
      frames: const ['#0 open (file:///home/ann/Vellum/books/y.dart:1)'],
    );
    final text = buildDiagnosticsReport(
      sample(errors: [err], home: '/home/ann', data: '/home/ann/Vellum'),
    );
    expect(text, isNot(contains('/home/ann')));
    expect(text, contains('<data>/books/x.pdf'));
    expect(text, contains('<home>/.cache'));
    expect(text, contains('file://<data>/books/y.dart'));
  });

  test('scrubbing handles Windows separators and refuses a bare root', () {
    expect(
      scrubPaths(
        r'C:\Users\Ann\Docs\a.pdf and C:/Users/Ann/b',
        homeDir: r'C:\Users\Ann',
      ),
      '<home>\\Docs\\a.pdf and <home>/b',
    );
    expect(scrubPaths('/usr/lib', homeDir: '/'), '/usr/lib');
  });

  test('the ring buffer caps, keeps the newest, and stays in order', () {
    final log = ErrorLog(capacity: 30);
    for (var i = 0; i < 45; i++) {
      log.record(StateError('e$i'), StackTrace.current);
    }
    expect(log.entries, hasLength(30));
    expect(log.entries.first.message, contains('e15'));
    expect(log.entries.last.message, contains('e44'));
    expect(log.entries.first.type, 'StateError');
    expect(log.entries.first.frames, isNotEmpty);
    expect(log.entries.first.frames.length, lessThanOrEqualTo(5));
  });

  test('a long message is cut, and newlines do not break the layout', () {
    final err = LoggedError(
      time: DateTime.utc(2026),
      type: 'X',
      message: 'a\nb ${'z' * 1000}',
      frames: const [],
    );
    final line = buildDiagnosticsReport(
      sample(errors: [err]),
    ).split('\n').firstWhere((l) => l.contains(' X: '));
    expect(line.length, lessThan(400));
    expect(line, contains('a b z'));
  });

  group('nothing about a book gets in', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vellum_diag'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('titles, authors, paths and the server address stay out', (
      tester,
    ) async {
      late String text;
      late LibraryRepository repo;
      await tester.pumpWidget(const SizedBox());
      final ctx = tester.element(find.byType(SizedBox));
      await tester.runAsync(() async {
        PackageInfo.setMockInitialValues(
          appName: 'Vellum',
          packageName: 'x',
          version: '1.2.3',
          buildNumber: '4',
          buildSignature: '',
        );
        SharedPreferences.setMockInitialValues({
          'server.url': 'https://secret-host.example',
          'server.email': 'ann@secret-mail.example',
        });
        repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()),
          dir,
        );
        final db = repo.db;
        await db
            .into(db.books)
            .insert(BooksCompanion.insert(id: 'b1', title: 'Zebra Manifesto'));
        await db
            .into(db.bookFiles)
            .insert(
              BookFilesCompanion.insert(
                id: 'f1',
                bookId: 'b1',
                format: 'pdf',
                path: '${dir.path}/Hidden Author - Zebra Manifesto.pdf',
                sizeBytes: 10,
                sha256: 'abc',
              ),
            );
        final connection = await ServerConnection.load();
        ErrorLog.instance.record(
          StateError('failed at ${dir.path}/cover.png'),
          null,
        );
        text = buildDiagnosticsReport(
          await collectDiagnostics(
            ctx,
            repository: repo,
            connection: connection,
          ),
        );
      });
      expect(text, contains('Books: 1'));
      expect(text, contains('Files: pdf 1'));
      expect(text, contains('Version: 1.2.3 (4)'));
      expect(text, contains('<data>/cover.png'));
      for (final secret in [
        'Zebra',
        'Hidden Author',
        '.pdf',
        'secret-host',
        'secret-mail',
        dir.path,
        'b1',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      await tester.runAsync(() => repo.db.close());
    });
  });
}
