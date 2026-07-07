import 'dart:io';
import 'dart:typed_data';

/// What a dropped/picked file actually is, judged by its magic bytes (not just
/// its extension), so we only upload genuine book files and cover images.
enum BookFileKind {
  pdf,
  epub,
  image,
  unsupported;

  bool get isBook => this == pdf || this == epub;
}

/// Inspects the first bytes of [path] to classify it.
Future<BookFileKind> classifyBookFile(String path) async {
  Uint8List head;
  try {
    final raf = await File(path).open();
    head = await raf.read(16);
    await raf.close();
  } catch (_) {
    return BookFileKind.unsupported;
  }

  if (_matches(head, const [0x25, 0x50, 0x44, 0x46])) {
    return BookFileKind.pdf; // %PDF
  }
  if (_matches(head, const [0xFF, 0xD8, 0xFF])) {
    return BookFileKind.image; // JPEG
  }
  if (_matches(head, const [0x89, 0x50, 0x4E, 0x47])) {
    return BookFileKind.image; // PNG
  }
  if (_matches(head, const [0x47, 0x49, 0x46, 0x38])) {
    return BookFileKind.image; // GIF
  }
  // EPUB is a ZIP (PK\x03\x04); only accept when the name says .epub, so we
  // don't treat arbitrary zip files as books.
  if (_matches(head, const [0x50, 0x4B, 0x03, 0x04]) &&
      path.toLowerCase().endsWith('.epub')) {
    return BookFileKind.epub;
  }
  return BookFileKind.unsupported;
}

bool _matches(Uint8List head, List<int> signature) {
  if (head.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (head[i] != signature[i]) return false;
  }
  return true;
}
