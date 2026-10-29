import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';

import 'support/hive_test_harness.dart';

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open();
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

  Future<void> pumpEditorWithProvider(
    WidgetTester tester, {
    WorkoutPlan? plan,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 880);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => WorkoutPlanProvider(),
        child: MaterialApp(
          home:
              plan == null
                  ? const PlanEditorScreen.create()
                  : PlanEditorScreen.edit(plan),
        ),
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

  Future<void> openExerciseGroup(
    WidgetTester tester, {
    String group = 'Chest',
  }) async {
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(group));
    await tester.pumpAndSettle();
  }

  Future<void> closeExercisePicker(WidgetTester tester) async {
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // From a category or selected review, Done first returns to the groups.
    if (find.text('Done').evaluate().isNotEmpty) {
      expect(find.byKey(const ValueKey('muscle-group-grid')), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Add exercises'), findsNothing);
    expect(find.text('Done'), findsNothing);
  }

  testWidgets('add exercise sheet survives being closed', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'press',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await closeExercisePicker(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the exercise picker does not refocus the plan name', (
    tester,
  ) async {
    await pumpEditor(tester);
    final nameField = find.byType(TextField).first;
    await tester.tap(nameField);
    await tester.enterText(nameField, 'Push');
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);

    await openExerciseGroup(tester);
    await tester.tap(find.text('Bench Press').first);
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);

    final editable = tester.widget<EditableText>(
      find.descendant(of: nameField, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('picker opens on a two-column muscle group browser', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('muscle-group-grid')), findsOneWidget);
    for (final group in [
      'Chest',
      'Back',
      'Shoulders',
      'Arms',
      'Legs',
      'Core',
    ]) {
      expect(find.text(group), findsOneWidget);
    }
    expect(find.text('Bench Press'), findsNothing);
    final chestTile = find.ancestor(
      of: find.text('Chest'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(chestTile).height, greaterThanOrEqualTo(48));
  });

  testWidgets('exercise selection can be toggled off', (tester) async {
    await pumpEditor(tester);
    await openExerciseGroup(tester);
    expect(find.text('Selected (0)'), findsOneWidget);

    await tester.tap(find.text('Bench Press').last);
    await tester.pump();
    expect(find.text('Selected (1)'), findsOneWidget);

    await tester.tap(find.text('Bench Press').last);
    await tester.pump();
    expect(find.text('Selected (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan color selection exposes selected semantics', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Change color'));
    await tester.pumpAndSettle();
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
    await openExerciseGroup(tester);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);
    for (final label in ['Add set', 'Delete exercise']) {
      expect(
        tester.getSize(find.bySemanticsLabel(label)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('exercise picker tiles are at least 48 pixels high', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openExerciseGroup(tester);
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

  testWidgets('group navigation and clearing search restore the category', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Barbell Row'), findsOneWidget);
    expect(find.byTooltip('Muscle groups'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'press',
    );
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Chest'), findsWidgets);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Barbell Row'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
  });

  testWidgets('empty search offers custom creation with the query prefilled', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'Cable Halo',
    );
    await tester.pumpAndSettle();
    expect(find.text('No exercises found'), findsOneWidget);
    await tester.tap(find.text('Create “Cable Halo”'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .controller
          .text,
      'Cable Halo',
    );
  });

  testWidgets('selected review includes custom exercises and dismiss retains', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create custom exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Cable Halo');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Selected (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Selected exercises'), findsOneWidget);
    expect(find.text('Cable Halo'), findsWidgets);
    expect(find.text('Custom'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('Add exercises'), findsNothing);
    expect(find.text('Cable Halo'), findsOneWidget);
    expect(HiveService.getPlans(), isEmpty);
  });

  testWidgets('dirty back confirms discard and cancel preserves editor', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');
    await tester.tapAt(const Offset(32, 48));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Push Day'), findsOneWidget);
  });

  testWidgets('dirty back discard leaves the editor', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');
    await tester.tapAt(const Offset(32, 48));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('New plan'), findsNothing);
  });

  testWidgets('blank plan name disables save', (tester) async {
    await pumpEditor(tester);
    final save = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('Save'), matching: find.byType(InkWell))
          .first,
    );
    expect(save.onTap, isNull);
  });

  testWidgets('save control uses centered unbracketed text', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');

    final saveText = find.text('Save');
    expect(saveText, findsOneWidget);
    expect(find.text('[SAVE]'), findsNothing);

    final button = find.ancestor(of: saveText, matching: find.byType(InkWell));
    expect(tester.getCenter(saveText), tester.getCenter(button));
  });

  testWidgets('save and add exercise use the accent, not the plan color', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');
    // The label's colour animates in once Save enables.
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(PlanEditorScreen));
    Color? painted(String text) =>
        tester
            .widget<RichText>(
              find.descendant(
                of: find.text(text),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style
            ?.color;

    final save = find.ancestor(
      of: find.text('Save'),
      matching: find.byType(ElevatedButton),
    );
    final ground = tester.widget<Material>(
      find.descendant(of: save, matching: find.byType(Material)).first,
    );
    expect(ground.color, accentFillColor(context));
    expect(painted('Save'), onAccentColor(context));
    expect(ground.color, isNot(planColorOf(kPlanColors[0], context)));
    // The header stretches actions; Save must stay a 48px button inside it.
    expect(tester.getSize(save).height, 48);

    final add = find.ancestor(
      of: find.text('Add exercise'),
      matching: find.byType(OutlinedButton),
    );
    expect(painted('Add exercise'), accentColor(context));
    final outline = tester.widget<Material>(
      find.descendant(of: add, matching: find.byType(Material)).first,
    );
    expect((outline.shape! as OutlinedBorder).side.color, accentColor(context));
  });

  testWidgets('editor save and add exercise actions have 48 pixel targets', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');

    for (final label in ['Save', 'Add exercise']) {
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
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create custom exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pump();
    expect(find.text('Name cannot be empty'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Bench Press');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create custom exercise'));
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
    await tester.longPress(find.byKey(const ValueKey('set_entry_row_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete set'));
    await tester.pumpAndSettle();
    expect(find.text('Each exercise needs at least one set'), findsOneWidget);
    expect(find.bySemanticsLabel('Set 1 Kg'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
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
    expect(find.text('80'), findsOneWidget);
    await tester.ensureVisible(find.byType(ReorderableDragStartListener).last);
    await tester.timedDrag(
      find.byType(ReorderableDragStartListener).last,
      const Offset(0, -300),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Barbell Row')).dy,
      lessThan(tester.getTopLeft(find.text('Bench Press')).dy),
    );
  });

  testWidgets('collapsed rows show the target and last time in figures', (
    tester,
  ) async {
    // Real I/O: Hive writes don't complete under the widget test's fake time.
    await tester.runAsync(
      () => Hive.box<WorkoutSession>(HiveService.sessionsBox).add(
        WorkoutSession(
          date: DateTime(2026, 10, 1),
          planName: 'Push',
          exercises: [
            Exercise(
              name: 'Bench Press',
              sets: [
                gym.Set(weight: 70, reps: 12),
                gym.Set(weight: 70, reps: 10),
              ],
            ),
          ],
        ),
      ),
    );
    final plan = WorkoutPlan(
      name: 'Push',
      exercises: [
        ExerciseTemplate(
          name: 'Bench Press',
          sets: 3,
          setTargets: [
            for (var i = 0; i < 3; i++) SetTemplate(reps: 12, weight: 70),
          ],
        ),
        ExerciseTemplate(
          name: 'Incline Press',
          sets: 6,
          setTargets: [
            for (final reps in [12, 10, 8, 8, 6, 6])
              SetTemplate(reps: reps, weight: 60),
          ],
        ),
      ],
    );
    await pumpEditorWithPlan(tester, plan);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incline Press'));
    await tester.pumpAndSettle();

    final target = find.textContaining('3 × 12  ·  70 kg', findRichText: true);
    expect(target, findsOneWidget);
    final spans = <TextSpan>[];
    tester.widget<RichText>(target).text.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    expect(spans, isNotEmpty);
    for (final span in spans) {
      // google_fonts suffixes the family with its weight: Manrope_700.
      expect(span.style?.fontFamily, startsWith('Manrope'));
      expect(
        span.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    }
    expect(find.text('Last: 70 kg × 12'), findsOneWidget);

    // Mixed sets are listed up to four, then counted; never trained, no line.
    expect(
      find.textContaining(
        '60 × 12, 60 × 10, 60 × 8, 60 × 8  +2',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Last:'), findsOneWidget);
  });

  testWidgets('editor controls expose 48 pixel targets and set semantics', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openExerciseGroup(tester);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);
    final title = tester.widget<Text>(find.text('Bench Press'));
    expect(
      title.style?.fontFamily,
      isNot(GoogleFonts.jetBrainsMono().fontFamily),
    );

    expect(find.bySemanticsLabel('Set 1 Kg'), findsOneWidget);
    expect(
      tester.getSize(find.bySemanticsLabel('Set 1 Kg').first).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('new exercise starts with one set and icon footer actions', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openExerciseGroup(tester);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);

    expect(find.bySemanticsLabel('Set 1 Kg'), findsOneWidget);
    expect(find.text('[+ ADD SET]'), findsNothing);
    expect(find.text('[DELETE]'), findsNothing);
    expect(find.bySemanticsLabel('Add set'), findsOneWidget);
    expect(find.bySemanticsLabel('Delete exercise'), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
  });

  testWidgets('opening the keypad does not stretch the exercise card', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openExerciseGroup(tester);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);

    final card = find.ancestor(
      of: find.bySemanticsLabel('Set 1 Kg'),
      matching: find.byType(Container),
    );
    final before = tester.getSize(card.last).height;
    await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
    await tester.pumpAndSettle();
    expect(tester.getSize(card.last).height, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor remains renderable at compact width', (tester) async {
    await pumpEditor(tester, size: const Size(320, 700));
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('save persists the plan through the provider and Hive storage', (
    tester,
  ) async {
    await pumpEditorWithProvider(tester);
    await tester.enterText(find.byType(TextField).first, 'Persisted Push');
    await openExerciseGroup(tester);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);
    await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
    await tester.pumpAndSettle();
    for (final key in [
      '5',
      '0',
      '.',
      '2',
      '5',
      'Next',
      '1',
      '2',
      'RPE',
      '8',
      'Done',
    ]) {
      await tester.tap(find.text(key).last);
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Hive.box<WorkoutPlan>(HiveService.plansBox).flush();
    });
    await tester.pumpAndSettle();
    final saved = HiveService.getPlans();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Persisted Push');
    expect(saved.single.exercises.single.name, 'Bench Press');
    expect(saved.single.exercises.single.targetAt(0)!.weight, 50.25);
    expect(saved.single.exercises.single.targetAt(0)!.reps, 12);
    expect(saved.single.exercises.single.targetAt(0)!.rpe, 8);
    expect(HiveService.getSessions(), isEmpty);
  });
  testWidgets(
    'edit retains RPE when weight changes and copies it to new sets',
    (tester) async {
      final plan = WorkoutPlan(
        name: 'Effort',
        exercises: [
          ExerciseTemplate(
            name: 'Squat',
            sets: 1,
            setTargets: [SetTemplate(reps: 5, weight: 80, rpe: 8)],
          ),
        ],
      );
      await pumpEditorWithProvider(tester, plan: plan);
      expect(find.bySemanticsLabel('Set 1 RPE value 8'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
      await tester.pumpAndSettle();
      for (final key in ['9', '0']) {
        await tester.tap(find.text(key).last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.bySemanticsLabel('Hide keypad'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add set'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Set 2 RPE value 8'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Hive.box<WorkoutPlan>(HiveService.plansBox).flush();
      });
      await tester.pumpAndSettle();
      final targets =
          HiveService.getPlans().single.exercises.single.setTargets!;
      expect(targets.map((set) => (set.weight, set.reps, set.rpe)), [
        (90.0, 5, 8),
        (90.0, 5, 8),
      ]);
    },
  );

  testWidgets('header Back closes a dirty keypad before asking to discard', (
    tester,
  ) async {
    final plan = WorkoutPlan(
      name: 'Effort',
      exercises: [
        ExerciseTemplate(
          name: 'Squat',
          sets: 1,
          setTargets: [SetTemplate(reps: 5, weight: 80, rpe: 8)],
        ),
      ],
    );
    await pumpEditorWithPlan(tester, plan);
    await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Hide keypad'), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(PlanEditorScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
  });

  testWidgets('RPE-only edits count as unsaved and can be cleared', (
    tester,
  ) async {
    final plan = WorkoutPlan(
      name: 'Effort',
      exercises: [
        ExerciseTemplate(
          name: 'Squat',
          sets: 1,
          setTargets: [SetTemplate(reps: 5, weight: 80, rpe: 8)],
        ),
      ],
    );
    await pumpEditorWithPlan(tester, plan);
    await tester.ensureVisible(find.bySemanticsLabel('Set 1 RPE value 8'));
    await tester.tap(find.bySemanticsLabel('Set 1 RPE value 8'));
    await tester.pumpAndSettle();
    await tester.longPress(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Set 1 RPE value, not set'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
  });
}
