// The volume keys as page turns: the Dart half. The native half (Android's
// MainActivity swallowing the keys) is a device check in docs/BACKLOG.md.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/reader/reader_settings.dart';
import 'package:vellum/reader/reader_settings_sheet.dart';
import 'package:vellum/reader/volume_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/volume_keys');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });

  /// What Android does when a volume key goes down.
  Future<void> press(String key) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .handlePlatformMessage(
        'test/volume_keys',
        const StandardMethodCodec().encodeMethodCall(MethodCall('key', key)),
        (_) {},
      );

  test(
    'on: down turns forward, up turns back; off: nothing is claimed',
    () async {
      final steps = <int>[];
      final keys = VolumeKeys(
        isActive: () => true,
        onStep: steps.add,
        channel: channel,
        supported: true,
      );
      await keys.sync(true);
      expect(calls, ['enable']);
      await press('down');
      await press('up');
      expect(steps, [1, -1]);

      await keys.sync(false);
      expect(calls, ['enable', 'disable']);
      await press('down');
      expect(steps, [1, -1], reason: 'handler removed');
    },
  );

  test('a covered reader ignores the keys', () async {
    final steps = <int>[];
    var active = true;
    final keys = VolumeKeys(
      isActive: () => active,
      onStep: steps.add,
      channel: channel,
      supported: true,
    );
    await keys.sync(true);
    active = false;
    await press('down');
    expect(steps, isEmpty);
    await keys.dispose();
  });

  test(
    'leaving the reader gives the keys back; a no-op when never on',
    () async {
      final keys = VolumeKeys(
        isActive: () => true,
        onStep: (_) {},
        channel: channel,
        supported: true,
      );
      await keys.dispose();
      expect(calls, isEmpty);
      await keys.sync(true);
      await keys.dispose();
      expect(calls, ['enable', 'disable']);
    },
  );

  test('unsupported platforms never touch the channel', () async {
    final keys = VolumeKeys(
      isActive: () => true,
      onStep: (_) {},
      channel: channel,
      supported: false,
    );
    await keys.sync(true);
    await keys.dispose();
    expect(calls, isEmpty);
  });

  test('a newer reader keeps the keys when an older one closes', () async {
    final steps = <int>[];
    final older = VolumeKeys(
      isActive: () => true,
      onStep: (_) {},
      channel: channel,
      supported: true,
    );
    final newer = VolumeKeys(
      isActive: () => true,
      onStep: steps.add,
      channel: channel,
      supported: true,
    );
    await older.sync(true);
    await newer.sync(true);
    calls.clear();
    await older.dispose();
    expect(calls, isEmpty, reason: 'native side stays on for the newer reader');
    await press('down');
    expect(steps, [1]);
    await newer.dispose();
  });

  testWidgets('the settings sheet offers the switch and saves it', (
    tester,
  ) async {
    final settings = await ReaderSettings.load();
    Widget sheet(bool show) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: ReaderSettingsSheet(
          settings: settings,
          showTypography: false,
          showPdfOptions: false,
          showVolumeKeys: show,
        ),
      ),
    );
    await tester.pumpWidget(sheet(false));
    expect(find.text('Volume keys turn pages'), findsNothing);

    await tester.pumpWidget(sheet(true));
    expect(settings.volumeKeysTurnPages, isFalse, reason: 'off by default');
    final tile = find.text('Volume keys turn pages');
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(tile);
    await tester.pump();
    expect(settings.volumeKeysTurnPages, isTrue);
  });
}
