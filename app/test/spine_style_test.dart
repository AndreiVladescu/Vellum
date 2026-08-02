import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/shelf/spine_style.dart';

void main() {
  test('spine style survives a JSON roundtrip', () {
    final style = SpineStyle.generate(
        title: 'The Hobbit', author: 'J.R.R. Tolkien', pageCount: 310);
    final parsed = SpineStyle.fromJson(style.toJson(), title: 'The Hobbit');
    expect(parsed.color, style.color);
    expect(parsed.textColor, style.textColor);
    expect(parsed.width, style.width);
    expect(parsed.heightFactor, style.heightFactor);
    expect(parsed.variant, style.variant);
  });

  test('generation is deterministic and page count drives width', () {
    final a = SpineStyle.generate(title: 'Dune', pageCount: 600);
    final b = SpineStyle.generate(title: 'Dune', pageCount: 600);
    expect(a.toJson(), b.toJson());
    final thin = SpineStyle.generate(title: 'Dune', pageCount: 120);
    expect(a.width, greaterThan(thin.width));
  });

  test('bad stored JSON falls back to generated style', () {
    final fallback = SpineStyle.fromJson('{broken', title: 'Dune');
    expect(fallback.toJson(), SpineStyle.generate(title: 'Dune').toJson());
  });

  test('the fallback is per-title, not memoised under the bad JSON', () {
    // `fromJson` caches decoded styles keyed by the JSON string. The failure
    // path must stay out of that cache: it falls back to `generate(title:)`,
    // which depends on the title, so caching it would give every book with the
    // same corrupt style the first one's colours.
    final dune = SpineStyle.fromJson('{broken', title: 'Dune');
    final solaris = SpineStyle.fromJson('{broken', title: 'Solaris');
    expect(solaris.toJson(), SpineStyle.generate(title: 'Solaris').toJson());
    expect(solaris.toJson(), isNot(dune.toJson()));
  });

  test('a memoised style equals a freshly decoded one', () {
    final json = SpineStyle.generate(title: 'Piranesi', pageCount: 272).toJson();
    final first = SpineStyle.fromJson(json, title: 'Piranesi');
    final second = SpineStyle.fromJson(json, title: 'Piranesi');
    expect(identical(first, second), isTrue, reason: 'served from the cache');
    SpineStyle.clearCache();
    final afterClear = SpineStyle.fromJson(json, title: 'Piranesi');
    expect(afterClear.toJson(), first.toJson());
  });
}
