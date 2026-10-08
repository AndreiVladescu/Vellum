import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The SHA-256 of the file at [path], as lowercase hex, worked out in a
/// background isolate.
///
/// Hashing is pure CPU: on the UI isolate a big file holds up frames for as
/// long as it takes, while in an isolate — Dart's thread, with its own memory —
/// it runs on another core. Several calls at once run on several cores.
Future<String> sha256OfFileInBackground(String path) =>
    Isolate.run(() => sha256OfFileSync(path));

/// The body of [sha256OfFileInBackground], for code already off the UI
/// isolate. Reads in 1 MB chunks, so memory stays flat over a 500 MB PDF.
String sha256OfFileSync(String path) {
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  final file = File(path).openSync();
  try {
    final buffer = Uint8List(1 << 20);
    while (true) {
      final read = file.readIntoSync(buffer);
      if (read == 0) break;
      hasher.add(
        read == buffer.length ? buffer : Uint8List.sublistView(buffer, 0, read),
      );
    }
  } finally {
    file.closeSync();
  }
  hasher.close();
  return sink.value!.toString();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
