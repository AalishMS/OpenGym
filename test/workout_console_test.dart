import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/underline_tab_strip.dart';
import 'package:gymapp/widgets/workout/workout_dialogs.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(Widget child) => MaterialApp(
    theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
    home: Scaffold(body: child),
  );

  testWidgets('workout plan tabs render with a 48 pixel target', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const UnderlineTabStrip(
          height: 48,
          rule: StripRule.bottom,
          selectedIndex: 0,
          color: Color(0xFF7C5CFF),
          tabs: [UnderlineTabData(label: 'PLAN', onTap: null)],
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(UnderlineTabStrip)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('all workout action dialogs fit narrow scaled screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    for (final show in <void Function(BuildContext)>[
      (context) => WorkoutDialogs.showAddExerciseDialog(context, onAdd: (_) {}),
      (context) => WorkoutDialogs.showRenameExerciseDialog(
        context,
        currentName: 'Bench Press',
        onRename: (_) {},
      ),
      (context) => WorkoutDialogs.showAddSetDialog(context, onAdd: (_) {}),
      (context) => WorkoutDialogs.showEditSetDialog(
        context,
        set: gym.Set(weight: 100, reps: 5),
        onSave: (_) {},
        onDelete: () {},
      ),
      (context) =>
          WorkoutDialogs.showExerciseNoteDialog(context, onSave: (_) {}),
      (context) => WorkoutDialogs.showRenameWeekDialog(
        context,
        currentWeek: 12,
        onRename: (_) {},
      ),
      (context) => WorkoutDialogs.showDeleteWeekDialog(context, week: 12),
      (context) => WorkoutDialogs.showDeleteExerciseDialog(
        context,
        exerciseName: 'Bench Press',
      ),
      (context) =>
          WorkoutDialogs.showDeletePlanDialog(context, planName: 'Push Day'),
      (context) => WorkoutDialogs.showDiscardChangesDialog(context),
      (context) => WorkoutDialogs.showEditPlanSetDialog(
        context,
        setNumber: 1,
        reps: 12,
        weight: 137.5,
        accent: const Color(0xFF7C5CFF),
        onSave: (_, __) {},
      ),
    ]) {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
            home: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () => show(context),
                    child: const Text('[OPEN]'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('[OPEN]'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('exercise names and confirmation prose use sans typography', (
    tester,
  ) async {
    await tester.pumpWidget(host(const SizedBox()));
    final context = tester.element(find.byType(Scaffold));
    WorkoutDialogs.showAddExerciseDialog(context, onAdd: (_) {});
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).style?.fontFamily,
      isNot(startsWith('JetBrainsMono')),
    );
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    WorkoutDialogs.showDeleteExerciseDialog(
      context,
      exerciseName: 'Bench Press',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.textContaining('permanently delete'))
          .style
          ?.fontFamily,
      isNot(startsWith('JetBrainsMono')),
    );
  });

  testWidgets('selected RPE uses the solved accent fill pairing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: host(const SizedBox()),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    WorkoutDialogs.showAddSetDialog(context, onAdd: (_) {});
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.pump();

    final tile = tester.widget<Container>(
      find
          .ancestor(of: find.text('1').last, matching: find.byType(Container))
          .first,
    );
    final decoration = tile.decoration! as BoxDecoration;
    expect(decoration.color, accentFillColor(context));
    Navigator.of(context).pop();
  });
}
