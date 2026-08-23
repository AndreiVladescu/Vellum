/// What version this actually is.
///
/// From the installed package, never a constant in the source: the About box
/// said "0.1.0" through eleven releases because that number lived in a widget
/// and `pubspec.yaml` moved on without it. `package_info_plus` reads what the
/// build declared — on Android the `versionName` from the merged manifest, on
/// the desktops the version compiled in — so it cannot drift.
library;

import 'package:package_info_plus/package_info_plus.dart';

/// "1.1.7" — or "1.1.7 (6)" when the build number says something the version
/// does not, which is the pair an Android bug report needs.
Future<String> appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    final build = info.buildNumber.trim();
    if (version.isEmpty) return 'unknown';
    return build.isEmpty || build == version ? version : '$version ($build)';
  } catch (_) {
    // A platform with no package metadata (a bare test binary): the About box
    // saying "unknown" is better than it failing to open.
    return 'unknown';
  }
}
