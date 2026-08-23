import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _refreshRateChannel = MethodChannel('com.aalishms.opengym/refresh_rate');

class AppAccent {
  final String name;
  final Color dark;
  final Color light;

  const AppAccent({
    required this.name,
    required this.dark,
    required this.light,
  });

  Color forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }
}

class SettingsProvider with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _weightUnitKey = 'weight_unit';
  static const String _autoFillKey = 'auto_fill_last';
  static const String _highRefreshRateKey = 'high_refresh_rate';

  static const List<AppAccent> accents = [
    AppAccent(
        name: 'ELECTRIC BLUE',
        dark: Color(0xFF00A8FF),
        light: Color(0xFF0077CC)),
    AppAccent(
        name: 'WARM AMBER', dark: Color(0xFFFF9500), light: Color(0xFFCC7700)),
    AppAccent(
        name: 'DEEP ORANGE', dark: Color(0xFFFF5722), light: Color(0xFFE64A19)),
    AppAccent(
        name: 'HOT PINK', dark: Color(0xFFFF1493), light: Color(0xFFCC1177)),
    AppAccent(name: 'CYAN', dark: Color(0xFF00CED1), light: Color(0xFF00A5A8)),
    AppAccent(
        name: 'PURPLE', dark: Color(0xFF8B5CF6), light: Color(0xFF6D28D9)),
    AppAccent(
        name: 'STEEL GRAY', dark: Color(0xFFA0A0A0), light: Color(0xFF666666)),
  ];

  ThemeMode _themeMode = ThemeMode.dark;
  int _accentIndex = 0;
  String _weightUnit = 'kg';
  bool _autoFillLast = true;
  bool _highRefreshRate = true;

  ThemeMode get themeMode => _themeMode;
  int get accentIndex => _accentIndex;
  String get weightUnit => _weightUnit;
  bool get autoFillLast => _autoFillLast;
  bool get highRefreshRate => _highRefreshRate;

  Color get accentColor => accents[_accentIndex].dark;

  Color accentColorFor(Brightness brightness) {
    return accents[_accentIndex].forBrightness(brightness);
  }

  Color get accentColorDark => accents[_accentIndex].dark;
  Color get accentColorLight => accents[_accentIndex].light;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Dark-first: default to ThemeMode.dark (index 2) when unset, matching the
    // field initializer and the terminal aesthetic. ThemeMode = {system, light, dark}.
    final themeIndex = prefs.getInt(_themeKey) ?? 2;
    _themeMode = ThemeMode.values[themeIndex];

    final accentColorIndex = prefs.getInt(_accentColorKey) ?? 0;
    if (accentColorIndex >= 0 && accentColorIndex < accents.length) {
      _accentIndex = accentColorIndex;
    }

    _weightUnit = prefs.getString(_weightUnitKey) ?? 'kg';
    _autoFillLast = prefs.getBool(_autoFillKey) ?? true;
    _highRefreshRate = prefs.getBool(_highRefreshRateKey) ?? true;

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setAccentColor(int index) async {
    if (index >= 0 && index < accents.length) {
      _accentIndex = index;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_accentColorKey, index);
      notifyListeners();
    }
  }

  Future<void> setWeightUnit(String unit) async {
    _weightUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weightUnitKey, unit);
    notifyListeners();
  }

  Future<void> setAutoFillLast(bool value) async {
    _autoFillLast = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoFillKey, value);
    notifyListeners();
  }

  Future<void> setHighRefreshRate(bool value) async {
    _highRefreshRate = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highRefreshRateKey, value);
    try {
      await _refreshRateChannel.invokeMethod('setHighRefreshRate', value);
    } catch (e) {
      debugPrint('Failed to set high refresh rate: $e');
    }
    notifyListeners();
  }
}
