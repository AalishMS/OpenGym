import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/theme/app_theme.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> data;
  _Sessions(this.data);
  @override
  void loadSessions() {}
  @override
  List<WorkoutSession> get sessions => data;
}

/// Keeps what the screen last worked out, to see whether it was refreshed.
class _Capturing extends StatisticsAnalyticsService {
  Map<String, String> directory = const {};
  List<RecordEvent> records = const [];

  @override
  Map<String, String> exerciseDirectory(Iterable<WorkoutSession> sessions) =>
      directory = super.exerciseDirectory(sessions);

  @override
  List<RecordEvent> recordEvents(Iterable<WorkoutSession> sessions) =>
      records = super.recordEvents(sessions);
}

/// Renames and merges change what a logged lift resolves to without touching
/// the workouts, so Stats' caches must follow the catalog too.
void main() {
  final harness = HiveTestHarness();

  setUpAll(loadTestFonts);
  setUp(() => harness.open());

  WorkoutSession workout(String id, int daysAgo, String exerciseId, double kg) {
    final today = DateTime.now();
    return WorkoutSession(
      id: id,
      splitId: 'split',
      planName: 'Push',
      date: DateTime(today.year, today.month, today.day - daysAgo, 10),
      isCompleted: true,
      exercises: [
        Exercise(
          name: 'Logged name',
          exerciseId: exerciseId,
          sets: [gym.Set(weight: kg, reps: 5)],
        ),
      ],
    );
  }

  testWidgets('a rename or merge refreshes names and records', (tester) async {
    try {
      late final String a;
      late final String b;
      await tester.runAsync(() async {
        a = (await ExerciseCatalog.createCustom('Alpha lift')).id;
        b = (await ExerciseCatalog.createCustom('Beta lift')).id;
      });
      final capturing = _Capturing();
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkoutSessionProvider>.value(
          value: _Sessions([
            workout('one', 2, a, 80),
            workout('two', 1, b, 90),
          ]),
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
            home: Scaffold(body: StatsScreen(analytics: capturing)),
          ),
        ),
      );
      await pumpWithStorage(tester);
      expect(capturing.directory, {b: 'Beta lift', a: 'Alpha lift'});
      expect(capturing.records, isEmpty, reason: 'each is its first workout');

      await tester.runAsync(() => ExerciseCatalog.rename(a, 'Alpha renamed'));
      await pumpWithStorage(tester);
      expect(capturing.directory[a], 'Alpha renamed');

      // The 90 kg workout now follows the 80 kg one of the same lift.
      await tester.runAsync(() => ExerciseCatalog.merge(a, b));
      await pumpWithStorage(tester);
      expect(capturing.directory, {b: 'Beta lift'});
      final record = capturing.records.single;
      expect(record.session.id, 'two');
      expect(
        record.achievements
            .where((r) => r.type == RecordType.heaviestWeight)
            .single
            .previousValue,
        80,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await closeStorageWithFrames(tester, harness.close);
    }
  });
}
