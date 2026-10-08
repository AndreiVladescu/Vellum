import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../data/cover_thumbnails.dart';

/// A book's cover, decoded at [height] physical pixels from its thumbnail when
/// it has one (performance round #3).
///
/// Used where `Image.file(cover, cacheHeight: …)` was. On a miss — the first
/// time a cover is shown at this size, or after it changed — it decodes the
/// cover itself, exactly as before, and has the thumbnail made in the
/// background for next time. So a cold shelf is no slower than it was, and
/// every later look at it reads a file ~30× smaller.
///
/// An `ImageProvider` is what an `Image` widget asks for pixels; Flutter caches
/// the decoded result under the provider's *key*. Here the key is resolved
/// asynchronously and includes the cover file's modified time and size, so a
/// rewritten cover can never be served from a stale cache entry — the cover
/// keeps a fixed path per book, and `FileImage`'s path-only key had no way to
/// tell.
@immutable
class CoverImage extends ImageProvider<CoverImageKey> {
  const CoverImage(this.cover, {required this.height, this.version});

  final File cover;

  /// Decode height in physical pixels. Callers bucket it (see
  /// `spineDecodeHeight`), because a new height is a new thumbnail on disk.
  final int height;

  /// Anything that changes when the book's cover may have (its `updatedAt`
  /// and `coverEtag`). Not part of the cache key — a changed value just makes
  /// the `Image` resolve again, which re-reads the file's modified time; an
  /// unchanged file then hits the cache as before.
  final Object? version;

  @override
  Future<CoverImageKey> obtainKey(ImageConfiguration configuration) async {
    final stat = await cover.stat();
    return CoverImageKey(cover.path, height, stat.modified, stat.size);
  }

  @override
  ImageStreamCompleter loadImage(
    CoverImageKey key,
    ImageDecoderCallback decode,
  ) =>
      MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: 1.0,
        debugLabel: '${cover.path}@$height',
      );

  Future<ui.Codec> _load(CoverImageKey key, ImageDecoderCallback decode) async {
    final thumb = await CoverThumbnails.current(
      cover,
      height,
      coverModified: key.modified,
    );
    if (thumb != null) {
      try {
        // Already the right height: decode it as it is.
        return await decode(await ui.ImmutableBuffer.fromFilePath(thumb.path));
      } catch (_) {
        // Truncated or unreadable; the cover below still works, and the
        // thumbnail is remade from it.
      }
    }
    // A missing file (an orphaned path) has nothing to make a thumbnail of;
    // the decode below fails and the caller's errorBuilder takes over.
    if (key.size > 0) unawaited(CoverThumbnails.make(cover, height));
    return decode(
      await ui.ImmutableBuffer.fromFilePath(cover.path),
      // Never upscale a cover that is smaller than asked for.
      getTargetSize: (_, intrinsicHeight) =>
          ui.TargetImageSize(height: math.min(height, intrinsicHeight)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoverImage &&
      other.cover.path == cover.path &&
      other.height == height &&
      other.version == version;

  @override
  int get hashCode => Object.hash(cover.path, height, version);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'CoverImage')}("${cover.path}", height: $height)';
}

/// Where a decoded cover sits in Flutter's image cache: the file *as it was*
/// when it was read, at one decode height.
@immutable
class CoverImageKey {
  const CoverImageKey(this.path, this.height, this.modified, this.size);

  final String path;
  final int height;
  final DateTime modified;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is CoverImageKey &&
      other.path == path &&
      other.height == height &&
      other.modified == modified &&
      other.size == size;

  @override
  int get hashCode => Object.hash(path, height, modified, size);
}
