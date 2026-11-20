import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

/// Built-in library wallpapers. Each adapts to light/dark theme.
enum Wallpaper {
  parchment,
  fern,
  ocean;
}

/// Paints the selected wallpaper behind [child].
class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({
    super.key,
    required this.wallpaper,
    required this.child,
  });

  final Wallpaper wallpaper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final view = View.of(context);
    final ramp = _VerticalRamp(switch ((wallpaper, dark)) {
      (Wallpaper.parchment, false) => const [
        Color(0xFFFAF4E8),
        Color(0xFFEBDCC3),
      ],
      (Wallpaper.parchment, true) => const [
        Color(0xFF262019),
        Color(0xFF171310),
      ],
      (Wallpaper.fern, false) => const [Color(0xFFFCFCFA), Color(0xFFEFEEE7)],
      (Wallpaper.fern, true) => const [Color(0xFF1F231E), Color(0xFF131511)],
      (Wallpaper.ocean, false) => const [Color(0xFFF0F6FB), Color(0xFFD3E2EF)],
      (Wallpaper.ocean, true) => const [Color(0xFF19202C), Color(0xFF0E1219)],
    });
    if (wallpaper != Wallpaper.fern) {
      return CustomPaint(painter: ramp, child: child);
    }
    return CustomPaint(
      painter: ramp,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: FernPainter(
                color: dark ? const Color(0x3D6E9960) : const Color(0x2E4C7A3F),
                // How far the keyboard has eaten into the window, taken from
                // the *view* rather than the MediaQuery.
                //
                // A Scaffold with `resizeToAvoidBottomInset` applies the inset
                // by shrinking its body and then zeroes it in the MediaQuery it
                // hands down — so `MediaQuery.viewInsetsOf` here always reads
                // 0, and a fix built on it does nothing at all. Confirmed on a
                // device: the fronds still climbed. The view's own insets are
                // in physical pixels, hence the ratio.
                bottomInset: view.viewInsets.bottom / view.devicePixelRatio,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// The wallpaper's top-to-bottom gradient, filling the box.
///
/// Drawn into a small 1 × [_height] box and scaled up to the real size, rather
/// than as a `BoxDecoration` gradient. Since Flutter 3.50, Impeller's OpenGL ES
/// backend (the Linux desktop) works out where a pixel sits along a gradient
/// on a rectangle in 16-bit floats, which overflow once position × gradient
/// length passes 65504 (flutter/flutter#196865): on a 720 px window the
/// parchment ramp stopped about 130 px down and the rest of the shelf was flat
/// end colour, with a hard edge. In the small box that product is at most
/// 128 × 128; the scale is applied after, by the GPU, so the colours are the
/// same ramp. Once the pinned Flutter has the fix this can go back to a
/// `BoxDecoration` with a `LinearGradient`.
class _VerticalRamp extends CustomPainter {
  const _VerticalRamp(this.colors);

  final List<Color> colors;

  static const _height = 128.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width, size.height / _height);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, _height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0, _height),
          colors,
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VerticalRamp oldDelegate) =>
      !listEquals(colors, oldDelegate.colors);
}

/// A few soft fern fronds growing out of the bottom-left corner.
///
/// Public so a test can assert the widget hands it the keyboard inset; there
/// is nothing else to configure.
class FernPainter extends CustomPainter {
  const FernPainter({required this.color, this.bottomInset = 0});

  final Color color;

  /// The keyboard's height, when one is open.
  ///
  /// The canvas is the Scaffold body, which shrinks to sit above the keyboard.
  /// Anchoring to that edge made the fronds climb the page every time someone
  /// typed — the wall behind a shelf does not move when a keyboard appears.
  /// Adding it back puts the anchor where the bottom of the screen still is.
  final double bottomInset;

  @override
  void paint(Canvas canvas, Size size) {
    // Anchored to the bottom-left corner with fixed pixel offsets and lengths,
    // so the fronds don't slide or scale as the window is resized.
    final h = size.height + bottomInset;
    _frond(canvas, Offset(26, h + 8), -1.35, 300);
    _frond(canvas, Offset(-4, h + 2), -0.95, 235);
    _frond(canvas, Offset(58, h + 8), -1.72, 210);
  }

  void _frond(Canvas canvas, Offset base, double angle, double length) {
    final dir = Offset(cos(angle), sin(angle));
    final normal = Offset(-dir.dy, dir.dx);
    final p0 = base;
    final p2 = base + dir * length;
    final p1 = base + dir * (length * 0.5) + normal * (length * 0.18);

    final stemPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(p0.dx, p0.dy)
        ..quadraticBezierTo(p1.dx, p1.dy, p2.dx, p2.dy),
      stemPaint,
    );

    final leafPaint = Paint()..color = color;
    const leaflets = 12;
    for (var i = 1; i <= leaflets; i++) {
      final t = i / (leaflets + 1);
      // Point and tangent on the quadratic bezier stem.
      final point = p0 * pow(1 - t, 2).toDouble() +
          p1 * (2 * (1 - t) * t) +
          p2 * (t * t);
      final tangent = (p1 - p0) * (2 * (1 - t)) + (p2 - p1) * (2 * t);
      final stemAngle = tangent.direction;
      final leafLen = length * 0.20 * (1 - t) + 6;
      for (final side in const [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(stemAngle + side * 1.05);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(leafLen / 2, 0),
            width: leafLen,
            height: leafLen * 0.30,
          ),
          leafPaint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(FernPainter oldDelegate) =>
      color != oldDelegate.color || bottomInset != oldDelegate.bottomInset;
}
