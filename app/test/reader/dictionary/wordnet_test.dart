// The offline dictionary (request 8/19 #9: "synonyms or dictionary for the
// highlighted word… only word for the moment, not phrase").
//
// The database is WordNet's own format, read straight off disk, so what is
// pinned here is the reading of it: a binary search that has to skip a licence
// header, the shape of one data line, the endings that let "dogs" find "dog",
// and the rule that decides whether the button appears at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/dictionary/wordnet.dart';

/// A miniature WordNet: a real licence header, sorted entries, and data lines
/// whose offsets are their own byte positions — the two things the reader
/// depends on and the two things a hand-written fixture gets wrong.
Future<void> writeFixture(Directory dir) async {
  // Definitions in WordNet's own order, keyed by the lemma that indexes them.
  final synsets = <String, List<(String, List<String>, String)>>{
    'dog': [
      (
        'dog',
        ['domestic_dog', 'Canis_familiaris'],
        'a member of the genus Canis; "the dog barked all night"',
      ),
      ('dog', ['frump'], 'a dull unattractive unpleasant girl or woman'),
    ],
    'happy': [
      ('happy', [], 'enjoying well-being and contentment'),
    ],
    'zebra': [
      ('zebra', [], 'any of several fleet black-and-white striped mammals'),
    ],
  };

  // Data file first, so the offsets are known before the index refers to them.
  final offsets = <String, List<int>>{};
  final data = StringBuffer();
  // Even the data file opens with the licence, which is why an offset is never
  // zero in a real database.
  final header = '  1 WordNet 3.0 licence\n  2 second line of it\n';
  data.write(header);
  var at = header.length;
  for (final entry in synsets.entries) {
    for (final (word, others, gloss) in entry.value) {
      final words = [word, ...others];
      final wordFields = [
        for (final w in words) '$w 0',
      ].join(' ');
      final line = '${at.toString().padLeft(8, '0')} 05 n '
          '${words.length.toRadixString(16).padLeft(2, '0')} '
          '$wordFields 000 | $gloss  \n';
      offsets.putIfAbsent(entry.key, () => []).add(at);
      data.write(line);
      at += line.length;
    }
  }
  await File('${dir.path}/data.noun').writeAsString(data.toString());

  final index = StringBuffer(header);
  // Sorted, as WordNet's index files are — the binary search relies on it.
  for (final lemma in synsets.keys.toList()..sort()) {
    final count = offsets[lemma]!.length;
    index.write('$lemma n $count 2 @ ~ $count 0 '
        '${offsets[lemma]!.map((o) => o.toString().padLeft(8, '0')).join(' ')}\n');
  }
  await File('${dir.path}/index.noun').writeAsString(index.toString());

  // The irregular forms file the real download happens not to ship.
  await File('${dir.path}/noun.exc').writeAsString('zebras zebra\n');
}

