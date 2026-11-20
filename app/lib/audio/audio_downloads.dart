import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/file_hash.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../server/server_client.dart';
import '../settings/app_settings.dart';
import 'audio_formats.dart';
import 'audiobook_import.dart';

/// What the network rule says about downloading a book's audio now.
enum AudioNetworkVerdict { go, askFirst }

/// The "Download audiobooks on Wi-Fi only" rule (docs/AUDIOBOOKS.md §6), as a
/// pure function so it can be tested without a phone.
///
/// Only Android asks: a computer downloads on whatever network it has. On a
/// metered network (mobile data, or a hotspot the system calls metered) with
/// the preference on, the answer is to ask, unless the listener already said
/// "Download anyway" for this book.
AudioNetworkVerdict audioNetworkVerdict({
  required bool isAndroid,
  required bool wifiOnly,
  required bool metered,
  required bool allowedForBook,
}) {
  if (!isAndroid || !wifiOnly || !metered || allowedForBook) {
    return AudioNetworkVerdict.go;
  }
  return AudioNetworkVerdict.askFirst;
}

/// Asks Android whether the active network is metered (`MainActivity`'s
/// `isMetered`). Elsewhere, and if the question cannot be answered, it says
/// metered on Android (ask rather than spend someone's data) and unmetered
/// everywhere else.
Future<bool> platformNetworkIsMetered() async {
  if (!Platform.isAndroid) return false;
  try {
    return await const MethodChannel('app.vellum.Vellum/network')
            .invokeMethod<bool>('isMetered') ??
        true;
  } catch (_) {
    return true;
  }
}

/// Where one book's audio download stands. Absent (null from
/// [AudioDownloads.statusOf]) means nothing is happening: the parts are
/// either here or not, which the `present` flag of each row says.
enum AudioDownloadPhase {
  /// Fetching parts now.
  downloading,

  /// On mobile data with "Wi-Fi only" on: waiting for "Download anyway".
  needsConsent,

  /// Stopped by an error; [AudioDownloadStatus.failure] says which.
  failed,
}

/// Why a download stopped.
enum AudioDownloadFailure {
  /// Not signed in to a server, so there is nowhere to download from.
  noServer,

  /// The network or the server failed, after the automatic retries.
  network,

  /// A part arrived but did not hash to the stored sha256, and was thrown
  /// away (twice, if the first attempt was a resume).
  hashMismatch,
}

/// One book's download, as the UI shows it.
@immutable
class AudioDownloadStatus {
  const AudioDownloadStatus({
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
    required this.partsDone,
    required this.partsTotal,
    this.failure,
    this.detail,
  });

  final AudioDownloadPhase phase;

  /// Bytes of the book's audio on this device, counting the part now
  /// arriving.
  final int receivedBytes;

  /// All the book's audio.
  final int totalBytes;
  final int partsDone;
  final int partsTotal;
  final AudioDownloadFailure? failure;

  /// The underlying error's text, for the second line of a failure.
  final String? detail;

  double? get fraction =>
      totalBytes <= 0 ? null : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

/// What [AudioDownloads.download] did.
enum AudioDownloadStart { started, alreadyHere, needsConsent, noServer }

/// What [AudioDownloads.remove] did.
enum AudioRemoveResult {
  removed,

