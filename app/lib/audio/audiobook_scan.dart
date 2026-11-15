import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import 'audio_formats.dart';
import 'mp3_duration.dart';
import 'mp4_reader.dart';

/// One chapter mark, from the start of its own part.
class ScannedChapter {
  const ScannedChapter(this.startMs, this.title);
  final int startMs;
  final String? title;
}

/// What the scan read from one audio file.
class AudioPartScan {
  AudioPartScan({
    required this.path,
    required this.format,
    this.durationMs,
    this.title,
    this.album,
    this.artist,
    this.albumArtist,
    this.narrator,
    this.disc,
    this.trackNo,
    this.chapters = const [],
  });

  final String path;

  /// 'm4b', 'm4a' or 'mp3'.
  final String format;
  final int? durationMs;

  /// The tags, as found: `©nam`/`TIT2`, `©alb`/`TALB`, `©ART`/`TPE1`,
  /// `aART`/`TPE2`, `©wrt`/`TCOM`.
  final String? title;
  final String? album;
  final String? artist;
  final String? albumArtist;
  final String? narrator;

  /// ID3 `TPOS` and `TRCK` (or their MP4 equivalents); null when absent.
  final int? disc;
  final int? trackNo;

  /// Chapter marks inside this file (an m4b's); empty for an mp3.
  final List<ScannedChapter> chapters;

  /// The part's title: its title tag, or the file name without extension.
  String get label {
    final t = title?.trim();
    return t == null || t.isEmpty ? p.basenameWithoutExtension(path) : t;
  }
}

/// A whole audiobook, parts in playing order.
class AudiobookScan {
  AudiobookScan({
    required this.parts,
    required this.title,
    this.author,
    this.narrator,
    this.cover,
  });

  final List<AudioPartScan> parts;
  final String title;
  final String? author;
  final String? narrator;

  /// Cover bytes (JPEG/PNG), or null for a generated spine.
  final Uint8List? cover;

  /// Null if any part's duration is unknown.
  int? get totalMs {
    var sum = 0;
    for (final part in parts) {
      final d = part.durationMs;
      if (d == null) return null;
      sum += d;
    }
    return sum;
  }

  /// The chapters a part is played with: its own marks, or one chapter at 0
  /// titled from its label (docs/AUDIOBOOKS.md §3).
  static List<ScannedChapter> chaptersOf(AudioPartScan part) =>
      part.chapters.isNotEmpty
          ? part.chapters
          : [ScannedChapter(0, part.label)];
}

/// Reads one audio file's tags, duration and (for MP4) chapters. Never reads
/// the audio data itself. Throws for a file that is neither MP4 nor MP3.
Future<AudioPartScan> scanAudioPart(String path) async {
  final format = extensionOf(path);
  final raf = await File(path).open();
  final head = await raf.read(16);
  await raf.close();
  final container = sniffAudio(head);
  if (container == AudioContainer.mp4) {
    final info = await readMp4(path);
    return AudioPartScan(
      path: path,
      format: format == 'mp3' ? 'm4a' : format,
      durationMs: info.durationMs,
      title: info.title,
      album: info.album,
      artist: info.artist,
      albumArtist: info.albumArtist,
      narrator: info.narrator,
      chapters: [for (final c in info.chapters) ScannedChapter(c.startMs, c.title)],
    );
  }
  if (container == AudioContainer.mp3) {
    final tag = readAllMetadata(File(path), getImage: false);
    if (tag is! Mp3Metadata) {
      throw FormatException('not an mp3: $path');
    }
    return AudioPartScan(
      path: path,
      format: 'mp3',
      durationMs: await mp3DurationMs(path) ?? tag.duration?.inMilliseconds,
      title: _clean(tag.songName),
      album: _clean(tag.album),
      artist: _clean(tag.leadPerformer),
      albumArtist: _clean(tag.bandOrOrchestra),
      narrator: _clean(tag.composer),
      disc: tag.discNumber,
      trackNo: tag.trackNumber,
    );
  }
  throw FormatException('not an audio file: $path');
}

String? _clean(String? s) {
  final t = s?.replaceAll('\u0000', '').trim();
  return t == null || t.isEmpty ? null : t;
}

