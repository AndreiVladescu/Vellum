import 'package:shared_preferences/shared_preferences.dart';

/// Playback speed and the sleep timer's arithmetic: the pure part, so it is
/// tested without a player.

/// The slowest and fastest speed the player offers.
const double minSpeed = 0.5;
const double maxSpeed = 3.0;

/// The slider's step.
const double speedStep = 0.05;

/// One-tap speeds beside the slider.
const List<double> speedPresets = [0.75, 1.0, 1.25, 1.5, 2.0];

/// [speed] clamped into range and snapped to [speedStep], so 1.2500001 from a
/// slider and 7.0 from a corrupt preference both land somewhere sensible.
double normaliseSpeed(double speed) {
  if (speed.isNaN) return 1.0;
  final clamped = speed.clamp(minSpeed, maxSpeed).toDouble();
  // Rounded to two decimals again: 25 * 0.05 is 1.2500000000000002.
  return double.parse(((clamped / speedStep).round() * speedStep).toStringAsFixed(2));
}

/// "1.25×", "1×": no trailing zeros.
String formatSpeed(double speed) {
  final fixed = normaliseSpeed(speed).toStringAsFixed(2);
  final trimmed =
      fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$trimmed×';
}

/// The durations offered by the sleep timer, in minutes. "End of chapter" is
/// the other choice and has no length.
const List<int> sleepMinutes = [5, 10, 15, 30, 45, 60];

/// How long the volume takes to reach zero before the timer stops playback.
const Duration sleepFade = Duration(seconds: 10);

/// The volume for a sleep timer with [remaining] (wall-clock) time left:
/// full until the last [fade], then a straight line down to silence.
double sleepVolume(Duration remaining, {Duration fade = sleepFade}) {
  if (remaining >= fade) return 1.0;
  if (remaining <= Duration.zero) return 0.0;
  return remaining.inMicroseconds / fade.inMicroseconds;
}

/// Where each book's speed is remembered.
abstract class SpeedStore {
  Future<double?> read(String bookId);
  Future<void> write(String bookId, double speed);
}

/// Per book, per device, in the preferences: no schema change and nothing to
/// sync. How fast you like a narrator is a habit of the listener, not data
/// about the book. A speed of 1.0 removes the entry.
class PrefsSpeedStore implements SpeedStore {
  PrefsSpeedStore([this._prefs]);

  SharedPreferences? _prefs;
  static String _key(String bookId) => 'listen.speed.$bookId';

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<double?> read(String bookId) async {
    final v = (await _p).getDouble(_key(bookId));
    return v == null ? null : normaliseSpeed(v);
  }

  @override
  Future<void> write(String bookId, double speed) async {
    final prefs = await _p;
    if ((speed - 1.0).abs() < 0.001) {
      await prefs.remove(_key(bookId));
    } else {
      await prefs.setDouble(_key(bookId), normaliseSpeed(speed));
    }
  }
}

/// For tests.
class MemorySpeedStore implements SpeedStore {
  final values = <String, double>{};
  @override
  Future<double?> read(String bookId) async => values[bookId];
  @override
  Future<void> write(String bookId, double speed) async => values[bookId] = speed;
}
