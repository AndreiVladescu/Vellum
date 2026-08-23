// What the About box says.
//
// It said "0.1.0" through eleven releases, because the number lived in a widget
// and `pubspec.yaml` moved on without it. It comes from the installed package
// now, so what is pinned here is the shape of the answer and that a platform
// with no package metadata still opens the box.
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vellum/app_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void install({required String version, required String build}) {
    PackageInfo.setMockInitialValues(
      appName: 'Vellum',
      packageName: 'com.vellum.app',
      version: version,
      buildNumber: build,
      buildSignature: '',
    );
  }

  test('is the version the build declares', () async {
    install(version: '1.1.7', build: '7');
    expect(await appVersion(), '1.1.7 (7)',
        reason: 'the build number is the half an Android report needs');
  });

  test('does not repeat itself when the two agree', () async {
    install(version: '1.1.7', build: '1.1.7');
    expect(await appVersion(), '1.1.7');
  });

  test('a build with no number is just the version', () async {
    install(version: '1.1.7', build: '');
    expect(await appVersion(), '1.1.7');
  });

  test('a package that says nothing does not break the box', () async {
    install(version: '', build: '');
    expect(await appVersion(), 'unknown');
  });
}
