import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/data/plan_starters.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/weight_units.dart';
import 'package:gymapp/widgets/motion/entrance.dart';
import 'package:gymapp/widgets/workout/set_entry_table.dart';

import 'support/fixed_unit_settings.dart';
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
    await ExerciseCatalog.clear();
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
    String? weightUnit,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final app = MaterialApp(home: PlanEditorScreen.edit(plan));
    await tester.pumpWidget(
      weightUnit == null
          ? app
          : ChangeNotifierProvider<SettingsProvider>.value(
            value: FixedUnitSettings(weightUnit),
            child: app,
          ),
    );
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
    await tester.tap(find.byTooltip('Change color'));
    await tester.pumpAndSettle();
    final swatch = find.bySemanticsLabel('Rose');
    expect(swatch, findsOneWidget);
    expect(
      tester.getSemantics(swatch),
      matchesSemantics(
        label: 'Rose',
        isSelected: true,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
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
    await tester.runAsync(() async {
      await tester.tap(find.text('Create'));
      await SyncService.instance.runExclusiveLocalMutation(() async {});
    });
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

  testWidgets('an incomplete plan keeps Save quiet but says what is missing', (
    tester,
  ) async {
    await pumpEditorWithProvider(tester);
    final context = tester.element(find.byType(PlanEditorScreen));
    Color? saveGround() =>
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.ancestor(
                      of: find.text('Save'),
                      matching: find.byType(ElevatedButton),
                    ),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;

    // Not advertised as ready, but still a button a reader can press.
    expect(saveGround(), controlFillColor(context));
    expect(find.text('Name this plan to save it'), findsNothing);
    expect(find.text('Add at least one exercise to save'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Name this plan to save it'), findsOneWidget);
    expect(find.text('Add at least one exercise to save'), findsOneWidget);
    expect(HiveService.getPlans(), isEmpty);
    final name = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(name.focusNode.hasFocus, isTrue);

    // Each message clears as soon as its gap is filled.
    await tester.enterText(find.byType(TextField).first, 'Push');
    await tester.pumpAndSettle();
    expect(find.text('Name this plan to save it'), findsNothing);
    expect(find.text('Add at least one exercise to save'), findsOneWidget);
    expect(saveGround(), controlFillColor(context));

    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one exercise to save'), findsNothing);
    expect(saveGround(), accentFillColor(context));
  });

  testWidgets('a new plan focuses its name and takes an unused colour', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final box = Hive.box<WorkoutPlan>(HiveService.plansBox);
      await box.add(
        WorkoutPlan(name: 'A', exercises: [], planColor: kPlanColors[0]),
      );
      await box.add(
        WorkoutPlan(name: 'B', exercises: [], planColor: kPlanColors[1]),
      );
      await box.add(
        WorkoutPlan(name: 'C', exercises: [], planColor: kPlanColors[3]),
      );
    });
    await pumpEditor(tester);

    final name = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(name.focusNode.hasFocus, isTrue);

    await tester.tap(find.byTooltip('Change color'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Orange')),
      matchesSemantics(
        label: 'Orange',
        isSelected: true,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasSelectedState: true,
      ),
    );
    // Picking the default is not an edit.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('editing a plan leaves the name unfocused', (tester) async {
    await pumpEditorWithPlan(
      tester,
      WorkoutPlan(
        name: 'Push',
        exercises: [ExerciseTemplate(name: 'Bench Press', sets: 1)],
      ),
    );
    final name = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(name.focusNode.hasFocus, isFalse);
  });

  testWidgets('a starter fills the plan, names it, and can be undone', (
    tester,
  ) async {
    await pumpEditor(tester);
    for (final label in [
      'Push day',
      'Pull day',
      'Leg day',
      'Upper body',
      'Lower body',
      'Full body',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    final pill = find.bySemanticsLabel(RegExp('^Start from Push day'));
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(44));

    await tester.tap(pill);
    await tester.pumpAndSettle();
    final push = planStarters.firstWhere((s) => s.name == 'Push day');
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Push day',
    );
    expect(find.text('Bench Press'), findsOneWidget);
    // Starters arrive folded, each row previewing its targets.
    expect(find.bySemanticsLabel('Set 1 Kg'), findsNothing);
    expect(find.textContaining('3 × 8', findRichText: true), findsWidgets);
    expect(
      find.text('Added ${push.exercises.length} exercises from Push day'),
      findsOneWidget,
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsNothing);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      isEmpty,
    );
    expect(find.text('Leg day'), findsOneWidget);
  });

  testWidgets('a starter\'s Undo is withdrawn once the picker opens', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Pull day')));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    await closeExercisePicker(tester);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Barbell Row'), findsOneWidget);
  });

  testWidgets('a starter keeps a name the reader already typed', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Monday');
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Leg day')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Monday',
    );
    expect(find.text('Squat'), findsOneWidget);
  });

  testWidgets('every starter resolves to catalog exercises with targets', (
    tester,
  ) async {
    expect(planStarters.map((s) => s.name), [
      'Push day',
      'Pull day',
      'Leg day',
      'Upper body',
      'Lower body',
      'Full body',
    ]);
    for (final starter in planStarters) {
      expect(starter.exercises, isNotEmpty, reason: starter.name);
      for (final exercise in starter.exercises) {
        expect(
          ExerciseCatalog.findByName(exercise.name),
          isNotNull,
          reason: '${starter.name}: ${exercise.name}',
        );
        expect(exercise.seedReps, isNotEmpty);
      }
    }
  });

  testWidgets('collapse all folds every exercise and expand all reopens', (
    tester,
  ) async {
    await pumpEditorWithPlan(
      tester,
      WorkoutPlan(
        name: 'Push',
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
      ),
    );
    expect(find.bySemanticsLabel('Set 1 Kg'), findsNWidgets(2));
    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Set 1 Kg'), findsNothing);
    expect(find.text('Expand all'), findsOneWidget);

    // One open exercise turns the action back into Collapse all.
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Collapse all'), findsOneWidget);
    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Set 1 Kg'), findsNWidgets(2));
  });

  testWidgets('exercises already in the plan are marked Added in the picker', (
    tester,
  ) async {
    await pumpEditorWithPlan(
      tester,
      WorkoutPlan(
        name: 'Push',
        exercises: [
          ExerciseTemplate(
            name: 'Bench Press',
            sets: 2,
            setTargets: [
              SetTemplate(reps: 5, weight: 80),
              SetTemplate(reps: 5, weight: 80),
            ],
          ),
        ],
      ),
    );
    await openExerciseGroup(tester);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Selected (0)'), findsOneWidget);

    // A tap on it no longer drops the exercise and its targets.
    await tester.tap(find.text('Bench Press').last);
    await tester.pumpAndSettle();
    expect(find.text('Selected (0)'), findsOneWidget);
    await closeExercisePicker(tester);
    expect(find.text('80'), findsNWidgets(2));
  });

  testWidgets('exercises added to a long plan are scrolled into view', (
    tester,
  ) async {
    await pumpEditorWithPlan(
      tester,
      WorkoutPlan(
        name: 'Push',
        exercises: [
          for (final name in [
            'Bench Press',
            'Incline Bench Press',
            'Dumbbell Fly',
            'Cable Fly',
          ])
            ExerciseTemplate(
              name: name,
              sets: 3,
              setTargets: [
                for (var i = 0; i < 3; i++) SetTemplate(reps: 8, weight: 60),
              ],
            ),
        ],
      ),
    );
    await openExerciseGroup(tester, group: 'Back');
    await tester.tap(find.text('Barbell Row'));
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);

    final row = find.text('Barbell Row');
    expect(row, findsOneWidget);
    final bar = tester.getTopLeft(
      find.ancestor(
        of: find.text('Add exercise'),
        matching: find.byType(ElevatedButton),
      ),
    );
    final top = tester.getTopLeft(row).dy;
    expect(top, greaterThan(kToolbarHeight));
    expect(top, lessThan(bar.dy));
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
    // Save turns to the accent once the plan has a name and an exercise.
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    // The label's colour animates in once Save is ready.
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
    // The header stretches actions; Save must stay a 48px target inside it
    // (a 40px pill with Material's padded tap target).
    expect(tester.getSize(save).height, 48);

    // Add exercise is the tonal accent: the accent's wash with accent ink.
    final add = find.ancestor(
      of: find.text('Add exercise'),
      matching: find.byType(ElevatedButton),
    );
    expect(painted('Add exercise'), accentOnMutedColor(context));
    final wash = tester.widget<Material>(
      find.descendant(of: add, matching: find.byType(Material)).first,
    );
    expect(wash.color, accentMutedColor(context));
    expect(wash.color, isNot(planColorOf(kPlanColors[0], context)));
  });

  testWidgets('editor save and add exercise actions have 48 pixel targets', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'Push Day');

    for (final label in ['Save', 'Add exercise']) {
      // The button's own box, which includes Material's padded tap target.
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(ElevatedButton),
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

  testWidgets('collapsed rows and targets read in pounds when chosen', (
    tester,
  ) async {
    final bar = unitToKilograms(135, 'lbs');
    await tester.runAsync(
      () => Hive.box<WorkoutSession>(HiveService.sessionsBox).add(
        WorkoutSession(
          date: DateTime(2026, 10, 1),
          planName: 'Push',
          exercises: [
            Exercise(
              name: 'Bench Press',
              sets: [gym.Set(weight: bar, reps: 12)],
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
            for (var i = 0; i < 3; i++) SetTemplate(reps: 12, weight: bar),
          ],
        ),
        ExerciseTemplate(
          name: 'Incline Press',
          sets: 2,
          setTargets: [
            SetTemplate(reps: 10, weight: 60),
            SetTemplate(reps: 8, weight: 60),
          ],
        ),
      ],
    );
    await pumpEditorWithPlan(tester, plan, weightUnit: 'lbs');
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incline Press'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('3 × 12  ·  135 lbs', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Last: 135 lbs × 12'), findsOneWidget);
    expect(
      find.textContaining('132.25 × 10, 132.25 × 8', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining(' kg', findRichText: true), findsNothing);

    // Expanded, the targets are entered in pounds too.
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Lbs'), findsOneWidget);
    expect(find.text('135'), findsNWidgets(3));
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

  testWidgets('new exercise starts with three sets and icon footer actions', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openExerciseGroup(tester);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await closeExercisePicker(tester);

    expect(kNewExerciseSets, 3);
    expect(find.bySemanticsLabel('Set 1 Kg'), findsOneWidget);
    expect(find.bySemanticsLabel('Set 3 Kg'), findsOneWidget);
    expect(find.bySemanticsLabel('Set 4 Kg'), findsNothing);
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
    for (final key in ['5', '0', '.', '2', '5', 'Next', '1', '2', 'RPE', '8']) {
      await tester.tap(find.text(key).last);
      await tester.pumpAndSettle();
    }
    // More sets follow, so the keypad's action is Next rather than Done.
    await tester.tap(find.bySemanticsLabel('Hide keypad'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await SyncService.instance.runExclusiveLocalMutation(() async {});
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
      expect(find.bySemanticsLabel('Set 1 RPE'), findsOneWidget);
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
      expect(find.bySemanticsLabel('Set 2 RPE'), findsOneWidget);
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
    await tester.ensureVisible(find.bySemanticsLabel('Set 1 RPE'));
    await tester.tap(find.bySemanticsLabel('Set 1 RPE'));
    await tester.pumpAndSettle();
    await tester.longPress(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Set 1 RPE'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
  });

  testWidgets('a starter\'s Undo leaves with the editor', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 880);
    addTearDown(tester.view.reset);
    // A host screen with its own Scaffold, so a snackbar left behind by the
    // editor would show on it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => Center(
                  child: TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PlanEditorScreen.create(),
                          ),
                        ),
                    child: const Text('Open editor'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('editing a starter\'s exercises withdraws its Undo', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    // Opening a card is not an edit; adding a set to it is.
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Add set').first);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Bench Press'), findsOneWidget);
  });

  testWidgets('a starter\'s Undo jumps any queued snackbars', (tester) async {
    await pumpEditor(tester);
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(PlanEditorScreen)),
    );
    messenger.showSnackBar(const SnackBar(content: Text('First')));
    messenger.showSnackBar(const SnackBar(content: Text('Second')));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    // Withdrawn by an edit, it stays gone: nothing it was queued behind
    // hands the stage back to it.
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add set').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Second'), findsNothing);
    }
  });

  testWidgets('a withdrawn Undo ignores a tap while it fades', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add set').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.bySemanticsLabel('Set 4 Kg'), findsOneWidget);
  });

  testWidgets('a starter puts the keyboard away', (tester) async {
    await pumpEditor(tester);
    EditableText name() => tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(name().focusNode.hasFocus, isTrue);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Leg day')));
    await tester.pumpAndSettle();
    expect(name().focusNode.hasFocus, isFalse);
  });

  testWidgets('starters say what they hold and train', (tester) async {
    final push = planStarters.firstWhere((s) => s.name == 'Push day');
    expect(push.focus, ['Chest', 'Shoulders', 'Arms']);
    for (final starter in planStarters) {
      expect(starter.focus, isNotEmpty, reason: starter.name);
      expect(starter.focus.length, lessThanOrEqualTo(3));
    }

    await pumpEditor(tester);
    expect(
      find.text(
        '${push.exercises.length} exercises  ·  Chest, shoulders, arms',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Start from Push day, ${push.exercises.length} exercises, '
        'chest, shoulders, arms',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the hint under Exercises follows whether cards are open', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Open an exercise to set its targets. Drag the grip to reorder.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap a target to change it'), findsOneWidget);
  });

  testWidgets('cards fold with motion, and at once under reduced motion', (
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-fold the table is still there, closing.
    expect(find.bySemanticsLabel('Set 1 Kg'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Set 1 Kg'), findsNothing);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.tap(find.text('Bench Press'));
    await tester.pump();
    expect(find.bySemanticsLabel('Set 1 Kg'), findsOneWidget);
    await tester.tap(find.text('Bench Press'));
    await tester.pump();
    expect(find.bySemanticsLabel('Set 1 Kg'), findsNothing);
  });

  testWidgets('a starter\'s cards arrive in sequence', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final push = planStarters.firstWhere((s) => s.name == 'Push day');
    double opacityOf(String name) =>
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.text(name),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;
    final first = opacityOf(push.exercises.first.name);
    final last = opacityOf(push.exercises.last.name);
    expect(first, greaterThan(last));
    expect(last, lessThan(1));
    await tester.pumpAndSettle();
    expect(opacityOf(push.exercises.last.name), 1);
  });

  testWidgets(
    'under reduced motion, what is missing and the hint just change',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpEditor(tester);

      // The name's error line takes its space at once.
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Name this plan to save it'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Push');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Name this plan to save it'), findsNothing);

      // The hint under the heading swaps lines, of different lengths, at once.
      await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
      await tester.pump();
      const folded =
          'Open an exercise to set its targets. Drag the grip to reorder.';
      expect(find.text(folded), findsOneWidget);
      await tester.tap(find.text('Expand all'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(folded), findsNothing);
      expect(
        find.text(
          'Tap a target to change it, or hold a set to delete it. Drag the '
          'grip to reorder exercises.',
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the hint arrives with the first exercises, not with a plan', (
    tester,
  ) async {
    // The arrival's own fade: the first one under the hint's Entrance.
    double hintOpacity(String hint) =>
        tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of:
                        find
                            .ancestor(
                              of: find.text(hint),
                              matching: find.byType(Entrance),
                            )
                            .first,
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;
    const folded =
        'Open an exercise to set its targets. Drag the grip to reorder.';

    await pumpEditor(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pump();
    // There from the first frame, on its way in.
    expect(find.text(folded), findsOneWidget);
    expect(hintOpacity(folded), lessThan(1));
    await tester.pumpAndSettle();
    expect(hintOpacity(folded), 1);

    // A plan that opens with exercises simply has it, from its first frame.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: PlanEditorScreen.edit(
          WorkoutPlan(
            name: 'Push',
            exercises: [ExerciseTemplate(name: 'Bench Press', sets: 1)],
          ),
        ),
      ),
    );
    const open = 'Tap a target to change it, or hold a set to delete it.';
    expect(hintOpacity(open), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('folding right after the keypad leaves no space reserved', (
    tester,
  ) async {
    await pumpEditorWithPlan(
      tester,
      WorkoutPlan(
        name: 'Push',
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
      ),
    );
    await tester.tap(find.bySemanticsLabel('Set 1 Kg').first);
    await tester.pumpAndSettle();
    expect(SetEntryTable.keyboardHeight.value, greaterThan(0));

    // A tap outside a value closes the keypad first; whether that tap or the
    // next one folds the cards, nothing may be left reserved or broken.
    await tester.tap(find.text('Collapse all'), warnIfMissed: false);
    await tester.pumpAndSettle();
    if (find.text('Collapse all').evaluate().isNotEmpty) {
      await tester.tap(find.text('Collapse all'));
      await tester.pumpAndSettle();
    }
    expect(find.bySemanticsLabel('Set 1 Kg'), findsNothing);
    expect(SetEntryTable.keyboardHeight.value, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving right after a starter still says the plan saved', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 880);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkoutPlanProvider>(
        // Persistence is covered elsewhere; this is about what the reader
        // sees as the editor closes.
        create: (_) => _InstantPlanProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => Center(
                    child: TextButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PlanEditorScreen.create(),
                            ),
                          ),
                      child: const Text('Open editor'),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Push day')));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.text('Plan saved'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('starter cards can be reordered once they have arrived', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Start from Pull day')));
    await tester.pumpAndSettle();
    final grips = find.byType(ReorderableDragStartListener);
    await tester.timedDrag(
      grips.at(1),
      const Offset(0, -120),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final pull = planStarters.firstWhere((s) => s.name == 'Pull day');
    expect(
      tester.getTopLeft(find.text(pull.exercises[1].name)).dy,
      lessThan(tester.getTopLeft(find.text(pull.exercises[0].name)).dy),
    );
    // A reorder is an edit, so the starter's Undo is gone.
    expect(find.text('Undo'), findsNothing);
  });
}

/// Takes a new plan without touching storage.
class _InstantPlanProvider extends WorkoutPlanProvider {
  @override
  Future<void> addPlan(WorkoutPlan plan, {String? startingWeekId}) async {}
}
