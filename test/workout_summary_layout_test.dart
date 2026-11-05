import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/screens/workout_summary_screen.dart';
import 'package:gymapp/services/pr_tracking_service.dart';
import 'package:gymapp/theme/app_theme.dart';

void main() {
  // Layout depends on the bundled production glyphs, especially when deciding
  // whether the duration, sets and reps fit on the same line.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.manrope(fontWeight: weight);
    }
    await GoogleFonts.pendingFonts();
  });

  Future<void> openSummary(
    WidgetTester tester, {
    required Brightness brightness,
    required double scale,
    double width = 360,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    final session = WorkoutSession(
      id: 'current',
      planId: 'legs',
      planName: 'Legs and shoulders',
      date: DateTime(2026, 11, 5),
      weekNumber: 3,
      durationSeconds: 13740,
      isCompleted: true,
      exercises: [
        Exercise(
          name: 'Leg press',
          sets: List.generate(10, (_) => gym.Set(weight: 20, reps: 8)),
        ),
        Exercise(name: 'Lateral raise', sets: [gym.Set(weight: 10, reps: 10)]),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF41B9B9), brightness),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 32, bottom: 24),
              ),
              child: child!,
            ),
        home: WorkoutSummaryScreen(
          session: session,
          history: [
            session.copyWith(
              id: 'previous',
              date: session.date.subtract(const Duration(days: 7)),
              exercises: [session.exercises.first],
            ),
          ],
          records: [
            PRResult(
              exerciseName: 'Leg press',
              previousPR: 150,
              newPR: 160,
              reps: 8,
            ),
            PRResult(
              exerciseName: 'Lateral raise',
              previousPR: 0,
              newPR: 10,
              reps: 10,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a full summary fits the Nord without scrolling in both themes', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      await openSummary(tester, brightness: brightness, scale: 1.15);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, 0);
      final duration = tester.getRect(find.text('3h 49m'));
      final sets = tester.getRect(find.text('11'));
      expect(duration.top, closeTo(sets.top, 1));
      expect(find.text('was 150 kg').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large text remains readable and can scroll on a small screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await openSummary(
      tester,
      brightness: Brightness.dark,
      scale: 2,
      width: 320,
    );
    await tester.ensureVisible(find.text('was 150 kg'));
    await tester.pumpAndSettle();
    expect(find.text('was 150 kg').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
