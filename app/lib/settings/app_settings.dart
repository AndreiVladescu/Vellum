import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
