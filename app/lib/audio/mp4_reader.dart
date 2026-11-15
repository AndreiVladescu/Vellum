import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One chapter mark inside an MP4 file.
class Mp4Chapter {
  const Mp4Chapter(this.startMs, this.title);

  /// From the start of *this file*.
  final int startMs;
  final String? title;

  @override
  String toString() => 'Mp4Chapter($startMs, $title)';
}

/// What [readMp4] found. Every field is optional: a file can lack any of them.
class Mp4Info {
  const Mp4Info({
    this.durationMs,
    this.chapters = const [],
    this.title,
    this.album,
    this.artist,
    this.albumArtist,
    this.narrator,
    this.cover,
  });

  final int? durationMs;
  final List<Mp4Chapter> chapters;

  /// `©nam`, `©alb`, `©ART`, `aART` and `©wrt` from `moov/udta/meta/ilst`.
  /// `©wrt` (the composer) is where audiobook tools put the narrator.
  final String? title;
  final String? album;
  final String? artist;
  final String? albumArtist;
  final String? narrator;

  /// The `covr` picture's bytes (JPEG or PNG), if there is one.
  final Uint8List? cover;
}

/// Whether [head] (the first bytes of a file) look like an MP4 container:
/// `ftyp` at offset 4.
bool looksLikeMp4(List<int> head) =>
    head.length >= 8 &&
    head[4] == 0x66 && // f
    head[5] == 0x74 && // t
    head[6] == 0x79 && // y
    head[7] == 0x70; // p

/// Reads duration, chapters, tags and cover from an `.m4b`/`.m4a`
/// (docs/AUDIOBOOKS.md §1).
///
/// A walk over the atom tree with a [RandomAccessFile]: only box headers and
/// the few small boxes we need are read. `mdat` — nearly all of a 900 MB
/// file — is skipped by seeking, and so are the audio track's sample tables
/// (a 40-hour book's `stsz` alone is tens of MB). `moov` is often at the end of
/// the file, which a seek costs nothing to reach.
///
/// Chapters come from Nero `chpl` when present, otherwise from a QuickTime
/// chapter track (a text track some other track's `tref/chap` points to). Tools
/// write either or both.
///
/// Throws [FormatException] for a file that is not MP4 at all.
Future<Mp4Info> readMp4(String path) async {
  final raf = await File(path).open();
  try {
    return await _Mp4Walker(raf, await raf.length()).run();
  } finally {
    await raf.close();
  }
}

/// The largest box payload we are willing to read into memory. Everything we
/// actually need — tags, a cover, a chapter track's tables — is far smaller;
/// this only guards against a corrupt size field.
const _maxPayload = 32 << 20;

class _Box {
  _Box(this.type, this.start, this.headerSize, this.size);

  final String type;
  final int start;
  final int headerSize;
  final int size;

  int get payloadStart => start + headerSize;
  int get end => start + size;
  int get payloadSize => size - headerSize;
}

class _Track {
  int? id;
  String? handler;
  int? timescale;
  final chapterRefs = <int>[];
  List<int>? sttsCounts;
  List<int>? sttsDeltas;
  List<int>? sampleSizes;
  List<int>? chunkOffsets;
  // stsc entries: (firstChunk, samplesPerChunk)
  List<(int, int)>? stsc;

  bool get isText => handler == 'text' || handler == 'sbtl';
}

class _Mp4Walker {
  _Mp4Walker(this.raf, this.length);

  final RandomAccessFile raf;
  final int length;

  int? _mvhdTimescale;
  int? _mvhdDuration;
  List<Mp4Chapter>? _chpl;
  final _tracks = <_Track>[];
  final _tags = <String, String>{};
  Uint8List? _cover;

  Future<Mp4Info> run() async {
    final head = await _read(0, 8);
    if (!looksLikeMp4(head)) {
      throw const FormatException('not an MP4 file (no ftyp)');
    }
    await for (final box in _children(0, length)) {
      if (box.type == 'moov') await _moov(box);
    }

    int? durationMs;
    if (_mvhdTimescale != null && _mvhdTimescale! > 0 && _mvhdDuration != null) {
      durationMs = (_mvhdDuration! * 1000 / _mvhdTimescale!).round();
    }
    var chapters = _chpl ?? const <Mp4Chapter>[];
    if (chapters.isEmpty) chapters = await _chapterTrack();
    return Mp4Info(
      durationMs: durationMs,
      chapters: chapters,
      title: _tags['©nam'],
      album: _tags['©alb'],
      artist: _tags['©ART'],
      albumArtist: _tags['aART'],
      narrator: _tags['©wrt'] ?? _tags['©nrt'],
      cover: _cover,
    );
  }

  Future<Uint8List> _read(int at, int count) async {
    await raf.setPosition(at);
    return raf.read(count);
  }

  Future<Uint8List> _payload(_Box box) {
    if (box.payloadSize < 0 || box.payloadSize > _maxPayload) {
      throw FormatException('box ${box.type} too large');
    }
    return _read(box.payloadStart, box.payloadSize);
  }

