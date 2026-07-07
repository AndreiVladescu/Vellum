import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import 'book_open_route.dart';
import 'spine_style.dart';

const _bookAreaHeight = 175.0;
const _boardHeight = 14.0;
const _spineGap = 5.0;
const _shelfPadding = 18.0;

/// The library as rows of wooden shelves holding book spines.
///
/// Spines have known widths (from their [SpineStyle]), so books are packed
/// greedily into as many shelf rows as the screen width requires.
class ShelfView extends StatelessWidget {
  const ShelfView({
    super.key,
    required this.books,
    required this.detailBuilder,
    this.coverFileOf,
  });

  final List<Book> books;

  /// Builds the page a book opens into (container-transform animation).
  final Widget Function(Book) detailBuilder;

  /// Resolves a book's downloaded cover image, if it has one. Spines of
  /// covered books are drawn from the cover art (like real books, where the
  /// spine continues the cover); others get a generated colored spine.
  final File? Function(Book)? coverFileOf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final rowWidth = constraints.maxWidth - 2 * _shelfPadding;
      final rows = _packIntoRows(rowWidth);
      return ListView.builder(
        padding: const EdgeInsets.symmetric(
            horizontal: _shelfPadding, vertical: 24),
        itemCount: rows.length,
        itemBuilder: (context, i) => _ShelfRow(
          row: rows[i],
          detailBuilder: detailBuilder,
          coverFileOf: coverFileOf,
        ),
      );
    });
  }

  List<List<Book>> _packIntoRows(double rowWidth) {
    final rows = <List<Book>>[[]];
    var used = 0.0;
    for (final book in books) {
      final w = SpineStyle.fromJson(book.spineStyle, title: book.title).width;
      if (rows.last.isNotEmpty && used + _spineGap + w > rowWidth) {
        rows.add([]);
        used = 0.0;
      }
      rows.last.add(book);
      used += w + _spineGap;
    }
    return rows;
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.row,
    required this.detailBuilder,
    required this.coverFileOf,
  });

  final List<Book> row;
  final Widget Function(Book) detailBuilder;
  final File? Function(Book)? coverFileOf;

  void _openBook(BuildContext spineContext, Book book) {
    final box = spineContext.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final coverFile = coverFileOf?.call(book);
    Navigator.of(spineContext).push(BookOpenRoute(
      spineRect: rect,
      spineFace: BookSpine(book: book, coverFile: coverFile),
      detailBuilder: (_) => detailBuilder(book),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final board = dark ? const Color(0xFF4A4038) : const Color(0xFFB09B82);
    return Column(
      children: [
        SizedBox(
          height: _bookAreaHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final book in row)
                Padding(
                  padding: const EdgeInsets.only(right: _spineGap),
                  // Builder gives each spine its own context so we can
                  // measure where it sits — the take-out animation starts
                  // from that exact spot on the shelf.
                  child: Builder(
                    builder: (spineContext) => BookSpine(
                      book: book,
                      coverFile: coverFileOf?.call(book),
                      onTap: () => _openBook(spineContext, book),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          height: _boardHeight,
          decoration: BoxDecoration(
            color: board,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.5 : 0.25),
                blurRadius: 4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// A single book spine standing on the shelf.
///
/// With a [coverFile], the spine is drawn from the cover art itself (real
/// spines usually continue the cover's artwork — we show the cover's left
/// edge, shaded like a rounded spine, with the title overlaid). Without one,
/// it falls back to the generated colored spine.
class BookSpine extends StatelessWidget {
  const BookSpine({
    super.key,
    required this.book,
    this.onTap,
    this.coverFile,
  });

  final Book book;
  final VoidCallback? onTap;
  final File? coverFile;

  @override
  Widget build(BuildContext context) {
    final style = SpineStyle.fromJson(book.spineStyle, title: book.title);
    final cover = coverFile;
    final hasCover = cover != null && cover.existsSync();
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: book.title,
        waitDuration: const Duration(milliseconds: 600),
        child: SizedBox(
          width: style.width,
          height: _bookAreaHeight * style.heightFactor,
          child: hasCover ? _coverSpine(cover) : _generatedSpine(style),
        ),
      ),
    );
  }

  /// Spine drawn from the left edge of the cover image.
  Widget _coverSpine(File cover) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // BoxFit.cover scales the image to fill the tall, narrow spine;
          // centerLeft alignment keeps the cover's left edge visible.
          Image.file(cover, fit: BoxFit.cover, alignment: Alignment.centerLeft),
          // Cylindrical shading: highlight near the left, shade to the right.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0x33FFFFFF),
                  Color(0x00000000),
                  Color(0x59000000),
                ],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          // Scrim so the title stays readable on any artwork.
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0x42000000)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: RotatedBox(
              quarterTurns: 1,
              child: Center(
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    shadows: [
                      Shadow(blurRadius: 4, color: Color(0xB3000000)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generatedSpine(SpineStyle style) {
    final accent = style.textColor.withValues(alpha: 0.85);
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        gradient: LinearGradient(
          // Subtle left highlight / right shade for a rounded-spine look.
          colors: [
            Color.lerp(style.color, Colors.white, 0.18)!,
            style.color,
            Color.lerp(style.color, Colors.black, 0.22)!,
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          if (style.variant == 1) _band(accent),
          if (style.variant == 2) _label(accent),
          Expanded(
            child: RotatedBox(
              quarterTurns: 1,
              child: Center(
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: style.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
          if (style.variant == 1) _band(accent),
        ],
      ),
    );
  }

  Widget _band(Color accent) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Column(
          children: [
            Container(height: 2, color: accent),
            const SizedBox(height: 2),
            Container(height: 1, color: accent),
          ],
        ),
      );

  Widget _label(Color accent) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        width: 18,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(color: accent, width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}
