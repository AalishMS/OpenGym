/// Kilograms and pounds at the interface edge.
///
/// **Storage is always kilograms**: Hive, sync rows, backups, and the Coach's
/// request and response all hold kg. The unit a person picks in Settings only
/// changes what is shown and how typed values are read, so every conversion
/// lives here and every screen that prints or accepts a weight calls these
/// instead of repeating the factor.
///
/// Units travel as the strings `SettingsProvider.weightUnit` stores, `kg` or
/// `lbs`, which is also what backups carry.
library;

import 'format.dart';

const String kWeightUnitKg = 'kg';
const String kWeightUnitLbs = 'lbs';
const List<String> kWeightUnits = [kWeightUnitKg, kWeightUnitLbs];

/// The international pound, exactly.
const double kKilogramsPerPound = 0.45359237;

/// `lbs` for either spelling of pounds, `kg` for anything else, so an unknown
/// or missing preference reads as the storage unit.
String normalizeWeightUnit(String? unit) =>
    unit == kWeightUnitLbs || unit == 'lb' ? kWeightUnitLbs : kWeightUnitKg;

bool isPounds(String unit) => normalizeWeightUnit(unit) == kWeightUnitLbs;

/// A stored weight in [unit]. Full precision: round only when formatting.
double kilogramsToUnit(double kilograms, String unit) =>
    isPounds(unit) ? kilograms / kKilogramsPerPound : kilograms;

/// A weight read in [unit], as kilograms for storage.
double unitToKilograms(double value, String unit) =>
    isPounds(unit) ? value * kKilogramsPerPound : value;

/// The precision a weight is typed and shown with in the set table: two
/// decimals, so whatever the keypad accepts reads back unchanged.
double roundEntryWeight(double value) => (value * 100).roundToDouble() / 100;

/// A weight as the set table shows it, `135` or `61.23`: up to two decimals,
/// no trailing zeros.
String formatEntryValue(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// A stored weight in [unit] at set-table precision.
String formatEntryWeight(double kilograms, String unit) =>
    formatEntryValue(kilogramsToUnit(kilograms, unit));

/// A stored weight in [unit] for summaries: one decimal at most.
String formatWeightIn(double kilograms, String unit) =>
    formatWeight(kilogramsToUnit(kilograms, unit));

/// `70 kg` or `154.3 lbs`.
String formatWeightWithUnit(double kilograms, String unit) =>
    '${formatWeightIn(kilograms, unit)} ${weightUnitLabel(unit)}';

/// A stored volume load (kg × reps) in [unit], compacted like
/// `formatVolume`: `4.2K`.
String formatVolumeIn(num kilograms, String unit) =>
    formatVolume(kilogramsToUnit(kilograms.toDouble(), unit));

/// [entered], typed in [unit], as kilograms to store.
///
/// When [original] — the stored value the cell held when it was opened —
/// shows as the same figure, it is returned untouched. Without this, opening
/// a cell that reads `132.28` and typing `132.28` again would store
/// 60.0004 kg instead of the 60 kg already there.
double kilogramsFromEntry(double entered, String unit, {double? original}) {
  if (original != null &&
      roundEntryWeight(kilogramsToUnit(original, unit)) ==
          roundEntryWeight(entered)) {
    return original;
  }
  return unitToKilograms(entered, unit);
}

/// `kg` or `lbs`, after a figure.
String weightUnitLabel(String unit) =>
    isPounds(unit) ? kWeightUnitLbs : kWeightUnitKg;

/// The set table's column heading: `Kg` or `Lbs`.
String weightColumnLabel(String unit) => isPounds(unit) ? 'Lbs' : 'Kg';

/// The keypad's field name: `Weight (kg)` or `Weight (lbs)`.
String weightFieldLabel(String unit) => 'Weight (${weightUnitLabel(unit)})';

/// The unit as a screen reader should say it.
String weightUnitSpoken(String unit) =>
    isPounds(unit) ? 'pounds' : 'kilograms';

/// The keypad's quick-adjust steps for weight, larger first. Kilograms keep
/// 2.5 and 1; pounds step by the smallest common plate pair, 5 and 2.5.
({double large, double small}) weightSteps(String unit) =>
    isPounds(unit) ? (large: 5.0, small: 2.5) : (large: 2.5, small: 1.0);
