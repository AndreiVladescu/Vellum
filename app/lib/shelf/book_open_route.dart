import 'package:flutter/material.dart';

/// Route that animates a book being eased partway out of the shelf: the tapped
/// spine grows a little — as if pulled forward off the shelf — while the detail
/// page fades in over it. Popping the route reverses it, so the book shrinks
/// back to its original size and slots back onto the shelf.
class BookOpenRoute extends PageRouteBuilder<void> {
  BookOpenRoute({
    required Rect spineRect,
    required Widget spineFace,
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
              spineRect: spineRect,
              spineFace: spineFace,
              page: page,
            );
          },
        );
}

class _BookOpenTransition extends StatelessWidget {
  const _BookOpenTransition({
    required this.animation,
    required this.spineRect,
    required this.spineFace,
    required this.page,
  });

  final Animation<double> animation;
  final Rect spineRect;
  final Widget spineFace;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final v = curved.value;

        // Enlarge the spine, keeping its base on the shelf so it grows upward
        // and outward — the "pulled a bit off the shelf" look. At v == 0 the
        // rect is exactly the spine's spot, so the animation starts seamlessly.
        const maxGrow = 0.22; // up to 1.22× at full open
        final scale = 1.0 + maxGrow * v;
        final w = spineRect.width * scale;
        final h = spineRect.height * scale;
        final rect = Rect.fromLTWH(
          spineRect.center.dx - w / 2,
          spineRect.bottom - h,
          w,
          h,
        );

        // The detail page fades in over the second half, so you see the book
        // ease out first; on pop it fades back out and the book shrinks home.
        final pageOpacity =
            Curves.easeIn.transform(((v - 0.5) / 0.5).clamp(0.0, 1.0));

        return Stack(
          children: [
            Opacity(opacity: pageOpacity, child: page),
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35 * v),
                        blurRadius: 20 * v,
                        offset: Offset(0, 8 * v),
                      ),
                    ],
                  ),
                  child: spineFace,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
