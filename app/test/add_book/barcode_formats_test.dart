import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:vellum/add_book/barcode_camera.dart';

/// The scanner's format mask actually reads a book's barcode.
///
/// `isbnFormats` narrows the decoder to EAN-13 and EAN-8 so it isn't hunting
/// QR codes on every camera frame. Narrowing is the sort of thing that is easy
/// to get subtly wrong — the constants are a bitmask, and a wrong one fails by
/// simply never finding anything, on a screen where "nothing found yet" is the
/// normal state. So: encode a real ISBN with zxing, read it back through the
/// app's own mask, and check the digits survive.
///
/// **Skipped unless the native library is loaded.** On Linux the plugin binds
/// with `DynamicLibrary.process()`, so a plain `flutter test` has no symbols to
/// call. Run it after a desktop build with:
///
/// ```sh
/// flutter build linux --debug
/// LD_PRELOAD=$PWD/build/linux/x64/debug/bundle/lib/libflutter_zxing.so \
///   flutter test test/add_book/barcode_formats_test.dart
/// ```
///
/// Skipping rather than failing is deliberate: this asserts something about a
/// C++ library, and a test that cannot reach it has learnt nothing — which is
/// different from having found a problem.
void main() {
  test('the ISBN mask reads an EAN-13 back', () {
    const isbn = '9780141439518'; // Pride and Prejudice, Penguin Classics.
    const width = 600, height = 300;

    final Encode encoded;
    try {
      encoded = zx.encodeBarcode(
        contents: isbn,
        params: EncodeParams(
          format: Format.ean13,
          width: width,
          height: height,
          margin: 20,
        ),
      );
    } on ArgumentError {
      markTestSkipped('libflutter_zxing is not loaded — see the file comment');
      return;
    }
    expect(encoded.isValid, isTrue, reason: 'zxing could not encode the ISBN');

    // The encoder hands back one byte per pixel, 0 for black — which is
    // exactly what `DecodeParams` wants, since `imageFormat` defaults to
    // `lum`. Handing it three-byte RGB instead decodes nothing at all, silently.
    final code = zx.readBarcode(
      encoded.data!,
      DecodeParams(format: isbnFormats, width: width, height: height),
    );

    expect(code.isValid, isTrue, reason: 'the mask found no barcode');
    expect(code.text, isbn);
  });
}
