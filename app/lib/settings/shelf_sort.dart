/// How the digital shelf orders its books. Applied in the widget layer over the
/// already-materialized list (see `sortBooks`), so it needs no extra query.
enum ShelfSort {
  title('Title'),
  author('Author'),
  year('Year');

  const ShelfSort(this.label);

  final String label;
}
