import 'package:gymapp/providers/settings_provider.dart';

/// Settings whose weight unit is fixed, for widgets that read the unit from
/// `SettingsProvider` without going through SharedPreferences.
class FixedUnitSettings extends SettingsProvider {
  final String unit;

  FixedUnitSettings(this.unit);

  @override
  String get weightUnit => unit;
}
