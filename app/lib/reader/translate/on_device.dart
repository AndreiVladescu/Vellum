/// Which on-device translator this build has, if any.
///
/// **`tool/flavour.sh` rewrites the export line below and nothing else.** The
/// free flavour (the default, and what F-Droid and IzzyOnDroid get) exports the
/// stub; the full flavour exports `proprietary/on_device.dart`, which is
/// Google's ML Kit.
///
/// Kept as one line in one file on purpose: a build variant that edits code in
/// several places is a build variant that drifts. Everything above this imports
/// `on_device.dart` and never the two sides directly.
library;

export 'on_device_stub.dart';
