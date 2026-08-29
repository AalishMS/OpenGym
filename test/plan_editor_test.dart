import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/services/hive_service.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    hiveDirectory = await Directory.systemTemp.createTemp(
      'opengym_plan_editor_test_',
    );
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(400, 880),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PlanEditorScreen.create()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpEditorWithProvider(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 880);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => WorkoutPlanProvider(),
        child: const MaterialApp(home: PlanEditorScreen.create()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpEditorWithPlan(
    WidgetTester tester,
    WorkoutPlan plan, {
    Size size = const Size(400, 880),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PlanEditorScreen.edit(plan)));
    await tester.pumpAndSettle();
  }

  testWidgets('add exercise sheet survives being closed', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'press',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('[DONE]'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected category exposes selected semantics', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    final category = find.text('Chest');
    expect(
      tester
          .getSize(
            find.ancestor(of: category, matching: find.byType(InkWell)).first,
          )
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSemantics(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == 'Chest',
            )
            .first,
      ),
      matchesSemantics(
        label: 'Chest',
        isSelected: true,
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
      ),
    );
  });

  testWidgets('plan color selection exposes selected semantics', (
    tester,
  ) async {
    await pumpEditor(tester);
    final swatch = find.bySemanticsLabel('Plan color 1');
    expect(swatch, findsOneWidget);
    expect(
      tester.getSemantics(swatch),
      matchesSemantics(
        label: 'Plan color 1',
        isSelected: true,
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
      ),
    );
  });

  testWidgets('footer actions have effective 48 pixel hit regions', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[DONE]'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('[+ ADD SET]'),
              matching: find.byType(InkWell),
            ),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('[DELETE]'),
              matching: find.byType(InkWell),
            ),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('exercise picker tiles are at least 48 pixels high', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    final tile = find.ancestor(
      of: find.text('Bench Press'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'press',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsNWidgets(2));
  });

  testWidgets('dirty back confirms discard and cancel preserves editor', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');
    await tester.tapAt(const Offset(32, 48));
    await tester.pumpAndSettle();
    expect(find.text('> DISCARD CHANGES?'), findsOneWidget);
    await tester.tap(find.text('[KEEP EDITING]'));
    await tester.pumpAndSettle();
    expect(find.text('Push Day'), findsOneWidget);
  });

  testWidgets('dirty back discard leaves the editor', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');
    await tester.tapAt(const Offset(32, 48));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[DISCARD]'));
    await tester.pumpAndSettle();
    expect(find.text('CREATE PLAN'), findsNothing);
  });

  testWidgets('blank plan name disables save', (tester) async {
    await pumpEditor(tester);
    final save = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('[SAVE]'), matching: find.byType(InkWell))
          .first,
    );
    expect(save.onTap, isNull);
  });

  testWidgets('editor save and add exercise actions have 48 pixel targets', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');

    for (final label in ['[SAVE]', '[+ ADD EXERCISE]']) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      expect(target, findsOneWidget, reason: label);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('custom exercise rejects blank and duplicate names', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[+ CUSTOM]'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pump();
    expect(find.text('Name cannot be empty'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Bench Press');
    await tester.tap(find.text('[CANCEL]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[+ CUSTOM]'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Bench Press');
    await tester.pump();
    expect(find.text('Exercise with this name already exists'), findsOneWidget);
  });

  testWidgets('last set deletion preserves the set and shows protection', (
    tester,
  ) async {
    final plan = WorkoutPlan(
      name: 'Push',
      exercises: [
        ExerciseTemplate(
          name: 'Bench Press',
          sets: 1,
          setTargets: [SetTemplate(reps: 5, weight: 80)],
        ),
      ],
    );
    await pumpEditorWithPlan(tester, plan);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Delete set'));
    await tester.pumpAndSettle();
    expect(find.text('> Cannot delete the last set'), findsOneWidget);
    expect(find.bySemanticsLabel('Decrease weight'), findsOneWidget);
    expect(find.text('80kg x 5', findRichText: true), findsOneWidget);
  });

  testWidgets('edit loads persisted set targets and reorder changes order', (
    tester,
  ) async {
    final plan = WorkoutPlan(
      name: 'Pull',
      exercises: [
        ExerciseTemplate(
          name: 'Bench Press',
          sets: 1,
          setTargets: [SetTemplate(reps: 5, weight: 80)],
        ),
        ExerciseTemplate(
          name: 'Barbell Row',
          sets: 1,
          setTargets: [SetTemplate(reps: 8, weight: 60)],
        ),
      ],
    );
    await pumpEditorWithPlan(tester, plan);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('80kg x 5', findRichText: true), findsOneWidget);
    await tester.drag(
      find.byType(ReorderableDragStartListener).first,
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Barbell Row')).dy,
      lessThan(tester.getTopLeft(find.text('Bench Press')).dy),
    );
  });

  testWidgets('editor controls expose 48 pixel targets and set semantics', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[DONE]'));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Bench Press'));
    expect(
      title.style?.fontFamily,
      isNot(GoogleFonts.jetBrainsMono().fontFamily),
    );
    expect(find.bySemanticsLabel('Decrease weight'), findsNWidgets(3));
    expect(
      tester.getSize(find.bySemanticsLabel('Decrease weight').first),
        const Size(32, 32),
    );
  });

  testWidgets('editor remains renderable at compact width', (tester) async {
    await pumpEditor(tester, size: const Size(320, 700));
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('save persists the plan through the provider and Hive storage', (
    tester,
  ) async {
    await pumpEditorWithProvider(tester);
    await tester.enterText(find.byType(TextField).first, 'Persisted Push');
    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[DONE]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[SAVE]'));
    await tester.pumpAndSettle();
    final saved = HiveService.getPlans();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Persisted Push');
    expect(saved.single.exercises.single.name, 'Bench Press');
    expect(saved.single.exercises.single.setTargets, isNotNull);
  });
}
