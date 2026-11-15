// The MP4 reader (docs/AUDIOBOOKS.md §1) against files built byte by byte
// here — so each chapter form can be tested on its own — and against one real
// ffmpeg-made m4b checked in under test/fixtures/audio/.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/audio/mp4_reader.dart';

Uint8List u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
Uint8List u64(int v) => (ByteData(8)..setUint64(0, v)).buffer.asUint8List();
Uint8List u16(int v) => (ByteData(2)..setUint16(0, v)).buffer.asUint8List();

Uint8List box(String type, List<List<int>> children) {
  final body = [for (final c in children) ...c];
  return Uint8List.fromList([...u32(8 + body.length), ...latin1.encode(type), ...body]);
}

List<int> fullHeader([int version = 0]) => [version, 0, 0, 0];

Uint8List mvhd({required int timescale, required int duration, int version = 0}) =>
    box('mvhd', [
      fullHeader(version),
      if (version == 1) ...[u64(0), u64(0), u32(timescale), u64(duration)]
      else ...[u32(0), u32(0), u32(timescale), u32(duration)],
      List.filled(80, 0),
    ]);

Uint8List tkhd(int id) => box('tkhd', [fullHeader(), u32(0), u32(0), u32(id), List.filled(64, 0)]);
Uint8List mdhd(int timescale) => box('mdhd', [fullHeader(), u32(0), u32(0), u32(timescale), u32(0), u32(0)]);
Uint8List hdlr(String handler) =>
    box('hdlr', [fullHeader(), u32(0), latin1.encode(handler), List.filled(13, 0)]);

Uint8List dataItem(String type, List<int> value, {int kind = 1}) =>
    box(type, [box('data', [u32(kind), u32(0), value])]);

Uint8List chpl(List<(int, String)> chapters) => box('chpl', [
      fullHeader(1),
      u32(0),
      [chapters.length],
      for (final (ms, title) in chapters) ...[
        u64(ms * 10000),
        [utf8.encode(title).length],
        utf8.encode(title),
      ],
    ]);

