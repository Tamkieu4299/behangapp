import 'package:shared_preferences/shared_preferences.dart';

/// Per-device settings. Currently holds the daily clip length
/// (PRD Feature 03: videos auto-trim to 1.0s by default, configurable up
/// to 3.0s).
class AppSettings {
  static const String _clipSecondsKey = 'clip_duration_seconds';

  static const List<double> clipChoices = [1.0, 2.0, 3.0];

  static double clipSeconds(SharedPreferences? prefs) =>
      (prefs?.getDouble(_clipSecondsKey) ?? 1.0);

  static Future<double> loadClipSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return clipSeconds(prefs);
  }

  static Future<void> setClipSeconds(double seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_clipSecondsKey, seconds);
  }
}