/// How books are shown on the shelf.
enum BookFace {
  /// Spine-out — the space-efficient bookshelf look (the default).
  spine('Spine out'),

  /// Face-out — the front cover, a clearer preview of each book.
  cover('Front cover');

  const BookFace(this.label);

  final String label;
}
