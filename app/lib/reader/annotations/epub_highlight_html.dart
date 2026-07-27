/// Painting stored highlights into an EPUB chapter's markup (plan 5 #22/#23).
///
/// **Why by quote and not by offset.** The stored locator's offsets index this
/// app's own extracted `plainText`, not the HTML — that is why the locator is
/// versioned and why `resolveOffsets` already treats the quote as authoritative
/// and the offsets as a hint. Mapping an offset back through tag boundaries
/// would be a second, subtler implementation of the extractor, wrong in a
/// different way each time the parser changes.
///
/// So this wraps the *quoted text* where it appears in the markup. The cost is
/// honest and bounded: a quote that straddles an inline tag (`the <em>very</em>
/// best`) isn't found as one string and simply isn't painted — which is exactly
/// what happened before this existed, so nothing regresses. The panel still
/// lists it, and it still resolves when you tap it.
library;

import '../../data/database.dart';
import 'annotation_locator.dart';
import 'highlight_palette.dart';

/// Wraps every highlight belonging to [chapter] in a `<mark>`.
///
/// Returns [html] unchanged when there is nothing to paint, so the common case
/// costs one list filter and no string building.
String withHighlights(
  String html,
  List<Annotation> annotations,
  int chapter,
) {
  final quotes = <String, int?>{};
  for (final a in annotations) {
    final locator = AnnotationLocator.decode(a.locator);
    if (locator is! EpubTextLocator || locator.chapter != chapter) continue;
    final quote = a.quotedText?.trim();
    if (quote == null || quote.length < 3) continue; // too short to place safely
    // Later annotations win a colour clash; the alternative is drawing both and
    // getting a muddy third colour that matches neither.
    quotes[quote] = a.color;
  }
  if (quotes.isEmpty) return html;

  // Longest first: a quote that contains another must be wrapped before its
  // substring, or the inner one splits the outer and neither matches.
  final ordered = quotes.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  var out = html;
  for (final quote in ordered) {
    out = _wrapOutsideTags(out, quote, HighlightColor.fromArgb(quotes[quote]));
  }
  return out;
}

/// Wraps occurrences of [needle] that lie wholly in text content.
///
/// Matches inside a tag are skipped — replacing text in `<img alt="the best">`
/// would corrupt the attribute and, with a `<mark>` in it, the document.
/// Matches already inside a `<mark>` are skipped too, so re-running this is
/// idempotent.
String _wrapOutsideTags(String html, String needle, HighlightColor colour) {
  final buffer = StringBuffer();
  var i = 0;
  var inTag = false;
  var markDepth = 0;

  while (i < html.length) {
    final ch = html[i];
    if (ch == '<') {
      // Track `<mark>` nesting so a second pass doesn't wrap a wrapped quote.
      final lower = html.substring(i, (i + 7).clamp(0, html.length)).toLowerCase();
      if (lower.startsWith('<mark')) markDepth++;
      if (lower.startsWith('</mark')) markDepth = markDepth > 0 ? markDepth - 1 : 0;
      inTag = true;
      buffer.write(ch);
      i++;
      continue;
    }
    if (ch == '>') {
      inTag = false;
      buffer.write(ch);
      i++;
      continue;
    }
    if (!inTag && markDepth == 0 && html.startsWith(needle, i)) {
      buffer
        ..write('<mark style="background-color:')
        ..write(_cssRgba(colour))
        ..write('">')
        ..write(needle)
        ..write('</mark>');
      i += needle.length;
      continue;
    }
    buffer.write(ch);
    i++;
  }
  return buffer.toString();
}

/// `rgba(...)` rather than a hex colour: the ink is translucent so the glyphs
/// read through it, and `#RRGGBBAA` isn't understood by every renderer.
String _cssRgba(HighlightColor colour) {
  final c = colour.color;
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 'rgba($r,$g,$b,0.42)';
}