/// Writes an MP4 with `moov` *after* `mdat`, as real audiobooks often are.
/// [chapterTrack] adds a QuickTime chapter track whose samples live in mdat.
Future<String> writeMp4(
  Directory dir, {
  int timescale = 1000,
  int duration = 125000,
  int mvhdVersion = 0,
  List<(int, String)>? nero,
  List<(int, String)>? chapterTrack,
  Map<String, String> tags = const {},
  List<int>? cover,
}) async {
  final ftyp = box('ftyp', [latin1.encode('M4B '), u32(0), latin1.encode('isomM4B ')]);
  // Chapter text samples: a 16-bit length, then UTF-8.
  final samples = [
    for (final (_, title) in chapterTrack ?? const <(int, String)>[])
      [...u16(utf8.encode(title).length), ...utf8.encode(title)],
  ];
  final audioBytes = List.filled(64, 0xAB);
  final mdatPayload = [...audioBytes, for (final s in samples) ...s];
  final mdat = box('mdat', [mdatPayload]);
  final mdatPayloadStart = ftyp.length + 8;
  final firstSample = mdatPayloadStart + audioBytes.length;

  final traks = <Uint8List>[
    box('trak', [
      tkhd(1),
      if (chapterTrack != null) box('tref', [box('chap', [u32(2)])]),
      box('mdia', [mdhd(44100), hdlr('soun')]),
    ]),
  ];
  if (chapterTrack != null) {
    final starts = [for (final (ms, _) in chapterTrack) ms];
    final deltas = [
      for (var i = 0; i < starts.length; i++)
        (i + 1 < starts.length ? starts[i + 1] : duration) - starts[i],
    ];
    final offsets = <int>[];
    var at = firstSample;
    for (final s in samples) {
      offsets.add(at);
      at += s.length;
    }
    traks.add(box('trak', [
      tkhd(2),
      box('mdia', [
        mdhd(1000),
        hdlr('text'),
        box('minf', [
          box('stbl', [
            box('stts', [fullHeader(), u32(deltas.length), for (final d in deltas) ...[u32(1), u32(d)]]),
            box('stsz', [fullHeader(), u32(0), u32(samples.length), for (final s in samples) u32(s.length)]),
            // One sample per chunk, so every chunk offset is a sample offset.
            box('stsc', [fullHeader(), u32(1), u32(1), u32(1), u32(1)]),
            box('stco', [fullHeader(), u32(offsets.length), for (final o in offsets) u32(o)]),
          ]),
        ]),
      ]),
    ]));
  }
  final ilst = box('ilst', [
    for (final e in tags.entries) dataItem(e.key, utf8.encode(e.value)),
    if (cover != null) dataItem('covr', cover, kind: 13),
  ]);
  final udta = box('udta', [
    box('meta', [fullHeader(), hdlr('mdir'), ilst]),
    if (nero != null) chpl(nero),
  ]);
  final moov = box('moov', [
    mvhd(timescale: timescale, duration: duration, version: mvhdVersion),
    ...traks,
    udta,
  ]);
  final path = p.join(dir.path, 'book${dir.listSync().length}.m4b');
  await File(path).writeAsBytes([...ftyp, ...mdat, ...moov]);
  return path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_mp4'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads duration, Nero chapters, tags and cover past mdat', () async {
    final path = await writeMp4(
      dir,
      nero: [(0, 'Prologue'), (61500, 'Chapter One'), (90000, 'Épilogue')],
      tags: {'©nam': 'Dune', '©ART': 'Frank Herbert', '©wrt': 'Scott Brick', '©alb': 'Dune (Unabridged)'},
      cover: [0xFF, 0xD8, 0xFF, 1, 2, 3],
    );
    final info = await readMp4(path);
    expect(info.durationMs, 125000);
    expect([for (final c in info.chapters) c.startMs], [0, 61500, 90000]);
    expect([for (final c in info.chapters) c.title], ['Prologue', 'Chapter One', 'Épilogue']);
    expect(info.title, 'Dune');
    expect(info.artist, 'Frank Herbert');
    expect(info.narrator, 'Scott Brick', reason: '©wrt is where tools put the narrator');
    expect(info.album, 'Dune (Unabridged)');
    expect(info.cover, [0xFF, 0xD8, 0xFF, 1, 2, 3]);
  });

  test('falls back to a QuickTime chapter track when there is no chpl', () async {
    final path = await writeMp4(
      dir,
      chapterTrack: [(0, 'One'), (30000, 'Two'), (100000, 'Three')],
    );
    final info = await readMp4(path);
    expect([for (final c in info.chapters) c.startMs], [0, 30000, 100000]);
    expect([for (final c in info.chapters) c.title], ['One', 'Two', 'Three']);
  });

  test('prefers chpl when a file has both', () async {
    final path = await writeMp4(
      dir,
      nero: [(0, 'From chpl')],
      chapterTrack: [(0, 'From track'), (5000, 'Second')],
    );
    final info = await readMp4(path);
    expect([for (final c in info.chapters) c.title], ['From chpl']);
  });

  test('reads a 64-bit mvhd (long books, fine timescales)', () async {
    // 40 hours at a 44.1 kHz timescale does not fit in 32 bits.
    const ms = 40 * 3600 * 1000;
    final path = await writeMp4(dir, timescale: 44100, duration: ms * 441 ~/ 10, mvhdVersion: 1);
    final info = await readMp4(path);
    expect(info.durationMs, ms);
    expect(info.chapters, isEmpty);
  });

  test('refuses a file that is not MP4', () async {
    final path = p.join(dir.path, 'x.m4b');
    File(path).writeAsBytesSync(utf8.encode('%PDF-1.7 not audio at all'));
    expect(readMp4(path), throwsFormatException);
    expect(looksLikeMp4(utf8.encode('%PDF-1.7 ')), isFalse);
  });

  test('a truncated file keeps what was read rather than throwing', () async {
    final path = await writeMp4(dir, nero: [(0, 'A')]);
    final bytes = File(path).readAsBytesSync();
    // Cut into the middle of moov: the box no longer fits its parent.
    File(path).writeAsBytesSync(bytes.sublist(0, bytes.length - 20));
    final info = await readMp4(path);
    expect(info.durationMs, isNull);
  });

  test('the ffmpeg fixture: both chapter forms, moov at the end, a cover', () async {
    final info = await readMp4('test/fixtures/audio/tiny.m4b');
    expect(info.durationMs, closeTo(6000, 150));
    expect([for (final c in info.chapters) c.title], ['Opening', 'Middle', 'End']);
    expect([for (final c in info.chapters) c.startMs], [0, 2000, 4500]);
    expect(info.title, 'Tiny Book');
    expect(info.artist, 'Ann Author');
    expect(info.narrator, 'Ned Narrator');
    expect(info.cover, isNotNull);
    expect(info.cover!.sublist(0, 2), [0xFF, 0xD8], reason: 'a JPEG');
  });
}
