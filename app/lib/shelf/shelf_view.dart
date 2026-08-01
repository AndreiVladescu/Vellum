import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../settings/appearance.dart';
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
    this.material = ShelfMaterial.fallback,
    this.typography = SpineTypography.normal,
    this.coverFileOf,
    this.selected = const {},
    this.onToggleSelected,
    this.selectionMode = false,
  });

  final List<Book> books;

  /// Book ids currently ticked (next features #4).
  final Set<String> selected;

  /// Toggles a book in the selection. Null means this shelf has no selection
  /// mode at all — a long-press then does nothing, as before.
  final void Function(Book)? onToggleSelected;

  /// While true a plain tap toggles instead of opening the book. Distinct from
  /// `selected.isNotEmpty` only so the caller stays in charge of when the mode
  /// ends.
  final bool selectionMode;

  /// What the boards are made of (plan 5 #39).
  final ShelfMaterial material;

  /// The user's spine size nudges. Applied at render rather than baked into
  /// `book.spine_style`, so changing it restyles the shelf instead of
  /// rewriting every book.
  final SpineTypography typography;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = constraints.maxWidth - 2 * _shelfPadding;
        final rows = _packIntoRows(rowWidth);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: _shelfPadding,
            vertical: 24,
          ),
          itemCount: rows.length,
          itemBuilder: (context, i) => _ShelfRow(
            row: rows[i],
            bookFace: bookFace,
            spineArt: spineArt,
            material: material,
            typography: typography,
            detailBuilder: detailBuilder,
            coverFileOf: coverFileOf,
            selected: selected,
            onToggleSelected: onToggleSelected,
            selectionMode: selectionMode,
          ),
        );
      },
    );
  }

  double _widthOf(Book book) => bookFace == BookFace.cover
      ? _coverWidth
      // The same scale the spine itself is drawn at, or the packer would lay
      // out rows for a width the books no longer have.
      : SpineStyle.fromJson(book.spineStyle, title: book.title).width *
          typography.clampedWidth;

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
    required this.material,
    required this.typography,
    required this.detailBuilder,
    required this.coverFileOf,
    required this.selected,
    required this.onToggleSelected,
    required this.selectionMode,
  });

  final List<Book> row;
  final Set<String> selected;
  final void Function(Book)? onToggleSelected;
  final bool selectionMode;
  final BookFace bookFace;
  final SpineArt spineArt;
  final ShelfMaterial material;
  final SpineTypography typography;
  final Widget Function(Book) detailBuilder;
  final File? Function(Book)? coverFileOf;

  void _openBook(BuildContext bookContext, Book book, Widget face) {
    final box = bookContext.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    Navigator.of(bookContext).push(
      BookOpenRoute(
        bookRect: rect,
        bookFace: face,
        detailBuilder: (_) => detailBuilder(book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      final toggle = onToggleSelected;
                      final isSelected = selected.contains(book.id);
                      Widget face({
                        VoidCallback? onTap,
                        VoidCallback? onLongPress,
                        bool ticked = false,
                      }) => bookFace == BookFace.cover
                          ? BookCover(
                              book: book,
                              coverFile: coverFile,
                              onTap: onTap,
                              onLongPress: onLongPress,
                              selected: ticked,
                            )
                          : BookSpine(
                              book: book,
                              coverFile: coverFile,
                              spineArt: spineArt,
                              typography: typography,
                              onTap: onTap,
                              onLongPress: onLongPress,
                              selected: ticked,
                            );
                      return face(
                        // In selection mode a tap ticks; otherwise it opens the
                        // book, as it always has. The pull-out animation is
                        // handed the *unticked* face, so a book doesn't fly off
                        // the shelf wearing a checkmark.
                        onTap: selectionMode && toggle != null
                            ? () => toggle(book)
                            : () => _openBook(bookContext, book, face()),
                        onLongPress: toggle == null ? null : () => toggle(book),
                        ticked: isSelected,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        Container(
          height: _boardHeight,
          decoration: shelfBoardDecoration(
            material,
            Theme.of(context).brightness,
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// The tick over a book that is part of the current selection (next features
/// #4).
///
/// Drawn over the artwork rather than replacing it, and the book is only
/// *dimmed* rather than hidden: the point of a visual shelf is that you
/// recognise books by their spines, and a selection that hides them would make
/// you check the count instead of looking.
class SelectedBookOverlay extends StatelessWidget {
  const SelectedBookOverlay({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.55, child: child),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.30),
            border: Border.all(color: scheme.primary, width: 2),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.check_circle,
                size: 18, color: scheme.primary, shadows: const [
              Shadow(color: Color(0x99000000), blurRadius: 3),
            ]),
          ),
        ),
      ],
    );
  }
}

/// A screen-reader label for a book: its title, plus the subtitle when present.
/// Authors aren't on the shelf's `Book` row (separate table), so title +
/// subtitle is what's available without a per-spine query.
String bookSemanticLabel(String title, String? subtitle) =>
    (subtitle != null && subtitle.isNotEmpty) ? '$title: $subtitle' : title;

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
    this.onLongPress,
    this.selected = false,
    this.coverFile,
    this.spineArt = SpineArt.coverSlice,
    this.typography = SpineTypography.normal,
  });

  final Book book;
  final VoidCallback? onTap;

  /// Enters selection mode (next features #4). Also fired by a right-click,
  /// which is what a mouse user reaches for.
  final VoidCallback? onLongPress;

  /// Ticked in selection mode: dimmed, with a check over it.
  final bool selected;
  final File? coverFile;
  final SpineArt spineArt;
  final SpineTypography typography;

  @override
  Widget build(BuildContext context) {
    final style = SpineStyle.fromJson(book.spineStyle, title: book.title);
    return Semantics(
      label: bookSemanticLabel(book.title, book.subtitle),
      button: onTap != null,
      onTap: onTap,
      // The title is painted into the spine art; screen readers get it from the
      // label above, so drop the child semantics (incl. the Tooltip's message).
      excludeSemantics: true,
      // InkWell rather than GestureDetector: a spine is the shelf's only way
      // into a book, and a GestureDetector cannot be reached by keyboard at
      // all (plan 5 #42). InkWell is focusable, activates on Enter/Space, and
      // paints a focus overlay so a keyboard user can see where they are.
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        child: Tooltip(
          message: book.title,
          waitDuration: const Duration(milliseconds: 600),
          // A Tooltip's default trigger on touch is a long-press, and it wins
          // the gesture arena against the InkWell above it — so with selection
          // mode on, holding a spine showed the title instead of ticking the
          // book. Hover is unaffected (it ignores triggerMode), so the desktop
          // tooltip still works.
          triggerMode: onLongPress != null
              ? TooltipTriggerMode.manual
              : TooltipTriggerMode.longPress,
          child: SizedBox(
            width: style.width * typography.clampedWidth,
            height: _bookAreaHeight * style.heightFactor,
            child: SelectedBookOverlay(
              selected: selected,
              child: SpineFace(
                book: book,
                coverFile: coverFile,
                style: style,
                spineArt: spineArt,
                titleScale: typography.clampedTitle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The decode height a spine of [wantedPx] physical pixels asks its cover for,
/// rounded up to the next power of two.
///
/// **This is why zooming the physical room used to blank every book.**
/// `cacheHeight` is part of an `Image`'s cache key: it wraps the file provider
/// in a `ResizeImage` keyed on that number. In the room the spine's on-screen
/// height changes on *every frame* of a pinch, so a raw `height * dpr` minted a
/// new provider per frame — each one a fresh asynchronous decode off the disk,
/// each one showing nothing until it finished, and each one retained in the
/// image cache, evicting the rest of the shelf while it was at it.
///
/// Buckets fix the cause: a whole zoom gesture reuses one decoded bitmap, and
/// the GPU scales it, which is free. Powers of two because they double —
/// crossing a boundary means the image was already off by up to 2×, which is
/// about where a resample starts to show.
///
/// Clamped at both ends: never below 64 (a thumbnail's worth, so a distant
/// spine still costs something to look at) and never above 2048 (past that the
/// slice on screen is a few hundred pixels wide and the rest is memory).
int spineDecodeHeight(double wantedPx) {
  const min = 64;
  const max = 2048;
  if (!wantedPx.isFinite || wantedPx <= min) return min;
  var bucket = min;
  while (bucket < wantedPx && bucket < max) {
    bucket *= 2;
  }
  return bucket;
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
    this.titleScale = 1.0,
  });

  final Book book;
  final File? coverFile;
  final SpineStyle? style;

  /// Multiplier on the title painted down the spine (plan 5 #39). Defaults to
  /// 1 so the physical view, which has no typography preference of its own,
  /// keeps drawing spines exactly as before.
  final double titleScale;

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
              final h = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : _bookAreaHeight;
              return Image.file(
                cover,
                fit: BoxFit.cover,
                alignment: Alignment.centerLeft,
                cacheHeight: spineDecodeHeight(h * dpr),
                // Keep the previous frame on screen while a new decode runs.
                // Crossing a bucket boundary swaps the provider, and without
                // this the spine goes blank until the new bitmap arrives —
                // which is the flicker this whole arrangement exists to avoid.
                gaplessPlayback: true,
                // Orphaned path: fall back to a plain fill; the shading and
                // title overlays below still render (coverless spine look).
                errorBuilder: (_, _, _) => ColoredBox(color: s.color),
              );
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13 * titleScale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    shadows: const [
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
                    fontSize: 13 * titleScale,
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
    this.onLongPress,
    this.selected = false,
    this.coverFile,
  });

  final Book book;
  final VoidCallback? onTap;

  /// Enters selection mode — see [BookSpine.onLongPress].
  final VoidCallback? onLongPress;
  final bool selected;
  final File? coverFile;

  @override
  Widget build(BuildContext context) {
    final cover = coverFile;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      label: bookSemanticLabel(book.title, book.subtitle),
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      // Keyboard-reachable, same reasoning as BookSpine above.
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        borderRadius: BorderRadius.circular(4),
        child: Tooltip(
          message: book.title,
          waitDuration: const Duration(milliseconds: 600),
          // A Tooltip's default trigger on touch is a long-press, and it wins
          // the gesture arena against the InkWell above it — so with selection
          // mode on, holding a spine showed the title instead of ticking the
          // book. Hover is unaffected (it ignores triggerMode), so the desktop
          // tooltip still works.
          triggerMode: onLongPress != null
              ? TooltipTriggerMode.manual
              : TooltipTriggerMode.longPress,
          child: SizedBox(
            width: _coverWidth,
            height: _bookAreaHeight,
            child: SelectedBookOverlay(
              selected: selected,
              child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              // Non-null path means "has a cover"; decode below full res but by
              // the box *height* (a 2:3 cover in this taller box is height-driven,
              // so a width budget would leave it soft). Fall back to a generated
              // cover if the file is missing. No filesystem call in build.
              child: cover != null
                  ? Image.file(
                      cover,
                      fit: BoxFit.cover,
                      cacheHeight: (_bookAreaHeight * dpr).round(),
                      errorBuilder: (_, _, _) => _generatedCover(),
                    )
                  : _generatedCover(),
              ),
            ),
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
