// What it costs to decode spine styles, which the shelf does per book per
// build (`ShelfView._widthOf`, inside a `LayoutBuilder`) and the physical
// library does per book per frame (`physical_metrics.dart`).
//
// A regression guard, not a frame-time target — see docs/PERFORMANCE.md on why
// CI runners cannot assert tight numbers.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/shelf/spine_style.dart';

void main() {
  test('decoding spine styles for a shelf-sized library', () {
    const n = 2000;
    // What the database actually holds: `SpineStyle.generate(...).toJson()`.
    final stored = <String>[
      for (var i = 0; i < n; i++)
        SpineStyle.generate(title: 'Book number $i').toJson(),
    ];
    final titles = [for (var i = 0; i < n; i++) 'Book number $i'];

    // Cold: nothing memoised yet, so this is what every call used to cost.
    SpineStyle.clearCache();
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      SpineStyle.fromJson(stored[i], title: titles[i]);
    }
    sw.stop();
    // ignore: avoid_print
    print('  fromJson x $n, cold (first shelf build): '
        '${(sw.elapsedMicroseconds / 1000.0).toStringAsFixed(1)} ms');

    // Warm: the shelf decodes every book to pack rows, then decodes each
    // visible one again to draw it, on every rebuild. 20 rebuilds is a burst of
    // typing in the search box — the case the cache exists for.
    final sw2 = Stopwatch()..start();
    for (var r = 0; r < 20; r++) {
      for (var i = 0; i < n; i++) {
        SpineStyle.fromJson(stored[i], title: titles[i]);
      }
    }
    sw2.stop();
    final warmPer = sw2.elapsedMicroseconds / 20.0 / 1000.0;
    // ignore: avoid_print
    print('  fromJson x $n, 20 rebuilds warm: '
        '${(sw2.elapsedMicroseconds / 1000.0).toStringAsFixed(1)} ms '
        '(${warmPer.toStringAsFixed(2)} ms per rebuild)');

    // The point of the cache: a warm rebuild must cost far less than a cold
    // decode of the same books. Loose enough for a loaded CI runner.
    expect(sw2.elapsedMicroseconds / 20, lessThan(sw.elapsedMicroseconds / 2),
        reason: 'a memoised rebuild should be much cheaper than decoding');

    // Generous: this is a guard against someone making the decode wildly more
    // expensive, not an assertion about any particular machine.
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
