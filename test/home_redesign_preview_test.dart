import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';

import 'support/hive_test_harness.dart';

void main() {
  final hiveHarness = HiveTestHarness();
  setUpAll(() => hiveHarness.open());
  tearDownAll(() => hiveHarness.close());
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final fullBody = WorkoutPlan(
    id: 'full-body',
    name: 'Full Body',
    exercises: [
      for (final entry
          in {
            'Squat': 3,
            'Bench Press': 3,
            'Deadlift': 2,
            'Overhead Press': 3,
            'Barbell Row': 3,
            'Lateral Raise': 3,
          }.entries)
        ExerciseTemplate(name: entry.key, sets: entry.value),
    ],
  );

  testWidgets(
    'duration uses completed timed sessions matched by plan identity',
    (tester) async {
      final now = DateTime.now();
      final sessions = [
        WorkoutSession(
          planId: fullBody.id,
          planName: 'Old name',
          date: now,
          exercises: const [],
          durationSeconds: 1200,
        ),
        WorkoutSession(
          planId: fullBody.id,
          planName: fullBody.name,
          date: now,
          exercises: const [],
          durationSeconds: 2400,
        ),
        WorkoutSession(
          planId: 'different-plan',
          planName: fullBody.name,
          date: now,
          exercises: const [],
          durationSeconds: 9000,
        ),
        WorkoutSession(
          planId: fullBody.id,
          planName: fullBody.name,
          date: now,
          exercises: const [],
          durationSeconds: 9000,
          isCompleted: false,
        ),
      ];
      await tester.pumpWidget(_host([fullBody], sessions, Brightness.light));
      expect(find.textContaining('~30 min'), findsOneWidget);
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Shoulders'), findsOneWidget);
      expect(find.text('Legs'), findsOneWidget);
      await tester.pumpWidget(_host([fullBody], const [], Brightness.light));
      expect(find.textContaining(' min'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reference layout renders in both themes with real activity', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
    const capture = bool.fromEnvironment('HOME_PREVIEW');
    if (capture) {
      final font = File('build/previews/manrope.ttf');
      if (font.existsSync()) {
        final bytes = ByteData.sublistView(font.readAsBytesSync());
        for (final weight in ['regular', '400', '500', '600', '700', '800']) {
          await (FontLoader('Manrope_$weight')
            ..addFont(Future.value(bytes))).load();
        }
        await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        )).load();
      }
    }
    final now = DateTime.now();
    final plans = [
      fullBody.copyWith(
        id: 'upper',
        name: 'Upper Body',
        planColor: kPlanColors[7],
      ),
      fullBody.copyWith(
        id: 'push',
        name: 'Push Day',
        planColor: kPlanColors[1],
      ),
      fullBody,
    ];
    WorkoutSession session(
      int daysAgo,
      int count,
      String id, {
      int? duration,
    }) => WorkoutSession(
      planId: id,
      planName: id == 'push' ? 'Push Day' : 'Full Body',
      date: now.subtract(
        Duration(days: daysAgo, minutes: id == 'upper' ? 60 : 0),
      ),
      durationSeconds: duration,
      exercises: [
        Exercise(
          name: 'Bench Press',
          sets: [for (var i = 0; i < count; i++) Set(reps: 8, weight: 60)],
        ),
      ],
    );
    final sessions = [
      session(3, 14, 'upper'),
      session(2, 12, 'push'),
      session(0, 18, 'upper'),
      session(0, 14, 'push'),
      session(6, 17, 'full-body', duration: 3300),
    ];
    for (final brightness in Brightness.values) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        _host(plans, sessions, brightness, boundary: boundary),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.textContaining('~55 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (capture) {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/previews').create(recursive: true);
          await File(
            'build/previews/home_${brightness.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}

Widget _host(
  List<WorkoutPlan> plans,
  List<WorkoutSession> sessions,
  Brightness brightness, {
  GlobalKey? boundary,
}) => MultiProvider(
  key: UniqueKey(),
  providers: [
    ChangeNotifierProvider<WorkoutPlanProvider>(create: (_) => _Plans(plans)),
    ChangeNotifierProvider<WorkoutSessionProvider>(
      create: (_) => _Sessions(sessions),
    ),
    ChangeNotifierProvider<SplitProvider>(create: (_) => _Splits()),
  ],
  child: MaterialApp(
    key: UniqueKey(),
    theme: buildTheme(const Color(0xFF008D8D), brightness),
    home: RepaintBoundary(
      key: boundary,
      child: Scaffold(
        body: const HomeScreen(),
        bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
      ),
    ),
  ),
);

class _Plans extends WorkoutPlanProvider {
  final List<WorkoutPlan> values;
  _Plans(this.values);
  @override
  List<WorkoutPlan> get plans => values;
}

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> values;
  _Sessions(this.values);
  @override
  List<WorkoutSession> get sessions => values;
}

class _Splits extends SplitProvider {
  @override
  void loadSplits() {}
  @override
  gym.Split get activeSplit => gym.Split(
    id: 'preview-split',
    name: 'My split',
    createdAt: DateTime(2026),
  );
}