  /// The boxes directly inside [from]..[to].
  Stream<_Box> _children(int from, int to) async* {
    var pos = from;
    while (pos + 8 <= to) {
      final h = await _read(pos, 16);
      if (h.length < 8) return;
      final bd = ByteData.sublistView(h);
      var size = bd.getUint32(0);
      final type = latin1.decode(h.sublist(4, 8));
      var header = 8;
      if (size == 1) {
        if (h.length < 16) return;
        size = bd.getUint64(8);
        header = 16;
      } else if (size == 0) {
        size = to - pos; // extends to the end of its parent
      }
      if (size < header || pos + size > to) return; // corrupt: stop, keep what we have
      yield _Box(type, pos, header, size);
      pos += size;
    }
  }

  Future<void> _moov(_Box moov) async {
    await for (final box in _children(moov.payloadStart, moov.end)) {
      switch (box.type) {
        case 'mvhd':
          final p = await _read(box.payloadStart, 32);
          final bd = ByteData.sublistView(p);
          if (p[0] == 1) {
            _mvhdTimescale = bd.getUint32(20);
            _mvhdDuration = bd.getUint64(24);
          } else {
            _mvhdTimescale = bd.getUint32(12);
            _mvhdDuration = bd.getUint32(16);
          }
        case 'udta':
          await _udta(box);
        case 'trak':
          final t = _Track();
          await _trak(box, t);
          _tracks.add(t);
      }
    }
  }

  Future<void> _udta(_Box udta) async {
    await for (final box in _children(udta.payloadStart, udta.end)) {
      if (box.type == 'chpl') {
        _chpl = _parseChpl(await _payload(box));
      } else if (box.type == 'meta') {
        // ISO `meta` is a full box (4 bytes of version/flags before its
        // children); QuickTime's is not. Tell them apart by whether a child
        // header ('hdlr') sits right at the payload.
        final peek = await _read(box.payloadStart + 4, 4);
        final quickTime = latin1.decode(peek, allowInvalid: true) == 'hdlr';
        final start = box.payloadStart + (quickTime ? 0 : 4);
        await for (final child in _children(start, box.end)) {
          if (child.type == 'ilst') await _ilst(child);
        }
      }
    }
  }

  Future<void> _ilst(_Box ilst) async {
    const wanted = {'©nam', '©alb', '©ART', 'aART', '©wrt', '©nrt', 'covr'};
    await for (final item in _children(ilst.payloadStart, ilst.end)) {
      if (!wanted.contains(item.type)) continue;
      await for (final data in _children(item.payloadStart, item.end)) {
        if (data.type != 'data' || data.payloadSize < 8) continue;
        final bytes = await _payload(data);
        final wellKnownType = ByteData.sublistView(bytes).getUint32(0) & 0xFFFFFF;
        final value = Uint8List.sublistView(bytes, 8);
        if (item.type == 'covr') {
          _cover ??= Uint8List.fromList(value);
        } else if (wellKnownType == 1 || wellKnownType == 0) {
          final text = utf8.decode(value, allowMalformed: true).trim();
          if (text.isNotEmpty) _tags.putIfAbsent(item.type, () => text);
        }
        break; // the first data box is the value
      }
    }
  }

  /// Nero chapters: version/flags, (v1) four reserved bytes, a count, then
  /// for each a start in 100 ns units and a length-prefixed title.
  static List<Mp4Chapter> _parseChpl(Uint8List p) {
    if (p.length < 5) return const [];
    final bd = ByteData.sublistView(p);
    var pos = 4;
    if (p[0] != 0) pos += 4;
    if (pos >= p.length) return const [];
    final count = p[pos++];
    final out = <Mp4Chapter>[];
    for (var i = 0; i < count; i++) {
      if (pos + 9 > p.length) break;
      final start = bd.getUint64(pos);
      pos += 8;
      final len = p[pos++];
      if (pos + len > p.length) break;
      final title = utf8.decode(p.sublist(pos, pos + len), allowMalformed: true);
      pos += len;
      out.add(Mp4Chapter((start / 10000).round(), title.isEmpty ? null : title));
    }
    return out;
  }

  Future<void> _trak(_Box trak, _Track t) async {
    await for (final box in _children(trak.payloadStart, trak.end)) {
      switch (box.type) {
        case 'tkhd':
          final p = await _read(box.payloadStart, 24);
          final bd = ByteData.sublistView(p);
          t.id = p[0] == 1 ? bd.getUint32(20) : bd.getUint32(12);
        case 'tref':
          await for (final ref in _children(box.payloadStart, box.end)) {
            if (ref.type != 'chap') continue;
            final p = await _payload(ref);
            final bd = ByteData.sublistView(p);
            for (var i = 0; i + 4 <= p.length; i += 4) {
              t.chapterRefs.add(bd.getUint32(i));
            }
          }
        case 'mdia':
          await _mdia(box, t);
      }
    }
  }

