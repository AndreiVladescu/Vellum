import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/tts/tts_text.dart';

List<String> say(String text, {int max = 260}) =>
    speechChunks(text, maxLength: max).map((c) => c.text).toList();

void main() {
  test('splits on sentence ends and keeps quotes with their sentence', () {
    expect(say('One. Two! "Three?" he asked. Four'),
        ['One.', 'Two!', '"Three?"', 'he asked.', 'Four']);
  });

  test('abbreviations, initials and decimals do not end a sentence', () {
    expect(say('Dr. Smith met J. R. R. Tolkien. Pi is 3.14 or so.'),
        ['Dr. Smith met J. R. R. Tolkien.', 'Pi is 3.14 or so.']);
    expect(say('Salt, pepper, etc. and more. Next.'),
        ['Salt, pepper, etc. and more.', 'Next.']);
  });

  test('CJK terminators need no space', () {
    expect(say('今日は晴れ。明日は雨。'), ['今日は晴れ。', '明日は雨。']);
  });

  test('offsets index the source text', () {
    const text = 'First one.   Second one.';
    for (final c in speechChunks(text)) {
      expect(text.substring(c.start, c.end), c.text);
    }
  });

  test('long sentences are cut at clause breaks, then spaces, then anywhere',
      () {
    const clauses = 'alpha beta gamma, delta epsilon zeta, eta theta iota';
    final byComma = say(clauses, max: 30);
    expect(byComma.every((c) => c.length <= 30), isTrue);
    expect(byComma.first.endsWith(','), isTrue);
    expect(say('a' * 70, max: 30), hasLength(3));
    expect(say('word ' * 40, max: 40).every((c) => c.length <= 40), isTrue);
  });

  test('nothing speakable is dropped', () {
    expect(say('* * *   Real text. ---'), ['* * *   Real text.']);
    expect(say(''), isEmpty);
    expect(say('* * *'), isEmpty);
  });

  test('chunkIndexAt finds the containing, next or last chunk', () {
    final chunks = speechChunks('One one. Two two. Three three.');
    expect(chunkIndexAt(chunks, 0), 0);
    expect(chunkIndexAt(chunks, 11), 1);
    expect(chunkIndexAt(chunks, 9), 1); // the gap goes to the next sentence
    expect(chunkIndexAt(chunks, 999), 2);
    expect(chunkIndexAt(const [], 3), -1);
  });

  test('PDF text is rejoined across lines and hyphens', () {
    expect(speakablePdfText('an exam-\nple of text\nover lines'),
        'an example of text over lines');
  });
}
