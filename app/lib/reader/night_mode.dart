/// Night mode: black pages, white type, pictures in grey.
///
/// **Two mechanisms, because the two formats are not the same kind of thing.**
/// An EPUB is text this app lays out, so it is simply *drawn* dark — the page
/// colour and the type colour are ours to choose, and only the pictures need
/// treating. A PDF page is a picture of a page; nothing in it can be restyled,
/// so the only lever is to filter the pixels, and the filter necessarily hits
/// everything on the page at once.
///
/// That difference is why highlights keep their colours in an EPUB and go muted
/// in a PDF. It is not an oversight: a highlight on a PDF page is painted onto
/// the same canvas as the page, so no filter that greys out a photograph can
/// spare it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// The filter that turns a rendered PDF page into a dark one.
///
/// Not a naive `1 - x` invert. Two things are done at once:
///
/// - **Desaturate**, keeping a tenth of the original chroma. Photographs and
///   coloured diagrams come out in greys rather than as colour negatives, which
///   is the thing that makes a plain inversion unreadable — a portrait turns
///   blue and a red warning box turns cyan.
/// - **Invert the luminance**, and land on 240 rather than 255 so black ink
///   becomes a soft off-white instead of glaring at you in a dark room.
///
/// The rows are the desaturation mix (Rec. 601 luma weights, blended 9:1 toward
/// grey) scaled by 0.90 and negated, which is the inversion.
const nightModeMatrix = <double>[
  // R'      G'      B'      A'  offset
  -0.3322, -0.4755, -0.0923, 0, 240, //
  -0.2422, -0.5655, -0.0923, 0, 240, //
  -0.2422, -0.4755, -0.1823, 0, 240, //
  0, 0, 0, 1, 0, //
];

/// Pictures inside an EPUB: all colour removed, and dimmed a little.
///
/// Dimmed as well as greyed because a photograph that was mostly white still
/// ends up mostly white, and a bright rectangle on a black page is exactly what
/// dark mode is for avoiding. Text is untouched by this — it is already drawn
/// in the reader's own near-white, and removing colour from near-white does
/// nothing.
const greyImageMatrix = <double>[
  0.2126 * 0.8, 0.7152 * 0.8, 0.0722 * 0.8, 0, 0, //
  0.2126 * 0.8, 0.7152 * 0.8, 0.0722 * 0.8, 0, 0, //
  0.2126 * 0.8, 0.7152 * 0.8, 0.0722 * 0.8, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Renders an EPUB's pictures in grey.
///
/// A factory rather than `customWidgetBuilder`: the builder *replaces* an
/// element, which would mean re-implementing image loading, sizing and data-URI
/// decoding to change one colour. Overriding [buildImage] lets the package do
/// all of that and wraps whatever it produced.
class NightModeFactory extends WidgetFactory {
  @override
  Widget? buildImage(BuildTree tree, ImageMetadata data) {
    final built = super.buildImage(tree, data);
    if (built == null) return null;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(greyImageMatrix),
      child: built,
    );
  }
}

/// Strips the colours a book asked for out of its own markup.
///
/// **Why the markup and not a style override.** `customStylesBuilder` loses to
/// an element's `style` attribute, which is exactly where a book puts
/// `color: #222` — so on a dark page its headings stayed black on black and
/// simply vanished. The declaration has to be gone, not outranked.
///
/// Backgrounds go too: a book's white callout box, left alone, is white type on
/// white in the middle of a dark page. What is left is the reader's own colours,
/// which is the whole point of the setting.
///
/// Everything else in the style attribute — margins, alignment, font sizes, the
/// author's actual layout — is untouched.
String withoutBookColours(String html) {
  var out = html.replaceAllMapped(_styleAttribute, (match) {
    final quote = match[1]!;
    final cleaned = match[2]!.replaceAll(_colourDeclaration, '').trim();
    return cleaned.isEmpty ? '' : 'style=$quote$cleaned$quote';
  });
  // The presentational attributes that predate CSS and still turn up in books
  // converted from other formats.
  out = out.replaceAll(_colourAttribute, '');
  return out;
}

final _styleAttribute = RegExp(
  '''style\\s*=\\s*(["'])(.*?)\\1''',
  caseSensitive: false,
  dotAll: true,
);

/// `color` and `background-color`, but not `border-color` and not the `color`
/// inside a longer property name — hence the lookbehind.
final _colourDeclaration = RegExp(
  r'(?:(?<![-\w])color|background-color|background)\s*:[^;]*;?',
  caseSensitive: false,
);

final _colourAttribute = RegExp(
  '''\\s(?:color|bgcolor|text)\\s*=\\s*(["'])[^"']*\\1''',
  caseSensitive: false,
);

/// The 5x4 matrix that changes nothing — night mode off, expressed as a filter
/// rather than as the absence of one. See [nightModeWrap].
const identityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Applies [nightModeMatrix] to [child] when [enabled].
///
/// One wrap around the viewer rather than a per-page paint: the pages are
/// rasters, so filtering the pixels is the only way to darken them, and doing it
/// once keeps every page — and the gaps between them — consistent.
///
/// **The wrapper is always there**, carrying an identity matrix when night mode
/// is off, and that is not a stylistic choice. Returning `child` unwrapped
/// changes the *shape* of the widget tree, so turning night mode on or off
/// replaces the element below it: Flutter unmounts the viewer and builds a new
/// one, which reopens the document and loses your place. That is what made a
/// book open blank the first time — the reader's settings arrive
/// asynchronously, so the viewer was built once without them and then thrown
/// away and rebuilt when they landed. Same matrix, same tree, no rebuild.
Widget nightModeWrap({required bool enabled, required Widget child}) =>
    ColorFiltered(
      colorFilter: ColorFilter.matrix(
        enabled ? nightModeMatrix : identityMatrix,
      ),
      child: child,
    );
