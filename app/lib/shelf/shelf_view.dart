import 'package:flutter/material.dart';

import '../data/database.dart';
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
  const ShelfView({super.key, required this.books, required this.onBookTap});

  final List<Book> books;
  final void Function(Book) onBookTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final rowWidth = constraints.maxWidth - 2 * _shelfPadding;
      final rows = _packIntoRows(rowWidth);
      return ListView.builder(
        padding: const EdgeInsets.symmetric(
            horizontal: _shelfPadding, vertical: 24),
        itemCount: rows.length,
        itemBuilder: (context, i) => _ShelfRow(row: rows[i], onTap: onBookTap),
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
  const _ShelfRow({required this.row, required this.onTap});

  final List<Book> row;
  final void Function(Book) onTap;

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
                  child: BookSpine(book: book, onTap: () => onTap(book)),
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

/// A single generated book spine, standing on the shelf.
class BookSpine extends StatelessWidget {
  const BookSpine({super.key, required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = SpineStyle.fromJson(book.spineStyle, title: book.title);
    final accent = style.textColor.withValues(alpha: 0.85);
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: book.title,
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          width: style.width,
          height: _bookAreaHeight * style.heightFactor,
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
        ),
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
