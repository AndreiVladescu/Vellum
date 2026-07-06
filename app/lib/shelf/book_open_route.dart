import 'dart:math';

import 'package:flutter/material.dart';

/// Route that animates a book being taken off the shelf:
///
/// 1. **Lift** — the spine slides up out of the shelf row;
/// 2. **Flip** — it travels toward the screen center while rotating 180° in
///    3D, revealing the front cover (the spine's "back face");
/// 3. **Open** — the cover fades into the detail page, like opening the book.
///
/// Popping the route plays the whole thing in reverse.
class BookOpenRoute extends PageRouteBuilder<void> {
  BookOpenRoute({
    required Rect spineRect,
    required Widget spineFace,
    required Widget coverFace,
    required WidgetBuilder detailBuilder,
  }) : super(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 700),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, secondaryAnimation) =>
              Builder(builder: detailBuilder),
          transitionsBuilder: (context, animation, secondaryAnimation, page) {
            return _BookOpenTransition(
              animation: animation,
              spineRect: spineRect,
              spineFace: spineFace,
              coverFace: coverFace,
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
    required this.coverFace,
    required this.page,
  });

  final Animation<double> animation;
  final Rect spineRect;
  final Widget spineFace;
  final Widget coverFace;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final v = curved.value;
        final size = MediaQuery.sizeOf(context);

        // Where the flipped-open cover ends up: centered, book-like aspect.
        final targetH = min(size.height * 0.62, 460.0);
        final target = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: targetH * 2 / 3,
          height: targetH,
        );

        // Phase 1 (0–0.2): lift out of the shelf.
        final lifted = spineRect.translate(0, -spineRect.height * 0.22);
        // Phase 2 (0.2–0.8): travel to center while flipping.
        final travel = ((v - 0.2) / 0.6).clamp(0.0, 1.0);
        final rect = v < 0.2
            ? Rect.lerp(spineRect, lifted, v / 0.2)!
            : Rect.lerp(lifted, target, travel)!;
        final flip = ((v - 0.22) / 0.56).clamp(0.0, 1.0) * pi;
        // Phase 3 (0.78–1): the book "opens" — page in, book out.
        final pageOpacity = ((v - 0.78) / 0.22).clamp(0.0, 1.0);
        final bookOpacity = 1.0 - ((v - 0.86) / 0.14).clamp(0.0, 1.0);

        // Until 90° we look at the spine; past it, the front cover
        // (pre-mirrored so it reads correctly when the flip completes).
        final face = flip <= pi / 2
            ? spineFace
            : Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(pi),
                child: coverFace,
              );

        return Stack(
          children: [
            Opacity(opacity: pageOpacity, child: page),
            if (bookOpacity > 0)
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: bookOpacity,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012) // perspective
                        ..rotateY(flip),
                      child: face,
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
