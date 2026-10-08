import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

/// Small JPEG copies of cover images, for the shelf (performance round #3).
///
/// A spine is a few hundred pixels tall, but its cover can be a 908×1200 PNG of
/// 1.7 MB — a rendered PDF page. Flutter inflated all of it for every spine that
/// scrolled into view, then threw most of it away. A thumbnail at the spine's
/// decode height is ~30× smaller, and a JPEG decodes far faster than a PNG.
///
/// Derived, never authoritative: kept in `covers/thumbs/`, named after the
/// cover, and remade whenever the cover file is newer than it. So the many
/// places that write a cover (sync, import, merge, the detail page) need not
/// know thumbnails exist. Backups and the library doctor only look at files
/// directly inside `covers/`, so neither sees them.
///
/// The work runs in background isolates — Dart's threads, each with its own
/// memory — a few at a time, so a cold shelf spreads over the machine's cores
/// instead of queueing on one.
abstract final class CoverThumbnails {
  /// Above this a spine is zoomed far enough in (the physical room) that the
  /// cover itself is what it should show.
  static const maxHeight = 1024;

  /// One isolate per spare core, at most four: the UI isolate keeps a core to
  /// itself, and past four a phone runs hot for no visible gain.
  static final _pool = Pool((Platform.numberOfProcessors - 1).clamp(1, 4));

  /// Thumbnails being made right now, so a cover asked for twice — two spines
  /// of the same book, or a rebuild mid-decode — is made once.
  static final _inFlight = <String, Future<bool>>{};

  /// `covers/thumbs/<cover name>-h<height>.jpg`.
  static File fileFor(File cover, int height) => File(p.join(
        p.dirname(cover.path),
        'thumbs',
        '${p.basenameWithoutExtension(cover.path)}-h$height.jpg',
      ));

  /// Whether [height] is a size worth making a thumbnail at.
  static bool supports(int height) => height > 0 && height <= maxHeight;

  /// The thumbnail of [cover] at [height] if one exists and is at least as new
  /// as [coverModified]; null otherwise. Never makes one — see [make].
  static Future<File?> current(
    File cover,
    int height, {
    required DateTime coverModified,
  }) async {
    if (!supports(height)) return null;
    final thumb = fileFor(cover, height);
    final stat = await thumb.stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return stat.modified.isBefore(coverModified) ? null : thumb;
  }

  /// Makes the thumbnail of [cover] at [height] in a background isolate.
  /// Returns false when the cover can't be decoded or [height] isn't a
  /// thumbnail size; the caller then uses the cover itself.
  static Future<bool> make(File cover, int height) {
    if (!supports(height)) return Future.value(false);
    // Plain strings into the closure: it is copied into the new isolate, and
    // anything it captures is copied with it.
    final source = cover.path;
    final thumb = fileFor(cover, height).path;
    return _inFlight[thumb] ??= _pool
        .withResource(() => Isolate.run(() => _write(source, thumb, height)))
        // A block body, not `=>`: `remove` returns the future being built
        // here, and `whenComplete` waits on whatever its callback returns — so
        // the arrow form waits on itself and never completes.
        .whenComplete(() {
          _inFlight.remove(thumb);
        });
  }

  /// Removes every thumbnail of [cover], for when its book is deleted.
  static Future<void> deleteFor(File cover) async {
    final dir = Directory(p.join(p.dirname(cover.path), 'thumbs'));
    if (!await dir.exists()) return;
    final prefix = '${p.basenameWithoutExtension(cover.path)}-h';
    await for (final entry in dir.list()) {
      if (entry is File && p.basename(entry.path).startsWith(prefix)) {
        try {
          await entry.delete();
        } catch (_) {
          // Derived data: an undeletable thumbnail costs disk, nothing else.
        }
      }
    }
  }

  /// Runs inside the isolate, so it may block: synchronous IO is simpler here
  /// and holds up nothing but this one job.
  static bool _write(String coverPath, String thumbPath, int height) {
    try {
      final decoded = img.decodeImage(File(coverPath).readAsBytesSync());
      if (decoded == null) return false;
      // A photo's EXIF rotation, applied the way Flutter's own decoder does.
      var image = img.bakeOrientation(decoded);
      if (image.height > height) {
        image = img.copyResize(
          image,
          height: height,
          interpolation: img.Interpolation.average,
        );
      }
      // JPEG has no transparency. Flatten onto white — what a PDF page renders
      // on (pdf_cover.dart) — rather than let the encoder drop the alpha and
      // leave whatever colour the transparent pixels happened to hold.
      if (image.hasAlpha) {
        final flat = img.Image(width: image.width, height: image.height)
          ..clear(img.ColorRgb8(255, 255, 255));
        image = img.compositeImage(flat, image);
      }
      final part = File('$thumbPath.part');
      part.parent.createSync(recursive: true);
      part.writeAsBytesSync(img.encodeJpg(image, quality: 85), flush: true);
      part.renameSync(thumbPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}
