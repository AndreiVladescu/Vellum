import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The local user profile.
///
/// Vellum is local-first, so for now the "account" lives on this device only.
/// When server sync lands, this becomes the identity used to sign in to a
/// library server. A [ChangeNotifier] so the drawer header updates on save.
class UserProfileStore extends ChangeNotifier {
  UserProfileStore._(this._prefs);

  static const _nameKey = 'profile.name';
  static const _emailKey = 'profile.email';

  final SharedPreferences _prefs;

  static Future<UserProfileStore> load() async =>
      UserProfileStore._(await SharedPreferences.getInstance());

  String get name => _prefs.getString(_nameKey) ?? '';
  String get email => _prefs.getString(_emailKey) ?? '';
  bool get isSet => name.isNotEmpty;

  String get initial => isSet ? name.trim()[0].toUpperCase() : '?';

  Future<void> save({required String name, required String email}) async {
    await _prefs.setString(_nameKey, name.trim());
    await _prefs.setString(_emailKey, email.trim());
    notifyListeners();
  }
}
