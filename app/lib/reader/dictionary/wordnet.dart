/// A dictionary that lives on the device (request 8/19 #9: "when highlighting
/// text… add synonyms or dictionary for the highlighted word").
///
/// WordNet's own database format, read straight off disk. Two reasons for the
/// format rather than a converted one: it is what the download from Princeton
/// contains, so nothing has to be repackaged and re-hosted, and its index files
/// are sorted, which means a lookup is a binary search over a few seeks instead
/// of loading thirty megabytes into a phone's memory to find one word.
///
/// The whole thing is offline by design — the same rule the translator follows.
/// A word you are reading should not have to travel to be looked up.
library;

import 'dart:convert';
import 'dart:io';

/// One meaning of a word: its part of speech, its definition, the other words
/// that mean the same thing, and any examples WordNet gives.
class WordSense {
  const WordSense({
    required this.partOfSpeech,
    required this.definition,
    required this.synonyms,
    this.examples = const [],
  });

  /// 'noun', 'verb', 'adjective', 'adverb'.
  final String partOfSpeech;
  final String definition;

  /// The other words in this sense's synset — the answer to "synonyms",
  /// which is what was actually asked for. Excludes the word looked up.
  final List<String> synonyms;

  final List<String> examples;
}

/// The four files-per-part-of-speech WordNet is made of, on this device.
class WordNet {
  WordNet(this.dir);

  /// The directory holding `index.noun`, `data.noun`, and so on.
  final Directory dir;

  /// WordNet's own names for the four parts of speech it covers. Adjective
  /// satellites live in the `adj` files, so there are four, not five.
  static const _parts = <String, String>{
    'noun': 'noun',
    'verb': 'verb',
    'adj': 'adjective',
    'adv': 'adverb',
  };

  /// The files a usable installation must have. `*.exc` are the irregular
  /// forms — "geese", "went" — without which a lookup of an ordinary sentence
  /// word misses more often than it should.
  static List<String> get requiredFiles => [
        for (final part in _parts.keys) ...['index.$part', 'data.$part'],
      ];

  static List<String> get wantedFiles => [
        ...requiredFiles,
        for (final part in _parts.keys) '$part.exc',
      ];

  bool get isInstalled =>
      requiredFiles.every((name) => File('${dir.path}/$name').existsSync());

  final _exceptions = <String, Map<String, List<String>>>{};

  /// Every sense of [word], in WordNet's own order — which is roughly
  /// commonest first, so the first line of the sheet is usually the one meant.
  Future<List<WordSense>> lookup(String word) async {
    final target = word.trim().toLowerCase();
    if (target.isEmpty) return const [];
    final senses = <WordSense>[];
    for (final part in _parts.keys) {
      for (final form in await _forms(target, part)) {
        final offsets = await _offsetsFor(form, part);
        if (offsets.isEmpty) continue;
        senses.addAll(await _readSenses(offsets, part, form));
        // The first form that hits is the word's own form; later ones are
        // guesses at a stem, and offering both would list "dog" twice.
        break;
      }
    }
    return senses;
  }

  /// The forms worth looking for: the word itself, then WordNet's irregulars,
  /// then the ordinary endings taken off.
  Future<List<String>> _forms(String word, String part) async {
    final forms = <String>[word];
    for (final base in (await _exceptionsFor(part))[word] ?? const <String>[]) {
      if (!forms.contains(base)) forms.add(base);
    }
    for (final base in _detach(word, part)) {
      if (!forms.contains(base)) forms.add(base);
    }
    return forms;
  }

