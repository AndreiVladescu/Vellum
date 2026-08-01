import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../server/sync_scope.dart';
import 'package:uuid/uuid.dart';

import 'appearance.dart';
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
  static const _syncScopeKey = 'settings.syncScope';
  static const _deviceIdKey = 'settings.deviceId';
  static const _deviceLabelKey = 'settings.deviceLabel';
  static const _watchedFolderKey = 'settings.watchedImportFolder';
  static const _seenFirstRunKey = 'settings.hasSeenFirstRun';
  static const _backupFrequencyKey = 'settings.backupFrequency';
  static const _backupFolderKey = 'settings.backupFolder';
  static const _backupKeepKey = 'settings.backupKeep';
  static const _lastBackupAtKey = 'settings.lastBackupAt';
  // Background sync on Android (plan 5 #40).
  static const _backgroundSyncKey = 'settings.backgroundSync';
  static const _lastBackgroundSyncKey = 'settings.lastBackgroundSync';
  // Appearance (plan 5 #39).
  static const _themeModeKey = 'settings.themeMode';
  static const _seedKey = 'settings.seedColor';
  static const _dynamicColorKey = 'settings.useDynamicColor';
  static const _shelfMaterialKey = 'settings.shelfMaterial';
  static const _spineTitleScaleKey = 'settings.spineTitleScale';
  static const _spineWidthScaleKey = 'settings.spineWidthScale';

  final SharedPreferences _prefs;

  static Future<AppSettingsStore> load() async =>
      AppSettingsStore._(await SharedPreferences.getInstance());

  // ---- Appearance (plan 5 #39) --------------------------------------------

  /// Light, dark, or follow the system. Previously not selectable at all.
  ThemeMode get themeMode {
    final stored = _prefs.getString(_themeModeKey);
    return ThemeMode.values.where((m) => m.name == stored).firstOrNull ??
        ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _prefs.setString(_themeModeKey, value.name);
    notifyListeners();
  }

  /// The scheme seed. Stored as a preset name when it is one, and as `#RRGGBB`
  /// when the user picked their own — so a preset survives us restyling it
  /// later, while a custom colour survives us adding presets.
  Color get seedColor {
    final stored = _prefs.getString(_seedKey);
    if (stored == null || stored.isEmpty) return SeedPreset.fallback.color;
    final preset =
        SeedPreset.values.where((p) => p.name == stored).firstOrNull;
    if (preset != null) return preset.color;
    if (stored.startsWith('#') && stored.length == 7) {
      final value = int.tryParse(stored.substring(1), radix: 16);
      if (value != null) return Color(value | 0xFF000000);
    }
    return SeedPreset.fallback.color;
  }

  /// The preset currently selected, or null when the seed is a custom colour.
  SeedPreset? get seedPreset {
    final stored = _prefs.getString(_seedKey);
    if (stored == null || stored.isEmpty) return SeedPreset.fallback;
    return SeedPreset.values.where((p) => p.name == stored).firstOrNull;
  }

  Future<void> setSeedPreset(SeedPreset value) async {
    await _prefs.setString(_seedKey, value.name);
    notifyListeners();
  }

  Future<void> setCustomSeed(Color value) async {
    final rgb = value.toARGB32() & 0xFFFFFF;
    await _prefs.setString(
      _seedKey,
      '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}',
    );
    notifyListeners();
  }

  /// Whether to take the scheme from Android's Material You wallpaper colours
  /// instead of [seedColor]. Off by default, and a no-op where the platform
  /// supplies nothing — the seed is then used as usual.
  bool get useDynamicColor => _prefs.getBool(_dynamicColorKey) ?? false;

  Future<void> setUseDynamicColor(bool value) async {
    await _prefs.setBool(_dynamicColorKey, value);
    notifyListeners();
  }

  /// What the shelf boards are made of.
  ShelfMaterial get shelfMaterial {
    final stored = _prefs.getString(_shelfMaterialKey);
    return ShelfMaterial.values.where((m) => m.name == stored).firstOrNull ??
        ShelfMaterial.fallback;
  }

  Future<void> setShelfMaterial(ShelfMaterial value) async {
    await _prefs.setString(_shelfMaterialKey, value.name);
    notifyListeners();
  }

  /// Spine title size and thickness multipliers.
  SpineTypography get spineTypography => SpineTypography(
        titleScale: _prefs.getDouble(_spineTitleScaleKey) ?? 1.0,
        widthScale: _prefs.getDouble(_spineWidthScaleKey) ?? 1.0,
      );

  Future<void> setSpineTypography(SpineTypography value) async {
    await _prefs.setDouble(_spineTitleScaleKey, value.clampedTitle);
    await _prefs.setDouble(_spineWidthScaleKey, value.clampedWidth);
    notifyListeners();
  }

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

  /// Which resources a sync is allowed to touch (next features #8). Defaults
  /// to everything, so a device that never opens the screen syncs exactly as it
  /// did before.
  SyncScope get syncScope => SyncScope(
        books: _prefs.getBool('$_syncScopeKey.books') ?? true,
        copies: _prefs.getBool('$_syncScopeKey.copies') ?? true,
        loans: _prefs.getBool('$_syncScopeKey.loans') ?? true,
        annotations: _prefs.getBool('$_syncScopeKey.annotations') ?? true,
        sessions: _prefs.getBool('$_syncScopeKey.sessions') ?? true,
        copyPhotos: _prefs.getBool('$_syncScopeKey.copyPhotos') ?? true,
      );

  Future<void> setSyncScope(SyncScope value) async {
    await _prefs.setBool('$_syncScopeKey.books', value.books);
    await _prefs.setBool('$_syncScopeKey.copies', value.copies);
    await _prefs.setBool('$_syncScopeKey.loans', value.loans);
    await _prefs.setBool('$_syncScopeKey.annotations', value.annotations);
    await _prefs.setBool('$_syncScopeKey.sessions', value.sessions);
    await _prefs.setBool('$_syncScopeKey.copyPhotos', value.copyPhotos);
    notifyListeners();
  }

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

  // ---- Scheduled backups (plan 5 #13) -------------------------------------
  //
  // Deliberately *not* a passphrase store: an encrypted scheduled backup would
  // need the passphrase kept somewhere the app can read unattended, which is
  // the same as not encrypting it. Scheduled archives are therefore plain zips
  // and the UI says so; encryption stays a manual, you-are-present action.

  /// 'off' | 'daily' | 'weekly'.
  // ---- Background sync (plan 5 #40) ---------------------------------------
  //
  // 'off' | 'everySixHours' | 'daily'. **Off by default**: a local-first app
  // already works without it, so the only thing background sync can do to
  // someone who didn't ask for it is drain their phone.

  String get backgroundSyncInterval =>
      _prefs.getString(_backgroundSyncKey) ?? 'off';

  Future<void> setBackgroundSyncInterval(String value) async {
    await _prefs.setString(_backgroundSyncKey, value);
    notifyListeners();
  }

  DateTime? get lastBackgroundSyncAt {
    final stored = _prefs.getString(_lastBackgroundSyncKey);
    return stored == null ? null : DateTime.tryParse(stored);
  }

  Future<void> setLastBackgroundSyncAt(DateTime value) async {
    await _prefs.setString(_lastBackgroundSyncKey, value.toIso8601String());
    notifyListeners();
  }

  String get backupFrequency =>
      _prefs.getString(_backupFrequencyKey) ?? 'off';

  Future<void> setBackupFrequency(String value) async {
    await _prefs.setString(_backupFrequencyKey, value);
    notifyListeners();
  }

  String? get backupFolder {
    final stored = _prefs.getString(_backupFolderKey);
    return (stored == null || stored.isEmpty) ? null : stored;
  }

  Future<void> setBackupFolder(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_backupFolderKey);
    } else {
      await _prefs.setString(_backupFolderKey, path.trim());
    }
    notifyListeners();
  }

  /// How many scheduled archives to keep. Five by default — enough that a
  /// problem noticed a few days late is still recoverable from, few enough that
  /// a library's worth of zips doesn't quietly fill the disk.
  int get backupKeep => _prefs.getInt(_backupKeepKey) ?? 5;

  Future<void> setBackupKeep(int value) async {
    await _prefs.setInt(_backupKeepKey, value.clamp(1, 30));
    notifyListeners();
  }

  DateTime? get lastBackupAt {
    final stored = _prefs.getString(_lastBackupAtKey);
    return stored == null ? null : DateTime.tryParse(stored);
  }

  Future<void> setLastBackupAt(DateTime value) async {
    await _prefs.setString(_lastBackupAtKey, value.toIso8601String());
    notifyListeners();
  }

  /// Whether the first-run introduction has been shown (plan 5 #41). Set as soon
  /// as it opens, not when it completes: someone who swipes it away has answered,
  /// and showing it again next launch would be nagging.
  bool get hasSeenFirstRun => _prefs.getBool(_seenFirstRunKey) ?? false;

  Future<void> setHasSeenFirstRun(bool value) async {
    await _prefs.setBool(_seenFirstRunKey, value);
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
