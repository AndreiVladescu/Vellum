import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A blurred text shadow, drawn once into an image and reused on every frame
/// after (performance round, November 2026).
///
/// A cover-slice spine's title has a soft dark shadow so it reads over any
/// artwork. A text shadow is a *blur*: every frame, for every title, the engine
/// draws the glyphs into an offscreen buffer and blurs them. The physical room
/// draws 400 titles a frame, and that was nearly all of its raster time — 58
/// ms at p90 panning, against 13 with the shadow switched off
/// (docs/PERFORMANCE.md). The shadow of a given title never changes while the
/// room pans, so this draws it once, through the engine's own text shadow, into
/// an image the size of the title plus the blur's reach, and from then on
/// paints that image — one textured quad — under the crisp title.
///
/// Usage: wrap a plain [Text] (one string, one style) whose style has **no**
/// shadow, and pass the shadow here:
///
/// ```dart
/// CachedTextShadow(
///   shadow: Shadow(blurRadius: 4, color: Color(0xB3000000)),
///   child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
/// )
/// ```
///
/// The image is the engine's own rendering of the same paragraph at the same
/// device pixel ratio, so it is the same pixels — `text_shadow_cache_test`
/// compares them against a `Text` with the shadow in its style. It takes only
/// a plain `Text`: several spans, or a fading overflow, it cannot reproduce.
class CachedTextShadow extends SingleChildRenderObjectWidget {
  const CachedTextShadow({
    super.key,
    required this.shadow,
    required Text super.child,
  });

  final Shadow shadow;

  @override
  RenderCachedTextShadow createRenderObject(BuildContext context) =>
      RenderCachedTextShadow(shadow, MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCachedTextShadow renderObject,
  ) {
    renderObject
      ..shadow = shadow
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderCachedTextShadow extends RenderProxyBox {
  RenderCachedTextShadow(this._shadow, this._devicePixelRatio);

  Shadow _shadow;
  set shadow(Shadow value) {
    if (value == _shadow) return;
    _shadow = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// What this box drew last, and its own handle on the image (a clone, so the
  /// shared cache can let go of it without pulling it out from under a frame).
  _ShadowKey? _key;
  _ShadowImage? _image;

  /// The key of a cut-off this box has seen once and not drawn yet.
  ///
  /// Zooming the room moves every title's ellipsis a character or two a frame,
  /// and drawing a new shadow for each of 400 titles on every frame of a zoom
  /// cost more than the blur it replaces. So while the cut-off is moving, the
  /// box keeps showing the shadow it has — the same title, the same glyphs up
  /// to the ellipsis, clipped to the box — and draws the new one once the
  /// cut-off has held still for a frame, a few dozen titles a frame at most
  /// ([TextShadowCache.changesPerFrame]). Another frame is asked for each time,
  /// so the last ones are drawn even when the zoom has stopped.
  _ShadowKey? _pending;
  bool _refreshScheduled = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final paragraph = child is RenderParagraph ? child : null;
    final key = paragraph == null
        ? null
        : _ShadowKey.of(paragraph, _shadow, _devicePixelRatio);
    assert(
      key != null,
      'CachedTextShadow needs a plain Text (one string, no fading overflow).',
    );
    if (paragraph != null && key != null) {
      if (key != _key) _update(key, paragraph);
      _image!.paint(context.canvas, offset, paragraph);
    }
    super.paint(context, offset);
  }

  void _update(_ShadowKey key, RenderParagraph paragraph) {
    final cache = TextShadowCache.instance;
    final image = _image;
    final old = _key;
    if (image != null &&
        old != null &&
        key.sameTextAs(old) &&
        !cache._has(key) &&
        (key != _pending || !cache._mayDrawChange())) {
      _pending = key;
      _scheduleRefresh();
      return;
    }
    image?.dispose();
    _image = cache._lookup(key, paragraph);
    _key = key;
    _pending = null;
  }

  void _scheduleRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (attached && _pending != null) markNeedsPaint();
    }, debugLabel: 'CachedTextShadow.refresh');
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

/// Everything the shadow's pixels depend on. Two paragraphs with equal keys
/// draw identical shadows.
@immutable
class _ShadowKey {
  const _ShadowKey({
    required this.text,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.maxLines,
    required this.overflow,
    required this.locale,
    required this.strutStyle,
    required this.textWidthBasis,
    required this.textHeightBehavior,
    required this.shadow,
    required this.devicePixelRatio,
    required this.lineBreak,
  });

  final TextSpan text;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final int? maxLines;
  final TextOverflow overflow;
  final Locale? locale;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Shadow shadow;
  final double devicePixelRatio;

