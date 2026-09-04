import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/stats_repository.dart';
import 'package:gymapp/services/backup_service.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/utils/split_identity.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('opengym_splits_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    Hive.registerAdapter(SplitAdapter());
    Hive.registerAdapter(SplitPreferenceAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
    await Hive.openBox<Split>(HiveService.splitsBox);
    await Hive.openBox<SplitPreference>(HiveService.splitPreferencesBox);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('legacy rows are assigned to the deterministic My Split', () async {
    const userId = '00000000-0000-0000-0000-000000000001';
    final plan = WorkoutPlan(id: 'plan-1', name: 'Legacy', exercises: []);
    final session = WorkoutSession(
      id: 'session-1',
      planId: plan.id,
      date: DateTime(2026),
      planName: plan.name,
      exercises: [],
    );
    await HiveService.putPlanRaw(plan);
    await HiveService.putSessionRaw(session);

    await HiveService.ensureSplitWorkspace(userId);

    final expected = defaultSplitIdForUser(userId);
    expect(HiveService.getSplits().single.id, expected);
    expect(HiveService.getSplitPreference(userId)?.activeSplitId, expected);
    expect(HiveService.getPlanById(plan.id!)?.splitId, expected);
    expect(HiveService.getSessionById(session.id!)?.splitId, expected);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('split_scope_backup_plans_$userId'), isNotNull);
    expect(prefs.getString('split_scope_backup_sessions_$userId'), isNotNull);
  });

  test('plans, sessions, and stats cannot cross split boundaries', () async {
    const userId = 'user-1';
    final now = DateTime(2026);
    for (final split in [
      Split(id: 'ppl', name: 'PPL', createdAt: now, userId: userId),
      Split(id: 'ul', name: 'UL', createdAt: now, userId: userId),
    ]) {
      await HiveService.putSplitRaw(split);
    }
    await HiveService.putPlanRaw(
      WorkoutPlan(id: 'p1', splitId: 'ppl', name: 'Push', exercises: []),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(id: 'p2', splitId: 'ul', name: 'Upper', exercises: []),
    );
    await HiveService.putSessionRaw(_session('s1', 'ppl', 100));
    await HiveService.putSessionRaw(_session('s2', 'ul', 60));

    final stats = StatsRepository();
    expect(HiveService.getPlans(splitId: 'ppl').single.name, 'Push');
    expect(HiveService.getSessions(splitId: 'ul').single.id, 's2');
    expect(stats.getExercisePR('Bench Press', 'ppl'), 100);
    expect(stats.getExercisePR('Bench Press', 'ul'), 60);
  });

  test('deleting a split tombstones only its descendants', () async {
    const userId = 'user-1';
    final now = DateTime(2026);
    await HiveService.putSplitRaw(
      Split(id: 'ppl', name: 'PPL', createdAt: now, userId: userId),
    );
    await HiveService.putSplitRaw(
      Split(id: 'ul', name: 'UL', createdAt: now, userId: userId),
    );
    await HiveService.putSplitPreferenceRaw(
      SplitPreference(userId: userId, activeSplitId: 'ppl'),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(id: 'p1', splitId: 'ppl', name: 'Push', exercises: []),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(id: 'p2', splitId: 'ul', name: 'Upper', exercises: []),
    );
    await HiveService.putSessionRaw(_session('s1', 'ppl', 100));
    await HiveService.putSessionRaw(_session('s2', 'ul', 60));

    await HiveService.softDeleteSplit(
      userId: userId,
      splitId: 'ppl',
      replacementSplitId: 'ul',
    );

    expect(HiveService.getSplitPreference(userId)?.activeSplitId, 'ul');
    expect(HiveService.getSplitById('ppl')?.deletedAt, isNotNull);
    expect(HiveService.getPlanById('p1')?.deletedAt, isNotNull);
    expect(HiveService.getSessionById('s1')?.deletedAt, isNotNull);
    expect(HiveService.getPlanById('p2')?.deletedAt, isNull);
    expect(HiveService.getSessionById('s2')?.deletedAt, isNull);
  });

  test('v2 backups upgrade into one deterministic split', () {
    const userId = '00000000-0000-0000-0000-000000000002';
    final backup = jsonEncode({
      'version': 2,
      'settings': <String, dynamic>{},
      'workoutPlans': [
        WorkoutPlan(id: 'p1', name: 'Legacy', exercises: []).toJson(),
      ],
      'workoutSessions': [
        WorkoutSession(
          id: 's1',
          planId: 'p1',
          date: DateTime(2026),
          planName: 'Legacy',
          exercises: [],
        ).toJson(),
      ],
    });

    final result = BackupService.importData(backup, userId: userId);

    expect(result.success, isTrue);
    expect(result.splits?.single.name, 'My Split');
    expect(result.activeSplitId, defaultSplitIdForUser(userId));
    expect(result.plans?.single.splitId, result.activeSplitId);
    expect(result.sessions?.single.splitId, result.activeSplitId);
  });

  test('v3 backups preserve all splits and the active selection', () {
    final createdAt = DateTime(2026);
    final splits = [
      Split(id: 'ppl', name: 'PPL', createdAt: createdAt),
      Split(id: 'ul', name: 'UL', createdAt: createdAt),
    ];
    final exported = BackupService.exportData(
      splits: splits,
      activeSplitId: 'ul',
      plans: [
        WorkoutPlan(id: 'p1', splitId: 'ppl', name: 'Push', exercises: []),
        WorkoutPlan(id: 'p2', splitId: 'ul', name: 'Upper', exercises: []),
      ],
      sessions: [_session('s1', 'ul', 60)],
      settings: const {'themeMode': 0},
    );

    final imported = BackupService.importData(
      exported.jsonString,
      userId: 'user-1',
    );

    expect(imported.success, isTrue);
    expect(imported.splits?.map((split) => split.name), ['PPL', 'UL']);
    expect(imported.activeSplitId, 'ul');
    expect(imported.plans?.map((plan) => plan.splitId), ['ppl', 'ul']);
    expect(imported.sessions?.single.splitId, 'ul');
  });
}

WorkoutSession _session(String id, String splitId, double weight) =>
    WorkoutSession(
      id: id,
      splitId: splitId,
      date: DateTime(2026),
      planName: 'Plan',
      exercises: [
        Exercise(
          name: 'Bench Press',
          sets: [Set(reps: 5, weight: weight)],
        ),
      ],
    );
