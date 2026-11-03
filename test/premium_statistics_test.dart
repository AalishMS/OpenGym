import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/statistics/strength_trend.dart';

import 'support/test_fonts.dart';

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> values;
  _Sessions(this.values);
  @override
  void loadSessions() {}
  @override
  List<WorkoutSession> get sessions => values;
}

void main() {
  setUpAll(loadTestFonts);
  final current = StatisticsAnalyticsService.startOfWeek(DateTime.now());
  WorkoutSession workout(String id, int daysAgo, double weight) =>
      WorkoutSession(
        id: id,
        planName: 'Push',
        date: current.subtract(Duration(days: daysAgo)),
        exercises: [
          Exercise(
            name: 'Bench press',
            sets: [
              gym.Set(weight: weight, reps: 8),
              gym.Set(weight: 99, reps: 0),
            ],
          ),
        ],
      );
  final sessions = [
    workout('before', 14, 25),
    workout('last', 7, 50),
    workout('current', 0, 60),
  ];

  Widget host({Brightness brightness = Brightness.light, double scale = 1}) =>
      ChangeNotifierProvider<WorkoutSessionProvider>(
        create: (_) => _Sessions(sessions),
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF41B9B9), brightness),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: StatsScreen(),
              bottomNavigationBar: SizedBox(height: 72),
            ),
          ),
        ),
      );

  testWidgets(
    'weekly selection keeps exact volume and performed totals together',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('400 kg'), findsOneWidget);
      expect(find.text('+100% vs previous week'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('training-week-2')));
      await tester.pump();
      expect(find.text('480 kg'), findsOneWidget);
      expect(find.text('Week in progress'), findsOneWidget);
      expect(find.textContaining('vs previous week'), findsNothing);
      // The zero-rep set never enters volume, set count, or rep count.
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('training-week-0')));
      await tester.pump();
      expect(find.text('200 kg'), findsOneWidget);
      expect(find.text('Week in progress'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'strength points select recorded values and support flat or single histories',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-tab-Strength')));
      await tester.pumpAndSettle();
      expect(find.text('Latest workout'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('progress-metric-info')));
      await tester.pumpAndSettle();
      expect(
        find.text(ExerciseMetric.estimatedOneRepMax.description),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-point-0')));
      await tester.pump();
      expect(find.text('Selected workout'), findsOneWidget);
      expect(find.text('31.67 kg'), findsOneWidget);
      for (final data in [
        <WorkoutSession>[],
        [workout('single', 0, 0)],
        [workout('flat-a', 1, 50), workout('flat-b', 0, 50)],
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(const Color(0xFF41B9B9), Brightness.dark),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StrengthTrend(
                  key: UniqueKey(),
                  progress: const StatisticsAnalyticsService().exerciseProgress(
                    data,
                    'Bench press',
                    ExerciseMetric.bestWeight,
                  ),
                  metric: ExerciseMetric.bestWeight,
                  weightUnit: 'lbs',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'every view handles small screens and enlarged text in both themes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = const Size(320, 640);
          await tester.pumpWidget(host(brightness: brightness, scale: scale));
          await tester.pumpAndSettle();
          for (final label in ['Overview', 'Strength', 'Blocks', 'Records']) {
            final tab = find.byKey(ValueKey('statistics-tab-$label'));
            await tester.ensureVisible(tab);
            await tester.tap(tab);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$label $brightness ${scale}x',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
}
