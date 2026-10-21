import 'package:flutter/material.dart';
import '../../services/settings_service.dart';

/// Manages the app's theme mode and persists user preference via [SettingsService].
class ThemeViewModel extends ChangeNotifier {
  final SettingsService _settingsService;

  ThemeMode _themeMode = ThemeMode.system;

  ThemeViewModel(this._settingsService);

  ThemeMode get themeMode => _themeMode;

  /// Loads the stored theme preference from [SettingsService].
  Future<void> loadTheme() async {
    _themeMode = await _settingsService.getThemeMode();
    notifyListeners();
  }

  /// Updates and persists the theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _settingsService.setThemeMode(mode);
  }
}
