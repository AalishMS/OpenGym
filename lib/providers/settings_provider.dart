import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _refreshRateChannel = MethodChannel('com.aalishms.opengym/refresh_rate');

/// A user-selectable accent, stored as a single **seed**.
///
/// There used to be a hand-picked `dark`/`light` pair here, and both were wrong
/// often enough to matter: the light hexes were only reachable through
/// `accentColorLight`, which one file read, so light mode drew the dark palette
/// (CYAN at 1.79:1), and four of the seven intended light values missed 4.5:1
/// anyway. A seed carries only hue and chroma; every *role* — the text accent,
/// the fill, its label, the two washes — is solved per brightness against the
/// real ground in `buildTheme`. There is no per-mode value left to get wrong.
class AppAccent {
  final String name;

  /// Hue and chroma. Its lightness is a starting point, not a promise: roles
  /// move it as far as legibility demands and no further.
  final Color seed;

  const AppAccent({required this.name, required this.seed});
}

class SettingsProvider with ChangeNotifier {
  static const ThemeMode defaultThemeMode = ThemeMode.light;
  static const int defaultAccentIndex = 4;

  static const String _themeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _weightUnitKey = 'weight_unit';
  static const String _autoFillKey = 'auto_fill_last';
  static const String _highRefreshRateKey = 'high_refresh_rate';

  /// **Order is persisted.** `_accentIndex` is stored as an integer, so indices
  /// 0–6 must keep the accent they have always named. GREEN is therefore
  /// appended at 7 rather than slotted next to CYAN where it belongs visually —
  /// reordering would silently repaint every existing user's app.
  static const List<AppAccent> accents = [
    AppAccent(name: 'ELECTRIC BLUE', seed: Color(0xFF00A8FF)),
    AppAccent(name: 'WARM AMBER', seed: Color(0xFFFF9500)),
    AppAccent(name: 'DEEP ORANGE', seed: Color(0xFFFF5722)),
    AppAccent(name: 'HOT PINK', seed: Color(0xFFFF1493)),
    AppAccent(name: 'CYAN', seed: Color(0xFF00CED1)),
    AppAccent(name: 'PURPLE', seed: Color(0xFF8B5CF6)),
    // A slate, not the old flat #A0A0A0. Zero chroma made it resolve to exactly
    // textSecondary in light mode — the same grey as disabled text — so it needs
    // just enough tint to stay a colour while still reading as grey.
    AppAccent(name: 'STEEL GRAY', seed: Color(0xFF7C8AA0)),
    // Fills the 146° gap the old set left between CYAN and WARM AMBER, and a
    // gym app wants a green.
    AppAccent(name: 'GREEN', seed: Color(0xFF22C55E)),
  ];

  ThemeMode _themeMode = defaultThemeMode;
  int _accentIndex = defaultAccentIndex;
  String _weightUnit = 'kg';
  bool _autoFillLast = true;
  bool _highRefreshRate = true;

  ThemeMode get themeMode => _themeMode;
  int get accentIndex => _accentIndex;
  String get weightUnit => _weightUnit;
  bool get autoFillLast => _autoFillLast;
  bool get highRefreshRate => _highRefreshRate;

  /// The active accent's seed — the *only* accent value that leaves this
  /// provider, and it exists for exactly one caller: `main.dart`, which hands it
  /// to `buildTheme` once per brightness.
  ///
  /// Widgets must not read this. A seed is not a colour you can paint: it has no
  /// mode and no guaranteed contrast. Use `accentColor(context)` (or
  /// `accentFillColor` / `accentMutedColor` / `accentDimColor`) from
  /// `theme/app_theme.dart`, which return tones already solved against the ground
  /// they will actually be drawn on. The getter this replaces returned the dark
  /// hex unconditionally, and twenty-six widgets read it — which is precisely how
  /// light mode ended up unthemed.
  Color get accentSeed => accents[_accentIndex].seed;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // These fallbacks apply only when a preference has never been written, so
    // existing users keep their chosen theme and accent.
    final themeIndex =
        prefs.getInt(_themeKey) ?? SettingsProvider.defaultThemeMode.index;
    _themeMode = ThemeMode.values[themeIndex];

    final accentColorIndex =
        prefs.getInt(_accentColorKey) ?? SettingsProvider.defaultAccentIndex;
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
