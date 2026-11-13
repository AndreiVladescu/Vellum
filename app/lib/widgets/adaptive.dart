import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'page_insets.dart';

/// The Material 3 window-size classes, by width.
///
/// Three, because the app has three layouts and no more: a phone held upright
/// (*compact*), a phone on its side or a tablet held upright (*medium*), and a
/// tablet on its side or a desktop window (*expanded*). The numbers are
/// Material's own, so a tablet lands where every other app on it does.
enum WindowSize {
  /// Under 600: the bottom navigation bar and a modal drawer.
  compact,

  /// 600 to 840: a navigation rail down the side; the drawer stays modal.
  medium,

  /// 840 and over: the drawer is always open beside the content.
  expanded;

  static const double mediumFrom = 600;
  static const double expandedFrom = 840;

  static WindowSize ofWidth(double width) => width < mediumFrom
      ? compact
      : width < expandedFrom
          ? medium
          : expanded;

  /// For a widget that fills the window — the shell, a pushed page. Uses
  /// `sizeOf` rather than `of` so only a size change rebuilds the caller, not
  /// every keyboard inset or text-scale change.
  static WindowSize of(BuildContext context) =>
      ofWidth(MediaQuery.sizeOf(context).width);
}

/// How wide a list or settings page grows before it stops and centres itself.
///
/// Past this a line of text is too long to read comfortably and a switch at
/// the end of a row is a long way from the words it belongs to.
const double readableWidth = 720;

/// [pageInsets], plus enough side padding to centre the content in
/// [maxWidth] once the window is wider than that.
///
/// **Padding, not a `Center` around the list.** Wrapping the scroll view would
/// shrink it too: the scrollbar would float in the middle of the window and the
/// mouse wheel would do nothing over the empty margins. Padding *inside* the
/// scroll view keeps it full-width and only moves the content.
///
/// Measures the window, so it is for a page that fills it — which every page
/// pushed with `Navigator.push` does.
EdgeInsets readableInsets(
  BuildContext context,
  EdgeInsets base, {
  double maxWidth = readableWidth,
}) =>
    pageInsets(context, base) +
    _centring(MediaQuery.sizeOf(context).width, maxWidth);

EdgeInsets _centring(double available, double maxWidth) =>
    EdgeInsets.symmetric(horizontal: math.max(0, (available - maxWidth) / 2));

/// A scrolling page that is one column when narrow and two side by side when
/// wide: [lead] on the left, a fixed [leadWidth], and [rest] taking what is
/// left.
///
/// For a page with a "who is this" part and a "everything about it" part — a
/// book's cover, title and read button, then its formats, copies and notes. On
/// a phone the two simply follow each other, exactly as one list would; on a
/// tablet on its side the first stays in view beside the second instead of
/// every row stretching a whole landscape wide.
///
/// Children are laid out as a `ListView` lays them out (stretched to the
/// column's width), so a widget written for the one-column page needs no
/// change to sit in either column.
class TwoColumnList extends StatelessWidget {
  const TwoColumnList({
    super.key,
    required this.padding,
    required this.lead,
    required this.rest,
    // Wider than a phone, so nothing that fits on one needs to reflow here —
    // the book page's read-button row in particular is laid out for a phone.
    this.leadWidth = 460,
    this.gap = 32,
    this.narrowMaxWidth = readableWidth,
    this.wideMaxWidth = 1200,
  });

  /// The page's own padding, before the system inset and centring are added.
  final EdgeInsets padding;
  final List<Widget> lead;
  final List<Widget> rest;
  final double leadWidth;
  final double gap;

  /// How wide the single column may grow before it centres.
  final double narrowMaxWidth;

  /// How wide the pair of columns may grow before they centre.
  final double wideMaxWidth;

  @override
  Widget build(BuildContext context) {
    // The space this page actually has, not the window: correct even if the
    // page is ever shown in a pane rather than as a whole route.
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final base = pageInsets(context, padding);
      if (WindowSize.ofWidth(width) != WindowSize.expanded) {
        return ListView(
          padding: base + _centring(width, narrowMaxWidth),
          children: [...lead, ...rest],
        );
      }
      return ListView(
        padding: base + _centring(width, wideMaxWidth),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: leadWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: lead,
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rest,
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}
