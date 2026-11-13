import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A left-to-right gradient, painted from a small image of itself instead of
/// as a gradient (performance round, November 2026).
///
/// Every spine is shaded by a horizontal gradient — a highlight on the left, a
/// shade on the right — so a shelf draws a hundred gradients a frame. On
/// Impeller's OpenGL ES backend (the Linux desktop, and Android devices without
/// Vulkan) each gradient draw costs about 0.15 ms of raster time: a screen of
/// gradient boxes took ~17 ms to rasterise against ~2 ms in flat colours, and
/// a fifth of the shelf's frames missed 60 Hz. A gradient drawn once into a
/// 256 × 1 image and stretched over the box is one textured quad: the shelf's
/// raster p90 went from 21 ms to 7 ms, and its janky frames from ~75 in a
/// 6-second scroll to one (docs/PERFORMANCE.md).
///
/// The image is the *same gradient*, drawn by the same engine, so the colours
/// are the engine's own; stretching it bilinearly reproduces a linear ramp
/// exactly between samples, and 256 samples across a spine a few dozen pixels
/// wide leaves at most one or two levels of rounding — `gradient_strip_test`
/// compares the pixels.
@immutable
class GradientStrip {
  const GradientStrip(this.colors, this.stops);

  final List<Color> colors;
  final List<double> stops;

  /// Samples across the ramp. Far more than any spine is wide, so the stretch
  /// only ever magnifies.
  static const width = 256;

  /// Strips already drawn, oldest first. A generated spine's ramp depends on
  /// its colour, and the dominant-colour artwork gives every covered book a
  /// colour of its own — so this is bounded, at 1 KB a strip.
  static final _images = <GradientStrip, ui.Image>{};
  static const _cap = 512;

  ui.Image get image {
    final hit = _images.remove(this);
    if (hit != null) return _images[this] = hit;
    if (_images.length >= _cap) {
      _images.remove(_images.keys.first)?.dispose();
    }
    return _images[this] = _draw();
  }

  ui.Image _draw() {
    final recorder = ui.PictureRecorder();
    const rect = Rect.fromLTWH(0, 0, width + 0.0, 1);
    Canvas(recorder).drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.src
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          colors,
          stops,
        ),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, 1);
    picture.dispose();
    return image;
  }

  /// Fills [bounds] with the strip, its top corners rounded by [topRadius].
  ///
  /// `drawImageRect`, not an `ImageShader` on a rounded rectangle: Impeller
  /// draws the former as one textured quad, and the latter measured *slower*
  /// than the gradient it replaced (46 ms against 21 ms at p90 for a screen of
  /// them). The rounded corners are a clip, which costs little.
  void paint(Canvas canvas, Rect bounds, {double topRadius = 0}) {
    final paint = Paint()..filterQuality = FilterQuality.low;
    const src = Rect.fromLTWH(0, 0, width + 0.0, 1);
    if (topRadius <= 0) {
      canvas.drawImageRect(image, src, bounds, paint);
      return;
    }
    // The clip anti-aliases the edges; the draw inside it must not as well,
    // or a fractional edge (most spines' right one) gets its partial coverage
    // applied twice and comes out lighter than the shape it replaces.
    paint.isAntiAlias = false;
    final radius = Radius.circular(topRadius);
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndCorners(bounds, topLeft: radius, topRight: radius),
      )
      ..drawImageRect(image, src, bounds, paint)
      ..restore();
  }

  @override
  bool operator ==(Object other) =>
      other is GradientStrip &&
      _listEquals(other.colors, colors) &&
      _listEquals(other.stops, stops);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(colors), Object.hashAll(stops));

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Paints a [GradientStrip] behind its child, filling the box, with the top
/// corners rounded by [topRadius] — what a `DecoratedBox` with a horizontal
/// `LinearGradient` and `BorderRadius.vertical(top: …)` paints, at a fraction
/// of the raster cost.
class GradientStripBox extends SingleChildRenderObjectWidget {
  const GradientStripBox({
    super.key,
    required this.strip,
    this.topRadius = 0,
    super.child,
  });

  final GradientStrip strip;
  final double topRadius;

  @override
  RenderGradientStripBox createRenderObject(BuildContext context) =>
      RenderGradientStripBox(strip, topRadius);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGradientStripBox renderObject,
  ) {
    renderObject
      ..strip = strip
      ..topRadius = topRadius;
  }
}

class RenderGradientStripBox extends RenderProxyBox {
  RenderGradientStripBox(this._strip, this._topRadius);

  GradientStrip _strip;
  set strip(GradientStrip value) {
    if (value == _strip) return;
    _strip = value;
    markNeedsPaint();
  }

  double _topRadius;
  set topRadius(double value) {
    if (value == _topRadius) return;
    _topRadius = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _strip.paint(context.canvas, offset & size, topRadius: _topRadius);
    super.paint(context, offset);
  }
}
