import 'package:flutter/material.dart';

import '../translation_backend.dart';
import 'language_packs_sheet.dart';
import 'on_device_backend.dart';

/// The full build's answer: Google's ML Kit, on the device.
///
/// The mirror of `../on_device_stub.dart` — same three names, so
/// `../on_device.dart` can export either one and nothing above it can tell the
/// difference. Only this side pulls `google_mlkit_translation` and
/// `google_mlkit_language_id` into the build, which is why the free flavour
/// simply never references it.
///
/// The **preference** is the second gate. ML Kit is proprietary, and shipping
/// it is not the same as running it, so the full build still asks: nothing here
/// is reached until `ReaderSettings.useOnDeviceTranslation` is on. See
/// `translate_sheet.dart`, which checks both.

bool get onDeviceTranslationAvailable => OnDeviceBackend.available;

TranslationBackend createOnDeviceBackend() => OnDeviceBackend();

Widget? onDeviceLanguagesSheet() => const LanguagePacksSheet();
