/// How the digital shelf orders its books. Applied in the widget layer over the
/// already-materialized list (see `sortBooks`), so it needs no extra query.
enum ShelfSort {
  title('Title'),
  author('Author'),
  year('Year'),
  /// Series name, then volume number, then title — with series-less books last
  /// (plan 5 #17). The whole point: *The Two Towers* next to *The Fellowship of
  /// the Ring* instead of nowhere near it.
  series('Series');

  const ShelfSort(this.label);

  final String label;
}
