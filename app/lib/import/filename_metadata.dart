/// Metadata guessed from a file name, before anything is looked up online.
class FilenameMeta {
  const FilenameMeta({
    this.authors = const [],
    this.title,
    this.publisher,
    this.year,
  });

  final List<String> authors;
  final String? title;
  final String? publisher;
  final int? year;

  /// The best query to hand the online lookup: author and title, which is what
  /// Open Library matches on far better than a raw file name.
  String get searchQuery => [...authors, ?title].join(' ').trim();
}

/// Strips a file name down to its stem: no directories, no extension.
String filenameStem(String path) {
  final base = path.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  return (dot <= 0 ? base : base.substring(0, dot)).trim();
}

/// Parses the common `Author(s) - Title-Publisher (Year)` naming convention out
/// of a file-name [stem] (extension already removed).
///
/// A **port of the server's `metadata::parse_filename`**, kept deliberately
/// rule-for-rule identical so a folder imported in the app and the same folder
/// imported through the console produce the same books. The app can't call the
/// server's version: bulk import has to work with no server at all (local-first),
/// and `filename_metadata_test.dart` re-runs the Rust test cases to keep the two
/// honest.
///
/// Every part is optional: authors run up to the first `" - "` (comma- or
/// `&`-separated), a trailing `(YYYY)` is the year, and within what's left the
/// *last* `-` splits title from publisher. A name that fits no part of the
/// pattern yields the whole string as the title.
FilenameMeta parseFilename(String stem) {
  var s = stem.trim();
  int? year;
  var authors = const <String>[];

  // Trailing "(YYYY)".
  if (s.endsWith(')')) {
    final open = s.lastIndexOf('(');
    if (open >= 0) {
      final inner = s.substring(open + 1, s.length - 1);
      if (inner.length == 4 && RegExp(r'^\d{4}$').hasMatch(inner)) {
        year = int.tryParse(inner);
        s = s.substring(0, open).trimRight();
      }
    }
  }

  // Authors up to the first " - ".
  final dash = s.indexOf(' - ');
  String rest;
  if (dash >= 0) {
    authors = [
      for (final a in s.substring(0, dash).split(RegExp('[,&]')))
        if (a.trim().isNotEmpty) a.trim(),
    ];
    rest = s.substring(dash + 3).trim();
  } else {
    rest = s;
  }

  // The last "-" splits title from publisher.
  final split = rest.lastIndexOf('-');
  if (split >= 0 &&
      rest.substring(0, split).trim().isNotEmpty &&
      rest.substring(split + 1).trim().isNotEmpty) {
    return FilenameMeta(
      authors: authors,
      title: rest.substring(0, split).trim(),
      publisher: rest.substring(split + 1).trim(),
      year: year,
    );
  }
  final title = rest.trim();
  return FilenameMeta(
    authors: authors,
    title: title.isEmpty ? null : title,
    year: year,
  );
}
