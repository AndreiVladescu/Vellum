// Sync failures are worded in the reader's language by kind, with the raw text
// kept as a diagnostic line.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/l10n/labels.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sync_service.dart';

void main() {
  test('classifies the known failures', () {
    ServerErrorKind k(Object e) => classifyServerError(e);
    expect(k(const SocketException('x')), ServerErrorKind.unreachable);
    expect(k(http.ClientException('x')), ServerErrorKind.unreachable);
    expect(k(TimeoutException('x')), ServerErrorKind.timeout);
    expect(k(ServerException('x', statusCode: 401)),
        ServerErrorKind.unauthorized);
    expect(k(ServerException('x', statusCode: 403)), ServerErrorKind.forbidden);
    expect(k(ServerException('x', statusCode: 404)), ServerErrorKind.notFound);
    expect(k(ServerException('x', statusCode: 503)),
        ServerErrorKind.serverError);
    expect(k(const HandshakeException('x')), ServerErrorKind.tls);
    expect(k(ServerException('x', statusCode: 400)), ServerErrorKind.other);
    expect(k(StateError('x')), ServerErrorKind.other);
  });

  test('an issue with an error gets a sentence, the raw text stays', () {
    final l10n = lookupL10n(const Locale('en'));
    final issue = SyncIssue(
      bookId: 'b',
      title: 'T',
      stage: 'push',
      message: 'Connection refused',
      error: const SocketException('Connection refused'),
    );
    expect(issue.reasonOf(l10n), l10n.serverErrorKindUnreachable);
    expect(issue.messageOf(l10n), 'Connection refused');
    expect(SyncIssue(bookId: 'b', title: 'T', stage: 's', message: 'm')
        .reasonOf(l10n), isNull);
  });
}
