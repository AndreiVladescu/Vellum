import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'book_face.dart';
import 'shelf_sort.dart';
import 'spine_art.dart';
import 'wallpaper.dart';

/// App-wide preferences stored on device.
class AppSettingsStore extends ChangeNotifier {
  AppSettingsStore._(this._prefs);

  static const _wallpaperKey = 'settings.wallpaper';
  static const _bookFaceKey = 'settings.bookFace';
  static const _spineArtKey = 'settings.spineArt';
  static const _selectedShelfKey = 'settings.selectedShelf';
  static const _shelfSortKey = 'settings.shelfSort';
  static const _autoPushKey = 'settings.autoPush';
  static const _importGenresKey = 'settings.importOpenLibraryGenres';
  static const _syncReadingPositionKey = 'settings.syncReadingPosition';
  static const _deviceIdKey = 'settings.deviceId';
  static const _deviceLabelKey = 'settings.deviceLabel';
  static const _watchedFolderKey = 'settings.watchedImportFolder';

  final SharedPreferences _prefs;

  static Future<AppSettingsStore> load() async =>
      AppSettingsStore._(await SharedPreferences.getInstance());

  Wallpaper get wallpaper {
    final stored = _prefs.getString(_wallpaperKey);
    return Wallpaper.values
            .where((w) => w.name == stored)
            .firstOrNull ??
        Wallpaper.parchment;
  }

  Future<void> setWallpaper(Wallpaper value) async {
    await _prefs.setString(_wallpaperKey, value.name);
    notifyListeners();
  }

  /// Whether the shelf shows spines or front covers.
  BookFace get bookFace {
    final stored = _prefs.getString(_bookFaceKey);
    return BookFace.values.where((f) => f.name == stored).firstOrNull ??
        BookFace.spine;
  }

  Future<void> setBookFace(BookFace value) async {
    await _prefs.setString(_bookFaceKey, value.name);
    notifyListeners();
  }

  /// How a spine-out book with cover art draws its spine (cover slice vs the
  /// cover's dominant colour). Only applies in [BookFace.spine] mode — a
  /// face-out shelf always shows the cover itself.
  SpineArt get spineArt {
    final stored = _prefs.getString(_spineArtKey);
    return SpineArt.values.where((s) => s.name == stored).firstOrNull ??
        SpineArt.coverSlice;
  }

  Future<void> setSpineArt(SpineArt value) async {
    await _prefs.setString(_spineArtKey, value.name);
    notifyListeners();
  }

  /// The custom shelf the digital tab last filtered by, or null for "All". The
  /// selected shelf may have since been deleted; callers fall back to All when
  /// the id no longer matches a shelf.
  String? get selectedShelfId => _prefs.getString(_selectedShelfKey);

  Future<void> setSelectedShelfId(String? value) async {
    if (value == null) {
      await _prefs.remove(_selectedShelfKey);
    } else {
      await _prefs.setString(_selectedShelfKey, value);
    }
    notifyListeners();
  }

  /// How the digital shelf orders books (title by default).
  ShelfSort get shelfSort {
    final stored = _prefs.getString(_shelfSortKey);
    return ShelfSort.values.where((s) => s.name == stored).firstOrNull ??
        ShelfSort.title;
  }

  Future<void> setShelfSort(ShelfSort value) async {
    await _prefs.setString(_shelfSortKey, value.name);
    notifyListeners();
  }

  /// Whether to push dirty books to the server in the background shortly after
  /// edits, while connected. On by default; only pushes (never pulls), so it
  /// can't overwrite local state. See [AutoPusher].
  bool get autoPush => _prefs.getBool(_autoPushKey) ?? true;

  Future<void> setAutoPush(bool value) async {
    await _prefs.setBool(_autoPushKey, value);
    notifyListeners();
  }

  /// Whether adding a book from search also imports Open Library's "subjects"
  /// as genres. Off by default: those subjects are noisy and inconsistent
  /// (odd one-offs, casing variants), so genres are yours to assign by hand.
  bool get importOpenLibraryGenres =>
      _prefs.getBool(_importGenresKey) ?? false;

  Future<void> setImportOpenLibraryGenres(bool value) async {
    await _prefs.setBool(_importGenresKey, value);
    notifyListeners();
  }

  /// Whether this device publishes its reading position to the server so other
  /// devices can offer to resume there (plan 5 #5).
  ///
  /// **Off by default, and stays a real opt-in.** Everything else the app syncs
  /// is catalogue data; where you are in a book is behaviour, and publishing it
  /// changes what the server knows about you. Nothing is written to the server
  /// until this is on, and turning it off un-publishes what it published (see
  /// `PreferencesPage`).
  bool get syncReadingPosition =>
      _prefs.getBool(_syncReadingPositionKey) ?? false;

  Future<void> setSyncReadingPosition(bool value) async {
    await _prefs.setBool(_syncReadingPositionKey, value);
    notifyListeners();
  }

  /// Stable, opaque id for this install — the key the reading-position channel
  /// files this device's rows under. Generated once and kept in preferences; a
  /// reinstall becoming a "new device" is fine and better than fingerprinting
  /// the hardware.
  String get deviceId {
    final existing = _prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = const Uuid().v4();
    // Fire-and-forget: the in-memory value is returned now and the write lands
    // shortly. A crash before it does just mints another id next launch.
    _prefs.setString(_deviceIdKey, generated);
    return generated;
  }

  /// Human name for this device, used in "you were on page 214 on **desktop**".
  /// The hostname is the most recognisable thing available without a plugin;
  /// falls back to the platform name if it's unhelpfully empty.
  String get deviceLabel {
    final stored = _prefs.getString(_deviceLabelKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    String label;
    try {
      label = Platform.localHostname;
    } catch (_) {
      label = '';
    }
    if (label.trim().isEmpty) label = Platform.operatingSystem;
    return label;
  }

  /// A folder the user asked Vellum to keep an eye on for new books (plan 5
  /// #15), or null. Checked **on launch only** — no filesystem watcher and no
  /// background service, so a folder on a disconnected drive is a no-op rather
  /// than a hang, and nothing is imported without the usual dry-run review.
  String? get watchedImportFolder {
    final stored = _prefs.getString(_watchedFolderKey);
    return (stored == null || stored.isEmpty) ? null : stored;
  }

  Future<void> setWatchedImportFolder(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_watchedFolderKey);
    } else {
      await _prefs.setString(_watchedFolderKey, path.trim());
    }
    notifyListeners();
  }

  /// Override the device label (a user who has two machines both called
  /// "localhost" needs this to mean anything).
  Future<void> setDeviceLabel(String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _prefs.remove(_deviceLabelKey);
    } else {
      await _prefs.setString(_deviceLabelKey, trimmed);
    }
    notifyListeners();
  }
}