  /// Some part is not on the server (or the server could not be asked), so
  /// removing it here could lose the only copy. Nothing was deleted.
  notOnServer,
}

/// "812 KB" / "430.2 MB" / "1.2 GB". The units read the same in every
/// language.
String formatBytes(int bytes) {
  const kb = 1024;
  if (bytes < kb * kb) return '${(bytes / kb).round()} KB';
  if (bytes < kb * kb * kb) return '${(bytes / (kb * kb)).toStringAsFixed(1)} MB';
  return '${(bytes / (kb * kb * kb)).toStringAsFixed(1)} GB';
}

/// How much audiobook audio this device holds.
typedef AudioStorage = ({int bytes, int books});

/// Watches the space downloaded audiobook audio takes on this device: the
/// sizes of the audio parts whose bytes are here.
Stream<AudioStorage> watchAudioStorage(VellumDatabase db) {
  final formats = audioFormats.map((f) => "'$f'").join(', ');
  return db
      .customSelect(
        'SELECT COALESCE(SUM(size_bytes), 0) AS bytes, '
        'COUNT(DISTINCT book_id) AS books FROM book_files '
        'WHERE present = 1 AND LOWER(format) IN ($formats)',
        readsFrom: {db.bookFiles},
      )
      .watchSingle()
      .map((row) => (bytes: row.read<int>('bytes'), books: row.read<int>('books')));
}

/// Downloads audiobook audio on demand (docs/AUDIOBOOKS.md §6).
///
/// A pull brings an audio part's *row* (`present = false`) but not its bytes.
/// This fetches them when someone wants to listen: the part holding the saved
/// position first, so playback can start as soon as it is here, then the rest
/// in order. Each part streams into `audio-downloads/` (outside `files/`, so
/// the startup sweep of `.part` files leaves it for the next attempt to
/// resume with `Range`), is checked against the row's sha256, and only then
/// moves into `files/` and becomes `present`.
///
/// One instance for the app ([instance]); the player, the player page and the
/// book page all watch it. Tests build their own with fakes.
class AudioDownloads extends ChangeNotifier {
  AudioDownloads({
    Future<VellumServerClient?> Function()? client,
    Future<bool> Function()? isMetered,
    Future<bool> Function()? wifiOnly,
    bool? isAndroid,
    Future<String> Function(String path)? hasher,
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 10)],
    this.progressInterval = const Duration(milliseconds: 200),
  })  : _client = client ?? _connectedClient,
        _isMetered = isMetered ?? platformNetworkIsMetered,
        _wifiOnly = wifiOnly ?? _storedWifiOnly,
        _isAndroid = isAndroid ?? Platform.isAndroid,
        _hasher = hasher ?? sha256OfFileInBackground;

  /// The app's downloads.
  static final AudioDownloads instance = AudioDownloads();

  final Future<VellumServerClient?> Function() _client;
  final Future<bool> Function() _isMetered;
  final Future<bool> Function() _wifiOnly;
  final bool _isAndroid;
  final Future<String> Function(String path) _hasher;

  /// Pauses before each automatic retry of a part after a network error; one
  /// retry per entry. The partial file is kept, so a retry resumes.
  final List<Duration> retryDelays;

  /// How often a running download tells its listeners how far it has got.
  final Duration progressInterval;

  static Future<VellumServerClient?> _connectedClient() async =>
      (await ServerConnection.load()).client;

  static Future<bool> _storedWifiOnly() async =>
      (await SharedPreferences.getInstance())
          .getBool(AppSettingsStore.audioWifiOnlyKey) ??
      true;

  final _jobs = <String, _Job>{};
  final _status = <String, AudioDownloadStatus>{};
  final _starting = <String, Future<AudioDownloadStart>>{};

  /// Books whose listener said "Download anyway" on mobile data, this run.
  final _meteredOk = <String>{};

  /// Where [bookId]'s download stands, or null when nothing is going on.
  AudioDownloadStatus? statusOf(String bookId) => _status[bookId];

  /// Whether a download of [bookId] is running.
  bool isDownloading(String bookId) => _jobs.containsKey(bookId);

  /// Completes when [bookId]'s running download stops, for whatever reason.
  /// Already complete when none is running.
  Future<void> whenSettled(String bookId) =>
      _jobs[bookId]?.done.future ?? Future.value();

  /// The partial file a part streams into before its hash is checked.
  static File partialOf(LibraryRepository repository, BookFile file) => File(
      p.join(repository.dataDir.path, 'audio-downloads', '${p.basename(file.path)}.partial'));

  /// Starts (or joins) downloading [bookId]'s missing audio parts.
  ///
  /// [firstFileId] goes first: the part holding the saved position, so the
  /// player can start on it. [allowMetered] is "Download anyway": it lifts the
  /// Wi-Fi-only rule for this book until the app restarts.
  Future<AudioDownloadStart> download(
    LibraryRepository repository,
    String bookId, {
    String? firstFileId,
    bool allowMetered = false,
  }) {
    if (allowMetered) _meteredOk.add(bookId);
    final running = _jobs[bookId];
    if (running != null && !running.cancelled) {
      if (firstFileId != null) running.prioritise(firstFileId);
      return Future.value(AudioDownloadStart.started);
    }
    // Two taps at once start one download; a cancelled one still winding
    // down (its last chunk) finishes first, so two never write one file.
    final previous = running?.done.future ?? Future<void>.value();
    return _starting[bookId] ??= previous
        .then((_) => _start(repository, bookId, firstFileId))
        // A block, not `=>`: whenComplete waits for a Future its callback
        // returns, and remove() returns this very future.
        .whenComplete(() {
      _starting.remove(bookId);
    });
  }

  Future<AudioDownloadStart> _start(
    LibraryRepository repository,
    String bookId,
    String? firstFileId,
  ) async {
    final parts = await AudiobookImporter(repository).audioFilesOf(bookId);
    final missing = [for (final f in parts) if (!f.present) f];
    if (missing.isEmpty) {
      _setStatus(bookId, null);
      return AudioDownloadStart.alreadyHere;
    }
    final totalBytes = parts.fold<int>(0, (n, f) => n + f.sizeBytes);
    final hereBytes = parts.fold<int>(0, (n, f) => f.present ? n + f.sizeBytes : n);
    AudioDownloadStatus status(AudioDownloadPhase phase,
            {AudioDownloadFailure? failure}) =>
        AudioDownloadStatus(
          phase: phase,
          receivedBytes: hereBytes,
          totalBytes: totalBytes,
          partsDone: parts.length - missing.length,
          partsTotal: parts.length,
          failure: failure,
        );

    if (_isAndroid) {
      final verdict = audioNetworkVerdict(
        isAndroid: true,
        wifiOnly: await _wifiOnly(),
        metered: await _isMetered(),
        allowedForBook: _meteredOk.contains(bookId),
      );
      if (verdict == AudioNetworkVerdict.askFirst) {
        _setStatus(bookId, status(AudioDownloadPhase.needsConsent));
        return AudioDownloadStart.needsConsent;
      }
    }
    final client = await _client();
    if (client == null) {
      _setStatus(bookId,
          status(AudioDownloadPhase.failed, failure: AudioDownloadFailure.noServer));
      return AudioDownloadStart.noServer;
    }

    // The part with the position first, then on to the end, then the ones
    // before it: the order someone listening needs them in.
    final from = firstFileId == null
        ? 0
        : missing.indexWhere((f) => f.id == firstFileId).clamp(0, missing.length);
    final job = _Job(
      bookId: bookId,
      queue: [...missing.skip(from), ...missing.take(from)],
      parts: parts,
    );
    _jobs[bookId] = job;
    _publish(job);
    unawaited(_run(repository, client, job));
    return AudioDownloadStart.started;
  }

  /// Stops [bookId]'s download. What has arrived stays: finished parts are
  /// playable, and the part in flight resumes next time. The "Wi-Fi only"
  /// question, if one was waiting, is dropped too.
  void cancel(String bookId) {
    final job = _jobs[bookId];
    if (job != null) {
      job.cancelled = true;
      job.transfer?.cancel();
    }
    _setStatus(bookId, null);
  }

  /// Clears a failure or an unanswered question from the book's status.
  void dismiss(String bookId) {
    if (_jobs.containsKey(bookId)) return;
    _setStatus(bookId, null);
  }

  /// Waits for [part]'s bytes, downloading the book from it onwards if
  /// nothing is yet. True once the part is playable here; false if the
  /// download could not run (no server, the Wi-Fi rule, an error, cancel).
  Future<bool> ensurePart(LibraryRepository repository, BookFile part) async {
    final fresh = await repository.fileById(part.id);
    if (fresh == null) return false;
    if (fresh.present) return true;
    final started = await download(repository, part.bookId, firstFileId: part.id);
    if (started == AudioDownloadStart.alreadyHere) {
      return (await repository.fileById(part.id))?.present ?? false;
    }
    if (started != AudioDownloadStart.started) return false;
    final job = _jobs[part.bookId];
    if (job == null) {
      return (await repository.fileById(part.id))?.present ?? false;
    }
    job.prioritise(part.id);
    // No await between the check and the registration, so a part that
    // finishes in between is seen in [finished] rather than missed.
    if (job.finished.contains(part.id)) return true;
    final waiter = Completer<bool>();
    job.waiters.putIfAbsent(part.id, () => []).add(waiter);
    return waiter.future;
  }

  /// Frees the space [bookId]'s audio takes here. The book, its parts' rows,
  /// chapters and listening position stay; the parts become not `present`
  /// and download again on Listen.
  ///
  /// Only when the server holds every part this device has: an audiobook
  /// imported here and never uploaded (no server, *keep on this device*, a
  /// push still pending) would otherwise be deleted outright. The caller
  /// stops playback of this book first.
  Future<AudioRemoveResult> remove(
    LibraryRepository repository,
    String bookId,
  ) async {
    final parts = await AudiobookImporter(repository).audioFilesOf(bookId);
    final here = [for (final f in parts) if (f.present) f];
    if (here.isNotEmpty) {
      final client = await _client();
      if (client == null) return AudioRemoveResult.notOnServer;
      try {
        final onServer = {for (final f in await client.listFiles(bookId)) f.sha256};
        if (!here.every((f) => onServer.contains(f.sha256))) {
          return AudioRemoveResult.notOnServer;
        }
      } catch (_) {
        return AudioRemoveResult.notOnServer;
      }
    }
    cancel(bookId);
    await whenSettled(bookId);
    final db = repository.db;
    await (db.update(db.bookFiles)
          ..where((f) => f.id.isIn([for (final f in parts) f.id])))
        .write(const BookFilesCompanion(present: Value(false)));
    for (final part in parts) {
      for (final file in [repository.fileOf(part), partialOf(repository, part)]) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Locked: the row already says the bytes are not here, and a
          // download writes the file again from scratch.
        }
      }
    }
    _setStatus(bookId, null);
    return AudioRemoveResult.removed;
  }

  Future<void> _run(
    LibraryRepository repository,
    VellumServerClient client,
    _Job job,
  ) async {
    AudioDownloadFailure? failure;
    String? detail;
    try {
      while (job.queue.isNotEmpty && !job.cancelled) {
        final next = job.queue.removeAt(0);
        final part = await repository.fileById(next.id);
        if (part == null) {
          job.settle(next.id, false); // removed meanwhile
          continue;
        }
        if (!part.present) {
          job.current = part;
          job.currentBytes = 0;
          _publish(job);
          await _fetch(repository, client, job, part);
          if (job.cancelled) break;
        }
        job.current = null;
        job.currentBytes = 0;
        job.hereBytes += part.sizeBytes;
        job.partsDone++;
        job.settle(part.id, true);
        _publish(job);
      }
    } on TransferCancelled {
      // Asked for; [cancel] already cleared the status.
    } on _HashMismatch catch (e) {
      failure = AudioDownloadFailure.hashMismatch;
      detail = e.fileId;
    } catch (e) {
      failure = AudioDownloadFailure.network;
      detail = '$e';
    } finally {
      _jobs.remove(job.bookId);
      job.timer?.cancel();
      job.settleAll(false);
      if (failure != null && !job.cancelled) {
        _setStatus(
          job.bookId,
          AudioDownloadStatus(
            phase: AudioDownloadPhase.failed,
            receivedBytes: job.hereBytes,
            totalBytes: job.totalBytes,
            partsDone: job.partsDone,
            partsTotal: job.parts.length,
            failure: failure,
            detail: detail,
          ),
        );
      } else {
        _setStatus(job.bookId, null);
      }
      job.done.complete();
    }
  }

  /// One part: stream, verify, move into place, mark present.
  Future<void> _fetch(
    LibraryRepository repository,
    VellumServerClient client,
    _Job job,
    BookFile part,
  ) async {
    final partial = partialOf(repository, part);
    await partial.parent.create(recursive: true);
    var retries = 0;
    var restarted = false;
    while (true) {
      if (job.cancelled) throw const TransferCancelled();
      final resumedFrom = await partial.exists() ? await partial.length() : 0;
      final transfer = TransferCancel();
      job.transfer = transfer;
      try {
        await client.downloadFileTo(
          part.id,
          partial,
          sha256: part.sha256,
          cancel: transfer,
          onProgress: (received, _) {
            job.currentBytes = received;
            _publishSoon(job);
          },
        );
      } on TransferCancelled {
        rethrow;
      } catch (e) {
        if (job.cancelled) throw const TransferCancelled();
        // A refusal (gone, no access) will not get better by asking again; a
        // dropped connection or a busy server might.
        final retryable = e is! ServerException || (e.statusCode ?? 500) >= 500;
        if (!retryable || retries >= retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[retries++]);
        continue;
      }
      if (job.cancelled) throw const TransferCancelled();
      final hash = await _hasher(partial.path);
      if (hash != part.sha256) {
        await partial.delete();
        // A resumed file can be bad in its first half (a crash mid-write);
        // one fresh start is worth it. A whole download that is wrong is.
        if (resumedFrom > 0 && !restarted) {
          restarted = true;
          continue;
        }
        throw _HashMismatch(part.id);
      }
      final dest = repository.fileOf(part);
      await dest.parent.create(recursive: true);
      await partial.rename(dest.path);
      final db = repository.db;
      await (db.update(db.bookFiles)..where((f) => f.id.equals(part.id)))
          .write(const BookFilesCompanion(present: Value(true)));
      // Chapters are derived, not synced: an m4b's come out of the bytes
      // that just arrived, as on the device that imported it.
      await AudiobookImporter(repository).rebuildChapters(part.id);
      return;
    }
  }

  void _publishSoon(_Job job) {
    if (job.timer != null) return;
    job.timer = Timer(progressInterval, () {
      job.timer = null;
      if (_jobs[job.bookId] == job) _publish(job);
    });
  }

  void _publish(_Job job) {
    if (job.cancelled) return;
    _setStatus(
      job.bookId,
      AudioDownloadStatus(
        phase: AudioDownloadPhase.downloading,
        receivedBytes: job.hereBytes + job.currentBytes,
        totalBytes: job.totalBytes,
        partsDone: job.partsDone,
        partsTotal: job.parts.length,
      ),
    );
  }

  void _setStatus(String bookId, AudioDownloadStatus? status) {
    if (status == null) {
      if (_status.remove(bookId) == null) return;
    } else {
      _status[bookId] = status;
    }
    notifyListeners();
  }
}

