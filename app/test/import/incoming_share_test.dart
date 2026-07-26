// The Dart half of open-with / share-target import (plan 5 #20), driven through
// a fake platform channel. The Kotlin half (resolving a content:// URI and
// copying the stream before it expires) can only be verified on a device — the
// manual steps are documented in docs/BACKLOG.md.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/import/incoming_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(IncomingShare.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers `takeInitialFiles` with [initial]; records the calls made.
  List<String> mockHost(List<String>? initial, {bool throwMissing = false}) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (throwMissing) throw MissingPluginException('no host here');
      if (call.method == 'takeInitialFiles') return initial;
      return null;
    });
    return calls;
  }

  /// Delivers a host→Dart `onFiles` call, as a warm-resume share does.
  Future<void> sendFiles(List<String> paths) async {
    await messenger.handlePlatformMessage(
      IncomingShare.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onFiles', paths),
      ),
      (_) {},
    );
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a cold-start share is collected once', () async {
    final calls = mockHost(['/cache/incoming/1/Dune.pdf']);
    final incoming = IncomingShare();
    addTearDown(incoming.dispose);

    expect(await incoming.takeInitialFiles(), ['/cache/incoming/1/Dune.pdf']);
    expect(calls, ['takeInitialFiles']);
  });

  test('no share means an empty list, not a null or a throw', () async {
    mockHost(const []);
    final incoming = IncomingShare();
    addTearDown(incoming.dispose);

    expect(await incoming.takeInitialFiles(), isEmpty);
  });

  test('a platform without the host degrades to nothing shared', () async {
    // Desktop, where no MainActivity answers this channel: a launch must not
    // fail because nothing was shared into the app.
    mockHost(null, throwMissing: true);
    final incoming = IncomingShare();
    addTearDown(incoming.dispose);

    expect(await incoming.takeInitialFiles(), isEmpty);
  });

  test('warm-resume shares arrive on the stream', () async {
    mockHost(const []);
    final incoming = IncomingShare();
    addTearDown(incoming.dispose);

    final received = <List<String>>[];
    final sub = incoming.files.listen(received.add);
    addTearDown(sub.cancel);

    await sendFiles(['/cache/a.pdf']);
    await sendFiles(['/cache/b.epub', '/cache/c.pdf']);

    expect(received, [
      ['/cache/a.pdf'],
      ['/cache/b.epub', '/cache/c.pdf'],
    ]);
  });

  test('an empty onFiles call is not forwarded', () async {
    mockHost(const []);
    final incoming = IncomingShare();
    addTearDown(incoming.dispose);

    final received = <List<String>>[];
    final sub = incoming.files.listen(received.add);
    addTearDown(sub.cancel);

    await sendFiles(const []);

    expect(received, isEmpty, reason: 'nothing to import, nothing to announce');
  });

  test('the stream is a broadcast, so several listeners can react', () async {
    // main.dart listens, and a future screen may too; a single-subscription
    // stream would throw on the second listen.
    mockHost(const []);
    final incoming = IncomingShare();
    addTearDown(incoming.dispose);

    final first = <List<String>>[];
    final second = <List<String>>[];
    final subs = [
      incoming.files.listen(first.add),
      incoming.files.listen(second.add),
    ];
    addTearDown(() async {
      for (final s in subs) {
        await s.cancel();
      }
    });

    await sendFiles(['/cache/a.pdf']);

    expect(first, hasLength(1));
    expect(second, hasLength(1));
  });
}
