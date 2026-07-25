import 'package:flutter/material.dart';

/// Route that animates a book being eased partway out of the shelf: the tapped
/// book grows a little — as if pulled forward off the shelf — while the detail
/// page fades in over it. Popping the route reverses it, so the book shrinks
/// back to its original size and slots back onto the shelf.
class BookOpenRoute extends PageRouteBuilder<void> {
  BookOpenRoute({
    required Rect bookRect,
    required Widget bookFace,
    required WidgetBuilder detailBuilder,
  }) : super(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (context, animation, secondaryAnimation) =>
              Builder(builder: detailBuilder),
          transitionsBuilder: (context, animation, secondaryAnimation, page) {
            return _BookOpenTransition(
              animation: animation,
              bookRect: bookRect,
              bookFace: bookFace,
              page: page,
            );
          },
        );
}

class _BookOpenTransition extends StatelessWidget {
  const _BookOpenTransition({
    required this.animation,
    required this.bookRect,
    required this.bookFace,
    required this.page,
  });

  final Animation<double> animation;
  final Rect bookRect;
  final Widget bookFace;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final v = curved.value;

        // Grow the book, keeping its base on the shelf so it enlarges upward
        // and outward — the "pulled a bit off the shelf" look. Done with a
        // Transform.scale rather than by resizing the rect, so *everything*
        // painted on the spine scales together — including the title text (a
        // fixed-size Text that would otherwise stay small while the spine grew).
        // At v == 0 the scale is 1, so the motion starts seamlessly from the
        // book's spot on the shelf.
        const maxGrow = 0.22; // up to 1.22x at full open
        final scale = 1.0 + maxGrow * v;

        // The page fades in over the second half; the book fades out as it
        // does, so none of it is left painted over the open page. On pop this
        // reverses — the page fades out and the book reappears, shrinking home.
        final pageOpacity = ((v - 0.5) / 0.5).clamp(0.0, 1.0);
        final bookOpacity = 1.0 - ((v - 0.6) / 0.4).clamp(0.0, 1.0);

        return Stack(
          children: [
            Opacity(opacity: pageOpacity, child: page),
            if (bookOpacity > 0)
              Positioned.fromRect(
                rect: bookRect,
                child: Transform.scale(
                  scale: scale,
                  // Anchor the bottom edge so the spine grows off the shelf.
                  alignment: Alignment.bottomCenter,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: bookOpacity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35 * v),
                              blurRadius: 20 * v,
                              offset: Offset(0, 8 * v),
                            ),
                          ],
                        ),
                        child: bookFace,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
