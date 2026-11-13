/// The EPUB reader's paged view: a chapter laid out once, shown a page at a
/// time (roadmap v1.4.0).
///
/// See `epub_pagination.dart` for the idea and the arithmetic. This file is the
/// part that touches the render tree: it lays the chapter column out at the
/// page's width and unbounded height (exactly what scrolled mode's scroll view
/// does, so lines wrap identically and positions carry across), measures where
/// every line and picture landed, and paints one page's slice of it.
///
/// **Why page turns are instant.** Turning changes which slice is painted and
/// nothing else — no widget rebuild, no layout. The column sits behind a
/// [RepaintBoundary], so even the chapter's drawing is reused; only the clip and
/// offset it is composited with change.
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'epub_pagination.dart';

/// Shows [child] — the chapter column — one page at a time.
///
/// [anchor] says which page; the view resolves it against its own layout every
/// time it paints, so a re-pagination (new text size, a resized window, the
/// chapter's long parse finishing) can never show a page from the old one.
/// [onPaginated] reports each new pagination so the reader can count pages and
/// turn them; it is called after the frame, never during layout.
class PagedChapterView extends StatelessWidget {
  const PagedChapterView({
    super.key,
    required this.anchor,
    required this.onPaginated,
    required this.child,
  });

  final PageAnchor anchor;
  final ValueChanged<ChapterPages> onPaginated;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => PageImageCap(
        // A picture taller than the page is scaled to fit it: there is no page
        // to put the rest of it on.
        maxHeight: constraints.maxHeight,
        child: _PagedViewport(
          anchor: anchor,
          onPaginated: onPaginated,
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

class _PagedViewport extends SingleChildRenderObjectWidget {
  const _PagedViewport({
    required this.anchor,
    required this.onPaginated,
    super.child,
  });

  final PageAnchor anchor;
  final ValueChanged<ChapterPages> onPaginated;

  @override
  RenderPagedViewport createRenderObject(BuildContext context) =>
      RenderPagedViewport(anchor, onPaginated: onPaginated);

  @override
  void updateRenderObject(
      BuildContext context, RenderPagedViewport renderObject) {
    renderObject
      ..anchor = anchor
      ..onPaginated = onPaginated;
  }
}

/// Lays its child out at unbounded height and paints one page of it.
class RenderPagedViewport extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  RenderPagedViewport(this._anchor, {required this.onPaginated});

  ValueChanged<ChapterPages> onPaginated;

  PageAnchor get anchor => _anchor;
  PageAnchor _anchor;
  set anchor(PageAnchor value) {
    if (value == _anchor) return;
    _anchor = value;
    // Paint only: a page turn never lays anything out again.
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ChapterPages? _pages;
  ChapterPages? _reported;
  bool _reportScheduled = false;

  int get _page => _pages?.pageFor(_anchor) ?? 0;
  double get _start => _pages?.starts[_page] ?? 0;
  double get _visible => _pages?.visibleHeight(_page) ?? size.height;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;
    child.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final measured = measureLines(child);
    _pages = ChapterPages.of(
      lines: measured.lines,
      pageHeight: size.height,
      contentHeight: child.size.height,
      ready: measured.ready,
    );
    _report();
  }

  void _report() {
    if (_pages == _reported || _reportScheduled) return;
    _reportScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      final pages = _pages;
      if (!attached || pages == null || pages == _reported) return;
      _reported = pages;
      onPaginated(pages);
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final start = _start;
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTWH(0, 0, size.width, _visible),
      (context, offset) => context.paintChild(child, offset + Offset(0, -start)),
      oldLayer: _clip.layer,
    );
  }

  // Held apart from [layer]: this is a repaint boundary, so [layer] is the
  // framework's own offset layer and not ours to replace.
  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, -_start, 0, 1);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      Rect.fromLTWH(0, _start, size.width, _visible);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    if (position.dy < 0 || position.dy > _visible) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, -_start),
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;
}

