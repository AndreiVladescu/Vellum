import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_face.dart';
import 'wallpaper.dart';

/// App-wide preferences stored on device.
class AppSettingsStore extends ChangeNotifier {
  AppSettingsStore._(this._prefs);

  static const _wallpaperKey = 'settings.wallpaper';
  static const _bookFaceKey = 'settings.bookFace';

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
}