  /// Where the lines break, when that depends on the width. Null when the text
  /// is one start-aligned line that fits: then it is drawn at the same place
  /// whatever the width. Otherwise the boxes of the text as laid out — which
  /// change only when another character fits, so zooming the room does not
  /// make a new image on every frame while the ellipsis stays where it was.
  final List<double>? lineBreak;

  /// The key for [p] as laid out, or null when the cache cannot reproduce it.
  static _ShadowKey? of(RenderParagraph p, Shadow shadow, double dpr) {
    final text = p.text;
    if (text is! TextSpan || text.children != null || text.text == null) {
      return null;
    }
    if (p.overflow == TextOverflow.fade) return null;
    final startAligned = switch (p.textAlign) {
      TextAlign.left => true,
      TextAlign.start => p.textDirection == TextDirection.ltr,
      _ => false,
    };
    List<double>? lineBreak;
    if (!startAligned || p.didExceedMaxLines) {
      final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.text!.length),
      );
      lineBreak = [
        // The width itself when the alignment depends on it.
        if (!startAligned) p.size.width,
        for (final b in boxes) ...[b.left, b.top, b.right, b.bottom],
      ];
    }
    return _ShadowKey(
      text: text,
      textAlign: p.textAlign,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      maxLines: p.maxLines,
      overflow: p.overflow,
      locale: p.locale,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
      textHeightBehavior: p.textHeightBehavior,
      shadow: shadow,
      devicePixelRatio: dpr,
      lineBreak: lineBreak,
    );
  }

  /// Whether [other] is the same text drawn the same way, cut off at a
  /// different place.
  bool sameTextAs(_ShadowKey other) =>
      _ShadowKey(
        text: other.text,
        textAlign: other.textAlign,
        textDirection: other.textDirection,
        textScaler: other.textScaler,
        maxLines: other.maxLines,
        overflow: other.overflow,
        locale: other.locale,
        strutStyle: other.strutStyle,
        textWidthBasis: other.textWidthBasis,
        textHeightBehavior: other.textHeightBehavior,
        shadow: other.shadow,
        devicePixelRatio: other.devicePixelRatio,
        lineBreak: lineBreak,
      ) ==
      this;

  @override
  bool operator ==(Object other) =>
      other is _ShadowKey &&
      other.text == text &&
      other.textAlign == textAlign &&
      other.textDirection == textDirection &&
      other.textScaler == textScaler &&
      other.maxLines == maxLines &&
      other.overflow == overflow &&
      other.locale == locale &&
      other.strutStyle == strutStyle &&
      other.textWidthBasis == textWidthBasis &&
      other.textHeightBehavior == textHeightBehavior &&
      other.shadow == shadow &&
      other.devicePixelRatio == devicePixelRatio &&
      listEquals(other.lineBreak, lineBreak);

  @override
  int get hashCode => Object.hash(
        text,
        textAlign,
        textDirection,
        textScaler,
        maxLines,
        overflow,
        locale,
        strutStyle,
        textWidthBasis,
        textHeightBehavior,
        shadow,
        devicePixelRatio,
        lineBreak == null ? null : Object.hashAll(lineBreak!),
      );
}

/// A drawn shadow: the image, and where it sits relative to the paragraph.
class _ShadowImage {
  _ShadowImage(this.image, this.pad, this.textSize, this.devicePixelRatio);

  final ui.Image image;

  /// How far the image reaches past the paragraph's top-left, in logical
  /// pixels — the blur's spread.
  final double pad;

  /// The paragraph's own size as it was laid out for the drawing.
  final Size textSize;
  final double devicePixelRatio;

  int get bytes => image.width * image.height * 4;

  _ShadowImage clone() =>
      _ShadowImage(image.clone(), pad, textSize, devicePixelRatio);

  void dispose() => image.dispose();

  void paint(Canvas canvas, Offset offset, RenderParagraph paragraph) {
    // A paragraph that overflowed clips everything it draws — its shadow
    // included — to its own box (RenderParagraph.paint). So must this.
    final size = paragraph.size;
    final clip = paragraph.overflow != TextOverflow.visible &&
        (paragraph.didExceedMaxLines ||
            size.height < textSize.height ||
            size.width < textSize.width);
    if (clip) {
      canvas
        ..save()
        ..clipRect(offset & size);
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width + 0.0, image.height + 0.0),
      Rect.fromLTWH(
        offset.dx - pad,
        offset.dy - pad,
        image.width / devicePixelRatio,
        image.height / devicePixelRatio,
      ),
      Paint()..filterQuality = FilterQuality.low,
    );
    if (clip) canvas.restore();
  }
}

/// The shared store of drawn shadows, least recently used first out.
class TextShadowCache with WidgetsBindingObserver {
  TextShadowCache._();

