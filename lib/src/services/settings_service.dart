import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user preferences (theme mode, walking time) to SharedPreferences.
class SettingsService {
  static const _themeModeKey = 'theme_mode';
  static const _walkTimeKey = 'walk_time_enabled';
  static const _busDataKey = 'bus_data_consent';
  static const _enabledModesKey = 'enabled_modes';
  static const _alertBannerKey = 'show_alert_banner';
  static const _staticWarningKey = 'show_static_warning';

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

  /// Whether the user agreed to download the (large) static bus timetable.
  Future<bool> getBusDataConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_busDataKey) ?? false;
  }

  Future<void> setBusDataConsent(bool consent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_busDataKey, consent);
  }

  /// Names of the transport modes the user has left switched on, or null
  /// when they've never changed it (all on).
  Future<List<String>?> getEnabledModes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_enabledModesKey);
  }

  Future<void> setEnabledModes(List<String> modeNames) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledModesKey, modeNames);
  }

  Future<bool> getShowAlertBanner() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_alertBannerKey) ?? true;
  }

  Future<void> setShowAlertBanner(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alertBannerKey, show);
  }

  Future<bool> getShowStaticWarning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_staticWarningKey) ?? true;
  }

  Future<void> setShowStaticWarning(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_staticWarningKey, show);
  }

  /// Reads the stored [ThemeMode]. Defaults to [ThemeMode.dark].
  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
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
