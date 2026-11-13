import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/screens/workout_summary_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

class _Plans extends WorkoutPlanProvider {
  final WorkoutPlan plan;
  _Plans(this.plan);
  @override
  List<WorkoutPlan> get plans => [plan];
}

class _Sessions extends WorkoutSessionProvider {
  bool fail = false;
  @override
  Future<void> upsertSession(WorkoutSession session) async {
    if (fail) throw StateError('disk unavailable');
    await super.upsertSession(session);
  }
}

void main() {
  final harness = HiveTestHarness();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      // The deep-link observer listens on the app_links channel, which has no
      // test plugin. Its MissingPluginException arrives asynchronously and
      // lands in whichever test is running, failing takeException() below.
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });
  for (final fails in [false, true]) {
    testWidgets(
      fails
          ? 'failed completion keeps draft and shows no summary'
          : 'visible finish logs once and closes to completed workout',
      (tester) async {
        await tester.runAsync(harness.open);
        try {
          final plan = WorkoutPlan(
            id: 'finish-plan',
            name: 'Push',
            exercises: [ExerciseTemplate(name: 'Bench press', sets: 1)],
          );
          await tester.runAsync(() async {
            await Hive.box<WorkoutSession>(HiveService.sessionsBox).put(
              'draft',
              WorkoutSession(
                id: 'draft',
                planId: plan.id,
                planName: plan.name,
                date: DateTime(2026, 1, 1),
                isCompleted: false,
                startedAt: DateTime(2026, 1, 1),
                durationSeconds: 90,
                exercises: [
                  Exercise(
                    name: 'Bench press',
                    sets: [gym.Set(weight: 50, reps: 5)],
                  ),
                ],
              ),
            );
            await harness.prepareTraining([plan]);
          });
          final sessions = _Sessions();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<WorkoutPlanProvider>(
                  create: (_) => _Plans(plan),
                ),
                ChangeNotifierProvider<WorkoutSessionProvider>.value(
                  value: sessions,
                ),
              ],
              child: MaterialApp(home: WorkoutScreen(plan: plan, planIndex: 0)),
            ),
          );
          await pumpWithStorage(tester);
          sessions.fail = fails;
          final finish = find.byKey(const ValueKey('finish-workout'));
          expect(finish, findsOneWidget);
          await tester.tap(finish);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Log workout'));
          await pumpWithStorage(tester);
          expect(
            find.byType(WorkoutSummaryScreen),
            fails ? findsNothing : findsOneWidget,
          );
          expect(HiveService.getSessionById('draft')!.isCompleted, !fails);
          if (!fails) {
            await tester.tap(find.byKey(const ValueKey('summary-done')));
            await tester.pumpAndSettle();
            expect(finish, findsNothing);
            expect(find.byType(WorkoutSummaryScreen), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await closeStorageWithFrames(tester, harness.close);
        }
      },
    );
  }
}
