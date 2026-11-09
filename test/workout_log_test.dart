import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/navigation/workout_destination.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:gymapp/widgets/workout/training_block_strip.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

void main() {
  final harness = HiveTestHarness();
  final writes = <WorkoutSession>[];
  var failWrites = false;
  void workoutTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        try {
          await body(tester);
        } finally {
          await closeStorageWithFrames(tester, harness.close);
        }
      });
  setUp(() async {
    writes.clear();
    failWrites = false;
    await harness.open();
  });
  final plan = WorkoutPlan(
    id: 'continuous-log',
    name: 'Push day',
    planColor: 4,
    exercises: [
      ExerciseTemplate(name: 'Bench press', sets: 4),
      ExerciseTemplate(name: 'Incline dumbbell press', sets: 3),
      ExerciseTemplate(name: 'Overhead press', sets: 3),
    ],
  );
  final exercises = [
    Exercise(
      name: 'Bench press',
      sets: [
        gym.Set(weight: 70, reps: 8, rpe: 8),
        gym.Set(weight: 70, reps: 8, rpe: 8),
        gym.Set(weight: 70, reps: 7, rpe: 9),
        gym.Set(weight: 70, reps: 5, rpe: 10),
      ],
    ),
    Exercise(
      name: 'Incline dumbbell press',
      sets: [
        gym.Set(weight: 32, reps: 10, rpe: 7),
        gym.Set(weight: 32, reps: 10, rpe: 8),
        gym.Set(weight: 32, reps: 8, rpe: 9),
      ],
    ),
    Exercise(
      name: 'Overhead press',
      sets: [
        gym.Set(weight: 50, reps: 8, rpe: 7),
        gym.Set(weight: 50, reps: 8, rpe: 8),
        gym.Set(weight: 50, reps: 6, rpe: 9),
      ],
    ),
  ];

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (!const bool.fromEnvironment('WORKOUT_PREVIEW')) await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
    if (const bool.fromEnvironment('WORKOUT_PREVIEW')) {
      final font = File('build/previews/manrope.ttf');
      final fontBytes = ByteData.sublistView(font.readAsBytesSync());
      await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      )).load();
      final manifest = const StandardMessageCodec().encodeMessage({
        for (final weight in [
          'Regular',
          'Medium',
          'SemiBold',
          'Bold',
          'ExtraBold',
        ])
          'Manrope-$weight.ttf': [
            {'asset': 'Manrope-$weight.ttf'},
          ],
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final asset = utf8.decode(message!.buffer.asUint8List());
            if (asset == 'AssetManifest.bin') return manifest;
            if (asset.startsWith('Manrope-')) return fontBytes;
            return null;
          });
    }
  });
  tearDownAll(() async {
    if (const bool.fromEnvironment('WORKOUT_PREVIEW')) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    }
    await harness.close();
  });

  Future<void> seed({bool completed = false, bool started = false}) async {
    final box = Hive.box<WorkoutSession>(HiveService.sessionsBox);
    await box.clear();
    for (final week in [5, 6]) {
      final session = WorkoutSession(
        id: 'week-$week',
        planId: plan.id,
        planName: plan.name,
        date: DateTime(2026, 9, week),
        weekNumber: week,
        isCompleted: week == 5 || completed,
        startedAt: week == 6 && started ? DateTime(2026, 9, 6) : null,
        durationSeconds: 0,
        exercises: exercises,
      );
      await box.put(session.id, session);
    }
    await harness.prepareTraining([plan]);
  }

  Widget host({
    Brightness brightness = Brightness.light,
    double scale = 1,
    GlobalKey? boundary,
  }) => MultiProvider(
    key: UniqueKey(),
    providers: [
      ChangeNotifierProvider<WorkoutPlanProvider>(
        create:
            (_) => _Plans([
              plan.copyWith(id: 'full-body', name: 'Full body'),
              plan,
              plan.copyWith(id: 'upper-body', name: 'Upper body'),
              plan.copyWith(id: 'leg-day', name: 'Leg day'),
              plan.copyWith(id: 'pull-day', name: 'Pull day'),
            ]),
      ),
      ChangeNotifierProvider<WorkoutSessionProvider>(
        create: (_) => _Sessions(writes, () => failWrites),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(const Color(0xFF008D8D), brightness),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
      home: RepaintBoundary(
        key: boundary,
        child: WorkoutScreen(
          plan: plan,
          planIndex: 1,
          destination: WorkoutDestination.week(
            plan.id!,
            legacyTrainingWeekId(plan.splitId!, 6),
          ),
        ),
      ),
    ),
  );

  workoutTest(
    'continuous log fits narrow screens and large text in both themes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Started, so the header carries its fullest set: clock, Finish, menu.
      await tester.runAsync(() => seed(started: true));
      for (final brightness in Brightness.values) {
        for (final width in [320.0, 390.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 844);
            final boundary = GlobalKey();
            await tester.pumpWidget(
              host(brightness: brightness, scale: scale, boundary: boundary),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final toolbar = tester.widget<AppBar>(find.byType(AppBar));
            if (scale == 1) {
              expect(toolbar.toolbarHeight, 64);
            } else {
              expect(toolbar.toolbarHeight, greaterThan(64));
            }
            if (const bool.fromEnvironment('WORKOUT_PREVIEW') &&
                width == 390 &&
                scale == 1) {
              expect(
                (tester.renderObject(find.text('Block 1 · Week 6'))
                        as RenderParagraph)
                    .didExceedMaxLines,
                isFalse,
                reason: 'The selected block and week must remain readable.',
              );
            }
            expect(find.text('Bench press'), findsOneWidget);
            final title =
                find
                    .descendant(
                      of: find.byType(AppBar),
                      matching: find.text('Push day'),
                    )
                    .first;
            final timer = find.byKey(const ValueKey('workout_elapsed_time'));
            expect(
              tester.getRect(title).overlaps(tester.getRect(timer)),
              isFalse,
              reason:
                  'width=$width scale=$scale title=${tester.getRect(title)} '
                  'timer=${tester.getRect(timer)}',
            );
            expect(tester.getRect(title).top, greaterThanOrEqualTo(0));
            expect(find.byTooltip('Delete set'), findsNothing);
            expect(find.bySemanticsLabel('Set 1 RPE value 8'), findsWidgets);
            final card = find.byType(ExerciseCard).first;
            final menu = find.descendant(
              of: card,
              matching: find.byTooltip('Exercise actions for Bench press'),
            );
            final rpe = find.descendant(of: card, matching: find.text('RPE'));
            expect(
              find.descendant(of: card, matching: find.byType(Scrollable)),
              findsNothing,
            );
            expect(rpe, findsOneWidget);
            expect(
              find.descendant(of: card, matching: find.text('Kg')),
              findsOneWidget,
            );
            expect(
              tester.getCenter(menu).dx,
              closeTo(tester.getCenter(rpe).dx, 0.1),
            );
            final row = find.descendant(
              of: card,
              matching: find.byKey(const ValueKey('set_entry_row_0')),
            );
            final weight = find.descendant(
              of: row,
              matching: find.bySemanticsLabel('Set 1 Kg'),
            );
            for (final label in ['Set 1 Reps', 'Set 1 RPE value 8']) {
              expect(
                tester
                    .getCenter(
                      find.descendant(
                        of: row,
                        matching: find.bySemanticsLabel(label),
                      ),
                    )
                    .dy,
                closeTo(tester.getCenter(weight).dy, 0.1),
                reason: 'The original columns must stay on the same row',
              );
            }
            expect(
              tester
                  .getCenter(
                    find.descendant(of: row, matching: find.text('70 × 8')),
                  )
                  .dy,
              closeTo(tester.getCenter(weight).dy, 0.1),
            );
            expect(tester.getSize(menu).width, greaterThanOrEqualTo(48));
            expect(
              find.descendant(of: card, matching: find.byType(Scrollbar)),
              findsNothing,
            );
            final finish = find.byKey(const ValueKey('finish-workout'));
            expect(finish, findsOneWidget);
            expect(
              tester
                  .getRect(find.byType(AppBar))
                  .contains(tester.getCenter(finish)),
              isTrue,
            );
            expect(
              tester.getSize(finish).shortestSide,
              greaterThanOrEqualTo(48),
            );

            if (const bool.fromEnvironment('WORKOUT_PREVIEW') &&
                width == 390 &&
                scale == 1) {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await render.toImage(pixelRatio: 2);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory('build/previews').create(recursive: true);
                await File(
                  'build/previews/workout_log_${brightness.name}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.scrollUntilVisible(
              find.text('Overhead press'),
              300,
              scrollable: find.descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Overhead press'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  workoutTest(
    'swiping the set table changes plans and restores the saved workout week',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => seed());
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final card = find.byType(ExerciseCard).first;
      final row = find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('set_entry_row_0')),
      );
      int selectedWeek() {
        final strip = tester.widget<TrainingBlockStrip>(
          find.byType(TrainingBlockStrip),
        );
        return strip.weeksByBlock.values
            .expand((w) => w)
            .firstWhere((w) => w.id == strip.selectedWeekId)
            .number;
      }

      expect(selectedWeek(), 6);
      expect(
        find.descendant(of: card, matching: find.byType(Scrollable)),
        findsNothing,
      );
      await tester.flingFrom(tester.getCenter(row), const Offset(120, 0), 1000);
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorkoutScreen>(find.byType(WorkoutScreen)).plan.name,
        'Full body',
      );
      expect(selectedWeek(), 1);
      await tester.flingFrom(
        tester.getCenter(row),
        const Offset(-120, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorkoutScreen>(find.byType(WorkoutScreen)).plan.name,
        'Push day',
      );
      expect(selectedWeek(), 6);
      expect(tester.widget<ExerciseCard>(card).exercise.sets.first.weight, 70);
      expect(writes, isEmpty);
      expect(HiveService.getSessionById('week-6')!.planId, plan.id);
      expect(HiveService.getSessionById('week-6')!.weekNumber, 6);
      expect(tester.takeException(), isNull);
    },
  );

  workoutTest('exercise menu moves an exercise without requiring a drag', (
    tester,
  ) async {
    await tester.runAsync(() => seed());
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Exercise actions for Bench press'));
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing);
    expect(find.text('Delete set'), findsNothing);
    await tester.tap(find.text('Move down'));
    await pumpWithStorage(tester);
    final order = tester.widgetList<ExerciseCard>(find.byType(ExerciseCard));
    expect(order.first.exercise.name, 'Incline dumbbell press');
    expect(order.elementAt(1).exercise.name, 'Bench press');
    expect(tester.takeException(), isNull);
  });

  workoutTest('exercise menu edges remain tappable on narrow screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => seed());
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final menu = find.byTooltip('Exercise actions for Bench press');
      final rect = tester.getRect(menu);
      for (final edge in [
        rect.centerLeft + const Offset(0.1, 0),
        rect.centerRight - const Offset(0.1, 0),
      ]) {
        await tester.tapAt(edge);
        await tester.pumpAndSettle();
        expect(find.text('Rename exercise'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    }
  });

  workoutTest('completed log edits in place and stays logged', (tester) async {
    await tester.runAsync(() => seed(completed: true));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    // A logged workout has no clock to run, but everything else is editable.
    expect(find.bySemanticsLabel('Start workout'), findsNothing);
    expect(find.byTooltip('Finish workout'), findsNothing);
    expect(find.text('Add set'), findsWidgets);
    expect(find.byTooltip('Exercise actions for Bench press'), findsOneWidget);

    await tester.tap(find.byTooltip('Exercise actions for Bench press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await pumpWithStorage(tester);
    var saved = HiveService.getSessionById('week-6')!;
    expect(saved.isCompleted, isTrue);
    expect(saved.exercises.first.name, 'Incline dumbbell press');
    expect(saved.planName, plan.name);

    await tester.tap(find.text('Add set').first);
    await pumpWithStorage(tester);
    saved = HiveService.getSessionById('week-6')!;
    expect(saved.isCompleted, isTrue);
    expect(saved.exercises.first.sets, hasLength(4));
    // A logged workout's edits never open the new-workout flow.
    expect(find.text('Log workout?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  workoutTest('completed log corrects its date and duration', (tester) async {
    await tester.runAsync(() => seed(completed: true));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    expect(find.text('Discard workout'), findsNothing);
    await tester.tap(find.text('Edit date and duration'));
    await tester.pumpAndSettle();
    expect(find.text('6 Sep 2026'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workout-duration-hours')),
      '24',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workout-time-error')), findsOneWidget);
    expect(writes, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('workout-duration-hours')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workout-duration-minutes')),
      '5',
    );
    await tester.tap(find.text('Save'));
    await pumpWithStorage(tester);
    final saved = HiveService.getSessionById('week-6')!;
    expect(saved.isCompleted, isTrue);
    expect(saved.durationSeconds, 65 * 60);
    expect(saved.date, DateTime(2026, 9, 6));
    expect(find.textContaining('1:05:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  workoutTest('changing only the date keeps a sub-minute duration', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seed(completed: true);
      final box = Hive.box<WorkoutSession>(HiveService.sessionsBox);
      await box.put(
        'week-6',
        box
            .get('week-6')!
            .copyWith(
              startedAt: DateTime(2026, 9, 6, 18),
              date: DateTime(2026, 9, 6, 18),
              durationSeconds: 42,
            ),
      );
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit date and duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workout-date')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('4'),
      ),
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await pumpWithStorage(tester);
    expect(find.byKey(const ValueKey('workout-time-error')), findsNothing);
    final saved = HiveService.getSessionById('week-6')!;
    expect(saved.date, DateTime(2026, 9, 4, 18));
    expect(saved.startedAt, DateTime(2026, 9, 4, 18));
    expect(saved.durationSeconds, 42);
    expect(tester.takeException(), isNull);
  });

  workoutTest('unsaved edits to a logged workout leave through saving', (
    tester,
  ) async {
    await tester.runAsync(() => seed(completed: true));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    bool canPop() =>
        tester
            .widget<PopScope<Object?>>(
              find
                  .descendant(
                    of: find.byType(WorkoutScreen),
                    matching: find.byWidgetPredicate((w) => w is PopScope),
                  )
                  .first,
            )
            .canPop;
    expect(canPop(), isTrue);
    failWrites = true;
    await tester.tap(find.text('Add set').first);
    await pumpWithStorage(tester);
    // The failed autosave keeps the edit, so Back must retry it, not pop.
    expect(find.text('Retry'), findsOneWidget);
    expect(canPop(), isFalse);
    failWrites = false;
    await tester.tap(find.text('Retry'));
    await pumpWithStorage(tester);
    expect(canPop(), isTrue);
    expect(
      HiveService.getSessionById('week-6')!.exercises.first.sets,
      hasLength(5),
    );
    expect(tester.takeException(), isNull);
  });

  workoutTest(
    'toolbar finish requires a started workout and keeps confirmation',
    (tester) async {
      const channel = MethodChannel(
        'com.aalishms.opengym/workout_timer_notification',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await tester.runAsync(() => seed());
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final finish = find.byKey(const ValueKey('finish-workout'));
      // Nothing to finish before Start, so the header leaves Finish out.
      expect(finish, findsNothing);
      expect(find.textContaining('Tap Start in the toolbar'), findsNothing);
      await tester.tap(find.byTooltip('Workout actions'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem && widget.value == 'finish',
        ),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.runAsync(() => seed(started: true));
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      final finishNode = tester.getSemantics(
        find.bySemanticsLabel('Finish workout'),
      );
      expect(
        finishNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      expect(
        finishNode.getSemanticsData().flagsCollection.isEnabled,
        ui.Tristate.isTrue,
      );
      final finishButton = tester.widget<TextButton>(finish);
      expect(finishButton.onPressed, isNotNull);
      expect(
        finishButton.style!.foregroundColor!.resolve({}),
        accentColor(tester.element(finish)),
      );
      // Labelled, so it can't be read as a generic save.
      expect(
        find.descendant(of: finish, matching: find.text('Finish')),
        findsOneWidget,
      );
      // Activate the action the same way a screen reader does.
      finishNode.owner!.performAction(finishNode.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.text('Log workout?'), findsOneWidget);
      semantics.dispose();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        HiveService.getSessionForPlanAndWeek(
          plan.name,
          6,
          plan.splitId,
        )!.isCompleted,
        isFalse,
      );

      await tester.tap(finish);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log workout'));
      await pumpWithStorage(tester);
      expect(writes.single.isCompleted, isTrue);
      expect(find.byTooltip('Workout actions'), findsNothing);
      expect(find.byTooltip('Finish workout'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Plans extends WorkoutPlanProvider {
  final List<WorkoutPlan> values;
  _Plans(this.values);

  @override
  List<WorkoutPlan> get plans => values;
}

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> writes;
  final bool Function() fail;
  _Sessions(this.writes, this.fail);

  @override
  Future<void> upsertSession(WorkoutSession session) async {
    if (fail()) throw StateError('disk full');
    await super.upsertSession(session);
    writes.add(session);
  }
}