/// Puts [parts] in playing order (docs/AUDIOBOOKS.md §1).
///
/// Disc then track number when every part has a track and no two parts share
/// a (disc, track) pair — rips that number every file "1" are common, and a
/// partial numbering is worse than none. Otherwise a natural sort of the paths,
/// so "2" comes before "10" and `CD1/`, `CD2/` are taken in order.
List<AudioPartScan> orderParts(List<AudioPartScan> parts) {
  final keys = <(int, int)>{};
  var usable = parts.length > 1;
  for (final part in parts) {
    final t = part.trackNo;
    if (t == null || !keys.add((part.disc ?? 1, t))) {
      usable = false;
      break;
    }
  }
  final sorted = [...parts];
  if (usable) {
    sorted.sort((a, b) {
      final c = (a.disc ?? 1).compareTo(b.disc ?? 1);
      return c != 0 ? c : a.trackNo!.compareTo(b.trackNo!);
    });
  } else {
    sorted.sort((a, b) => compareNatural(a.path, b.path));
  }
  return sorted;
}

/// Scans the files that make one audiobook: every part's tags and duration,
/// the order, the book's title, author and narrator, and a cover.
///
/// Pure Dart and file I/O only, so it can run in a background isolate.
Future<AudiobookScan> scanAudiobook(List<String> paths) async {
  final parts = orderParts([for (final path in paths) await scanAudioPart(path)]);
  if (parts.isEmpty) throw ArgumentError('no audio files');
  final first = parts.first;

  String? pick(String? Function(AudioPartScan) f) {
    for (final part in parts) {
      final v = f(part);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  // A single m4b's own title is the book's; across parts the album is.
  final String? title;
  if (parts.length == 1) {
    title = first.album ?? first.title;
  } else {
    title = pick((x) => x.album) ?? _folderTitle(first.path);
  }
  return AudiobookScan(
    parts: parts,
    title: title ?? p.basenameWithoutExtension(first.path),
    author: pick((x) => x.albumArtist) ?? pick((x) => x.artist),
    narrator: pick((x) => x.narrator),
    cover: await findCover(first),
  );
}

/// The folder a multi-part book is in, skipping a `CD1`-style disc folder.
String _folderTitle(String partPath) {
  var dir = p.dirname(partPath);
  if (isDiscFolderName(p.basename(dir))) dir = p.dirname(dir);
  return p.basename(dir);
}

/// "CD1", "Disc 2", "disk_03", "Part 4": a folder that is one disc of a book.
bool isDiscFolderName(String name) =>
    RegExp(r'^(cd|disc|disk|part)[\s_-]*\d+$', caseSensitive: false)
        .hasMatch(name.trim());

/// The cover, in order of preference (docs/AUDIOBOOKS.md §1): the m4b's
/// `covr`; the first part's `APIC`, front cover first; `cover`/`folder`/`front`
/// images beside it; the only image in its folder.
Future<Uint8List?> findCover(AudioPartScan first) async {
  try {
    if (first.format != 'mp3') {
      final cover = (await readMp4(first.path)).cover;
      if (cover != null && cover.isNotEmpty) return cover;
    } else {
      final tag = readAllMetadata(File(first.path), getImage: true);
      if (tag is Mp3Metadata && tag.pictures.isNotEmpty) {
        final front = tag.pictures
            .where((x) => x.pictureType == PictureType.coverFront)
            .toList();
        final picture = front.isNotEmpty ? front.first : tag.pictures.first;
        if (picture.bytes.isNotEmpty) return picture.bytes;
      }
    }
  } catch (_) {
    // A broken tag is not a broken book: fall through to the folder.
  }

  final dirs = [p.dirname(first.path)];
  if (isDiscFolderName(p.basename(dirs.first))) dirs.add(p.dirname(dirs.first));
  for (final dir in dirs) {
    final images = <File>[];
    try {
      await for (final entry in Directory(dir).list(followLinks: false)) {
        if (entry is File &&
            const {'jpg', 'jpeg', 'png'}.contains(extensionOf(entry.path))) {
          images.add(entry);
        }
      }
    } catch (_) {
      continue;
    }
    for (final name in const ['cover', 'folder', 'front']) {
      for (final image in images) {
        if (p.basenameWithoutExtension(image.path).toLowerCase() == name) {
          return image.readAsBytes();
        }
      }
    }
    if (images.length == 1) return images.single.readAsBytes();
  }
  return null;
}

/// Groups audio files found under a folder into books: each directory of
/// audio files is one book, except that disc folders (`CD1/`, `CD2/`) join
/// their parent's book. Groups come back in natural path order, each with its
/// files in no particular order ([scanAudiobook] orders them).
Map<String, List<String>> groupAudioByFolder(Iterable<String> paths) {
  final groups = <String, List<String>>{};
  for (final path in paths) {
    var dir = p.dirname(path);
    if (isDiscFolderName(p.basename(dir))) dir = p.dirname(dir);
    groups.putIfAbsent(dir, () => []).add(path);
  }
  final keys = groups.keys.toList()..sort(compareNatural);
  return {for (final k in keys) k: groups[k]!};
}
