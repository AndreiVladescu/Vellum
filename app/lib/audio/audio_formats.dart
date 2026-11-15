import 'dart:io';

import 'package:path/path.dart' as p;

/// The audio formats an audiobook can be made of (docs/AUDIOBOOKS.md §1).
/// `.opus`/`.ogg` are deliberately absent: macOS's AVPlayer does not play Ogg.
const audioFormats = {'m4b', 'm4a', 'mp3'};

/// Whether a `book_files.format` is an audio part rather than text.
///
/// Every consumer of `bookFiles` that assumes text (the read button, the
/// reading unit, the text index, send-to-device) asks this first.
bool isAudioFormat(String format) => audioFormats.contains(format.toLowerCase());

/// The lowercased extension of [path], without the dot.
String extensionOf(String path) =>
    p.extension(path).replaceFirst('.', '').toLowerCase();

/// What an audio file's first bytes say it is.
enum AudioContainer { mp4, mp3 }

/// Classifies [head] by magic bytes: `ftyp` at offset 4 is MP4; `ID3` or an
/// MPEG audio frame sync (eleven set bits) is MP3.
AudioContainer? sniffAudio(List<int> head) {
  if (head.length >= 8 &&
      head[4] == 0x66 &&
      head[5] == 0x74 &&
      head[6] == 0x79 &&
      head[7] == 0x70) {
    return AudioContainer.mp4;
  }
  if (head.length >= 3 && head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
    return AudioContainer.mp3; // ID3
  }
  if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
    return AudioContainer.mp3; // frame sync, no tag
  }
  return null;
}

/// Whether [path] is an audio file we can import: the extension is one of
/// [audioFormats] *and* the bytes agree with it.
Future<bool> isImportableAudio(String path) async {
  final ext = extensionOf(path);
  if (!audioFormats.contains(ext)) return false;
  try {
    final raf = await File(path).open();
    final head = await raf.read(16);
    await raf.close();
    final kind = sniffAudio(head);
    return ext == 'mp3' ? kind == AudioContainer.mp3 : kind == AudioContainer.mp4;
  } catch (_) {
    return false;
  }
}

/// "Natural" comparison: digit runs compare as numbers, so "2" sorts before
/// "10", and letters compare case-insensitively.
int compareNatural(String a, String b) {
  final chunk = RegExp(r'\d+|\D+');
  final xs = chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final ys = chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final x = xs[i], y = ys[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  final c = xs.length.compareTo(ys.length);
  return c != 0 ? c : a.compareTo(b);
}
