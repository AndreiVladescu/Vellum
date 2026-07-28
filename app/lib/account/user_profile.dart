import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'avatar_image.dart';

/// The local user profile.
///
/// Vellum is local-first, so for now the "account" lives on this device only.
/// When server sync lands, this becomes the identity used to sign in to a
/// library server. A [ChangeNotifier] so the drawer header updates on save.
class UserProfileStore extends ChangeNotifier {
  UserProfileStore._(this._prefs, this._dataDir);

  static const _nameKey = 'profile.name';
  static const _emailKey = 'profile.email';
  static const _photoKey = 'profile.photo';
  static const _updatedKey = 'profile.updatedAt';

  /// The folder the avatar is written to, under the library's data directory.
  /// Beside `covers` and `files` on purpose: the backup archive copies whole
  /// subdirectories, so being one of them is what puts the photo in a backup.
  static const photoDirName = 'profile';

  final SharedPreferences _prefs;

  /// Where the avatar lives. Null when the profile is loaded without one — then
  /// a photo simply can't be set, and the initial stands in.
  final Directory? _dataDir;

  /// [dataDir] is the library's data directory, normally `repository.dataDir`.
  static Future<UserProfileStore> load({Directory? dataDir}) async {
    final store = UserProfileStore._(
      await SharedPreferences.getInstance(),
      dataDir,
    );
    await store._forgetMissingPhoto();
    return store;
  }

  String get name => _prefs.getString(_nameKey) ?? '';
  String get email => _prefs.getString(_emailKey) ?? '';
  bool get isSet => name.isNotEmpty;

  String get initial => isSet ? name.trim()[0].toUpperCase() : '?';

  /// The avatar file, or null if there isn't one.
  String? get photoPath => _prefs.getString(_photoKey);

  bool get canSetPhoto => _dataDir != null;

  /// When this profile last changed here — the key the account sync compares
  /// against the server's `profile_updated_at` to decide which side is newer.
  DateTime? get updatedAt {
    final stored = _prefs.getInt(_updatedKey);
    return stored == null ? null : DateTime.fromMillisecondsSinceEpoch(stored);
  }

  Future<void> _stamp([DateTime? at]) => _prefs.setInt(
        _updatedKey,
        (at ?? DateTime.now()).millisecondsSinceEpoch,
      );

  /// Takes the account's name as this device's, without re-publishing it —
  /// the stamp is the server's, so the next sync sees the two agree.
  Future<void> adopt({required String name, DateTime? at}) async {
    await _prefs.setString(_nameKey, name.trim());
    await _stamp(at);
    notifyListeners();
  }

  /// Takes the account's photo. Same as [setPhoto] but stamped with the
  /// server's clock, so adopting it doesn't look like a local edit that then
  /// needs pushing back.
  Future<void> adoptPhoto(Uint8List bytes, {DateTime? at}) async {
    await setPhoto(bytes);
    await _stamp(at);
  }

  Future<void> save({required String name, required String email}) async {
    await _prefs.setString(_nameKey, name.trim());
    await _prefs.setString(_emailKey, email.trim());
    await _stamp();
    notifyListeners();
  }

  /// Stores [picked] as the avatar, scaled down first.
  ///
  /// Written under a new name each time rather than overwriting: Flutter's
  /// image cache is keyed by path, so reusing one would leave the old photo on
  /// screen until the app restarted.
  Future<void> setPhoto(Uint8List picked) async {
    final dir = _dataDir;
    if (dir == null) {
      throw const AvatarImageException('There is nowhere to save a photo.');
    }
    final bytes = await avatarBytes(picked);
    final folder = Directory(p.join(dir.path, photoDirName));
    await folder.create(recursive: true);
    final file = File(p.join(
      folder.path,
      'avatar-${DateTime.now().millisecondsSinceEpoch}.png',
    ));
    await file.writeAsBytes(bytes, flush: true);

    final previous = photoPath;
    await _prefs.setString(_photoKey, file.path);
    await _deleteQuietly(previous);
    await _stamp();
    notifyListeners();
  }

  Future<void> clearPhoto() async {
    final previous = photoPath;
    await _prefs.remove(_photoKey);
    await _deleteQuietly(previous);
    await _stamp();
    notifyListeners();
  }

  /// Drops a stored path whose file has gone — after a restore onto a different
  /// machine, or a hand-cleaned data folder. Without this the drawer would keep
  /// trying to paint a file that isn't there.
  Future<void> _forgetMissingPhoto() async {
    final path = photoPath;
    if (path == null || File(path).existsSync()) return;
    await _prefs.remove(_photoKey);
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A locked or already-removed file costs one orphaned image, not
      // correctness — and Library health sweeps the data folder anyway.
    }
  }
}
