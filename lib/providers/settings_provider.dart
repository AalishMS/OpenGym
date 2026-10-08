import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// **Order is persisted.** `_accentIndex` is stored as an integer, so indices
  /// Each index keeps its original color family so saved preferences survive
  /// palette refinements. Green remains at 7; cyan remains the default at 4.
  ///
  /// Every seed sits at OKLab lightness 0.72 — it is also the dark-mode accent
  /// — and is specified by hue and *vividness* (share of the sRGB chroma ceiling
  /// at that hue), not by absolute chroma. Vividness is what the roles carry
  /// into each mode, so matching it keeps the set evenly saturated: 0.64–0.85
  /// for the colours, lower for rose and violet, whose wide gamut reads as
  /// louder per unit, and 0.24 for slate.
  static const List<AppAccent> accents = [
    AppAccent(name: 'Blue', seed: Color(0xFF6AA9ED)), // h252 v.80
    AppAccent(name: 'Amber', seed: Color(0xFFDB9339)), // h68 v.85
    AppAccent(name: 'Coral', seed: Color(0xFFE98764)), // h40 v.72
    AppAccent(name: 'Rose', seed: Color(0xFFE282A4)), // h358 v.64
    AppAccent(name: 'Teal', seed: Color(0xFF41B9B9)), // h195 v.85
    AppAccent(name: 'Violet', seed: Color(0xFFA399E1)), // h290 v.66
    // Enough tint to stay distinct from disabled neutral text in light mode.
    AppAccent(name: 'Slate', seed: Color(0xFF96A6BB)), // h255 v.24
    AppAccent(name: 'Green', seed: Color(0xFF59BD79)), // h152 v.72
  ];

  ThemeMode _themeMode = defaultThemeMode;
  int _accentIndex = defaultAccentIndex;
  String _weightUnit = 'kg';
  bool _autoFillLast = true;

  ThemeMode get themeMode => _themeMode;
  int get accentIndex => _accentIndex;
  String get weightUnit => _weightUnit;
  bool get autoFillLast => _autoFillLast;

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
}
