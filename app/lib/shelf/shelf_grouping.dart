import '../data/library_queries.dart';
import '../settings/shelf_group_by.dart';

/// One headed section of the shelf. [name] is null for the closing "No
/// author" / "No series" / "No genre" group, and for the single header-less
/// group that "no grouping" produces ([headed] false).
class ShelfGroup {
  const ShelfGroup({
    required this.by,
    required this.key,
    required this.name,
    required this.entries,
    this.headed = true,
  });

  final ShelfGroupBy by;

  /// Stable across rebuilds (lowercased name), so a collapsed group stays
  /// collapsed when the list changes underneath it.
  final String key;
  final String? name;
  final List<LibraryEntry> entries;
  final bool headed;
}

/// The names a book falls under for [by]: trimmed, de-duplicated
/// case-insensitively, blanks dropped. Empty means "no author" etc.
List<String> _valuesOf(LibraryEntry e, ShelfGroupBy by) {
  final raw = switch (by) {
    ShelfGroupBy.author => e.authors,
    ShelfGroupBy.genre => e.genres,
    ShelfGroupBy.series => [if (e.seriesName != null) e.seriesName!],
    ShelfGroupBy.none => const <String>[],
  };
  final seen = <String>{};
  return [
    for (final v in raw)
      if (v.trim().isNotEmpty && seen.add(v.trim().toLowerCase())) v.trim(),
  ];
}

/// Splits [entries] (already filtered and sorted) into groups.
///
/// A book with several authors (or genres) appears under **each** of them —
/// the point of looking at "Pratchett" is to see every Pratchett book,
/// including the co-written ones. Selection works by book id, so a book shown
/// twice is ticked in both places. Books with no value go into a final group.
///
/// Groups are ordered by name, case-insensitively, with the empty group last.
/// Inside a group the incoming (sort) order is kept, except in a series, which
/// is ordered by series index (unnumbered last, then title) — reading order is
/// the only sensible one there.
///
/// Pure and synchronous: callers memoise it on the entry list (see
/// [GroupMemo]) so it runs once per query result, never per frame.
List<ShelfGroup> groupEntries(List<LibraryEntry> entries, ShelfGroupBy by) {
  if (by == ShelfGroupBy.none) {
    return [
      ShelfGroup(by: by, key: '', name: null, entries: entries, headed: false),
    ];
  }

  final buckets = <String, List<LibraryEntry>>{};
  final names = <String, String>{}; // first spelling seen wins
  final missing = <LibraryEntry>[];

  for (final e in entries) {
    final values = _valuesOf(e, by);
    if (values.isEmpty) {
      missing.add(e);
      continue;
    }
    for (final v in values) {
      final key = v.toLowerCase();
      names.putIfAbsent(key, () => v);
      (buckets[key] ??= []).add(e);
    }
  }

  final keys = buckets.keys.toList()..sort();
  return [
    for (final k in keys)
      ShelfGroup(
        by: by,
        key: k,
        name: names[k],
        entries: by == ShelfGroupBy.series
            ? _inSeriesOrder(buckets[k]!)
            : buckets[k]!,
      ),
    if (missing.isNotEmpty)
      ShelfGroup(by: by, key: '\u0000', name: null, entries: missing),
  ];
}

List<LibraryEntry> _inSeriesOrder(List<LibraryEntry> group) {
  final sorted = [...group];
  sorted.sort((a, b) {
    final ai = a.book.seriesIndex;
    final bi = b.book.seriesIndex;
    if ((ai == null) != (bi == null)) return ai == null ? 1 : -1;
    if (ai != null && bi != null && ai != bi) return ai.compareTo(bi);
    return a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase());
  });
  return sorted;
}

/// Remembers the last grouping so a rebuild with the same list and mode costs
/// nothing. Keyed on the *identity* of the list: the query stream emits a new
/// list on every change, so identity is exactly "has the library changed".
class GroupMemo {
  List<LibraryEntry>? _entries;
  ShelfGroupBy? _by;
  List<ShelfGroup> _groups = const [];

  List<ShelfGroup> of(List<LibraryEntry> entries, ShelfGroupBy by) {
    if (!identical(entries, _entries) || by != _by) {
      _entries = entries;
      _by = by;
      _groups = groupEntries(entries, by);
    }
    return _groups;
  }
}
