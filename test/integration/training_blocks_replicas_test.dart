import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/split_repository.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/services/training_week_session_resolver.dart';
import 'package:gymapp/services/workout_progression_service.dart';
import 'package:gymapp/services/workout_session_initializer.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../support/hive_test_harness.dart';

/// The Python API suite seeds this owner in the named, loopback-only database.
/// The JWT below is signed with its public test secret; it is not an app key.
const _owner = '00000000-0000-4000-8000-000000000012';
const _token =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMTIiLCJyb2xlIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MjA4Mjc1ODQwMH0.ong4l-e3Eq8xSS32sLYIqWffqML8JQ9nn_hYPgSohfA';

void main() {
  test(
    'two isolated Hive replicas converge offline completions and competing appends',
    () async {
      final storage = HiveTestHarness();
      final secondStorage = HiveTestHarness();
      final native = http.Client();
      SharedPreferences.setMockInitialValues({});
      await storage.open(includeSplits: true);
      await Supabase.initialize(
        url: 'http://127.0.0.1:55440',
        publishableKey: 'isolated-test-key',
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/user')) {
            return http.Response(
              jsonEncode({
                'id': _owner,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'test@example.com',
                'created_at': '2026-01-01T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              }),
              200,
              request: r,
            );
          }
          if (r.url.path.startsWith('/rest/v1/')) {
            final target = r.url.replace(
              path: r.url.path.replaceFirst('/rest/v1', ''),
            );
            final request =
                http.Request(r.method, target)
                  ..headers.addAll(r.headers)
                  ..bodyBytes = r.bodyBytes;
            final response = await http.Response.fromStream(
              await native.send(request),
            );
            return response;
          }
          return http.Response('{}', 200, request: r);
        }),
      );
      Future<void> mount(String path) async {
        await Hive.close();
        SharedPreferences.setMockInitialValues({});
        Hive.init(path);
        await Hive.openBox<Split>(HiveService.splitsBox);
        await Hive.openBox<SplitPreference>(HiveService.splitPreferencesBox);
        await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
        await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
        await Hive.openBox<TrainingBlock>(HiveService.trainingBlocksBox);
        await Hive.openBox<TrainingWeek>(HiveService.trainingWeeksBox);
        await Hive.openBox<WorkoutProgress>(HiveService.workoutProgressBox);
        await Hive.openBox<dynamic>(HiveService.trainingOperationsBox);
      }

      Future<void> sync() async {
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(SyncService.instance.status, SyncStatus.synced);
      }

      String? trialSplitId;
      try {
        await SupabaseService.auth.getSessionFromUrl(
          Uri.parse(
            'io.opengym.app://callback/#access_token=$_token&refresh_token=local&expires_in=3600&token_type=bearer&type=signup',
          ),
        );
        await sync();
        expect(
          HiveService.getAllSessionsRaw().every((s) => s.userId == _owner),
          isTrue,
        );
        final splitId = const Uuid().v4();
        trialSplitId = splitId;
        final pushId = const Uuid().v4();
        final pullId = const Uuid().v4();
        await SplitRepository().upsertSplit(
          Split(
            id: splitId,
            name: 'Replica ${splitId.substring(0, 8)}',
            userId: _owner,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            dirty: true,
          ),
        );
        for (final pair in [(pushId, 'Trial push'), (pullId, 'Trial pull')]) {
          await HiveService.createPlan(
            WorkoutPlan(
              id: pair.$1,
              splitId: splitId,
              userId: _owner,
              name: pair.$2,
              exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
            ),
          );
        }
        final repo = TrainingBlockRepository(ownerId: () => _owner);
        final firstBlock = repo.blocksForSplit(splitId).single.id;
        final firstWeek = repo.weeksForBlock(splitId, firstBlock).single.id;
        final secondWeek = (await repo.appendWeek(splitId, firstBlock)).id;
        final laterBlock = await repo.createBlock(
          splitId: splitId,
          name: 'Matching',
          weekCount: 2,
        );
        final matchingWeek =
            repo.weeksForBlock(splitId, laterBlock.id).first.id;
        await sync();
        final pathA =
            File(
              Hive.box<WorkoutSession>(HiveService.sessionsBox).path!,
            ).parent.path;

        Future<String> log(String planId, double weight) async {
          final plan = HiveService.getPlanById(planId)!;
          final week = HiveService.getTrainingWeekById(firstWeek)!;
          final draft = WorkoutSessionInitializer.initialize(
            plan: plan,
            week: week,
          ).copyWith(
            startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
            durationSeconds: 60,
            exercises: [
              Exercise(name: 'Squat', sets: [gym.Set(weight: weight, reps: 5)]),
            ],
          );
          await HiveService.upsertSession(draft);
          await WorkoutProgressionService(
            ownerId: () => _owner,
          ).complete(draft.id!);
          expect(
            HiveService.progressForPlan(splitId, planId)!.activeWeekId,
            secondWeek,
          );
          return draft.id!;
        }

        await Hive.close();
        SharedPreferences.setMockInitialValues({});
        await secondStorage.open(includeSplits: true);
        final pathB =
            File(
              Hive.box<WorkoutSession>(HiveService.sessionsBox).path!,
            ).parent.path;
        await sync();
        final pullLog = await log(pullId, 75);
        final appendB = await repo.appendWeek(splitId, firstBlock);
        expect(appendB.number, 3);

        await mount(pathA);
        expect(HiveService.getSessionById(pullLog), isNull);
        final pushLog = await log(pushId, 60);
        final appendA = await repo.appendWeek(splitId, firstBlock);
        expect(appendA.number, 3);
        await sync();

        await mount(pathB);
        expect(HiveService.getSessionById(pushLog), isNull);
        await sync();
        expect(
          HiveService.getSessionById(
            pushLog,
          )!.exercises.single.sets.single.weight,
          60,
        );
        expect(
          HiveService.getSessionById(
            pullLog,
          )!.exercises.single.sets.single.weight,
          75,
        );
        expect(repo.weeksForBlock(splitId, firstBlock).map((w) => w.number), [
          1,
          2,
          3,
          4,
        ]);
        expect(
          repo.weeksForBlock(splitId, firstBlock).map((w) => w.id),
          containsAll([appendA.id, appendB.id]),
        );
        expect(
          HiveService.progressForPlan(splitId, pushId)!.activeWeekId,
          secondWeek,
        );
        expect(
          HiveService.progressForPlan(splitId, pullId)!.activeWeekId,
          secondWeek,
        );
        final source = TrainingWeekSessionResolver.source(
          splitId: splitId,
          planId: pushId,
          weekId: matchingWeek,
          blocks: repo.blocksForSplit(splitId),
          weeks: HiveService.getAllTrainingWeeksRaw(),
          sessions: HiveService.getAllSessionsRaw(),
        );
        final preview = WorkoutSessionInitializer.initialize(
          plan: HiveService.getPlanById(pushId)!,
          week: HiveService.getTrainingWeekById(matchingWeek)!,
          previousSession: source,
        );
        expect(preview.exercises.single.sets.single.weight, 60);
        expect(preview.isCompleted, isFalse);
        expect(preview.hasStarted, isFalse);
        await mount(pathA);
        await sync();
        expect(HiveService.getSessionById(pullLog)!.isCompleted, isTrue);
        expect(repo.weeksForBlock(splitId, firstBlock).map((w) => w.number), [
          1,
          2,
          3,
          4,
        ]);
        expect(
          HiveService.progressForPlan(splitId, pullId)!.activeWeekId,
          secondWeek,
        );
      } finally {
        if (trialSplitId != null) {
          final stamp = DateTime.now().toUtc().toIso8601String();
          final cleanup = await native.patch(
            Uri.parse('http://127.0.0.1:55440/splits?id=eq.$trialSplitId'),
            headers: {
              'Authorization': 'Bearer $_token',
              'x-opengym-training-schema': '1',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'deleted_at': stamp, 'updated_at': stamp}),
          );
          expect(cleanup.statusCode, 204, reason: cleanup.body);
        }
        await Supabase.instance.dispose();
        native.close();
        await storage.close();
        await secondStorage.close();
      }
    },
    skip: !const bool.fromEnvironment('OPENGYM_LOCAL_API_TESTS'),
  );
}
