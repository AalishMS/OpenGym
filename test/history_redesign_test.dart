import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/hive_service.dart';

import 'support/hive_test_harness.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/statistics_format.dart';
import 'package:gymapp/widgets/history/history_journal_data.dart';
import 'package:gymapp/widgets/history/history_journal_widgets.dart';

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
    await hiveHarness.open(includeSplits: true);
  });

  tearDownAll(() async {
    await hiveHarness.close();
    await Supabase.instance.dispose();
  });

  /// Saves [sessions] where opening a workout looks them up. None has a plan
  /// or a week, so each opens in the editor, as a workout whose plan was
  /// deleted does.
  Future<void> store(WidgetTester tester, List<WorkoutSession> sessions) =>
      tester.runAsync(() async {
        await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
        if (HiveService.getSplitById('a') == null) {
          await HiveService.putSplitRaw(
            gym.Split(id: 'a', name: 'Split A', createdAt: DateTime(2026)),
          );
        }
        for (final session in sessions) {
          await HiveService.putSessionRaw(session.copyWith());
        }
      });

  WorkoutSession session({
    required String id,
    required String name,
    required DateTime date,
    String splitId = 'a',
    bool completed = true,
    DateTime? deletedAt,
    int? durationSeconds,
    String exerciseName = 'Bench Press',
    double weight = 80,
    int reps = 5,
    String? exerciseNote,
    String? setNote,
    int? rpe,
  }) => WorkoutSession(
    id: id,
    planName: name,
    date: date,
    splitId: splitId,
    isCompleted: completed,
    deletedAt: deletedAt,
    durationSeconds: durationSeconds,
    weekNumber: 4,
    exercises: [
      Exercise(
        name: exerciseName,
        note: exerciseNote,
        sets: [Set(weight: weight, reps: reps, note: setNote, rpe: rpe)],
      ),
    ],
  );

  Widget host(
    WorkoutSessionProvider provider, {
    Widget screen = const HistoryScreen(),
    SettingsProvider? settings,
    Size size = const Size(390, 800),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<WorkoutSessionProvider>.value(value: provider),
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings ?? SettingsProvider(),
      ),
    ],
    child: MaterialApp(
      key: ValueKey('history-host-${identityHashCode(provider)}'),
      theme: buildTheme(const Color(0xFF00A2FF), brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: SizedBox(width: size.width, height: size.height, child: screen),
      ),
    ),
  );

  /// A History over [sessions] whose rows open their workouts.
  Future<_Sessions> pumpHistory(
    WidgetTester tester,
    List<WorkoutSession> sessions, {
    SettingsProvider? settings,
    Size size = const Size(390, 800),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await store(tester, sessions);
    final provider = _Sessions(sessions);
    await tester.pumpWidget(
      host(
        provider,
        settings: settings,
        size: size,
        brightness: brightness,
        textScale: textScale,
      ),
    );
    await tester.pump();
    return provider;
  }

  test('groups by month and year newest first and keeps same-day workouts', () {
    final data = buildHistoryJournalData([
      session(id: 'aug', name: 'August', date: DateTime(2026, 8, 31, 18)),
      session(
        id: 'sep-old-year',
        name: 'Old September',
        date: DateTime(2025, 9, 1),
      ),
      session(
        id: 'same-late',
        name: 'Evening',
        date: DateTime(2026, 9, 11, 18),
      ),
      session(
        id: 'same-early',
        name: 'Morning',
        date: DateTime(2026, 9, 11, 7),
      ),
    ]);

    expect(
      data.groups.map((group) => historyMonthLabel(group.month, group.year)),
      ['September 2026', 'August 2026', 'September 2025'],
    );
    expect(
      data.groups.first.workouts.map((workout) => workout.session.planName),
      ['Evening', 'Morning'],
    );
  });

  test(
    'searches workout and exercise names and excludes ineligible sessions',
    () {
      final sessions = [
        session(id: 'push', name: 'Push Day', date: DateTime(2026, 9, 2)),
        session(
          id: 'pull',
          name: 'Back session',
          date: DateTime(2026, 9, 1),
          exerciseName: 'Lat Pulldown',
        ),
        session(
          id: 'draft',
          name: 'Draft match',
          date: DateTime(2026, 9, 3),
          completed: false,
        ),
        session(
          id: 'deleted',
          name: 'Deleted match',
          date: DateTime(2026, 9, 4),
          deletedAt: DateTime(2026, 9, 5),
        ),
        session(
          id: 'other-split',
          name: 'Other match',
          date: DateTime(2026, 9, 6),
          splitId: 'b',
        ),
      ];

      expect(
        buildHistoryJournalData(
          sessions,
          query: ' PUSH ',
          splitId: 'a',
        ).groups.single.workouts.single.session.id,
        'push',
      );
      final byExercise =
          buildHistoryJournalData(
            sessions,
            query: 'pulldown',
            splitId: 'a',
          ).groups.single.workouts.single;
      expect(byExercise.session.id, 'pull');
      // Found by an exercise, so the row names it.
      expect(byExercise.matchedExercises, [
        ExerciseCatalog.label('Lat Pulldown', null),
      ]);
      // Found by its name, so nothing more needs explaining.
      expect(
        buildHistoryJournalData(
          sessions,
          query: ' PUSH ',
          splitId: 'a',
        ).groups.single.workouts.single.matchedExercises,
        isEmpty,
      );
      final all = buildHistoryJournalData(sessions, splitId: 'a');
      expect(all.eligibleSessions, hasLength(2));
      expect(
        all.groups
            .expand((group) => group.workouts)
            .map((workout) => workout.matchedExercises),
        everyElement(isEmpty),
      );
    },
  );

  test(
    'summaries retain fractional volume and historical records before search',
    () {
      final first = session(
        id: 'first',
        name: 'Foundation',
        date: DateTime(2026, 8, 1),
        weight: 12.25,
        reps: 3,
      );
      final later = session(
        id: 'later',
        name: 'Later',
        date: DateTime(2026, 8, 8),
        weight: 20,
        reps: 3,
      );
      final data = buildHistoryJournalData([later, first], query: 'Foundation');
      final summary = data.groups.single.workouts.single;

      expect(summary.statistics.totalSets, 1);
      expect(summary.statistics.volumeLoad, 36.75);
      // The first workout with a lift only sets its baseline.
      expect(summary.hasPersonalRecord, isFalse);

      // The search hides the baseline workout, but the later one is still
      // judged against it.
      final found =
          buildHistoryJournalData([
            later,
            first,
          ], query: 'Later').groups.single.workouts.single;
      expect(found.hasPersonalRecord, isTrue);
    },
  );

  testWidgets('the record mark is accent ink on no ground in every theme', (
    tester,
  ) async {
    final summary =
        buildHistoryJournalData([
          session(id: 'baseline', name: 'Baseline', date: DateTime(2026, 9, 4)),
          session(
            id: 'accent-pr',
            name: 'Accent day',
            date: DateTime(2026, 9, 11),
            weight: 85,
          ),
        ]).groups.single.workouts.first;
    expect(summary.session.id, 'accent-pr');
    expect(summary.recordCount, 1);

    for (final brightness in Brightness.values) {
      for (final accent in SettingsProvider.accents) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(accent.seed, brightness),
            home: Scaffold(
              body: HistoryWorkoutRow(summary: summary, onTap: () {}),
            ),
          ),
        );

        final mark = find.byKey(const ValueKey('history-record-mark'));
        final context = tester.element(mark);
        final variant = '${accent.name} / ${brightness.name}';
        expect(
          tester.widget<Text>(find.text('1 PR')).style?.color,
          accentColor(context),
          reason: '$variant should read as accent ink',
        );
        expect(
          find.ancestor(of: mark, matching: find.byType(DecoratedBox)),
          findsNothing,
          reason: '$variant should have no ground',
        );
      }
    }
  });

  test('the record mark counts the exercises that set a record', () {
    final baseline = session(
      id: 'baseline',
      name: 'Baseline',
      date: DateTime(2026, 9, 4),
    ).copyWith(
      exercises: [
        Exercise(name: 'Bench Press', sets: [Set(weight: 80, reps: 5)]),
        Exercise(name: 'Back Squat', sets: [Set(weight: 100, reps: 5)]),
      ],
    );
    final both = session(
      id: 'both',
      name: 'Both up',
      date: DateTime(2026, 9, 11),
    ).copyWith(
      exercises: [
        Exercise(name: 'Bench Press', sets: [Set(weight: 85, reps: 5)]),
        Exercise(name: 'Back Squat', sets: [Set(weight: 110, reps: 5)]),
      ],
    );
    final workouts =
        buildHistoryJournalData([baseline, both]).groups.single.workouts;
    expect(workouts.map((workout) => workout.recordCount), [2, 0]);
    expect(workouts.last.hasPersonalRecord, isFalse);
  });

  testWidgets(
    'a row is its name, then block, week and duration, PR at the end',
    (tester) async {
      final summary =
          buildHistoryJournalData([
            session(
              id: 'baseline',
              name: 'Baseline',
              date: DateTime(2026, 9, 4),
            ),
            session(
              id: 'record',
              name: 'Heavy upper body with a long name',
              date: DateTime(2026, 9, 11),
              weight: 85,
              durationSeconds: 3900,
            ),
          ]).groups.single.workouts.first;
      expect(summary.hasPersonalRecord, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
          home: Scaffold(
            body: HistoryWorkoutRow(summary: summary, onTap: () {}),
          ),
        ),
      );

      // No volume and no set count: the row is the workout and when it was.
      expect(find.textContaining('kg'), findsNothing);
      expect(find.textContaining(' t'), findsNothing);
      expect(find.textContaining('set'), findsNothing);
      final details = find.text('Week 4 · 1h 5m');
      expect(details, findsOneWidget);

      final row = tester.getRect(find.byType(HistoryWorkoutRow));
      final nameFinder = find.text('Heavy upper body with a long name');
      final name = tester.getRect(nameFinder);
      final mark = tester.getRect(
        find.byKey(const ValueKey('history-record-mark')),
      );
      // The name runs to the right edge, with nothing beside it.
      expect(name.right, moreOrLessEquals(row.right));
      // The PR mark ends the details line, at the bottom right.
      expect(mark.top, greaterThanOrEqualTo(name.bottom));
      expect(mark.right, moreOrLessEquals(row.right));
      expect(
        mark.center.dy,
        moreOrLessEquals(tester.getRect(details).center.dy, epsilon: 2),
      );

      // The date indexes the row: smaller than the name, on its line.
      final day = find.text('11');
      expect(
        tester.widget<Text>(day).style!.fontSize,
        lessThan(tester.widget<Text>(nameFinder).style!.fontSize!),
      );
      final dayRect = tester.getRect(day);
      expect(dayRect.center.dy, inInclusiveRange(name.top, name.bottom));
      expect(
        tester.getRect(find.text('Fri')).center.dy,
        moreOrLessEquals(tester.getRect(details).center.dy, epsilon: 2),
      );
    },
  );

  testWidgets(
    'a list back while the last is still leaving scrolls on its own',
    (tester) async {
      final provider = _Sessions([
        session(id: 'a', name: 'Push Day', date: DateTime(2026, 9, 1)),
      ]);
      await tester.pumpWidget(host(provider));
      await tester.pump();
      final field = find.byKey(const ValueKey('history-search-field'));
      // A typo empties the results, and a quick backspace brings them back
      // before the first list has finished leaving.
      await tester.enterText(field, 'Pushx');
      await tester.pump();
      await tester.enterText(field, 'Push');
      await tester.pump();
      final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
      expect(lists, hasLength(2));
      // Each list owns its controller: one controller holding both positions
      // throws wherever its single position is read (the desktop scrollbar).
      expect(lists.map((list) => list.controller!.positions.length), [1, 1]);
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('journal search clears and split changes reset the query', (
    tester,
  ) async {
    final provider = _Sessions([
      session(id: 'a', name: 'Push Day', date: DateTime(2026, 9, 1)),
    ]);
    await tester.pumpWidget(host(provider));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('history-search-field')),
      'missing',
    );
    await tester.pump();
    expect(find.text('No matching workouts'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    // The ledger crosses back in place of the empty state.
    await tester.pumpAndSettle();
    expect(find.text('Push Day'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('history-search-field')),
      'Push',
    );
    provider.replaceSplit('b', [
      session(
        id: 'b',
        name: 'Pull Day',
        date: DateTime(2026, 9, 2),
        splitId: 'b',
      ),
    ]);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('history-search-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.text('Pull Day'), findsOneWidget);
  });

  testWidgets('journal preserves scroll position after opening a workout', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 600);
    await pumpHistory(tester, [
      for (var index = 0; index < 18; index++)
        session(
          id: 'scroll-$index',
          name: 'Workout $index',
          date: DateTime(2026, 9, 20 - index),
        ),
    ], size: const Size(390, 600));

    await tester.drag(
      find.byKey(const PageStorageKey('history-journal-list')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final listFinder = find.byKey(const PageStorageKey('history-journal-list'));
    final before = tester.widget<ListView>(listFinder).controller!.offset;
    expect(before, greaterThan(0));

    // Rows are short, so the first one built may sit above the viewport.
    await tester.tap(find.byType(HistoryWorkoutRow).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(EditSessionScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final after = tester.widget<ListView>(listFinder).controller!.offset;
    expect(after, moreOrLessEquals(before));
  });

  testWidgets('rows leave exercises out; a search names the one it matched', (
    tester,
  ) async {
    await pumpHistory(tester, [
      session(
        id: 'push',
        name: 'Push Day',
        date: DateTime(2026, 9, 12),
        exerciseName: 'Overhead Press',
      ),
      session(
        id: 'pull',
        name: 'Pull Day',
        date: DateTime(2026, 9, 11),
        exerciseName: 'Lat Pulldown',
      ),
    ]);
    final pulldown = ExerciseCatalog.label('Lat Pulldown', null);
    final press = ExerciseCatalog.label('Overhead Press', null);
    expect(find.text('Push Day'), findsOneWidget);
    expect(find.text('Pull Day'), findsOneWidget);
    expect(find.text(press), findsNothing);
    expect(find.text(pulldown), findsNothing);
    expect(
      find.byKey(const ValueKey('history-matched-exercises')),
      findsNothing,
    );

    final field = find.byKey(const ValueKey('history-search-field'));
    await tester.enterText(field, 'pulldown');
    await tester.pumpAndSettle();
    expect(find.text('Push Day'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('history-matched-exercises')))
          .data,
      pulldown,
    );

    // A match on the workout's own name needs no explaining.
    await tester.enterText(field, 'Pull Day');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HistoryWorkoutRow),
        matching: find.text('Pull Day'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('history-matched-exercises')),
      findsNothing,
    );
  });

  testWidgets('a workout opened from a search returns to the same search', (
    tester,
  ) async {
    await pumpHistory(tester, [
      session(
        id: 'detail',
        name: 'Mixed Case Day',
        date: DateTime(2026, 9, 11),
      ),
      session(id: 'other', name: 'Other day', date: DateTime(2026, 9, 10)),
    ]);
    await tester.enterText(
      find.byKey(const ValueKey('history-search-field')),
      'Mixed',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mixed Case Day'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditSessionScreen>(find.byType(EditSessionScreen))
          .session
          .id,
      'detail',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('history-search-field')))
          .controller
          ?.text,
      'Mixed',
    );
    expect(find.text('Other day'), findsNothing);
  });

  test('a duration under a minute is unknown', () {
    expect(knownDurationSeconds(null), isNull);
    expect(knownDurationSeconds(0), isNull);
    expect(knownDurationSeconds(59), isNull);
    expect(knownDurationSeconds(60), 60);
    expect(knownDurationSeconds(1800), 1800);
  });

  testWidgets('journal hides an unknown duration instead of showing 0m', (
    tester,
  ) async {
    final provider = _Sessions([
      session(
        id: 'zero',
        name: 'Zero day',
        date: DateTime(2026, 9, 13),
        durationSeconds: 0,
      ),
      session(
        id: 'short',
        name: 'Short day',
        date: DateTime(2026, 9, 12),
        durationSeconds: 30,
      ),
      session(
        id: 'timed',
        name: 'Timed day',
        date: DateTime(2026, 9, 11),
        durationSeconds: 1800,
      ),
    ]);
    await tester.pumpWidget(host(provider));
    await tester.pump();

    String detailsOf(String name) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(HistoryWorkoutRow),
      );
      final details = find.descendant(
        of: row,
        matching: find.textContaining('Week 4'),
      );
      return tester.widget<Text>(details).data!;
    }

    expect(detailsOf('Zero day'), 'Week 4');
    expect(detailsOf('Short day'), 'Week 4');
    expect(detailsOf('Timed day'), 'Week 4 · 30m');
    expect(find.textContaining('0m'), findsOneWidget);
  });

  testWidgets('journal date sits on the card with no ground of its own', (
    tester,
  ) async {
    final provider = _Sessions([
      session(id: 'one', name: 'Push Day', date: DateTime(2026, 9, 11)),
    ]);
    await tester.pumpWidget(host(provider));
    await tester.pump();

    final date = find.byKey(const ValueKey('history-date'));
    expect(date, findsOneWidget);
    expect(
      find.descendant(of: date, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    final row = find.byType(HistoryWorkoutRow);
    final betweenCardAndDate = find.descendant(
      of: row,
      matching: find.ancestor(of: date, matching: find.byType(DecoratedBox)),
    );
    expect(betweenCardAndDate, findsNothing);
  });

  testWidgets('a successful edit returns to History; a failed one keeps it', (
    tester,
  ) async {
    final provider = await pumpHistory(tester, [
      session(id: 'edit', name: 'Original', date: DateTime(2026, 9, 11)),
    ]);
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workout'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('workout-name-field')),
      'Updated',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workout'), findsNothing);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Workout updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.text('Updated'));
    await tester.pumpAndSettle();
    provider.failUpdate = true;
    await tester.enterText(
      find.byKey(const ValueKey('workout-name-field')),
      'Recoverable draft',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workout'), findsOneWidget);
    expect(find.textContaining('Your edits are still here'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('workout-name-field')))
          .controller
          ?.text,
      'Recoverable draft',
    );
  });

  testWidgets('editor confirms exercise deletion and saves only on Save', (
    tester,
  ) async {
    final original = session(
      id: 'exercise-delete',
      name: 'Push',
      date: DateTime(2026, 9, 11),
    );
    final provider = await pumpHistory(tester, [original]);
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Delete exercise?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Bench Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No exercises in this workout'), findsOneWidget);
    expect(provider.sessions.single.exercises, hasLength(1));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(provider.sessions.single.exercises, isEmpty);
    expect(find.text('Week 4 · No sets logged'), findsOneWidget);
  });

  testWidgets(
    'editor has compact PRs, set details, and confirmed set deletion',
    (tester) async {
      final original = session(
        id: 'set-delete',
        name: 'Push',
        date: DateTime(2026, 9, 11),
      ).copyWith(
        exercises: [
          Exercise(
            name: 'Bench Press',
            sets: [
              Set(weight: 80, reps: 5, rpe: 9, note: 'New PR!'),
              Set(weight: 60, reps: 8, rpe: 7, note: 'Controlled tempo'),
            ],
          ),
        ],
      );
      final provider = await pumpHistory(tester, [original]);
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('New PR!'), findsNothing);
      expect(find.text('PR'), findsOneWidget);
      expect(find.byTooltip('Delete set'), findsNWidgets(2));
      expect(find.text('Controlled tempo'), findsOneWidget);
      final rowTop = tester.getTopLeft(find.byTooltip('Delete set').first).dy;
      final rowBottom =
          tester.getBottomLeft(find.byTooltip('Delete set').first).dy;
      expect(
        tester.getCenter(find.text('PR')).dy,
        inInclusiveRange(rowTop, rowBottom),
      );

      await tester.tap(find.byTooltip('Set 1 details'));
      await tester.pumpAndSettle();
      expect(find.text('Edit set'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller?.text,
        'New PR!',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete set').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete set?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete set'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Delete set').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete set'), findsOneWidget);
      expect(find.text('PR'), findsNothing);
      expect(provider.sessions.single.exercises.single.sets, hasLength(2));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final remaining = provider.sessions.single.exercises.single.sets.single;
      expect(remaining.weight, 60);
      expect(remaining.reps, 8);
      expect(remaining.rpe, 7);
      expect(remaining.note, 'Controlled tempo');
      expect(original.exercises.single.sets, hasLength(2));
    },
  );

  testWidgets(
    'deleting through set details also confirms and handles the last set',
    (tester) async {
      final original = session(
        id: 'last-set',
        name: 'Push',
        date: DateTime(2026, 9, 11),
        setNote: 'New PR!',
      );
      final provider = await pumpHistory(tester, [original]);
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Set 1 details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete set?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete set'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete set'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No sets recorded'), findsOneWidget);
      expect(find.text('Add set'), findsOneWidget);
      expect(find.text('Reps'), findsNothing);
      expect(provider.sessions.single.exercises.single.sets, hasLength(1));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(provider.sessions.single.exercises.single.sets, isEmpty);
    },
  );

  testWidgets(
    'history edits timed sets in seconds and keeps saved values until Save',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 900);
      addTearDown(tester.view.reset);
      final original = session(
        id: 'hold',
        name: 'Core',
        date: DateTime(2026, 9, 12),
        exerciseName: 'Plank',
        weight: 0,
        reps: 45,
      );
      final provider = _Sessions([
        original,
        session(
          id: 'previous-hold',
          name: 'Core',
          date: DateTime(2026, 9, 11),
          exerciseName: 'Plank',
          weight: 0,
          reps: 30,
        ),
      ]);
      await tester.pumpWidget(
        host(
          provider,
          screen: EditSessionScreen(session: original),
          size: const Size(1000, 900),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seconds'), findsOneWidget);
      expect(find.text('30 s'), findsOneWidget);
      expect(find.text('Reps'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Set 1 Seconds'));
      await tester.pumpAndSettle();
      for (final digit in ['6', '0']) {
        await tester.tap(find.widgetWithText(InkWell, digit).last);
        await tester.pump();
      }
      await tester.tap(
        find.descendant(
          of: find.bySemanticsLabel('Hide keypad'),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.sessions.first.exercises.single.sets.single.reps, 45);
      await tester.tap(find.byTooltip('Set 1 details'));
      await tester.pumpAndSettle();
      expect(find.text('Seconds'), findsNWidgets(2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(provider.sessions.first.exercises.single.sets.single.reps, 60);
      expect(original.exercises.single.sets.single.reps, 45);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor PR controls fit small screens and enlarged text', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final brightness in Brightness.values) {
      for (final scenario in [
        (const Size(320, 800), 1.0),
        (const Size(390, 1000), 2.0),
        (const Size(1000, 800), 1.0),
      ]) {
        final original = session(
          id: 'pr-layout',
          name: 'Push',
          date: DateTime(2026, 9, 11),
          setNote: 'New PR!',
          rpe: 8,
        );
        tester.view.physicalSize = scenario.$1;
        await tester.pumpWidget(
          host(
            _Sessions([original]),
            screen: EditSessionScreen(session: original),
            brightness: brightness,
            size: scenario.$1,
            textScale: scenario.$2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('PR'), findsOneWidget);
        expect(find.text('New PR!'), findsNothing);
        expect(
          tester.getSize(find.byTooltip('Set 1 details')).width,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byTooltip('Set 1 details')).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          find.text('Prev'),
          scenario.$1.width >= 1000 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('delete supports cancel, failure retry, and confirmed removal', (
    tester,
  ) async {
    final provider = await pumpHistory(tester, [
      session(id: 'delete', name: 'Delete Me', date: DateTime(2026, 9, 11)),
    ]);
    await tester.tap(find.text('Delete Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delete “Delete Me” from 11 Sep 2026?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workout'), findsOneWidget);

    provider.failDelete = true;
    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('delete-workout-error')), findsOneWidget);
    expect(find.text('Delete workout?'), findsOneWidget);

    provider.failDelete = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No completed workouts'), findsOneWidget);
  });

  testWidgets('journal, editing, and empty states do not overflow', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final brightness in Brightness.values) {
      for (final scenario in [
        (const Size(320, 800), 1.0),
        (const Size(390, 800), 2.0),
        (const Size(1000, 800), 1.0),
      ]) {
        tester.view.physicalSize = scenario.$1;
        await pumpHistory(
          tester,
          [
            session(
              id: 'visual',
              name: 'Long lower-body training session',
              date: DateTime(2026, 9, 11),
              exerciseName: 'Single-leg Romanian deadlift',
              exerciseNote:
                  'Use a slow lowering phase and keep the hips level.',
              setNote: 'Left side first, then match repetitions on the right.',
            ),
          ],
          brightness: brightness,
          size: scenario.$1,
          textScale: scenario.$2,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Long lower-body training session'));
        await tester.pumpAndSettle();
        expect(find.text('Edit workout'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }

    tester.view.physicalSize = const Size(320, 800);
    await tester.pumpWidget(host(_Sessions([]), size: const Size(320, 800)));
    await tester.pump();
    expect(find.text('No completed workouts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Sessions extends WorkoutSessionProvider {
  _Sessions(List<WorkoutSession> sessions) : _sessions = List.of(sessions);

  List<WorkoutSession> _sessions;
  String _splitId = 'a';
  bool failUpdate = false;
  bool failDelete = false;

  @override
  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  @override
  String? get activeSplitId => _splitId;

  void replaceSplit(String splitId, List<WorkoutSession> sessions) {
    _splitId = splitId;
    _sessions = List.of(sessions);
    notifyListeners();
  }

  @override
  Future<void> upsertSession(WorkoutSession updated) async {
    if (failUpdate) throw StateError('update failed');
    final index = _sessions.indexWhere((session) => session.id == updated.id);
    _sessions[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> deleteSession(String id) async {
    if (failDelete) throw StateError('delete failed');
    _sessions.removeWhere((session) => session.id == id);
    notifyListeners();
  }
}
