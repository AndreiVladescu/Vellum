import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/notifications/tray.dart';

/// What the background check puts in the status bar.
///
/// The policy is split out from the plugin call for the same reason
/// `BackgroundSyncPolicy` is: the interesting cases are the ones a device makes
/// awkward to reach, and the worst of them is the *repeat* — a notification
/// that reappears every six hours about the same unanswered request is how
/// people learn to turn notifications off entirely.
void main() {
  final morning = DateTime(2026, 8, 11, 9);
  final noon = DateTime(2026, 8, 11, 12);

  TrayDecision decide({
    int unread = 1,
    String? newest = 'Ana would like to borrow “Dune”',
    DateTime? newestAt,
    DateTime? lastShownAt,
  }) =>
      TrayDecision.forUnread(
        unread: unread,
        newest: newest,
        newestAt: newestAt,
        lastShownAt: lastShownAt,
      );

  test('nothing unread says nothing', () {
    expect(decide(unread: 0, newest: null).silent, isTrue);
  });

  test('a count with no message to show is still silent', () {
    // Defensive: `unread` and the list come from two different parts of one
    // response, and a notification with an empty body helps nobody.
    expect(decide(unread: 3, newest: null).silent, isTrue);
  });

  test('something new is announced, in the words the server chose', () {
    final d = decide(newestAt: noon, lastShownAt: morning);
    expect(d.silent, isFalse);
    expect(d.body, 'Ana would like to borrow “Dune”');
  });

  test('the first ever check announces', () {
    expect(decide(newestAt: noon, lastShownAt: null).silent, isFalse);
  });

  test('the same thing is not announced twice', () {
    expect(decide(newestAt: morning, lastShownAt: morning).silent, isTrue,
        reason: 'already told them about this one');
    expect(decide(newestAt: morning, lastShownAt: noon).silent, isTrue,
        reason: 'older than the last thing shown');
  });

  test('several waiting reads as one line, not seven notifications', () {
    final d = decide(unread: 4, newestAt: noon, lastShownAt: morning);
    expect(d.body, 'Ana would like to borrow “Dune” · and 3 more');
  });

  test('exactly one waiting does not say "and 0 more"', () {
    expect(decide(unread: 1, newestAt: noon).body,
        'Ana would like to borrow “Dune”');
  });

  test('an undated notification is announced rather than dropped', () {
    // Nothing to compare against means "cannot prove it is old", and staying
    // silent about a real request is the worse of the two mistakes.
    expect(decide(newestAt: null, lastShownAt: noon).silent, isFalse);
  });
}
