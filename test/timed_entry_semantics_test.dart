import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:gymapp/widgets/workout/set_entry_table.dart';

import 'support/test_fonts.dart';
import 'support/hive_test_harness.dart';

void main() {
  final storage = HiveTestHarness();
  setUpAll(() async {
    await loadTestFonts();
    await storage.open();
  });
  tearDownAll(storage.close);

  for (final name in ['Plank', 'Bench Press', 'My hold']) {
    testWidgets('$name uses its measurement in logger and keypad', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      int? changed;
      final timed = name == 'Plank';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseCard(
              exercise: Exercise(
                name: name,
                sets: [gym.Set(weight: 0, reps: 30)],
              ),
              exerciseIndex: 0,
              accent: ThemeData().colorScheme.primary,
              previousSets: [gym.Set(weight: 0, reps: 25)],
              onSetChanged: (_, _, _, reps) => changed = reps,
              onSetRpeChanged: (_, _, _) {},
              onAddSet: (_) {},
              onDeleteSet: (_, _) {},
              onAddNote: (_) {},
              onRename: (_) {},
              onDeleteExercise: (_) {},
            ),
          ),
        ),
      );
      final label = timed ? 'Seconds' : 'Reps';
      expect(find.text(label), findsOneWidget);
      expect(find.text(timed ? '0 × 25 s' : '0 × 25'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Set 1 $label'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(RegExp('Set 1.*$label'), findRichText: true),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(timed ? '+1 seconds' : '+1 reps'),
        findsOneWidget,
      );
      await tester.tap(find.text('4'));
      await tester.pump();
      expect(changed, 4);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    });
  }

  testWidgets('RPE is an accessible editable field at large text sizes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    int? effort;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SetEntryTable(
              sets: const [SetEntry(weight: 0, reps: 30)],
              isTimed: true,
              scrollWideTable: true,
              continuousLog: true,
              onChanged: (_, _, _) {},
              onRpeChanged: (_, value) => effort = value,
            ),
          ),
        ),
      ),
    );
    final field = find.bySemanticsLabel('Set 1 RPE');
    await tester.ensureVisible(field);
    expect(
      tester
          .getSemantics(field)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.pump();
    expect(effort, 8);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('read-only exercise removes all entry actions', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExerciseCard(
            exercise: Exercise(
              name: 'Plank',
              sets: [gym.Set(weight: 0, reps: 30, rpe: 7)],
            ),
            exerciseIndex: 0,
            readOnly: true,
            accent: ThemeData().colorScheme.primary,
            onSetRpeChanged: (_, _, _) => fail('Read-only RPE changed'),
            onAddSet: (_) {},
            onDeleteSet: (_, _) {},
            onAddNote: (_) {},
            onRename: (_) {},
            onDeleteExercise: (_) {},
          ),
        ),
      ),
    );
    for (final label in ['Set 1 Seconds', 'Set 1 RPE']) {
      final field = find.bySemanticsLabel(label);
      expect(
        tester
            .getSemantics(field)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('plan targets preserve seconds and ordinary reps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlanEditorScreen.edit(
          WorkoutPlan(
            name: 'Mixed',
            exercises: [
              ExerciseTemplate(
                name: 'Plank',
                sets: 1,
                setTargets: [SetTemplate(reps: 45, weight: 0)],
              ),
              ExerciseTemplate(
                name: 'Bench Press',
                sets: 1,
                setTargets: [SetTemplate(reps: 8, weight: 20)],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tables =
        tester.widgetList<SetEntryTable>(find.byType(SetEntryTable)).toList();
    expect(tables.map((table) => table.isTimed), [true, false]);
    expect(tables.map((table) => table.sets.single.reps), [45, 8]);
    await tester.tap(find.text('Plank'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'1.*45 s'), findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Plank'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Set 1 Seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<SetEntryTable>(find.byType(SetEntryTable))
          .first
          .sets
          .single
          .reps,
      6,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
