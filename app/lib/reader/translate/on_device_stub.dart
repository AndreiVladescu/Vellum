import 'package:flutter/material.dart';

import 'translation_backend.dart';

/// The free build's answer about on-device translation: there isn't any.
///
/// Vellum ships in two flavours from one source tree (`tool/flavour.sh`). This
/// is the default one — the whole app is free software, so it can go to F-Droid
/// and IzzyOnDroid without an anti-feature flag. The other flavour swaps
/// `on_device.dart` to export
/// `proprietary/on_device_backend.dart` instead, which is Google's ML Kit:
/// closed source, and about 17 MB of `.so` files in the APK.
///
/// **This has to be a build-time switch, not a setting.** A dependency that is
/// listed is a dependency that ships, whether or not any code calls it, so a
/// runtime toggle would leave the blobs and the flag exactly where they were.
/// The setting in the full build is a second gate on top of this one, so even
/// there nothing proprietary runs until someone asks for it.
///
/// Everything a caller needs is these three names, and both sides define all
/// three — which is what keeps the two flavours honestly interchangeable.

/// Whether this build can translate on the device itself.
bool get onDeviceTranslationAvailable => false;

/// The on-device backend. Never called when [onDeviceTranslationAvailable] is
/// false; it throws rather than returning null so a caller that forgets the
/// check fails loudly here instead of quietly translating nothing.
TranslationBackend createOnDeviceBackend() =>
    throw UnsupportedError('this build has no on-device translator');

/// The screen for managing downloaded language packs, or null where there are
/// no packs because there is no on-device translator.
Widget? onDeviceLanguagesSheet() => null;
