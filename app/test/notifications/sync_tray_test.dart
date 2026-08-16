import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/notifications/sync_tray.dart';

/// The wording under the sync progress notification — the one piece of
/// [SyncNotificationTray] that's pure enough to test without a device.
void main() {
  test('a phase with a real count reads as "phase — done of total"', () {
    expect(syncProgressBody(12, 40, 'Pushing books'), 'Pushing books — 12 of 40');
  });

  test('a phase with nothing to count yet is just the phase name', () {
    expect(syncProgressBody(0, 0, 'Checking for changes'), 'Checking for changes');
  });

  test('a negative total (should never happen) is treated the same as none', () {
    expect(syncProgressBody(0, -1, 'Starting'), 'Starting');
  });
}
