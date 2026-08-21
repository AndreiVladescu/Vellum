// What the reader's counter says, and what it says when it cannot say it.
//
// "128 / 340" announces a long book's length on every page turn, which is the
// thing being escaped. The rule that matters most here is the fallback: *time
// left* with no measured pace shows a percentage rather than a made-up time,
// because a confident "about 20 min left" that is wrong every time is worse
// than a coarser answer.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/page_metric.dart';

void main() {
  String label(PageMetric m, {int page = 128, int count = 340, double? pace}) =>
      pageMetricLabel(m, page: page, count: count, pagesPerMinute: pace);

  group('each metric says its own thing', () {
    test('page and total', () {
      expect(label(PageMetric.pagesOf), '128 / 340');
    });

    test('percent', () {
      expect(label(PageMetric.percent), '38%');
    });

    test('pages read, without the total looming', () {
      expect(label(PageMetric.pagesRead), 'page 128');
    });

    test('pages left counts down', () {
      expect(label(PageMetric.pagesLeft), '212 left');
    });

    test('the last page says so rather than "0 left"', () {
      expect(label(PageMetric.pagesLeft, page: 340), 'last page');
    });
  });

  group('time left', () {
    test('is measured from the reader own pace', () {
      // 212 pages at 4 a minute.
      expect(label(PageMetric.timeLeft, pace: 4), 'about 53 min left');
    });

    test('reads in hours once it is long', () {
      expect(label(PageMetric.timeLeft, pace: 0.5), 'about 7 h 4 min left');
    });

    test('drops the minutes when there are none', () {
      expect(label(PageMetric.timeLeft, page: 100, count: 340, pace: 2),
          'about 2 h left');
    });

    test('falls back to a percentage when no pace is known', () {
      expect(
        label(PageMetric.timeLeft),
        '38%',
        reason: 'an honest coarser answer beats a confident wrong time',
      );
    });

    test('a nonsense pace falls back too', () {
      expect(label(PageMetric.timeLeft, pace: 0), '38%');
      expect(label(PageMetric.timeLeft, pace: -3), '38%');
    });

    test('almost finished says so', () {
      expect(label(PageMetric.timeLeft, page: 340, count: 340, pace: 2),
          'nearly done');
    });
  });

  group('edges', () {
    test('a document with no page count still shows where you are', () {
      expect(label(PageMetric.pagesOf, count: 0), '128');
    });

    test('a page beyond the end is clamped rather than shown as over 100%', () {
      expect(label(PageMetric.percent, page: 400, count: 340), '100%');
      expect(label(PageMetric.pagesLeft, page: 400, count: 340), 'last page');
    });
  });

  group('cycling', () {
    test('long-pressing walks the whole list and comes back', () {
      var metric = PageMetric.pagesOf;
      final seen = <PageMetric>{metric};
      for (var i = 0; i < PageMetric.values.length - 1; i++) {
        metric = metric.next;
        expect(seen.add(metric), true, reason: 'each one appears once');
      }
      expect(metric.next, PageMetric.pagesOf, reason: 'and it wraps');
    });

    test('an unknown stored value falls back to the plain counter', () {
      expect(PageMetric.parse('nonsense'), PageMetric.pagesOf);
      expect(PageMetric.parse(null), PageMetric.pagesOf);
      expect(PageMetric.parse('percent'), PageMetric.percent);
    });
  });
}
