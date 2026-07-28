// Taking a book's own colours out of its markup for night mode.
//
// The bug this exists for: `customStylesBuilder` loses to an element's `style`
// attribute, which is exactly where books put `color: #222`. Overriding was not
// enough — the declaration has to be gone, and it has to go without taking the
// author's layout with it.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/night_mode.dart';

void main() {
  test('a colour the book asked for is removed', () {
    const html = '<h1 style="color:#111111">Chapter One</h1>';
    expect(withoutBookColours(html), isNot(contains('#111111')));
  });

  test('a light background box does not survive onto a night-mode page', () {
    // White type on the reader's white callout, in the middle of black paper.
    const html = '<div style="background-color:#fff;padding:8px">Note</div>';
    final out = withoutBookColours(html);
    expect(out, isNot(contains('#fff')));
    expect(out, contains('padding:8px'), reason: 'the layout is not the problem');
  });

  test('everything else in the style attribute is left alone', () {
    const html =
        '<p style="margin-left:2em;color:red;text-align:justify">Body</p>';
    final out = withoutBookColours(html);
    expect(out, contains('margin-left:2em'));
    expect(out, contains('text-align:justify'));
    expect(out, isNot(contains('red')));
  });

  test('border-color is not mistaken for a text colour', () {
    // A rule under a heading is structure, not a colour choice to override —
    // and a naive `color:` match eats it.
    const html = '<hr style="border-color:#888"/>';
    expect(withoutBookColours(html), contains('border-color:#888'));
  });

  test('an attribute emptied of everything loses the attribute too', () {
    const html = '<p style="color:#333">Body</p>';
    expect(withoutBookColours(html), '<p >Body</p>');
  });

  test('the presentational attributes from converted books go as well', () {
    const html = '<body bgcolor="#ffffff" text="#000000">'
        '<font color="navy">Old markup</font></body>';
    final out = withoutBookColours(html);
    expect(out, isNot(contains('#ffffff')));
    expect(out, isNot(contains('navy')));
    expect(out, contains('Old markup'));
  });

  test('prose that merely mentions a colour is not markup', () {
    const html = '<p>The wall was color: red, or so he claimed.</p>';
    expect(withoutBookColours(html), html);
  });

  test('single-quoted attributes are handled, and stay single-quoted', () {
    const html = "<p style='color:#333;margin:0'>Body</p>";
    expect(withoutBookColours(html), "<p style='margin:0'>Body</p>");
  });
}
