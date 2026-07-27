/// Painting stored highlights into an EPUB chapter's markup (plan 5 #22/#23).
///
/// **Why this is not a substring replace on the HTML.** The quote is taken from
/// [stripHtml]'s output — tags gone, entities decoded, whitespace collapsed —
/// and real EPUBs are pretty-printed, so a paragraph's source says
/// `the quick\n    brown fox` where the quote says `the quick brown fox`.
/// Searching the raw markup for the quote therefore fails for almost every
/// highlight longer than one word, which is why highlights were being stored and
/// listed but never appearing on the page.
///
/// So the markup is walked once into the *same* normalised text the quote came
/// from, keeping for every character the span of source it came from. A quote is
/// then found in that text and mapped back to source spans. Two things fall out
/// of that for free: a quote split across an inline tag (`the <em>very</em>
/// best`) is now painted as several adjacent `<mark>`s instead of being skipped,
/// and the stored offsets can pick *which* occurrence of a repeated phrase was
/// meant.
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
  final wanted = <({String quote, int at, int? color})>[];
  for (final a in annotations) {
    final locator = AnnotationLocator.decode(a.locator);
    if (locator is! EpubTextLocator || locator.chapter != chapter) continue;
    final quote = _collapse(a.quotedText ?? '');
    if (quote.length < 3) continue; // too short to place safely
    wanted.add((quote: quote, at: locator.start, color: a.color));
  }
  if (wanted.isEmpty) return html;

  // Longest first: where one quote contains another, the longer one should get
  // the span, and claiming it first means the shorter one's overlapping run is
  // simply dropped rather than splitting the longer one in two.
  wanted.sort((a, b) => b.quote.length.compareTo(a.quote.length));

  final map = mapHtmlText(html);
  if (map.text.isEmpty) return html;

  final runs = <_Run>[];
  for (final want in wanted) {
    final at = _locate(map.text, want.quote, want.at);
    if (at < 0) continue;
    for (final run in map.runsIn(at, at + want.quote.length)) {
      // Nothing is gained by colouring the gap between two paragraphs.
      if (html.substring(run.start, run.end).trim().isEmpty) continue;
      // First claim wins. Overlapping highlights would otherwise nest, and a
      // <mark> inside a <mark> paints the same words twice at double strength.
      if (runs.any((r) => r.start < run.end && run.start < r.end)) continue;
      runs.add(_Run(run.start, run.end, HighlightColor.fromArgb(want.color)));
    }
  }
  if (runs.isEmpty) return html;

  runs.sort((a, b) => a.start.compareTo(b.start));
  final buffer = StringBuffer();
  var cursor = 0;
  for (final run in runs) {
    buffer
      ..write(html.substring(cursor, run.start))
      ..write('<mark style="background-color:${_cssRgba(run.colour)}">')
      ..write(html.substring(run.start, run.end))
      ..write('</mark>');
    cursor = run.end;
  }
  buffer.write(html.substring(cursor));
  return buffer.toString();
}

class _Run {
  const _Run(this.start, this.end, this.colour);

  final int start;
  final int end;
  final HighlightColor colour;
}

/// Finds [quote] in [text], preferring the occurrence nearest [hint].
///
/// The hint is the stored offset, which indexes the same normalised text — but
/// only as a hint, exactly as `resolveOffsets` treats it: the extractor may have
/// changed since the highlight was made, while the words have not.
int _locate(String text, String quote, int hint) {
  var best = -1;
  var bestDistance = -1;
  var from = 0;
  while (true) {
    final at = text.indexOf(quote, from);
    if (at < 0) break;
    final distance = (at - hint).abs();
    if (best < 0 || distance < bestDistance) {
      best = at;
      bestDistance = distance;
    }
    from = at + 1;
  }
  return best;
}