/// Every line of text and every picture under [root], in [root]'s coordinates
/// — what [paginate] must not cut — and whether the chapter has finished
/// building (see [ChapterLoadingMarker]).
///
/// Walks the render tree once per layout, not per page turn. Lines come from
/// each paragraph's own text boxes (at full line height, so a page break lands
/// between lines rather than through their leading); pictures are their boxes.
({List<LineSpan> lines, bool ready}) measureLines(RenderBox root) {
  final lines = <LineSpan>[];
  var ready = true;

  void visit(RenderObject node, Matrix4 transform) {
    if (node is RenderChapterLoading) {
      ready = false;
      return;
    }
    if (node is RenderParagraph) {
      final dy = transform.getTranslation().y;
      final length = node.text.toPlainText(includeSemanticsLabels: false).length;
      if (length > 0) {
        final boxes = node.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: length),
          boxHeightStyle: ui.BoxHeightStyle.max,
        );
        lines.addAll(mergeIntoLines([
          for (final box in boxes) (top: box.top + dy, bottom: box.bottom + dy),
        ]));
      }
    } else if (node is RenderImage && node.hasSize) {
      final dy = transform.getTranslation().y;
      lines.add((top: dy, bottom: dy + node.size.height));
    }
    // Into a paragraph's children too: an inline block (a WidgetSpan) has its
    // own lines, which matter when the block is taller than a page.
    node.visitChildren((child) {
      final childTransform = transform.clone();
      node.applyPaintTransform(child, childTransform);
      visit(child, childTransform);
    });
  }

  root.visitChildren((child) {
    final transform = Matrix4.identity();
    root.applyPaintTransform(child, transform);
    visit(child, transform);
  });
  return (lines: lines, ready: ready);
}

/// The tallest a picture may be drawn: the page height in paged mode, unbounded
/// in scrolled mode (where there is no ancestor of this kind).
class PageImageCap extends InheritedWidget {
  const PageImageCap({super.key, required this.maxHeight, required super.child});

  final double maxHeight;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageImageCap>()?.maxHeight ??
      double.infinity;

  @override
  bool updateShouldNotify(PageImageCap oldWidget) =>
      oldWidget.maxHeight != maxHeight;
}

/// The reader's `HtmlWidget` factory: pictures held to the page height, and a
/// placeholder the paged view can recognise while a long chapter builds.
///
/// Pictures read the cap through an inherited widget rather than a factory
/// field so that a new page height — a resized window, the toolbar hidden —
/// rebuilds the pictures and nothing else. Changing a field would mean a new
/// `HtmlWidget`, and a long chapter parsed all over again.
class ReaderHtmlFactory extends WidgetFactory {
  @override
  Widget? buildImage(BuildTree tree, ImageMetadata data) {
    final built = super.buildImage(tree, data);
    if (built == null) return null;
    return Builder(
      builder: (context) {
        final cap = PageImageCap.of(context);
        if (cap == double.infinity) return built;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: cap),
          child: built,
        );
      },
    );
  }

  @override
  Widget? onLoadingBuilder(
    BuildContext context,
    BuildTree tree, [
    double? loadingProgress,
    dynamic data,
  ]) {
    final built = super.onLoadingBuilder(context, tree, loadingProgress, data);
    // Only the whole-chapter placeholder: a picture's progress passes its
    // source as [data].
    if (data != null || built == null) return built;
    return ChapterLoadingMarker(child: built);
  }
}

/// Wraps the placeholder shown while a chapter is still being built, so the
/// paged view knows its one "page" is not the chapter's.
///
/// Without it, pressing → twice at the end of a chapter would skip the next
/// one: the second press arrives while the next chapter is still parsing, sees
/// a chapter of one page, and turns past it.
class ChapterLoadingMarker extends SingleChildRenderObjectWidget {
  const ChapterLoadingMarker({super.key, super.child});

  @override
  RenderChapterLoading createRenderObject(BuildContext context) =>
      RenderChapterLoading();
}

class RenderChapterLoading extends RenderProxyBox {}
