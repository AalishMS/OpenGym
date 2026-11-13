import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/weight_units.dart';
import 'package:gymapp/widgets/coach/coach_diff_card.dart';
import 'package:gymapp/widgets/workout/set_entry_table.dart';
import 'package:gymapp/widgets/workout/workout_dialogs.dart';

import 'support/fixed_unit_settings.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('conversion', () {
    test('kilograms to pounds and back', () {
      expect(kilogramsToUnit(100, 'lbs'), closeTo(220.4623, 1e-4));
      expect(unitToKilograms(220.46226218, 'lbs'), closeTo(100, 1e-8));
      expect(unitToKilograms(135, 'lbs'), closeTo(61.23496995, 1e-8));
      expect(kilogramsToUnit(61.23496995, 'lbs'), closeTo(135, 1e-7));
    });

    test('kilograms pass through unchanged', () {
      expect(kilogramsToUnit(61.2349, 'kg'), 61.2349);
      expect(unitToKilograms(61.2349, 'kg'), 61.2349);
      expect(formatEntryWeight(50.25, 'kg'), '50.25');
      expect(formatWeightWithUnit(70, 'kg'), '70 kg');
    });

    test('a weight typed in pounds reads back as typed', () {
      for (final typed in [135.0, 45.0, 225.0, 102.5, 1.25, 999.0, 0.0]) {
        final stored = kilogramsFromEntry(typed, 'lbs');
        expect(formatEntryWeight(stored, 'lbs'), formatEntryValue(typed));
      }
      expect(formatEntryWeight(unitToKilograms(135, 'lbs'), 'lbs'), '135');
      expect(
        formatWeightWithUnit(unitToKilograms(135, 'lbs'), 'lbs'),
        '135 lbs',
      );
    });

    test('retyping the figure a cell showed keeps the stored kilograms', () {
      // 60 kg reads 132.25 lbs; typing 132.25 again must not store 59.988.
      expect(formatEntryWeight(60, 'lbs'), '132.25');
      expect(kilogramsFromEntry(132.25, 'lbs', original: 60), 60);
      // 102.5 kg (225.97 lbs) reads 226; retyping 226 keeps 102.5 kg.
      expect(formatEntryWeight(102.5, 'lbs'), '226');
      expect(kilogramsFromEntry(226, 'lbs', original: 102.5), 102.5);
      expect(
        kilogramsFromEntry(135, 'lbs', original: 60),
        unitToKilograms(135, 'lbs'),
      );
      expect(kilogramsFromEntry(60, 'kg', original: 60.004), 60.004);
      expect(kilogramsFromEntry(62.5, 'kg', original: 60), 62.5);
    });

    test('pounds show to the nearest quarter pound', () {
      // Kilogram logs converted to pounds: 225.97, 203.93, 407.86, 104.72.
      expect(formatEntryWeight(102.5, 'lbs'), '226');
      expect(formatEntryWeight(92.5, 'lbs'), '204');
      expect(formatEntryWeight(185, 'lbs'), '407.75');
      expect(formatEntryWeight(47.5, 'lbs'), '104.75');
      expect(formatEntryWeight(unitToKilograms(225.5, 'lbs'), 'lbs'), '225.5');
      expect(
        formatEntryWeight(unitToKilograms(225.25, 'lbs'), 'lbs'),
        '225.25',
      );
      // Summaries round the same way rather than to one decimal.
      expect(formatWeightIn(185, 'lbs'), '407.75');
      expect(formatWeightWithUnit(102.5, 'lbs'), '226 lbs');
      expect(formatShownWeight(203.93, 'lbs'), '204');
      // Kilograms are untouched.
      expect(formatEntryWeight(61.23, 'kg'), '61.23');
      expect(formatWeightIn(61.25, 'kg'), '61.3');
    });

    test('units normalize, label, and step per unit', () {
      expect(normalizeWeightUnit(null), 'kg');
      expect(normalizeWeightUnit('lb'), 'lbs');
      expect(normalizeWeightUnit('lbs'), 'lbs');
      expect(normalizeWeightUnit('stone'), 'kg');
      expect(weightColumnLabel('kg'), 'Kg');
      expect(weightColumnLabel('lbs'), 'Lbs');
      expect(weightFieldLabel('lbs'), 'Weight (lbs)');
      expect(weightUnitSpoken('lbs'), 'pounds');
      expect(weightSteps('kg'), (large: 2.5, small: 1.0));
      expect(weightSteps('lbs'), (large: 5.0, small: 2.5));
      expect(formatVolumeIn(1000, 'lbs'), '2.2K');
      expect(formatVolumeIn(1000, 'kg'), '1.0K');
    });

    test('the Coach review converts for display only', () {
      const sets = [
        CoachSet(reps: 8, kg: 60),
        CoachSet(reps: 8, kg: 60),
        CoachSet(reps: 6, kg: 0),
      ];
      expect(formatCoachSets(sets), '2 × 8 · 60 kg, 1 × 6');
      expect(
        formatCoachSets(sets, weightUnit: 'lbs'),
        '2 × 8 · 132.25 lbs, 1 × 6',
      );
      // The sets themselves are untouched kilograms.
      expect(sets.first.toJson(), {'reps': 8, 'kg': 60});
    });
  });

  group('set entry keypad', () {
    Widget host(
      List<SetEntry> entries,
      void Function(int, double, int) onChanged, {
      String? weightUnit,
      SettingsProvider? settings,
    }) {
      final app = MaterialApp(
        theme: buildTheme(const Color(0xFF00BCD4), Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SetEntryTable(
              sets: entries,
              weightUnit: weightUnit,
              onChanged: onChanged,
            ),
          ),
        ),
      );
      if (settings == null) return app;
      return ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: app,
      );
    }

    Future<void> tap(WidgetTester tester, String text) async {
      await tester.tap(find.widgetWithText(TextButton, text).last);
      await tester.pumpAndSettle();
    }

    Future<void> hide(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.bySemanticsLabel('Hide keypad'),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool enabled(WidgetTester tester, String label) =>
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, label))
            .onPressed !=
        null;

    testWidgets('pounds label every weight surface and step by plates', (
      tester,
    ) async {
      final entries = [
        SetEntry(
          weight: unitToKilograms(135, 'lbs'),
          reps: 5,
          previous: '${formatEntryWeight(60, 'lbs')} × 5',
        ),
      ];
      final changes = <double>[];
      await tester.pumpWidget(
        host(entries, (i, weight, reps) {
          changes.add(weight);
          entries[i] = SetEntry(
            weight: weight,
            reps: reps,
            previous: entries[i].previous,
          );
        }, weightUnit: 'lbs'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lbs'), findsOneWidget);
      expect(find.text('Kg'), findsNothing);
      expect(find.text('135'), findsOneWidget);
      expect(find.text('132.25 × 5'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Set 1 Lbs'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Weight (lbs)', findRichText: true),
        findsOneWidget,
      );
      for (final label in ['+5', '−5', '+2.5', '−2.5']) {
        expect(enabled(tester, label), isTrue, reason: label);
      }
      expect(find.widgetWithText(TextButton, '+1'), findsNothing);
      expect(find.bySemanticsLabel('+5 pounds'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Set 1 Lbs').last).value,
        '135 pounds',
      );

      await tap(tester, '+5');
      expect(changes.last, closeTo(unitToKilograms(140, 'lbs'), 1e-9));
      await tap(tester, '−2.5');
      expect(changes.last, closeTo(unitToKilograms(137.5, 'lbs'), 1e-9));

      // Reps keep their ±1 in pounds; the plate steps switch off.
      await tap(tester, 'Next');
      expect(find.widgetWithText(TextButton, '+2.5'), findsNothing);
      expect(enabled(tester, '+1'), isTrue);
      expect(enabled(tester, '−1'), isTrue);
      expect(enabled(tester, '+5'), isFalse);
      await tap(tester, '+1');
      expect(entries.first.reps, 6);
      expect(changes.last, closeTo(unitToKilograms(137.5, 'lbs'), 1e-9));
    });

    testWidgets('a kilogram log steps from its rounded pound figure', (
      tester,
    ) async {
      // 102.5 kg is 225.97 lbs, shown as 226.
      final entries = [const SetEntry(weight: 102.5, reps: 5)];
      final changes = <double>[];
      await tester.pumpWidget(
        host(entries, (i, weight, reps) {
          changes.add(weight);
          entries[i] = SetEntry(weight: weight, reps: reps);
        }, weightUnit: 'lbs'),
      );
      await tester.pumpAndSettle();
      expect(find.text('226'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Set 1 Lbs'));
      await tester.pumpAndSettle();
      await tap(tester, '+5');
      expect(changes.last, closeTo(unitToKilograms(231, 'lbs'), 1e-9));
      // Stepping back to the figure it opened on restores the exact kilograms.
      await tap(tester, '−5');
      expect(changes.last, 102.5);
    });

    testWidgets('135 typed in pounds is stored in kilograms and reads 135', (
      tester,
    ) async {
      final entries = [const SetEntry(weight: 0, reps: 5)];
      await tester.pumpWidget(
        host(entries, (i, weight, reps) {
          entries[i] = SetEntry(weight: weight, reps: reps);
        }, weightUnit: 'lbs'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Set 1 Lbs'));
      await tester.pumpAndSettle();
      for (final key in ['1', '3', '5']) {
        await tap(tester, key);
      }
      expect(entries.first.weight, unitToKilograms(135, 'lbs'));
      expect(entries.first.weight, closeTo(61.235, 1e-3));
      await hide(tester);

      // Leave and come back: the cell and the keypad both read 135.
      await tester.pumpWidget(
        host(List.of(entries), (i, weight, reps) {
          entries[i] = SetEntry(weight: weight, reps: reps);
        }, weightUnit: 'lbs'),
      );
      await tester.pumpAndSettle();
      expect(find.text('135'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Set 1 Lbs'));
      await tester.pumpAndSettle();
      expect(find.text('135'), findsNWidgets(2));
    });

    testWidgets('opening an unchanged cell never rewrites its kilograms', (
      tester,
    ) async {
      final changes = <double>[];
      final entries = [const SetEntry(weight: 60, reps: 8)];
      await tester.pumpWidget(
        host(entries, (i, weight, reps) {
          changes.add(weight);
          entries[i] = SetEntry(weight: weight, reps: reps);
        }, weightUnit: 'lbs'),
      );
      await tester.pumpAndSettle();
      expect(find.text('132.25'), findsOneWidget);

      // Open and close: nothing is written.
      await tester.tap(find.bySemanticsLabel('Set 1 Lbs'));
      await tester.pumpAndSettle();
      await hide(tester);
      expect(changes, isEmpty);

      // Retyping the figure it showed restores 60 exactly, not 59.988.
      await tester.tap(find.bySemanticsLabel('Set 1 Lbs'));
      await tester.pumpAndSettle();
      for (final key in ['1', '3', '2', '.', '2', '5']) {
        await tap(tester, key);
      }
      expect(changes.last, 60);

      // Editing reps hands the stored weight back untouched.
      await tap(tester, 'Next');
      await tap(tester, '9');
      expect(entries.first.reps, 9);
      expect(changes.last, 60);
      await hide(tester);
    });

    testWidgets('the table follows SettingsProvider when no unit is passed', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          [SetEntry(weight: unitToKilograms(225, 'lbs'), reps: 5)],
          (_, __, ___) {},
          settings: FixedUnitSettings('lbs'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lbs'), findsOneWidget);
      expect(find.text('225'), findsOneWidget);
    });

    testWidgets('the edit-set sheet shows pounds and saves exact kilograms', (
      tester,
    ) async {
      final original = gym.Set(weight: unitToKilograms(135, 'lbs'), reps: 5);
      final saved = <gym.Set>[];
      Future<void> open() async {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: FixedUnitSettings('lbs'),
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF00BCD4), Brightness.light),
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => WorkoutDialogs.showEditSetDialog(
                            context,
                            set: saved.isEmpty ? original : saved.last,
                            onSave: saved.add,
                            onDelete: () {},
                          ),
                      child: const Text('Open'),
                    ),
              ),
            ),
          ),
        ),
      );

      // Untouched, a save hands back the stored kilograms bit for bit.
      await open();
      expect(find.text('Lbs'), findsOneWidget);
      expect(find.text('135'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.single.weight, original.weight);

      // Typed in pounds, stored in kilograms.
      await open();
      await tester.tap(find.bySemanticsLabel('Set 1 Lbs'));
      await tester.pumpAndSettle();
      for (final key in ['2', '2', '5']) {
        await tap(tester, key);
      }
      await hide(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.last.weight, unitToKilograms(225, 'lbs'));
    });

    testWidgets('kilograms stay the default with the original keys', (
      tester,
    ) async {
      final changes = <double>[];
      await tester.pumpWidget(
        host([const SetEntry(weight: 60, reps: 8)], (_, weight, __) {
          changes.add(weight);
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kg'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Weight (kg)', findRichText: true),
        findsOneWidget,
      );
      for (final label in ['+2.5', '−2.5', '+1', '−1']) {
        expect(enabled(tester, label), isTrue, reason: label);
      }
      expect(find.bySemanticsLabel('+2.5 kilograms'), findsOneWidget);
      await tap(tester, '+2.5');
      expect(changes.last, 62.5);
      await tap(tester, '7');
      expect(changes.last, 7);
      await hide(tester);
    });
  });
}