void main() {
  group('singleWord — what the button appears for', () {
    test('a plain word', () {
      expect(singleWord('dog'), 'dog');
      expect(singleWord('  Dog  '), 'Dog');
    });

    test('a word with the punctuation it was read with', () {
      expect(singleWord('dog.'), 'dog');
      expect(singleWord('“dog”'), 'dog');
      expect(singleWord('(dog),'), 'dog');
    });

    test('a hyphenated or possessive word is still one word', () {
      expect(singleWord('well-known'), 'well-known');
      expect(singleWord("don't"), "don't");
    });

    test('a phrase is not', () {
      expect(singleWord('a dog'), isNull, reason: 'words only, as asked');
      expect(singleWord('the quick brown fox'), isNull);
    });

    test('nor is punctuation, a number, or nothing at all', () {
      expect(singleWord(''), isNull);
      expect(singleWord('   '), isNull);
      expect(singleWord('42'), isNull);
      expect(singleWord('—'), isNull);
    });

    test('nor a single letter, which is never a lookup worth offering', () {
      expect(singleWord('a'), isNull);
    });

    test('nor a whole line that happens to have no spaces', () {
      expect(singleWord('a' * 60), isNull);
    });

    test('a word in another script is a word', () {
      expect(singleWord('Wörterbuch'), 'Wörterbuch');
    });
  });

  group('one data line', () {
    test('yields the definition, the synonyms and the examples', () {
      final sense = WordNet.parseDataLine(
        '02084071 05 n 03 dog 0 domestic_dog 0 Canis_familiaris 0 003 @ '
        '02085998 n 0000 | a member of the genus Canis; "the dog barked"  ',
        part: 'noun',
        lemma: 'dog',
      )!;
      expect(sense.partOfSpeech, 'noun');
      expect(sense.definition, 'a member of the genus Canis');
      expect(sense.synonyms, ['domestic dog', 'Canis familiaris'],
          reason: 'underscores are WordNet’s spaces, and the word looked up '
              'is not its own synonym');
      expect(sense.examples, ['the dog barked']);
    });

    test('keeps a semicolon that belongs to the definition', () {
      final sense = WordNet.parseDataLine(
        '00001740 03 n 01 entity 0 000 | that which is perceived; '
        'something having existence  ',
        part: 'noun',
        lemma: 'entity',
      )!;
      expect(sense.definition,
          'that which is perceived; something having existence');
      expect(sense.examples, isEmpty);
    });

    test('drops the position markers adjectives carry', () {
      final sense = WordNet.parseDataLine(
        '00003553 00 a 02 whole(a) 0 entire(p) 0 000 | including everything  ',
        part: 'adjective',
        lemma: 'whole',
      )!;
      expect(sense.synonyms, ['entire']);
    });

    test('a line that is not one is refused rather than half-read', () {
      expect(WordNet.parseDataLine('', part: 'noun', lemma: 'x'), isNull);
      expect(WordNet.parseDataLine('  1 licence text', part: 'noun', lemma: 'x'),
          isNull);
    });
  });

  group('looking a word up', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('vellum_wordnet');
      await writeFixture(dir);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('finds every sense, in the order the database has them', () async {
      final senses = await WordNet(dir).lookup('dog');
      expect(senses, hasLength(2));
      expect(senses.first.definition, 'a member of the genus Canis');
      expect(senses.first.synonyms, ['domestic dog', 'Canis familiaris']);
      expect(senses.last.synonyms, ['frump']);
    });

    test('finds the first and last entries, not just the middle', () async {
      // The binary search has to walk past a licence header at one end and stop
      // at the file's end at the other.
      expect(await WordNet(dir).lookup('happy'), hasLength(1));
      expect(await WordNet(dir).lookup('zebra'), hasLength(1));
    });

    test('is not case-sensitive', () async {
      expect(await WordNet(dir).lookup('Dog'), hasLength(2));
    });

    test('takes a regular ending off', () async {
      expect(await WordNet(dir).lookup('dogs'), hasLength(2),
          reason: '"dogs" is what you select in a sentence');
    });

    test('uses the exception list where there is one', () async {
      expect(await WordNet(dir).lookup('zebras'), hasLength(1));
    });

    test('a word it does not have is empty, not an error', () async {
      expect(await WordNet(dir).lookup('the'), isEmpty);
      expect(await WordNet(dir).lookup('quixotic'), isEmpty);
      expect(await WordNet(dir).lookup(''), isEmpty);
    });

    test('an installation missing its files reports itself as missing',
        () async {
      final empty = Directory.systemTemp.createTempSync('vellum_wordnet_none');
      addTearDown(() => empty.deleteSync(recursive: true));
      expect(WordNet(empty).isInstalled, false);
      expect(await WordNet(empty).lookup('dog'), isEmpty,
          reason: 'a lookup before the download must not throw');
      // The fixture has nouns only, so it is not a complete installation
      // either — which is the check that stops a half-unpacked download
      // looking finished.
      expect(WordNet(dir).isInstalled, false);
    });
  });
}
