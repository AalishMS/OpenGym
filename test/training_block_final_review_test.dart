import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/training_block_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/split_install_target.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/utils/split_identity.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';
import 'training_block_sync_test.dart' show ReplicaApi;

void main() {
  final storage = HiveTestHarness();
  late ReplicaApi api;
  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      httpClient: MockClient((r) async {
        final response = await api.handle(r);
        return http.Response(
          response.body,
          response.statusCode,
          headers: {'content-type': 'application/json', ...response.headers},
          request: r,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    api = ReplicaApi();
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
  });
  testWidgets(
    'unsaved logger edit after a canonical week rebase must retain the new label',
    (tester) async {
      try {
        await tester.runAsync(() async {
          await HiveService.putSplitRaw(
            gym.Split(id: 's', name: 'Training', createdAt: DateTime(2026)),
          );
          await HiveService.putPlanRaw(
            WorkoutPlan(
              id: 'p',
              splitId: 's',
              name: 'Push',
              exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
            ),
          );
          await HiveService.putSessionRaw(
            WorkoutSession(
              id: 'draft',
              planId: 'p',
              splitId: 's',
              planName: 'Push',
              date: DateTime(2026),
              isCompleted: false,
              exercises: [
                Exercise(name: 'Squat', sets: [gym.Set(weight: 40, reps: 8)]),
              ],
            ),
          );
          await TrainingBlockMigration().normalize(ownerId: null);
        });
        final training = TrainingBlockProvider(
          splitIdProvider: () => 's',
          ownerId: () => null,
        );
        final sessions = WorkoutSessionProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TrainingBlockProvider>.value(
                value: training,
              ),
              ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
              ChangeNotifierProvider<WorkoutSessionProvider>.value(
                value: sessions,
              ),
            ],
            child: MaterialApp(
              theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
              home: WorkoutScreen(
                plan: HiveService.getPlanById('p')!,
                planIndex: 0,
              ),
            ),
          ),
        );
        await pumpWithStorage(tester);
        tester
            .widget<ExerciseCard>(find.byType(ExerciseCard).first)
            .onSetChanged!(0, 0, 80, 8);
        await tester.pump();
        final week = HiveService.getAllTrainingWeeksRaw().single;
        await tester.runAsync(
          () => HiveService.persistTrainingWeekRebase(
            week.copyWith(number: 2),
            ownerId: null,
          ),
        );
        training.reload();
        await tester.pump();
        tester
            .widget<ExerciseCard>(find.byType(ExerciseCard).first)
            .onEntryFinished!();
        await pumpWithStorage(tester);
        final saved = HiveService.getSessionById('draft')!;
        debugPrint(
          'REPRO edited=${saved.exercises.first.sets.first.weight}; session label=${saved.weekNumber}; week label=${HiveService.getTrainingWeekById(week.id)!.number}',
        );
        Object? failed;
        try {
          HiveService.readTrainingGraph(ownerId: null).validate();
        } catch (e) {
          failed = e;
        }
        debugPrint('REPRO graph validation=$failed');
        expect(saved.exercises.first.sets.first.weight, 80);
        expect(find.text('Block 1 · Week 2'), findsOneWidget);
        expect(
          saved.weekNumber,
          2,
          reason:
              'Stable link must retain canonical label through a stale UI edit',
        );
        expect(
          () => HiveService.readTrainingGraph(ownerId: null).validate(),
          returnsNormally,
        );
      } finally {
        await closeStorageWithFrames(tester, storage.close);
      }
    },
  );
  test('sync keeps a pristine default split reusable', () async {
    try {
      await SupabaseService.auth.getSessionFromUrl(
        Uri.parse(
          'io.opengym.app://callback/#access_token=test&refresh_token=test&expires_in=3600&token_type=bearer&type=signup',
        ),
      );
      final owner = SupabaseService.currentUserId!;
      final id = defaultSplitIdForUser(owner);
      await HiveService.putSplitRaw(
        gym.Split(
          id: id,
          name: 'My Split',
          userId: owner,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          dirty: true,
        ),
      );
      await TrainingBlockMigration().normalize(ownerId: owner);
      expect(
        SplitInstallTarget.isUntouchedDefault(
          HiveService.getSplitById(id),
          owner,
        ),
        isTrue,
      );
      await SyncService.instance.syncNow(fullReconciliation: true);
      debugPrint(
        'REPRO after sync block timestamp=${HiveService.getAllTrainingBlocksRaw().single.updatedAt}; week timestamp=${HiveService.getAllTrainingWeeksRaw().single.updatedAt}; status=${SyncService.instance.status}',
      );
      expect(
        SplitInstallTarget.isUntouchedDefault(
          HiveService.getSplitById(id),
          owner,
        ),
        isTrue,
      );
    } finally {
      await SupabaseService.signOut();
      await storage.close();
    }
  });
  test(
    'stale timer session writes keep the canonical week label and values',
    () async {
      try {
        await HiveService.putSplitRaw(
          gym.Split(id: 's', name: 'Training', createdAt: DateTime(2026)),
        );
        await HiveService.putPlanRaw(
          WorkoutPlan(id: 'p', splitId: 's', name: 'Push', exercises: []),
        );
        await HiveService.putSessionRaw(
          WorkoutSession(
            id: 'timer',
            splitId: 's',
            planId: 'p',
            planName: 'Push',
            date: DateTime(2026),
            isCompleted: false,
            startedAt: DateTime(2026),
            durationSeconds: 40,
            exercises: [
              Exercise(name: 'Squat', sets: [gym.Set(weight: 80, reps: 8)]),
            ],
          ),
        );
        await TrainingBlockMigration().normalize(ownerId: null);
        final stale = HiveService.getSessionById('timer')!;
        final week = HiveService.getTrainingWeekById(stale.trainingWeekId!)!;
        await HiveService.persistTrainingWeekRebase(
          week.copyWith(number: 2),
          ownerId: null,
        );
        await HiveService.upsertSession(stale.copyWith(durationSeconds: 55));
        final saved = HiveService.getSessionById('timer')!;
        expect(saved.weekNumber, 2);
        expect(saved.trainingWeekId, week.id);
        expect(saved.durationSeconds, 55);
        expect(saved.exercises.single.sets.single.weight, 80);
        expect(
          () => HiveService.readTrainingGraph(ownerId: null).validate(),
          returnsNormally,
        );
      } finally {
        await storage.close();
      }
    },
  );
}
