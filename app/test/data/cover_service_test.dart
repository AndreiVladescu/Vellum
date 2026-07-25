import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/cover_service.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/shelf/spine_style.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_cover_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('backfillCoverColors fills missing spine colours and is idempotent',
      () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final covers = CoverService(db, dir);

    // A covered book: write a real solid-blue PNG where the service expects it.
    final coversDir = Directory(p.join(dir.path, 'covers'))
      ..createSync(recursive: true);
    File(p.join(coversDir.path, 'b1.png'))
        .writeAsBytesSync(await _solidPng(const Color(0xFF2E5A9C)));
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Covered',
          coverPath: const Value('covers/b1.png'),
        ));
    // A cover-less book must be skipped, not crash the sweep.
    await db
        .into(db.books)
        .insert(BooksCompanion.insert(id: 'b2', title: 'No cover'));

    await covers.backfillCoverColors();

    Future<Book> book(String id) async =>
        (await (db.select(db.books)..where((b) => b.id.equals(id))).get())
            .single;

    final b1 = await book('b1');
    final color = SpineStyle.fromJson(b1.spineStyle, title: b1.title).coverColor;
    expect(color, isNotNull, reason: 'the covered book got a dominant colour');

    // A second sweep is a no-op: books that already have a colour are skipped
    // before any decode, so the stored colour is unchanged.
    await covers.backfillCoverColors();
    final again = await book('b1');
    expect(SpineStyle.fromJson(again.spineStyle, title: again.title).coverColor,
        color);
  });
}

/// A solid-colour PNG via the engine codec, so backfill has a real image to
/// decode (mirrors cover_color_test's helper).
Future<Uint8List> _solidPng(Color color, {int size = 16}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