  Future<void> _mdia(_Box mdia, _Track t) async {
    _Box? minf;
    await for (final box in _children(mdia.payloadStart, mdia.end)) {
      switch (box.type) {
        case 'mdhd':
          final p = await _read(box.payloadStart, 24);
          final bd = ByteData.sublistView(p);
          t.timescale = p[0] == 1 ? bd.getUint32(20) : bd.getUint32(12);
        case 'hdlr':
          final p = await _read(box.payloadStart, 12);
          if (p.length >= 12) t.handler = latin1.decode(p.sublist(8, 12));
        case 'minf':
          minf = box;
      }
    }
    // Only a text track's sample tables are read: the audio track's are huge
    // and say nothing we need.
    if (minf == null || !t.isText) return;
    await for (final box in _children(minf.payloadStart, minf.end)) {
      if (box.type != 'stbl') continue;
      await for (final table in _children(box.payloadStart, box.end)) {
        switch (table.type) {
          case 'stts':
            final p = await _payload(table);
            final bd = ByteData.sublistView(p);
            final n = bd.getUint32(4);
            t.sttsCounts = [];
            t.sttsDeltas = [];
            for (var i = 0; i < n && 8 + i * 8 + 8 <= p.length; i++) {
              t.sttsCounts!.add(bd.getUint32(8 + i * 8));
              t.sttsDeltas!.add(bd.getUint32(12 + i * 8));
            }
          case 'stsz':
            final p = await _payload(table);
            final bd = ByteData.sublistView(p);
            final fixed = bd.getUint32(4);
            final n = bd.getUint32(8);
            t.sampleSizes = [
              for (var i = 0; i < n && (fixed != 0 || 12 + i * 4 + 4 <= p.length); i++)
                fixed != 0 ? fixed : bd.getUint32(12 + i * 4),
            ];
          case 'stco':
          case 'co64':
            final p = await _payload(table);
            final bd = ByteData.sublistView(p);
            final n = bd.getUint32(4);
            final wide = table.type == 'co64';
            final step = wide ? 8 : 4;
            t.chunkOffsets = [
              for (var i = 0; i < n && 8 + i * step + step <= p.length; i++)
                wide ? bd.getUint64(8 + i * step) : bd.getUint32(8 + i * step),
            ];
          case 'stsc':
            final p = await _payload(table);
            final bd = ByteData.sublistView(p);
            final n = bd.getUint32(4);
            t.stsc = [
              for (var i = 0; i < n && 8 + i * 12 + 12 <= p.length; i++)
                (bd.getUint32(8 + i * 12), bd.getUint32(12 + i * 12)),
            ];
        }
      }
    }
  }

  /// Chapters from a QuickTime chapter track: each text sample is a title,
  /// and its time in the track is the chapter's start.
  Future<List<Mp4Chapter>> _chapterTrack() async {
    final refs = {for (final t in _tracks) ...t.chapterRefs};
    _Track? track;
    for (final t in _tracks) {
      if (t.isText && (refs.isEmpty || refs.contains(t.id))) {
        track = t;
        break;
      }
    }
    final t = track;
    if (t == null ||
        t.timescale == null ||
        t.timescale == 0 ||
        t.sttsCounts == null ||
        t.sampleSizes == null ||
        t.chunkOffsets == null) {
      return const [];
    }

    // Sample offsets, from chunks and the sample-to-chunk table.
    final offsets = <int>[];
    final stsc = t.stsc ?? [(1, 1)];
    var sample = 0;
    for (var c = 0; c < t.chunkOffsets!.length; c++) {
      final chunk = c + 1;
      var perChunk = 1;
      for (final (first, n) in stsc) {
        if (first <= chunk) perChunk = n;
      }
      var at = t.chunkOffsets![c];
      for (var s = 0; s < perChunk && sample < t.sampleSizes!.length; s++) {
        offsets.add(at);
        at += t.sampleSizes![sample++];
      }
    }

    final out = <Mp4Chapter>[];
    var time = 0;
    var i = 0;
    for (var e = 0; e < t.sttsCounts!.length; e++) {
      for (var k = 0; k < t.sttsCounts![e]; k++) {
        if (i >= offsets.length) break;
        final size = t.sampleSizes![i];
        String? title;
        if (size >= 2 && size <= 4096) {
          final bytes = await _read(offsets[i], size);
          title = _textSample(bytes);
        }
        out.add(Mp4Chapter((time * 1000 / t.timescale!).round(), title));
        time += t.sttsDeltas![e];
        i++;
      }
    }
    return out;
  }

  /// A QuickTime text sample: a 16-bit length, then the text (UTF-8, or
  /// UTF-16 with a byte-order mark), then optional style boxes.
  static String? _textSample(Uint8List b) {
    if (b.length < 2) return null;
    final len = ByteData.sublistView(b).getUint16(0);
    if (len == 0 || 2 + len > b.length) return null;
    final text = b.sublist(2, 2 + len);
    String s;
    if (text.length >= 2 && text[0] == 0xFE && text[1] == 0xFF) {
      final units = <int>[
        for (var i = 2; i + 1 < text.length; i += 2) (text[i] << 8) | text[i + 1],
      ];
      s = String.fromCharCodes(units);
    } else {
      s = utf8.decode(text, allowMalformed: true);
    }
    s = s.trim();
    return s.isEmpty ? null : s;
  }
}
