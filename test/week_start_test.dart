import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/format.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';

import 'support/test_fonts.dart';

/// A week that runs Sunday to Friday with Wednesday off: the user's split,
/// on the Thursday of its week.
final DateTime _thursday = DateTime(2026, 11, 26, 9);
final DateTime _sunday = DateTime(2026, 11, 22, 18);
final DateTime _monday = DateTime(2026, 11, 23, 18);
final DateTime _tuesday = DateTime(2026, 11, 24, 18);

WorkoutSession _session(String id, DateTime date) => WorkoutSession(
  id: id,
  date: date,
  planName: 'Plan $id',
  exercises: [
    Exercise(name: 'Bench Press', sets: [Set(reps: 5, weight: 100)]),
  ],
);

void main() {
  group('startOfWeek', () {
    test('finds the latest chosen weekday on or before the date', () {
      expect(
        startOfWeek(_thursday, firstDay: DateTime.monday),
        DateTime(2026, 11, 23),
      );
      expect(
        startOfWeek(_thursday, firstDay: DateTime.sunday),
        DateTime(2026, 11, 22),
      );
      expect(
        startOfWeek(_thursday, firstDay: DateTime.saturday),
        DateTime(2026, 11, 21),
      );
    });

    test('a date on the first day starts its own week', () {
      expect(
        startOfWeek(_sunday, firstDay: DateTime.sunday),
        DateTime(2026, 11, 22),
      );
      // A Monday week puts that Sunday at the end of the week before.
      expect(
        startOfWeek(_sunday, firstDay: DateTime.monday),
        DateTime(2026, 11, 16),
      );
    });

    test('crosses month and year boundaries', () {
      // Friday 1 January 2027.
      expect(
        startOfWeek(DateTime(2027, 1, 1), firstDay: DateTime.sunday),
        DateTime(2026, 12, 27),
      );
    });

    test('the analytics week is the same week', () {
      for (final day in [DateTime.monday, DateTime.sunday, DateTime.saturday]) {
        expect(
          StatisticsAnalyticsService.startOfWeek(_thursday, firstDay: day),
          startOfWeek(_thursday, firstDay: day),
        );
      }
    });
  });

  test('weekdays are listed from the first day', () {
    expect(weekdaysFrom(DateTime.monday), [1, 2, 3, 4, 5, 6, 7]);
    expect(weekdaysFrom(DateTime.sunday), [7, 1, 2, 3, 4, 5, 6]);
    expect(weekdaysFrom(DateTime.saturday), [6, 7, 1, 2, 3, 4, 5]);
    expect(weekdaysFrom(DateTime.sunday).map(weekdayLetter).join(), 'SMTWTFS');
  });

  group('the setting', () {
    Future<SettingsProvider> loaded() async {
      final settings = SettingsProvider();
      final done = Completer<void>();
      settings.addListener(() {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      return settings;
    }

    test('starts on Monday, as the app always has', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await loaded()).weekStartsOn, DateTime.monday);
    });

    test('is stored and read back', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await loaded();
      await settings.setWeekStartsOn(DateTime.sunday);
      expect(settings.weekStartsOn, DateTime.sunday);
      expect(
        (await SharedPreferences.getInstance()).getInt('week_starts_on'),
        DateTime.sunday,
      );
      expect((await loaded()).weekStartsOn, DateTime.sunday);
    });

    test('ignores a value that is not a weekday', () async {
      SharedPreferences.setMockInitialValues({'week_starts_on': 9});
      final settings = await loaded();
      expect(settings.weekStartsOn, DateTime.monday);
      await settings.setWeekStartsOn(0);
      expect(settings.weekStartsOn, DateTime.monday);
    });

    test('a backup restores it, and a backup without it is valid', () {
      TrainingBlockRestore.validateSettings({});
      TrainingBlockRestore.validateSettings({'weekStartsOn': DateTime.sunday});
      for (final bad in [0, 8, '7', null]) {
        expect(
          () => TrainingBlockRestore.validateSettings({'weekStartsOn': bad}),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });

  group('statistics', () {
    const analytics = StatisticsAnalyticsService();
    final saturday = _session('sat', DateTime(2026, 11, 21, 18));
    final sunday = _session('sun', _sunday);

    test('weekly volume buckets weeks from the chosen day', () {
      // Weeks run through the current one, empty or not.
      final monday = analytics.weeklyVolume([saturday, sunday], now: _thursday);
      expect(monday.map((week) => week.weekStart), [
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 23),
      ]);
      expect(monday.map((week) => week.volumeLoad), [1000, 0]);

      final sundayWeeks = analytics.weeklyVolume(
        [saturday, sunday],
        now: _thursday,
        firstDayOfWeek: DateTime.sunday,
      );
      expect(sundayWeeks.map((week) => week.weekStart), [
        DateTime(2026, 11, 15),
        DateTime(2026, 11, 22),
      ]);
      expect(sundayWeeks.map((week) => week.volumeLoad), [500, 500]);
    });

    test('periods end with the chosen week', () {
      // Four weeks back from a Sunday week reaches Sunday 1 November; a Monday
      // week only reaches Monday 2 November.
      final early = _session('early', DateTime(2026, 11, 1, 18));
      expect(
        analytics.sessionsInPeriod(
          [early],
          StatisticsPeriod.fourWeeks,
          now: _thursday,
        ),
        isEmpty,
      );
      expect(
        analytics.sessionsInPeriod(
          [early],
          StatisticsPeriod.fourWeeks,
          now: _thursday,
          firstDayOfWeek: DateTime.sunday,
        ),
        [early],
      );
    });

    test('a period starts at midnight of its first day', () {
      // Sunday 1 November 2026 is when clocks go back in North America.
      // Counting the four weeks in 24-hour steps put the start at 1 a.m.
      // there, which dropped a workout logged in the hour after midnight.
      final firstHour = _session('first-hour', DateTime(2026, 11, 1, 0, 30));
      final lastHour = _session('last-hour', DateTime(2026, 11, 28, 23, 30));
      expect(
        analytics.sessionsInPeriod(
          [firstHour, lastHour],
          StatisticsPeriod.fourWeeks,
          now: _thursday,
          firstDayOfWeek: DateTime.sunday,
        ),
        unorderedEquals([firstHour, lastHour]),
      );
    });
  });

  group('the Home week strip', () {
    setUpAll(loadTestFonts);

    Future<void> pumpStrip(WidgetTester tester, int firstDay) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
            home: Scaffold(
              body: TrainingSnapshot(
                plans: const [],
                sessions: [
                  _session('sun', _sunday),
                  _session('mon', _monday),
                  _session('tue', _tuesday),
                ],
                now: _thursday,
                firstDayOfWeek: firstDay,
              ),
            ),
          ),
        );

    Finder day(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    /// The day drawn [index] places from the left of the strip.
    Finder slot(int index, String label) => find.ancestor(
      of: find.byKey(ValueKey('training-day-$index')),
      matching: day(label),
    );

    testWidgets('a Sunday week counts Sunday and reads S to S', (tester) async {
      await pumpStrip(tester, DateTime.sunday);

      expect(find.text('3 workouts · 3 sets'), findsOneWidget);
      expect(slot(0, 'Sunday: 1 workout, 1 set'), findsOneWidget);
      expect(slot(3, 'Wednesday: 0 workouts, 0 sets'), findsOneWidget);
      expect(slot(4, 'Thursday: 0 workouts, 0 sets, today'), findsOneWidget);
      expect(slot(6, 'Saturday: 0 workouts, 0 sets'), findsOneWidget);
    });

    testWidgets('a Monday week leaves Sunday in the week before', (
      tester,
    ) async {
      await pumpStrip(tester, DateTime.monday);

      expect(find.text('2 workouts · 2 sets'), findsOneWidget);
      expect(slot(0, 'Monday: 1 workout, 1 set'), findsOneWidget);
      expect(slot(6, 'Sunday: 0 workouts, 0 sets'), findsOneWidget);
    });
  });
}
