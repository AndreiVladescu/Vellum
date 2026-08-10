import 'package:flutter/material.dart';

/// How books are shown on the shelf.
enum BookFace {
  /// Spine-out — the space-efficient bookshelf look (the default).
  spine('Spine out', Icons.menu_book_outlined),

  /// Face-out — the front cover, a clearer preview of each book.
  cover('Front cover', Icons.image_outlined),

  /// A plain list: no artwork at all, one line per book.
  ///
  /// The other two are pictures of a library, and pictures are what make a
  /// shelf pleasant to browse and slow to *scan*. At a few hundred books,
  /// "which of these have I not started" stops being a question you answer by
  /// looking at spines. This is the mode for reading the library as data —
  /// dense, sortable by the same controls, and showing the things a spine
  /// cannot say.
  list('List', Icons.view_list_outlined);

  const BookFace(this.label, this.icon);

  final String label;
  final IconData icon;
}
