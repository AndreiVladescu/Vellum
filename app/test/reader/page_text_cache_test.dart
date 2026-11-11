// When a PDF page's text is asked for, remembered, and given up on.
//
// The bug these guard: a page that pdfrx had not finished loading answered
// with an *empty* text, the painter kept that for the session, and a highlight
// on that page was never drawn again — which is what "the mark is gone after I
// reopened the book" was. The cache itself knows nothing about loading state;
// what it must do is never keep a result the loader says it cannot give, never
// ask twice at once, and never retry a failing page on every paint.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:vellum/reader/annotations/pdf_highlight_painter.dart';

PdfPageText _text(int page, String full) => PdfPageText(
      pageNumber: page,
      fullText: full,
      charRects: const [],
      fragments: const [],
    );

void main() {
  late int loaded;
  late PageTextCache cache;

  setUp(() {
    loaded = 0;
    cache = PageTextCache(onLoaded: () => loaded++);
  });

  test('the first ask starts a load; the answer is kept and announced',
      () async {
    final done = Completer<PdfPageText?>();
    expect(cache.textFor(3, () => done.future), isNull);
    done.complete(_text(3, 'hello'));
    await pumpEventQueue();

    expect(loaded, 1, reason: 'a repaint is requested when the text lands');
    expect(cache.textFor(3, () => fail('must not load twice'))?.fullText,
        'hello');
  });

  test('asking again while the load is running does not start another', () {
    var starts = 0;
    final pending = Completer<PdfPageText?>();
    Future<PdfPageText?> load() {
      starts++;
      return pending.future;
    }

    cache.textFor(1, load);
    cache.textFor(1, load);
    cache.textFor(1, load);
    expect(starts, 1, reason: 'a paint per frame must not pile up loads');
  });

  test('a load that cannot be had is not cached and not retried per paint',
      () async {
    var starts = 0;
    Future<PdfPageText?> unavailable() async {
      starts++;
      return null; // the document closed while we waited
    }

    cache.textFor(2, unavailable);
    await pumpEventQueue();
    for (var frame = 0; frame < 5; frame++) {
      expect(cache.textFor(2, unavailable), isNull);
    }
    expect(starts, 1);
    expect(loaded, 0, reason: 'nothing arrived, so nothing to repaint for');
  });

  test('a load that throws is treated the same, not rethrown', () async {
    var starts = 0;
    Future<PdfPageText?> broken() async {
      starts++;
      throw StateError('a font table PDFium cannot read');
    }

    cache.textFor(2, broken);
    await pumpEventQueue();
    cache.textFor(2, broken);
    await pumpEventQueue();
    expect(starts, 1);
  });

  test('retryFailed gives a failed page another chance', () async {
    var attempt = 0;
    Future<PdfPageText?> flaky() async => ++attempt == 1 ? null : _text(2, 'ok');

    cache.textFor(2, flaky);
    await pumpEventQueue();
    expect(cache.textFor(2, flaky), isNull);

    cache.retryFailed(); // what a change to the marks does
    cache.textFor(2, flaky);
    await pumpEventQueue();
    expect(cache.textFor(2, flaky)?.fullText, 'ok');
    expect(loaded, 1);
  });

  test('retryFailed leaves good text alone', () async {
    cache.textFor(1, () async => _text(1, 'kept'));
    await pumpEventQueue();
    cache.retryFailed();
    expect(cache.textFor(1, () => fail('must not reload'))?.fullText, 'kept');
  });

  test('reset forgets a document, and a load still in flight cannot land in '
      'the next one', () async {
    final late = Completer<PdfPageText?>();
    cache.textFor(4, () => late.future);
    cache.reset();

    late.complete(_text(4, 'from the old document'));
    await pumpEventQueue();
    expect(loaded, 0);
    expect(cache.textFor(4, () async => _text(4, 'new'))?.fullText, isNull,
        reason: 'the stale answer was discarded, so this is a fresh ask');
    await pumpEventQueue();
    expect(cache.textFor(4, () => fail('cached'))?.fullText, 'new');
  });

  test('after dispose nothing is loaded and nothing is announced', () async {
    final done = Completer<PdfPageText?>();
    cache.textFor(1, () => done.future);
    cache.dispose();
    done.complete(_text(1, 'too late'));
    await pumpEventQueue();
    expect(loaded, 0);
    expect(cache.textFor(2, () => fail('disposed')), isNull);
  });
}