/// Whitespace collapsed and trimmed, matching [stripHtml]'s normalisation, so a
/// quote and the mapped text are in the same shape.
String _collapse(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// `rgba(...)` rather than a hex colour: the ink is translucent so the glyphs
/// read through it, and `#RRGGBBAA` isn't understood by every renderer.
String _cssRgba(HighlightColor colour) {
  final c = colour.color;
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 'rgba($r,$g,$b,0.42)';
}

/// A chapter's visible text alongside where in the markup each character came
/// from — the bridge between an annotation's offsets and the HTML.
class HtmlTextMap {
  HtmlTextMap._(this.text, this._start, this._end, this._wrappable);

  /// The visible text, normalised exactly as `stripHtml` normalises it.
  final String text;

  /// Source span of each character of [text].
  final List<int> _start;
  final List<int> _end;

  /// Whether this character's source span may be wrapped in a tag. False for a
  /// space that stands in for `</p>\n<p>`: its span contains markup, so putting
  /// a `<mark>` around it would nest tags illegally. Runs break there instead.
  final List<bool> _wrappable;

  /// The source spans covering `text[from..to)`, split wherever the source is
  /// not contiguous — i.e. at every intervening tag.
  ///
  /// Several spans is the normal case, not a failure: `the <em>very</em> best`
  /// yields three, which render as one continuous stripe because they abut.
  Iterable<({int start, int end})> runsIn(int from, int to) sync* {
    final lo = from.clamp(0, text.length);
    final hi = to.clamp(lo, text.length);
    int? start;
    int? end;
    for (var i = lo; i < hi; i++) {
      if (!_wrappable[i]) {
        if (start != null) yield (start: start, end: end!);
        start = null;
        continue;
      }
      if (start != null && _start[i] == end) {
        end = _end[i];
        continue;
      }
      if (start != null) yield (start: start, end: end!);
      start = _start[i];
      end = _end[i];
    }
    if (start != null) yield (start: start, end: end!);
  }
}

/// The tags `stripHtml` turns into a space rather than deleting, so words either
/// side of a block don't run together. Kept character-identical to its patterns:
/// the two must agree or the stored offsets stop meaning anything.
final _blockSpace = RegExp(
  r'<br\s*/?>|</(p|div|h[1-6]|li|tr|blockquote)>',
  caseSensitive: false,
);

const _entities = <String, String>{
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
};

/// Walks [html] once, producing its visible text and the source span of every
/// character in it.
HtmlTextMap mapHtmlText(String html) {
  final text = StringBuffer();
  final start = <int>[];
  final end = <int>[];
  final wrappable = <bool>[];

  // A pending run of whitespace, emitted as a single space only once a real
  // character follows it — which is what collapsing and trimming amount to.
  var spaceFrom = -1;
  var spaceTo = -1;
  var spaceHasMarkup = false;
  var markDepth = 0;
  final lowerHtml = html.toLowerCase();
  // Where every block boundary is, resolved up front for the same reason
  // `stripHtml` resolves them first: they change what counts as a tag.
  final blocks = <int, int>{
    for (final m in _blockSpace.allMatches(html)) m.start: m.end,
  };
  final blockStarts = blocks.keys.toList()..sort();

  void emit(String ch, int from, int to, {bool canWrap = true}) {
    text.write(ch);
    start.add(from);
    end.add(to);
    // Never wrap inside an existing <mark>: re-running this must not nest.
    wrappable.add(canWrap && markDepth == 0);
  }

  void space(int from, int to, {bool markup = false}) {
    if (spaceFrom < 0) spaceFrom = from;
    spaceTo = to;
    spaceHasMarkup |= markup;
  }

  void flushSpace() {
    if (spaceFrom < 0) return;
    // Leading whitespace is dropped, which is the `trim()`.
    if (text.isNotEmpty) {
      emit(' ', spaceFrom, spaceTo, canWrap: !spaceHasMarkup);
    }
    spaceFrom = -1;
    spaceTo = -1;
    spaceHasMarkup = false;
  }

  var i = 0;
  while (i < html.length) {
    final ch = html[i];

    if (ch == '<') {
      final block = blocks[i];
      if (block != null) {
        space(i, block, markup: true);
        i = block;
        continue;
      }
      final close = html.indexOf('>', i);
      // A `<` is only a tag if it closes before the next block boundary does.
      // `stripHtml` replaces `</p>` with a space *before* it strips tags, so in
      // `five < seven</p>` the stray `<` never gets a `>` to pair with and stays
      // as text. Getting this wrong loses a whole paragraph from the map.
      final nextBlock = blockStarts.firstWhere(
        (start) => start > i,
        orElse: () => -1,
      );
      if (close < 0 || (nextBlock >= 0 && nextBlock < close)) {
        flushSpace();
        emit(ch, i, i + 1);
        i++;
        continue;
      }
      final lower = lowerHtml.substring(i, close + 1);
      if (lower.startsWith('<script') || lower.startsWith('<style')) {
        final name = lower.startsWith('<script') ? 'script' : 'style';
        final bodyEnd = lowerHtml.indexOf('</$name', close);
        final skipTo = bodyEnd < 0 ? -1 : html.indexOf('>', bodyEnd);
        // An unclosed <script> is not a script body; `stripHtml`'s regex needs
        // the closing tag too, and without one treats the opener as an ordinary
        // tag and keeps what follows as text.
        if (skipTo >= 0) {
          space(i, skipTo + 1, markup: true);
          i = skipTo + 1;
          continue;
        }
      }
      if (lower.startsWith('<mark')) markDepth++;
      if (lower.startsWith('</mark')) {
        markDepth = markDepth > 0 ? markDepth - 1 : 0;
      }
      // An inline tag contributes nothing at all — not text, and not a space
      // either (`the<em>very` really is "thevery"). It still breaks the source
      // span, because the characters either side are no longer adjacent, and
      // that is what `runsIn` turns into two adjacent marks.
      i = close + 1;
      continue;
    }

    if (ch == '&') {
      final entity = _entities.keys.firstWhere(
        (e) => html.startsWith(e, i),
        orElse: () => '',
      );
      if (entity.isNotEmpty) {
        final decoded = _entities[entity]!;
        if (decoded.trim().isEmpty) {
          space(i, i + entity.length);
        } else {
          flushSpace();
          emit(decoded, i, i + entity.length);
        }
        i += entity.length;
        continue;
      }
    }

    if (ch.trim().isEmpty) {
      space(i, i + 1);
      i++;
      continue;
    }

    flushSpace();
    emit(ch, i, i + 1);
    i++;
  }

  return HtmlTextMap._(text.toString(), start, end, wrappable);
}