  static final instance = TextShadowCache._();

  /// What the cache may hold, in decoded bytes. A box keeps its own handle on
  /// the image it is showing, so this bounds only what is kept for titles that
  /// come back (a shelf scrolled back, the room reopened) — not what is on
  /// screen. 16 MB is ~2,000 room titles or ~800 shelf ones at 1×.
  static const maxBytes = 16 << 20;

  final _images = <_ShadowKey, _ShadowImage>{}; // insertion-ordered
  int _bytes = 0;

  /// How many images the cache holds now.
  int get length => _images.length;

  /// What the cache holds, in decoded bytes. A box's clone of an image shares
  /// the cache's pixels (`Image.clone` is another handle, not a copy), so this
  /// is the memory the shadows cost, but for images only a box still holds
  /// after the cache let go of them.
  int get bytes => _bytes;

  bool _observing = false;

  /// Lets go of every stored image when the system is short of memory. Boxes
  /// keep the one they show (it is on screen), so a frame never loses a shadow;
  /// what is dropped is the store for titles that are not showing.
  @override
  void didHaveMemoryPressure() => trim();

  /// Empties the store; the images boxes hold stay alive until they let go.
  void trim() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }

  /// How many shadows have been drawn since the start; for tests.
  @visibleForTesting
  int drawn = 0;

  @visibleForTesting
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
    drawn = 0;
  }

  bool _has(_ShadowKey key) => _images.containsKey(key);

  /// How many shadows a frame may redraw because a title's cut-off moved. A
  /// title appearing for the first time is drawn regardless — it has nothing
  /// else to show.
  static const changesPerFrame = 24;
  Duration? _budgetFrame;
  int _budgetUsed = 0;

  bool _mayDrawChange() {
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (frame != _budgetFrame) {
      _budgetFrame = frame;
      _budgetUsed = 0;
    }
    if (_budgetUsed >= changesPerFrame) return false;
    _budgetUsed++;
    return true;
  }

  /// A clone of the image for [key], drawn from [paragraph] if it is new. The
  /// caller owns the clone.
  _ShadowImage _lookup(_ShadowKey key, RenderParagraph paragraph) {
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit;
      return hit.clone();
    }
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    final made = _draw(key, paragraph);
    _images[key] = made;
    _bytes += made.bytes;
    while (_bytes > maxBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      final gone = _images.remove(oldest)!;
      _bytes -= gone.bytes;
      gone.dispose();
    }
    return made.clone();
  }

  /// Lays the paragraph out again with a transparent fill and the shadow, as
  /// [RenderParagraph] would, and records only the shadow into an image.
  _ShadowImage _draw(_ShadowKey key, RenderParagraph p) {
    drawn++;
    final dpr = key.devicePixelRatio;
    final shadow = key.shadow;
    final painter = TextPainter(
      text: TextSpan(
        text: key.text.text,
        style: (key.text.style ?? const TextStyle()).copyWith(
          // The fill is drawn by the child, crisp, every frame; the image is
          // only what the shadow adds. The engine draws a shadow whatever the
          // fill's colour.
          color: const Color(0x00000000),
          shadows: [shadow],
        ),
        locale: key.text.locale,
        spellOut: key.text.spellOut,
      ),
      textAlign: key.textAlign,
      textDirection: key.textDirection,
      textScaler: key.textScaler,
      maxLines: key.maxLines,
      ellipsis: key.overflow == TextOverflow.ellipsis ? '…' : null,
      locale: key.locale,
      strutStyle: key.strutStyle,
      textWidthBasis: key.textWidthBasis,
      textHeightBehavior: key.textHeightBehavior,
    );
    final c = p.constraints;
    painter.layout(
      minWidth: c.minWidth,
      maxWidth: p.softWrap || p.overflow == TextOverflow.ellipsis
          ? c.maxWidth
          : double.infinity,
    );
    // Three sigmas hold all but a fraction of a level of a Gaussian; the extra
    // pixel is for rounding. Measured in logical pixels, which is the larger
    // reading whether the engine scales the blur with the canvas or not — and
    // rounded to whole *device* pixels, so that a paragraph that sits on the
    // pixel grid gets its image drawn on the grid too, unresampled.
    final reach = (shadow.blurSigma * 3).ceilToDouble() +
        shadow.offset.distance.ceilToDouble() +
        1;
    final pad = (reach * dpr).ceilToDouble() / dpr;
    final size = painter.size;
    final width = ((size.width + 2 * pad) * dpr).ceil();
    final height = ((size.height + 2 * pad) * dpr).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(dpr)
      ..translate(pad, pad);
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    painter.dispose();
    return _ShadowImage(image, pad, size, dpr);
  }
}
