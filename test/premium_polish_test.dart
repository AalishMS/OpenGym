import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gymapp/main.dart' show useBundledFonts;
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/screens/workout_summary_screen.dart';
import 'package:gymapp/services/pr_tracking_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/statistics_format.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';
import 'package:gymapp/widgets/plan_title_hero.dart';
import 'package:gymapp/widgets/rolling_figure.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';

import 'support/test_fonts.dart';

void main() {
  setUpAll(loadTestFonts);

  Widget app(Widget child, {bool reduceMotion = false}) => MaterialApp(
    theme: buildTheme(const Color(0xFF41B9B9), Brightness.light),
    home: Builder(
      builder:
          (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: Scaffold(body: child),
          ),
    ),
  );

  group('bundled fonts', () {
    test('every weight the theme asks for ships with the app', () {
      for (final family in ['Manrope', 'JetBrainsMono']) {
        for (final weight in [
          'Regular',
          'Medium',
          'SemiBold',
          'Bold',
          'ExtraBold',
        ]) {
          expect(
            File('assets/google_fonts/$family-$weight.ttf').existsSync(),
            isTrue,
            reason: '$family $weight is missing from assets/google_fonts',
          );
        }
        expect(
          File('assets/google_fonts/$family-OFL.txt').existsSync(),
          isTrue,
        );
      }
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- assets/google_fonts/'),
      );
    });

    test('startup never falls back to fetching type from the network', () {
      final before = GoogleFonts.config.allowRuntimeFetching;
      addTearDown(() => GoogleFonts.config.allowRuntimeFetching = before);
      GoogleFonts.config.allowRuntimeFetching = true;
      TestWidgetsFlutterBinding.ensureInitialized();
      useBundledFonts();
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    });
  });

  group('signed changes', () {
    String percent(num change) =>
        formatSignedChange(change, (v) => '${v.round()}%');

    test('use a true minus sign, matching the plus', () {
      expect(percent(12.4), '+12%');
      expect(percent(-49), '−49%');
      expect(percent(-49), isNot(contains('-')));
    });

    test('a change that rounds to nothing carries no sign', () {
      expect(percent(0), '0%');
      expect(percent(-0.4), '0%');
      expect(percent(0.3), '0%');
    });
  });

  testWidgets('a 390dp phone shows all seven days without scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);
    final today = DateTime(2026, 11, 5); // Thursday
    await tester.pumpWidget(
      app(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TrainingSnapshot(
            plans: const [],
            sessions: [
              WorkoutSession(
                date: today,
                planName: 'Push',
                exercises: [
                  Exercise(
                    name: 'Bench press',
                    sets: [gym.Set(reps: 8, weight: 60)],
                  ),
                ],
                isCompleted: true,
              ),
            ],
            now: today,
            onOpenWeeklyTraining: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TrainingSnapshot),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    for (var day = 0; day < 7; day++) {
      final rect = tester.getRect(find.byKey(ValueKey('training-day-$day')));
      expect(rect.width, greaterThanOrEqualTo(48), reason: 'day $day target');
      expect(rect.right, lessThanOrEqualTo(390 - 16 + 0.01));
    }
    // Today is marked once, by the dot.
    expect(
      find.byKey(const ValueKey('training-day-today-dot')),
      findsOneWidget,
    );
  });

  group('records while you lift', () {
    Widget card({
      required List<gym.Set> sets,
      List<gym.Set> previous = const [],
      double? recordWeight,
      bool readOnly = false,
    }) => app(
      SingleChildScrollView(
        child: ExerciseCard(
          exercise: Exercise(name: 'Bench press', sets: sets),
          exerciseIndex: 0,
          readOnly: readOnly,
          accent: const Color(0xFF41B9B9),
          previousSets: previous,
          recordWeight: recordWeight,
          onSetRpeChanged: (_, _, _) {},
          onAddSet: (_) {},
          onDeleteSet: (_, _) {},
          onAddNote: (_) {},
          onRename: (_) {},
          onDeleteExercise: (_) {},
        ),
      ),
    );

    testWidgets('an entered weight above the record earns the PR mark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        card(
          recordWeight: 100,
          sets: [
            gym.Set(weight: 102.5, reps: 5),
            gym.Set(weight: 100, reps: 5),
            gym.Set(weight: 110, reps: 0),
          ],
          previous: [
            gym.Set(weight: 100, reps: 5),
            gym.Set(weight: 100, reps: 5),
            gym.Set(weight: 80, reps: 8),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // Heavier than ever: record. Equal to it: not. No reps: not lifted.
      expect(find.byKey(const ValueKey('live-record-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-record-1')), findsNothing);
      expect(find.byKey(const ValueKey('live-record-2')), findsNothing);
      // Both read out as part of the set's row.
      expect(find.bySemanticsLabel(RegExp('Personal record')), findsOneWidget);
      // Past Previous: arrow. Matching it, or with no reps, is not "beaten".
      expect(find.byKey(const ValueKey('beats-previous-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('beats-previous-1')), findsNothing);
      expect(find.byKey(const ValueKey('beats-previous-2')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'Previous set 1: 100 × 5, beaten')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('more reps at the same weight beats Previous', (tester) async {
      await tester.pumpWidget(
        card(
          sets: [gym.Set(weight: 80, reps: 10)],
          previous: [gym.Set(weight: 80, reps: 8)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('beats-previous-0')), findsOneWidget);
      // No history, so no record to beat.
      expect(find.byKey(const ValueKey('live-record-0')), findsNothing);
    });

    testWidgets('a finished log shows no live marks', (tester) async {
      await tester.pumpWidget(
        card(
          readOnly: true,
          recordWeight: 50,
          sets: [gym.Set(weight: 100, reps: 5)],
          previous: [gym.Set(weight: 90, reps: 5)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-record-0')), findsNothing);
      expect(find.byKey(const ValueKey('beats-previous-0')), findsNothing);
    });

    test('a record needs reps and history, like Finish', () {
      expect(ExerciseCard.isRecord(gym.Set(weight: 101, reps: 1), 100), isTrue);
      expect(
        ExerciseCard.isRecord(gym.Set(weight: 100, reps: 5), 100),
        isFalse,
      );
      expect(
        ExerciseCard.isRecord(gym.Set(weight: 120, reps: 0), 100),
        isFalse,
      );
      expect(
        ExerciseCard.isRecord(gym.Set(weight: 120, reps: 5), null),
        isFalse,
      );
    });
  });

  group('workout summary', () {
    final date = DateTime(2026, 11, 5, 18);
    WorkoutSession push(String id, DateTime date, double weight) =>
        WorkoutSession(
          id: id,
          planId: 'push',
          planName: 'Push',
          date: date,
          weekNumber: 3,
          durationSeconds: 3125,
          isCompleted: true,
          exercises: [
            Exercise(
              name: 'Bench press',
              sets: [
                gym.Set(weight: weight, reps: 5),
                gym.Set(weight: weight, reps: 5),
              ],
            ),
          ],
        );

    Future<void> pumpSummary(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.reset);
      final session = push('now', date, 105);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF41B9B9), Brightness.light),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => WorkoutSummaryScreen(
                                    session: session,
                                    history: [
                                      push(
                                        'last',
                                        date.subtract(const Duration(days: 7)),
                                        100,
                                      ),
                                      push(
                                        'tuesday',
                                        date.subtract(const Duration(days: 2)),
                                        90,
                                      ),
                                    ],
                                    records: [
                                      PRResult(
                                        exerciseName: 'Bench press',
                                        previousPR: 100,
                                        newPR: 105,
                                        reps: 5,
                                      ),
                                      PRResult(
                                        exerciseName: 'Curl',
                                        previousPR: 0,
                                        newPR: 20,
                                        reps: 10,
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('celebrates real records and counts first logs apart', (
      tester,
    ) async {
      await pumpSummary(tester);
      expect(find.text('Workout logged'), findsOneWidget);
      expect(find.text('Push'), findsOneWidget);
      // Tuesday's Push and this one: the second workout this week.
      expect(find.textContaining('Workout 2 this week'), findsOneWidget);
      expect(find.text('Personal record'), findsOneWidget);
      expect(find.text('was 100 kg'), findsOneWidget);
      expect(find.text('Curl'), findsNothing);
      expect(find.text('1 exercise logged for the first time'), findsOneWidget);
      // Compared with the most recent earlier Push (90 kg), not the older one.
      expect(find.text('+17% volume vs last Push'), findsOneWidget);
      // Figures settle on their exact values after counting up.
      expect(find.text('52m'), findsOneWidget);
      expect(find.text('1.1 t'), findsOneWidget);
    });

    testWidgets('Done returns to the workout', (tester) async {
      await pumpSummary(tester);
      await tester.tap(find.byKey(const ValueKey('summary-done')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutSummaryScreen), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });
  });

  group('rolling figures', () {
    Widget figure(String text, {bool reduceMotion = false}) =>
        app(Center(child: RollingFigure(text)), reduceMotion: reduceMotion);

    testWidgets('roll between values, then settle into one figure', (
      tester,
    ) async {
      await tester.pumpWidget(figure('1,200 kg'));
      await tester.pumpWidget(figure('1,450 kg'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1,200 kg'), findsOneWidget);
      expect(find.text('1,450 kg'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('1,200 kg'), findsNothing);
      expect(find.text('1,450 kg'), findsOneWidget);
    });

    testWidgets('change in place under reduced motion', (tester) async {
      await tester.pumpWidget(figure('1,200 kg', reduceMotion: true));
      await tester.pumpWidget(figure('1,450 kg', reduceMotion: true));
      expect(find.text('1,200 kg'), findsNothing);
      expect(find.text('1,450 kg'), findsOneWidget);
    });
  });

  testWidgets('the plan name flies between its two styles', (tester) async {
    const small = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    const large = TextStyle(fontSize: 22, fontWeight: FontWeight.w600);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: GestureDetector(
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => const Scaffold(
                                body: Align(
                                  alignment: Alignment.topLeft,
                                  child: PlanTitleHero(
                                    tag: 'plan',
                                    text: 'Push Day',
                                    style: small,
                                  ),
                                ),
                              ),
                        ),
                      ),
                  child: const Center(
                    child: PlanTitleHero(
                      tag: 'plan',
                      text: 'Push Day',
                      style: large,
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Push Day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final inFlight = tester
        .widgetList<Text>(find.text('Push Day'))
        .map((text) => text.style?.fontSize);
    // Somewhere between the card's size and the header's.
    expect(
      inFlight.any((size) => size != null && size > 18 && size < 22),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
