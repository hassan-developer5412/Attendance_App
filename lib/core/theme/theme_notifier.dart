import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode persisted to local storage.
///
/// Defaults to [ThemeMode.system] so the app follows the device theme until the
/// user explicitly picks Light or Dark from the Settings page.
class ThemeNotifier extends ChangeNotifier {
  static const _prefKey = 'theme_mode';

  ThemeNotifier() : _mode = ThemeMode.system {
    _load();
  }

  ThemeMode _mode;

  ThemeMode get themeMode => _mode;

  /// Loads the persisted theme mode (or system if none saved).
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_prefKey);
    if (index != null && index >= 0 && index <= 2) {
      _mode = ThemeMode.values[index];
    }
    notifyListeners();
  }

  /// Persists and applies a new theme mode. Rebuilds the entire app via
  /// [ChangeNotifier] so [MaterialApp.themeMode] updates immediately.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, mode.index);
  }
}