  /// WordNet's detachment rules — the regular endings, taken off one at a time.
  static List<String> _detach(String word, String part) {
    const rules = <String, List<(String, String)>>{
      'noun': [
        ('ses', 's'),
        ('xes', 'x'),
        ('zes', 'z'),
        ('ches', 'ch'),
        ('shes', 'sh'),
        ('ies', 'y'),
        ('men', 'man'),
        ('s', ''),
      ],
      'verb': [
        ('ies', 'y'),
        ('ied', 'y'),
        ('ying', 'ie'),
        ('es', 'e'),
        ('es', ''),
        ('ed', 'e'),
        ('ed', ''),
        ('ing', 'e'),
        ('ing', ''),
        ('s', ''),
      ],
      // 'iest'/'ier' before the plain endings: "happier" is "happy", and the
      // exception file that would have said so is not in the download.
      'adj': [
        ('iest', 'y'),
        ('ier', 'y'),
        ('est', ''),
        ('est', 'e'),
        ('er', ''),
        ('er', 'e'),
      ],
      'adv': [],
    };
    final out = <String>[];
    for (final (suffix, replacement)
        in rules[part] ?? const <(String, String)>[]) {
      if (word.length > suffix.length && word.endsWith(suffix)) {
        out.add(word.substring(0, word.length - suffix.length) + replacement);
      }
    }
    return out;
  }

  Future<Map<String, List<String>>> _exceptionsFor(String part) async {
    final cached = _exceptions[part];
    if (cached != null) return cached;
    final file = File('${dir.path}/$part.exc');
    final map = <String, List<String>>{};
    if (file.existsSync()) {
      for (final line in await file.readAsLines()) {
        final words = line.trim().split(' ');
        if (words.length < 2) continue;
        map[words.first] = words.sublist(1);
      }
    }
    _exceptions[part] = map;
    return map;
  }

  /// Binary search over the sorted index file.
  ///
  /// The index is ASCII, one entry per line, sorted by lemma — so a lookup is
  /// a handful of seeks. The file opens with a licence header whose lines all
  /// begin with two spaces; those sort before every real entry, which is why
  /// the search can ignore them entirely.
  Future<List<int>> _offsetsFor(String lemma, String part) async {
    final file = File('${dir.path}/index.$part');
    if (!file.existsSync()) return const [];
    final handle = await file.open();
    try {
      var low = 0;
      var high = await handle.length();
      while (low < high) {
        final mid = (low + high) ~/ 2;
        final start = await _lineStart(handle, mid);
        final line = await _readLine(handle, start);
        if (line == null) break;
        final space = line.indexOf(' ');
        if (space < 0) {
          low = start + line.length + 1;
          continue;
        }
        final found = line.substring(0, space);
        final order = found.compareTo(lemma);
        if (order == 0) return _parseIndexLine(line);
        if (order < 0) {
          low = start + line.length + 1;
        } else {
          if (high == start) break;
          high = start;
        }
      }
      return const [];
    } finally {
      await handle.close();
    }
  }

  /// Where the line containing byte [position] begins.
  Future<int> _lineStart(RandomAccessFile handle, int position) async {
    var at = position;
    const window = 256;
    while (at > 0) {
      final from = at - window < 0 ? 0 : at - window;
      await handle.setPosition(from);
      final bytes = await handle.read(at - from);
      final newline = bytes.lastIndexOf(0x0a);
      if (newline >= 0) return from + newline + 1;
      at = from;
    }
    return 0;
  }

  Future<String?> _readLine(RandomAccessFile handle, int start) async {
    await handle.setPosition(start);
    final buffer = <int>[];
    while (true) {
      final chunk = await handle.read(512);
      if (chunk.isEmpty) break;
      final newline = chunk.indexOf(0x0a);
      if (newline >= 0) {
        buffer.addAll(chunk.sublist(0, newline));
        break;
      }
      buffer.addAll(chunk);
    }
    if (buffer.isEmpty) return null;
    return latin1.decode(buffer);
  }