class _HashMismatch implements Exception {
  _HashMismatch(this.fileId);
  final String fileId;
}

class _Job {
  _Job({required this.bookId, required this.queue, required this.parts})
      : totalBytes = parts.fold<int>(0, (n, f) => n + f.sizeBytes),
        hereBytes = parts.fold<int>(0, (n, f) => f.present ? n + f.sizeBytes : n),
        partsDone = parts.where((f) => f.present).length;

  final String bookId;
  final List<BookFile> queue;
  final List<BookFile> parts;
  final int totalBytes;
  int hereBytes;
  int partsDone;
  BookFile? current;
  int currentBytes = 0;
  bool cancelled = false;
  TransferCancel? transfer;
  Timer? timer;
  final done = Completer<void>();

  /// Parts this job has made present.
  final finished = <String>{};
  final waiters = <String, List<Completer<bool>>>{};

  /// Moves [fileId] to the front of what is left, after the part in flight.
  void prioritise(String fileId) {
    final at = queue.indexWhere((f) => f.id == fileId);
    if (at > 0) queue.insert(0, queue.removeAt(at));
  }

  void settle(String fileId, bool ok) {
    if (ok) finished.add(fileId);
    for (final w in waiters.remove(fileId) ?? const <Completer<bool>>[]) {
      if (!w.isCompleted) w.complete(ok);
    }
  }

  void settleAll(bool ok) {
    for (final id in [...waiters.keys]) {
      settle(id, ok);
    }
  }
}
