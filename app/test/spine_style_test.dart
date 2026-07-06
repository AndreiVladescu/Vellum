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
}