  /// `lemma pos synset_cnt p_cnt [ptr…] sense_cnt tagsense_cnt offset…`
  static List<int> _parseIndexLine(String line) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 6) return const [];
    final pointerCount = int.tryParse(fields[3]) ?? 0;
    // lemma, pos, synset_cnt, p_cnt, the pointer symbols, sense_cnt, tagsense.
    final offsetsStart = 4 + pointerCount + 2;
    if (offsetsStart >= fields.length) return const [];
    return [
      for (final field in fields.sublist(offsetsStart))
        if (int.tryParse(field) != null) int.parse(field),
    ];
  }

  Future<List<WordSense>> _readSenses(
    List<int> offsets,
    String part,
    String lemma,
  ) async {
    final file = File('${dir.path}/data.$part');
    if (!file.existsSync()) return const [];
    final handle = await file.open();
    try {
      final senses = <WordSense>[];
      for (final offset in offsets) {
        final line = await _readLine(handle, offset);
        if (line == null) continue;
        final sense = parseDataLine(line, part: _parts[part]!, lemma: lemma);
        if (sense != null) senses.add(sense);
      }
      return senses;
    } finally {
      await handle.close();
    }
  }

  /// `offset lex_file ss_type w_cnt word lex_id … | gloss`
  ///
  /// Public because it is the half worth testing directly: everything above it
  /// is seeking, and everything below is the shape of one line.
  static WordSense? parseDataLine(
    String line, {
    required String part,
    required String lemma,
  }) {
    final bar = line.indexOf('|');
    final head = (bar < 0 ? line : line.substring(0, bar)).trim();
    final gloss = bar < 0 ? '' : line.substring(bar + 1).trim();
    final fields = head.split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final wordCount = int.tryParse(fields[3], radix: 16) ?? 0;
    final words = <String>[];
    for (var i = 0; i < wordCount; i++) {
      final at = 4 + i * 2;
      if (at >= fields.length) break;
      words.add(_readable(fields[at]));
    }
    // The gloss is the definition, then any number of quoted examples, all
    // separated by semicolons — but a definition can contain a semicolon of its
    // own, so the examples are found by their quotes rather than by splitting.
    final examples = <String>[];
    var definition = gloss;
    final firstQuote = gloss.indexOf('"');
    if (firstQuote >= 0) {
      definition = gloss.substring(0, firstQuote).trim();
      for (final match in RegExp(r'"([^"]*)"').allMatches(gloss)) {
        final example = match.group(1)?.trim();
        if (example != null && example.isNotEmpty) examples.add(example);
      }
    }
    definition = definition.replaceFirst(RegExp(r'[;\s]+$'), '');
    return WordSense(
      partOfSpeech: part,
      definition: definition,
      synonyms: [
        for (final word in words)
          if (word.toLowerCase() != lemma.toLowerCase()) word,
      ],
      examples: examples,
    );
  }

  /// WordNet writes spaces as underscores and marks adjective positions with a
  /// trailing `(p)`, `(a)` or `(ip)`. Neither belongs on screen.
  static String _readable(String word) =>
      word.replaceAll('_', ' ').replaceFirst(RegExp(r'\((a|p|ip)\)$'), '');
}

/// The selection, if it is a single word — and null if it is not.
///
/// The request was explicit: "yes, only word for the moment, not phrase". So
/// the button appears for a word and not for a sentence, rather than appearing
/// always and returning nothing for a paragraph, which reads as broken.
/// Hyphens and apostrophes are inside a word; a trailing comma or quote is not.
String? singleWord(String selection) {
  final trimmed = selection.trim();
  if (trimmed.isEmpty || trimmed.length > 40) return null;
  final match = RegExp(
    r'''^[\p{Pi}\p{Ps}"'“‘(\[]*([\p{L}][\p{L}\-’']*)[\p{Pf}\p{Pe}"'”’)\]\.,;:!?]*$''',
    unicode: true,
  ).firstMatch(trimmed);
  final word = match?.group(1);
  if (word == null) return null;
  // A word that is all hyphens after the first letter is not a word.
  return RegExp(r'\p{L}{2,}', unicode: true).hasMatch(word) ? word : null;
}
