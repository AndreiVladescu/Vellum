import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// The camera half of the two scanning screens, in one place.
///
/// **Why not ML Kit.** This used to be `mobile_scanner`, which decodes with
/// Google's ML Kit barcode library — closed source, about 5 MB of `.so` in the
/// APK, and it drags Play Services in with it. That is an anti-feature flag on
/// IzzyOnDroid and a refusal from F-Droid, for a job that a free library does
/// perfectly well: zxing-cpp is Apache-2.0 and builds from source with the rest
/// of the app, so nothing here is a blob anybody has to trust.
///
/// Unlike the translator, this needed no flavour split — the free replacement
/// keeps the whole feature, so there is nothing to choose between.
///
/// Both callers already have a typed fallback (an ISBN field, a shelf-code
/// field) and only reach for this when a camera is available, which is why
/// there is no permission dance here.
class BarcodeCamera extends StatelessWidget {
  const BarcodeCamera({
    super.key,
    required this.formats,
    required this.onCode,
    this.onError,
  });

  /// A bitmask from [Format]. Narrow it: a decoder told to find everything
  /// spends every frame hunting symbologies a book will never have.
  final int formats;

  /// Called with the decoded text. May fire repeatedly while a code is held in
  /// view — callers debounce (see `ScanPage._onBarcode`).
  final void Function(String value) onCode;

  /// Shown instead of the preview when the camera cannot start.
  final Widget Function(String message)? onError;

  @override
  Widget build(BuildContext context) {
    return ReaderWidget(
      codeFormat: formats,
      // The reader's own chrome is for a general-purpose scanner app: a
      // gallery picker and a camera flip are not what someone pointing a phone
      // at a book's back cover wants. The torch stays — barcodes live on
      // shelves, and shelves are dark.
      showGallery: false,
      showToggleCamera: false,
      showFlashlight: true,
      // A book's barcode is often printed small and read at an angle.
      tryRotate: true,
      tryInverted: true,
      onScan: (Code code) {
        final text = code.text;
        if (text != null && text.isNotEmpty) onCode(text);
      },
      // `onScanFailure` fires for every frame that decodes to nothing, which is
      // most of them — it is not an error, and wiring it to the error state
      // would flash a message continuously while someone lines up a shot.
      onScanFailure: (_) {},
    );
  }
}

/// The symbologies printed on the back of a book: EAN-13 (the ISBN) and the
/// occasional EAN-8.
const int isbnFormats = Format.ean13 | Format.ean8;

/// What a shelf label carries.
const int shelfLabelFormats = Format.qrCode;
