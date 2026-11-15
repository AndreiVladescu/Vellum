import 'dart:io';
import 'dart:typed_data';

/// The length of an MP3, from its first frame's Xing/Info or VBRI header, or
/// from the bitrate when there is neither (docs/AUDIOBOOKS.md §1).
///
/// Ours rather than `audio_metadata_reader`'s, which the spike found
/// miscounting MPEG-2 files (22.05 kHz mono, a common audiobook encoding).
/// Reads the ID3v2 header and a few KB after it; never the whole file.
/// Returns null when no MPEG audio frame is found.
Future<int?> mp3DurationMs(String path) async {
  final raf = await File(path).open();
  try {
    final length = await raf.length();
    var start = 0;
    final id3 = await raf.read(10);
    if (id3.length == 10 && id3[0] == 0x49 && id3[1] == 0x44 && id3[2] == 0x33) {
      // Syncsafe size: seven bits per byte. A footer adds ten more bytes.
      final size = (id3[6] << 21) | (id3[7] << 14) | (id3[8] << 7) | id3[9];
      start = 10 + size + ((id3[5] & 0x10) != 0 ? 10 : 0);
    }
    await raf.setPosition(start);
    final buf = await raf.read(16 * 1024);
    var hasTrailingTag = false;
    if (length >= 128) {
      await raf.setPosition(length - 128);
      final tail = await raf.read(3);
      hasTrailingTag = tail.length == 3 && tail[0] == 0x54 && tail[1] == 0x41 && tail[2] == 0x47; // TAG
    }
    for (var i = 0; i + 4 <= buf.length; i++) {
      final frame = _FrameHeader.parse(buf, i);
      if (frame == null) continue;
      // A real frame is followed by another: guards against a stray 0xFF.
      final next = i + frame.length;
      if (next + 4 <= buf.length && _FrameHeader.parse(buf, next) == null) continue;
      final frames = _xingFrames(buf, i, frame) ?? _vbriFrames(buf, i);
      if (frames != null && frames > 0) {
        return (frames * frame.samplesPerFrame * 1000 / frame.sampleRate).round();
      }
      final audioBytes = length - start - i - (hasTrailingTag ? 128 : 0);
      return (audioBytes * 8 / frame.bitrate).round(); // bits / (bits/ms)
    }
    return null;
  } finally {
    await raf.close();
  }
}

int? _xingFrames(Uint8List b, int at, _FrameHeader f) {
  final o = at + 4 + f.sideInfoSize;
  if (o + 12 > b.length) return null;
  final tag = String.fromCharCodes(b.sublist(o, o + 4));
  if (tag != 'Xing' && tag != 'Info') return null;
  final flags = ByteData.sublistView(b).getUint32(o + 4);
  if (flags & 1 == 0) return null;
  return ByteData.sublistView(b).getUint32(o + 8);
}

int? _vbriFrames(Uint8List b, int at) {
  final o = at + 4 + 32;
  if (o + 18 > b.length) return null;
  if (String.fromCharCodes(b.sublist(o, o + 4)) != 'VBRI') return null;
  return ByteData.sublistView(b).getUint32(o + 14);
}

class _FrameHeader {
  _FrameHeader(this.version, this.layer, this.bitrate, this.sampleRate,
      this.padding, this.mono);

  /// 1, 2 or 25 (MPEG 2.5).
  final int version;
  final int layer;

  /// In bits per millisecond (kb/s).
  final int bitrate;
  final int sampleRate;
  final bool padding;
  final bool mono;

  int get samplesPerFrame => switch (layer) {
        1 => 384,
        2 => 1152,
        _ => version == 1 ? 1152 : 576,
      };

  int get sideInfoSize => version == 1 ? (mono ? 17 : 32) : (mono ? 9 : 17);

  int get length {
    final pad = padding ? 1 : 0;
    if (layer == 1) return (12 * bitrate * 1000 ~/ sampleRate + pad) * 4;
    final coefficient = layer == 3 && version != 1 ? 72 : 144;
    return coefficient * bitrate * 1000 ~/ sampleRate + pad;
  }

  static const _v1 = {
    1: [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
    2: [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
    3: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
  };
  static const _v2 = {
    1: [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
    2: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    3: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  };
  static const _rates = {
    1: [44100, 48000, 32000],
    2: [22050, 24000, 16000],
    25: [11025, 12000, 8000],
  };

  static _FrameHeader? parse(Uint8List b, int i) {
    if (i + 4 > b.length || b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) return null;
    final version = switch ((b[i + 1] >> 3) & 3) { 0 => 25, 2 => 2, 3 => 1, _ => 0 };
    final layer = switch ((b[i + 1] >> 1) & 3) { 1 => 3, 2 => 2, 3 => 1, _ => 0 };
    if (version == 0 || layer == 0) return null;
    final bitrateIndex = b[i + 2] >> 4;
    final rateIndex = (b[i + 2] >> 2) & 3;
    if (bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) return null;
    final bitrate = (version == 1 ? _v1 : _v2)[layer]![bitrateIndex];
    final rate = _rates[version]![rateIndex];
    return _FrameHeader(version, layer, bitrate, rate, (b[i + 2] >> 1) & 1 == 1,
        (b[i + 3] >> 6) == 3);
  }
}
