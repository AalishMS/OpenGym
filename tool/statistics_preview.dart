// A read-only, in-memory fixture for reviewing multi-block statistics on a device.
// Build with: flutter build apk --debug --target tool/statistics_preview.dart
// It does not initialize Hive, auth, or sync, and never writes training data.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/training_block_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';

const _split = 'statistics-preview';
final _blocks = [
  for (var i = 0; i < 7; i++)
    TrainingBlock(
      id: 'preview-$i',
      splitId: _split,
      name: 'Block ${i + 1}',
      position: i,
      createdAt: DateTime(2026, 4, 1 + i * 28),
      plannedWeekCount: 4,
    ),
];
final _weeks = {
  for (var i = 0; i < _blocks.length; i++)
    _blocks[i].id: [
      for (var week = 1; week <= 4; week++)
        TrainingWeek(
          id: 'preview-$i-$week',
          splitId: _split,
          blockId: _blocks[i].id,
          number: week,
          createdAt: _blocks[i].createdAt,
        ),
    ],
};
final _sessions = [
  for (var i = 0; i < _blocks.length; i++)
    for (var week = 1; week <= 4; week++)
      for (var day = 0; day < 3; day++)
        WorkoutSession(
          id: 'preview-$i-$week-$day',
          splitId: _split,
          trainingWeekId: 'preview-$i-$week',
          planName: ['Push', 'Pull', 'Legs'][day],
          date: DateTime(2026, 4, 1 + i * 28 + (week - 1) * 7 + day * 2),
          exercises: [
            for (final (name, start) in switch (day) {
              0 => [
                ('Bench press', 55.0),
                ('Shoulder press', 30.0),
                ('Tricep pushdown', 25.0),
              ],
              1 => [
                ('Barbell row', 45.0),
                ('Lat pulldown', 40.0),
                ('Bicep curl', 17.5),
              ],
              _ => [
                ('Squat', 70.0),
                ('Romanian deadlift', 55.0),
                ('Leg press', 110.0),
              ],
            })
              Exercise(
                name: name,
                sets: [
                  for (var set = 0; set < 3 + (week % 2); set++)
                    gym.Set(
                      weight:
                          start +
                          [0.0, 5.0, 2.5, 10.0, 7.5, 15.0, 17.5][i] +
                          week * 2.5,
                      reps: 8,
                    ),
                ],
              ),
          ],
        ),
];

class _PreviewSessions extends WorkoutSessionProvider {
  @override
  void loadSessions() {}
  @override
  List<WorkoutSession> get sessions => _sessions;
}

class _PreviewBlocks extends TrainingBlockProvider {
  _PreviewBlocks() : super(splitIdProvider: () => _split, ownerId: () => null) {
    blocks = _blocks;
    blockById = {for (final block in blocks) block.id: block};
    weeksByBlock = _weeks;
    weekById = {
      for (final week in _weeks.values.expand((weeks) => weeks)) week.id: week,
    };
  }
  @override
  void reload() {}
}

void main() {
  if (!kDebugMode) {
    throw StateError('Statistics preview is only available in debug builds.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WorkoutSessionProvider>(
          create: (_) => _PreviewSessions(),
        ),
        ChangeNotifierProvider<TrainingBlockProvider>(
          create: (_) => _PreviewBlocks(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(const Color(0xFF41B9B9), Brightness.light),
        darkTheme: buildTheme(const Color(0xFF41B9B9), Brightness.dark),
        home: Scaffold(
          body: const StatsScreen(),
          bottomNavigationBar: AppBottomNav(currentIndex: 2, onTap: (_) {}),
        ),
      ),
    ),
  );
}
