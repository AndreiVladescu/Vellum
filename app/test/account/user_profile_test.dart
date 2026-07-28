// The profile photo.
//
// Two things are worth defending: a picked photo is scaled *before* it is
// stored (a phone photo is megabytes and is shown at forty pixels), and the
// stored path never outlives the file it points at.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/avatar_image.dart';
import 'package:vellum/account/profile_avatar.dart';
import 'package:vellum/account/user_profile.dart';

/// A real PNG of the given size, so the decoder has something honest to chew.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('vellum_profile');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('scaling', () {
    test('a large photo is scaled down to the long edge', () async {
      final out = await avatarBytes(await _png(2400, 1600));
      final image = await _decode(out);
      expect(image.width, avatarMaxEdge);
      expect(image.height, 341, reason: 'the aspect ratio is kept');
      image.dispose();
    });

    test('a tall photo is scaled on its own long edge', () async {
      final out = await avatarBytes(await _png(1000, 3000));
      final image = await _decode(out);
      expect(image.height, avatarMaxEdge);
      expect(image.width, 171);
      image.dispose();
    });

    test('one already small is stored exactly as it came', () async {
      // Re-encoding it would cost quality and gain nothing.
      final source = await _png(200, 200);
      expect(await avatarBytes(source), same(source));
    });

    test('something that is not an image is refused, in words', () async {
      // A file picker filtered to images still passes a text file someone
      // renamed to .png.
      await expectLater(
        avatarBytes(Uint8List.fromList('not an image'.codeUnits)),
        throwsA(isA<AvatarImageException>()),
      );
    });
  });

  group('storing', () {
    test('the photo is written under the data folder and remembered', () async {
      final profile = await UserProfileStore.load(dataDir: dir);
      expect(profile.photoPath, isNull);

      await profile.setPhoto(await _png(80, 80));
      final path = profile.photoPath;
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(path, contains(UserProfileStore.photoDirName),
          reason: 'a folder the backup archive copies');

      // It survives the next launch.
      final reloaded = await UserProfileStore.load(dataDir: dir);
      expect(reloaded.photoPath, path);
    });

    test('replacing one removes the file it replaced', () async {
      // And lands on a new name, because Flutter caches images by path — the
      // old photo would otherwise stay on screen until a restart.
      final profile = await UserProfileStore.load(dataDir: dir);
      await profile.setPhoto(await _png(80, 80));
      final first = profile.photoPath!;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await profile.setPhoto(await _png(90, 90));
      final second = profile.photoPath!;

      expect(second, isNot(first));
      expect(File(first).existsSync(), isFalse, reason: 'no orphan left behind');
      expect(File(second).existsSync(), isTrue);
    });

    test('removing it deletes the file too', () async {
      final profile = await UserProfileStore.load(dataDir: dir);
      await profile.setPhoto(await _png(80, 80));
      final path = profile.photoPath!;

      await profile.clearPhoto();
      expect(profile.photoPath, isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test('a path whose file has gone is forgotten on load', () async {
      // What a restore onto another machine, or a hand-cleaned data folder,
      // leaves behind. Keeping it would mean a drawer trying to paint nothing.
      final profile = await UserProfileStore.load(dataDir: dir);
      await profile.setPhoto(await _png(80, 80));
      await File(profile.photoPath!).delete();

      final reloaded = await UserProfileStore.load(dataDir: dir);
      expect(reloaded.photoPath, isNull);
    });

    test('setting one notifies, so the drawer repaints', () async {
      final profile = await UserProfileStore.load(dataDir: dir);
      var notifications = 0;
      profile.addListener(() => notifications++);
      await profile.setPhoto(await _png(80, 80));
      await profile.clearPhoto();
      expect(notifications, 2);
    });

    test('without a data folder a photo cannot be set, and says so', () async {
      final profile = await UserProfileStore.load();
      expect(profile.canSetPhoto, isFalse);
      await expectLater(
        profile.setPhoto(await _png(80, 80)),
        throwsA(isA<AvatarImageException>()),
      );
    });
  });

  group('the avatar', () {
    // Preferences and file writes go through `runAsync`: real I/O inside
    // `testWidgets`' fake-async clock never completes, and the test hangs
    // rather than failing.
    testWidgets('falls back to the initial when there is no photo',
        (tester) async {
      late UserProfileStore profile;
      await tester.runAsync(() async {
        profile = await UserProfileStore.load(dataDir: dir);
        await profile.save(name: 'Ana Petrescu', email: '');
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProfileAvatar(profile: profile)),
      ));
      expect(find.text('A'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundImage, isNull);
    });

    testWidgets('shows the file once there is one', (tester) async {
      late UserProfileStore profile;
      late String path;
      await tester.runAsync(() async {
        profile = await UserProfileStore.load(dataDir: dir);
        await profile.save(name: 'Ana Petrescu', email: '');
        await profile.setPhoto(await _png(80, 80));
        path = profile.photoPath!;
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProfileAvatar(profile: profile)),
      ));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundImage, isA<FileImage>());
      expect((avatar.foregroundImage! as FileImage).file.path, path);
      // The initial stays underneath: it is what shows while the file decodes,
      // and if the file turns out to be unreadable.
      expect(find.text('A'), findsOneWidget);
    });
  });
}
