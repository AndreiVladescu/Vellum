import 'dart:typed_data';
import 'dart:ui' as ui;

/// Preparing a picked photo to be an avatar.
///
/// **Why not just store the file the user chose.** A photo off a phone is
/// several thousand pixels wide and a few megabytes; it is displayed here at
/// forty. Keeping the original would put that in the backup archive, and decode
/// the whole thing into memory every time the drawer opens. Nothing is gained —
/// the circle cannot show it.
///
/// So it is scaled down once, on the way in, and the small version is what gets
/// stored. An image already small enough is left exactly as it was: re-encoding
/// it would cost quality for no benefit.
const avatarMaxEdge = 512;

/// The bytes to store for [source], scaled so its longest edge is at most
/// [maxEdge].
///
/// Returns [source] unchanged when it is already small enough, and throws
/// [AvatarImageException] when it isn't an image at all — which is worth saying
/// out loud, because a file picker filtered to images will still hand over a
/// `.png` that is actually a text file someone renamed.
Future<Uint8List> avatarBytes(
  Uint8List source, {
  int maxEdge = avatarMaxEdge,
}) async {
  final ui.Image decoded;
  try {
    decoded = await _decode(source);
  } catch (e) {
    throw AvatarImageException("That file isn't an image Vellum can read.");
  }
  final longest =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  final wide = decoded.width >= decoded.height;
  decoded.dispose();
  if (longest <= maxEdge) return source;

  // Only one of the two is given, so the aspect ratio is kept.
  final scaled = await _decode(
    source,
    targetWidth: wide ? maxEdge : null,
    targetHeight: wide ? null : maxEdge,
  );
  final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
  scaled.dispose();
  if (data == null) {
    throw const AvatarImageException("That image couldn't be resized.");
  }
  return data.buffer.asUint8List();
}

Future<ui.Image> _decode(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

class AvatarImageException implements Exception {
  const AvatarImageException(this.message);

  final String message;

  @override
  String toString() => message;
}
