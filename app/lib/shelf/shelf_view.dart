import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../settings/book_face.dart';
import '../settings/spine_art.dart';
import 'book_open_route.dart';
import 'cover_color.dart';
import 'spine_style.dart';

const _bookAreaHeight = 175.0;
const _boardHeight = 14.0;
const _spineGap = 5.0;
const _shelfPadding = 18.0;
// Face-out covers are uniform, in a roughly 2:3 book aspect ratio.
const _coverWidth = 116.0;

/// The library as rows of wooden shelves holding book spines.
///
/// Spines have known widths (from their [SpineStyle]), so books are packed
/// greedily into as many shelf rows as the screen width requires.
class ShelfView extends StatelessWidget {
  const ShelfView({
    super.key,
    required this.books,
    required this.detailBuilder,
    this.bookFace = BookFace.spine,
    this.spineArt = SpineArt.coverSlice,
    this.coverFileOf,
  });

  final List<Book> books;

  /// Whether books stand spine-out or face-out with their front cover.
  final BookFace bookFace;

  /// In spine mode: cover-slice spines or dominant-colour spines.
  final SpineArt spineArt;

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
          bookFace: bookFace,
          spineArt: spineArt,
          detailBuilder: detailBuilder,
          coverFileOf: coverFileOf,
        ),
      );
    });
  }

  double _widthOf(Book book) => bookFace == BookFace.cover
      ? _coverWidth
      : SpineStyle.fromJson(book.spineStyle, title: book.title).width;

  List<List<Book>> _packIntoRows(double rowWidth) {
    final rows = <List<Book>>[[]];
    var used = 0.0;
    for (final book in books) {
      final w = _widthOf(book);
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
    required this.bookFace,
    required this.spineArt,
    required this.detailBuilder,
    required this.coverFileOf,
  });

  final List<Book> row;
  final BookFace bookFace;
  final SpineArt spineArt;
  final Widget Function(Book) detailBuilder;
  final File? Function(Book)? coverFileOf;

  void _openBook(BuildContext bookContext, Book book, Widget face) {
    final box = bookContext.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    Navigator.of(bookContext).push(BookOpenRoute(
      bookRect: rect,
      bookFace: face,
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
                  // Builder gives each book its own context so we can measure
                  // where it sits — the pull-out animation starts from that
                  // exact spot on the shelf.
                  child: Builder(
                    builder: (bookContext) {
                      final coverFile = coverFileOf?.call(book);
                      Widget face({VoidCallback? onTap}) =>
                          bookFace == BookFace.cover
                              ? BookCover(
                                  book: book,
                                  coverFile: coverFile,
                                  onTap: onTap)
                              : BookSpine(
                                  book: book,
                                  coverFile: coverFile,
                                  spineArt: spineArt,
                                  onTap: onTap);
                      return face(
                        onTap: () => _openBook(bookContext, book, face()),
                      );
                    },
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
    this.spineArt = SpineArt.coverSlice,
  });

  final Book book;
  final VoidCallback? onTap;
  final File? coverFile;
  final SpineArt spineArt;

  @override
  Widget build(BuildContext context) {
    final style = SpineStyle.fromJson(book.spineStyle, title: book.title);
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: book.title,
        waitDuration: const Duration(milliseconds: 600),
        child: SizedBox(
          width: style.width,
          height: _bookAreaHeight * style.heightFactor,
          child: SpineFace(
            book: book,
            coverFile: coverFile,
            style: style,
            spineArt: spineArt,
          ),
        ),
      ),
    );
  }
}

/// The spine artwork alone, filling its parent (the caller sizes it): a slice of
/// the cover image if there is one, otherwise the generated spine. Shared by the
/// digital shelf and the physical-layout view, so a book looks the same in both.
class SpineFace extends StatelessWidget {
  const SpineFace({
    super.key,
    required this.book,
    this.coverFile,
    this.style,
    this.spineArt = SpineArt.coverSlice,
  });

  final Book book;
  final File? coverFile;
  final SpineStyle? style;

  /// How a covered book draws its spine. [SpineArt.dominantColor] uses the
  /// generated spine in the cover's extracted colour; until that colour has
  /// been extracted it falls back to the cover slice.
  final SpineArt spineArt;

  @override
  Widget build(BuildContext context) {
    final s = style ?? SpineStyle.fromJson(book.spineStyle, title: book.title);
    final cover = coverFile;
    // No filesystem call in build: a non-null path means "has a cover". If the
    // file is actually missing (rare orphaned path), Image.file's errorBuilder
    // falls back to the generated spine.
    if (cover == null) return _generatedSpine(s);
    final dominant = s.coverColor;
    if (spineArt == SpineArt.dominantColor && dominant != null) {
      return _generatedSpine(
        s.withCoverColor(null).recolored(dominant, spineTextColorFor(dominant)),
      );
    }
    return _coverSpine(context, cover, s);
  }

  /// Spine drawn from the left edge of the cover image.
  Widget _coverSpine(BuildContext context, File cover, SpineStyle s) {
    // Decode below full resolution to bound memory, but size the budget by the
    // spine's *height*: BoxFit.cover on a tall, narrow box is height-driven and
    // shows a full-height vertical slice, so a width-based budget would upscale
    // a tiny bitmap and look blurry. LayoutBuilder gives the real on-screen
    // height (the spine size varies: digital shelf vs. zoomed physical view).
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // BoxFit.cover scales the image to fill the tall, narrow spine;
          // centerLeft alignment keeps the cover's left edge visible.
          LayoutBuilder(
            builder: (context, constraints) {
              final h =
                  constraints.maxHeight.isFinite ? constraints.maxHeight : _bookAreaHeight;
              return Image.file(cover,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerLeft,
                  cacheHeight: (h * dpr).round(),
                  // Orphaned path: fall back to a plain fill; the shading and
                  // title overlays below still render (coverless spine look).
                  errorBuilder: (_, _, _) => ColoredBox(color: s.color));
            },
          ),
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

/// A single book shown face-out with its front cover — the downloaded cover
/// image if there is one, otherwise a cover generated in the book's spine
/// style. Used when the shelf is in [BookFace.cover] mode.
class BookCover extends StatelessWidget {
  const BookCover({
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
    final cover = coverFile;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: book.title,
        waitDuration: const Duration(milliseconds: 600),
        child: SizedBox(
          width: _coverWidth,
          height: _bookAreaHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            // Non-null path means "has a cover"; decode below full res but by
            // the box *height* (a 2:3 cover in this taller box is height-driven,
            // so a width budget would leave it soft). Fall back to a generated
            // cover if the file is missing. No filesystem call in build.
            child: cover != null
                ? Image.file(cover,
                    fit: BoxFit.cover,
                    cacheHeight: (_bookAreaHeight * dpr).round(),
                    errorBuilder: (_, _, _) => _generatedCover())
                : _generatedCover(),
          ),
        ),
      ),
    );
  }

  /// Front cover synthesized from the spine style, for books without art.
  Widget _generatedCover() {
    final style = SpineStyle.fromJson(book.spineStyle, title: book.title);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(style.color, Colors.white, 0.10)!,
            Color.lerp(style.color, Colors.black, 0.15)!,
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text(
          book.title,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: style.textColor,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
