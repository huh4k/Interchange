import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user preferences (theme mode, walking time) to SharedPreferences.
class SettingsService {
  static const _themeModeKey = 'theme_mode';
  static const _walkTimeKey = 'walk_time_enabled';

  /// Whether walking time to the selected station is shown. Off by default so
  /// the app never asks for location unprompted.
  Future<bool> getWalkTimeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_walkTimeKey) ?? false;
  }

  Future<void> setWalkTimeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_walkTimeKey, enabled);
  }

  /// Reads the stored [ThemeMode]. Defaults to [ThemeMode.system].
  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Saves [themeMode] to SharedPreferences.
  Future<void> setThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeModeKey, value);
  }
}
