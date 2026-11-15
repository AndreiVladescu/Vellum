/// Cutting text into what a speech engine is given one at a time (roadmap
/// v1.4.3, read aloud).
///
/// **Why sentences.** An engine speaks whatever it is handed and reports back
/// only when it has finished. A whole chapter in one call cannot be paused
/// (Android's engine just stops, losing the place), skipped within, or followed
/// on the page; a sentence at a time can do all three, and the gap between two
/// of them is shorter than the breath a narrator takes. Android also refuses
/// text longer than `getMaxSpeechInputLength` (about 4000 characters), which a
/// paragraph with no full stop in it can exceed.
///
/// Everything here is pure — text in, offsets out — so it is unit tested
/// without an engine (`test/reader/tts/tts_text_test.dart`).
library;

/// One thing to say: a sentence, or a piece of one too long to say in one go.
///
/// [start] and [end] are offsets into the text it was cut from, which is how
/// the readers turn "this is being spoken" into "this is where on the page":
/// for an EPUB they index the chapter's `plainText`.
class TtsChunk {
  const TtsChunk(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is TtsChunk &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'TtsChunk($start, $end, "$text")';
}

/// Words that end in a full stop without ending the sentence. Lower case, no
/// final dot. Deliberately short: an abbreviation missed here costs one
/// sentence spoken as two, which is barely audible. The lower-case rule below
/// catches most of the rest ("etc. and so on").
const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'mt', 'vs', 'etc', //
  'e.g', 'i.e', 'fig', 'vol', 'no', 'ch', 'pp', 'cf', 'approx', 'dept',
  'gen', 'col', 'capt', 'lt', 'sgt', 'rev', 'hon', 'inc', 'ltd', 'co',
};

/// What closes a sentence once its terminator has been said: a quotation mark
/// or bracket belongs to the sentence it finishes ("Go away!" she said.).
const _closers = '"\'”’»)]}';

bool _isTerminator(String c) =>
    c == '.' || c == '!' || c == '?' || c == '…' || _isCjkTerminator(c);

/// Scripts that write no space after a full stop, so "followed by whitespace"
/// cannot be what ends the sentence.
bool _isCjkTerminator(String c) => c == '。' || c == '！' || c == '？';

bool _isSpace(String c) => c.trim().isEmpty;

final _lower = RegExp(r'\p{Ll}', unicode: true);
final _upper = RegExp(r'\p{Lu}', unicode: true);
final _speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The sentences of [text], as `(start, end)` offsets with the whitespace
/// trimmed off both ends.
List<({int start, int end})> sentenceSpans(String text) {
  final spans = <({int start, int end})>[];
  var from = 0;

  void add(int start, int end) {
    while (start < end && _isSpace(text[start])) {
      start++;
    }
    while (end > start && _isSpace(text[end - 1])) {
      end--;
    }
    if (end > start) spans.add((start: start, end: end));
  }

  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (!_isTerminator(c)) {
      i++;
      continue;
    }
    // Swallow a run of terminators ("?!", "...") and what closes the sentence.
    var j = i + 1;
    while (j < text.length && _isTerminator(text[j])) {
      j++;
    }
    while (j < text.length && _closers.contains(text[j])) {
      j++;
    }
    final atEnd = j >= text.length;
    final cjk = _isCjkTerminator(c);
    if (!atEnd && !cjk && !_isSpace(text[j])) {
      // "3.14", "e.g.", "www.example.com": a dot inside something.
      i = j;
      continue;
    }
    if (!atEnd && !cjk && c == '.' && !_endsSentence(text, i, j)) {
      i = j;
      continue;
    }
    add(from, j);
    from = j;
    i = j;
  }
  add(from, text.length);
  return spans;
}

/// Whether the full stop at [dot] (its run ends before [after]) closes a
/// sentence, given that whitespace follows it.
bool _endsSentence(String text, int dot, int after) {
  // The word it is attached to.
  var w = dot;
  while (w > 0 && !_isSpace(text[w - 1]) && !_closers.contains(text[w - 1])) {
    w--;
  }
  final word = text.substring(w, dot);
  if (_abbreviations.contains(word.toLowerCase())) return false;
  // An initial: "J. R. R. Tolkien".
  if (word.length == 1 && _upper.hasMatch(word)) return false;
  // A sentence starts with a capital, a digit or a quote — not a lower-case
  // letter.
  var n = after;
  while (n < text.length && _isSpace(text[n])) {
    n++;
  }
  if (n < text.length && _lower.hasMatch(text[n])) return false;
  return true;
}

/// [text] cut into [TtsChunk]s of at most about [maxLength] characters.
///
/// A sentence longer than that is cut at the last comma, semicolon, colon or
/// dash before the limit, or failing that at a space, or failing that — a
/// string with no break in it — where it must. Spans with nothing to say in
/// them (a row of asterisks, a rule) are dropped.
List<TtsChunk> speechChunks(String text, {int maxLength = 260}) {
  assert(maxLength >= 20);
  final chunks = <TtsChunk>[];
  for (final span in sentenceSpans(text)) {
    var start = span.start;
    final end = span.end;
    while (end - start > maxLength) {
      final cut = _cutPoint(text, start, start + maxLength);
      _push(chunks, text, start, cut);
      start = cut;
      while (start < end && _isSpace(text[start])) {
        start++;
      }
    }
    _push(chunks, text, start, end);
  }
  return chunks;
}

void _push(List<TtsChunk> out, String text, int start, int end) {
  while (end > start && _isSpace(text[end - 1])) {
    end--;
  }
  if (end <= start) return;
  final piece = text.substring(start, end);
  if (!_speakable.hasMatch(piece)) return;
  out.add(TtsChunk(start, end, piece));
}

/// Where to cut [text] between [start] and [limit]: after the last clause
/// break in the second half, else at the last space, else at [limit].
int _cutPoint(String text, int start, int limit) {
  final half = start + (limit - start) ~/ 2;
  for (var i = limit - 1; i > half; i--) {
    if (',;:—–'.contains(text[i])) return i + 1;
  }
  for (var i = limit; i > start; i--) {
    if (_isSpace(text[i])) return i;
  }
  return limit;
}

/// The index of the chunk to start from for [offset]: the one containing it,
/// or the first one after it (an offset in the gap between two sentences), or
/// the last when the offset is past them all. -1 when there are no chunks.
int chunkIndexAt(List<TtsChunk> chunks, int offset) {
  if (chunks.isEmpty) return -1;
  var lo = 0, hi = chunks.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (chunks[mid].end > offset) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}

/// A PDF page's text as something to say: lines joined into running text, and
/// a word broken across two lines by a hyphen made whole again. (A real
/// hyphenated compound broken at its hyphen loses it — one in a few hundred
/// line ends, and spoken the same.)
String speakablePdfText(String text) => text
    .replaceAllMapped(
      RegExp(r'(\p{L})-[ \t]*\r?\n[ \t]*(\p{Ll})', unicode: true),
      (m) => '${m[1]}${m[2]}',
    )
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
