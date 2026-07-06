import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallpaper.dart';

/// App-wide preferences stored on device.
class AppSettingsStore extends ChangeNotifier {
  AppSettingsStore._(this._prefs);

  static const _wallpaperKey = 'settings.wallpaper';

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
}
