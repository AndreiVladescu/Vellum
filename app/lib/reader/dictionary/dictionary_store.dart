/// Where the offline dictionary lives, and how it gets there.
///
/// The pack is WordNet 3.0 as Princeton publishes it — one 10 MB download,
/// under a permissive licence that allows redistribution, so it is fetched
/// from the original rather than mirrored. Only the files a lookup needs are
/// kept: `index.sense` is a third of the archive and nothing here reads it.
///
/// Nothing is downloaded until the reader asks for it. A dictionary is a big
/// file to push at someone who may never open it, and an app that fetches
/// 34 MB on first launch to be helpful is not being helpful.
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'wordnet.dart';

/// The published archive. Princeton has served this exact path since 2007.
///
/// The full distribution rather than the database-only `WNdb-3.0.tar.gz`: it is
/// one megabyte larger and it carries the `.exc` files, which are what make
/// "ran" find *run* and "geese" find *goose*. Everything in it that a lookup
/// does not read is dropped on the way in.
const wordNetArchiveUrl =
    'https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz';

/// What the download costs, for the sentence shown before it starts. Nobody
/// should find out how big it was from their data bill.
const wordNetDownloadBytes = 11537239;

/// Roughly what it takes once unpacked, for the same reason.
const wordNetInstalledBytes = 20 << 20;

const wordNetLicence =
    'WordNet 3.0, Princeton University. Free to use and redistribute; see the '
    'licence inside the download.';

/// Progress of an install, from 0 to 1, or null while the work has no
/// measurable length (unpacking, which is fast and gives no callbacks).
typedef DictionaryProgress = void Function(double? fraction);

class DictionaryStore {
  DictionaryStore(this.dir);

  /// The directory the dictionary files sit in.
  final Directory dir;

  static Future<DictionaryStore> open() async {
    final support = await getApplicationSupportDirectory();
    return DictionaryStore(Directory('${support.path}/dictionary'));
  }

  WordNet get wordNet => WordNet(dir);

  bool get isInstalled => wordNet.isInstalled;

  /// What the installed files take up, or zero if there are none.
  int get bytesOnDisk {
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final entity in dir.listSync()) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }

  /// Fetches the archive and installs it.
  ///
  /// Downloaded to a file rather than held in memory: the archive is 10 MB
  /// compressed and 34 MB open, and a phone that is also holding a rendered PDF
  /// should not have to hold both.
  Future<void> download({
    DictionaryProgress? onProgress,
    http.Client? client,
  }) async {
    final own = client == null;
    final http.Client fetcher = client ?? http.Client();
    final temporary = File('${dir.path}/.download.tar.gz');
    await dir.create(recursive: true);
    try {
      final request = http.Request('GET', Uri.parse(wordNetArchiveUrl));
      final response = await fetcher.send(request);
      if (response.statusCode != 200) {
        throw DictionaryInstallException(
          'The download answered ${response.statusCode}.',
        );
      }
      final total = response.contentLength ?? wordNetDownloadBytes;
      final sink = temporary.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(total <= 0 ? null : (received / total).clamp(0, 1));
        }
      } finally {
        await sink.close();
      }
      onProgress?.call(null);
      await installFromArchive(temporary);
    } finally {
      if (temporary.existsSync()) {
        try {
          temporary.deleteSync();
        } catch (_) {
          // A leftover temp file is not worth failing an install over.
        }
      }
      if (own) fetcher.close();
    }
  }

  /// Unpacks a WordNet archive that is already on disk.
  ///
  /// Also the way in for someone who downloaded it themselves — the same file,
  /// from the same place, on a machine that cannot reach it from inside the app.
  Future<void> installFromArchive(File archiveFile) async {
    await dir.create(recursive: true);
    final tarPath = '${dir.path}/.download.tar';
    final tar = File(tarPath);
    try {
      final input = InputFileStream(archiveFile.path);
      final output = OutputFileStream(tarPath);
      try {
        GZipDecoder().decodeStream(input, output);
      } finally {
        await input.close();
        await output.close();
      }
      // Held in a local and closed below: an open handle on the unpacked tar
      // makes the delete in the `finally` fail on Windows, which would leave
      // 34 MB sitting in the dictionary directory — and counted by
      // [bytesOnDisk] as if it were the dictionary.
      final tarInput = InputFileStream(tarPath);
      var written = 0;
      try {
        final entries = TarDecoder().decodeStream(tarInput);
        for (final entry in entries.files) {
          if (!entry.isFile) continue;
          final name = entry.name.split('/').last;
          if (!WordNet.wantedFiles.contains(name)) continue;
          final out = OutputFileStream('${dir.path}/$name');
          try {
            entry.writeContent(out);
          } finally {
            await out.close();
          }
          written++;
        }
      } finally {
        await tarInput.close();
      }
      if (written == 0 || !isInstalled) {
        throw const DictionaryInstallException(
          'That file is not a WordNet database.',
        );
      }
    } finally {
      if (tar.existsSync()) {
        try {
          tar.deleteSync();
        } catch (_) {
          // As above: a leftover temp file is not a failed install.
        }
      }
    }
  }

  /// Gives the space back. The pack is re-downloadable, so this asks nothing
  /// beyond the confirmation the caller already got.
  Future<void> remove() async {
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is File) await entity.delete();
    }
  }
}

class DictionaryInstallException implements Exception {
  const DictionaryInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}
