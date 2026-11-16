import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gymapp/models/exercise_definition.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/services/adopt_local_data.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/services/training_block_lifecycle.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/workout_progression_service.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/hive_test_harness.dart';

const owner = '00000000-0000-4000-8000-000000000001';
const splitId = '00000000-0000-4000-8000-000000000002';
const planId = '00000000-0000-4000-8000-000000000003';
final stamp = DateTime.utc(2026, 1, 1);

class ReplicaApi {
  final requests = <http.Request>[];
  final tables = <String, List<Map<String, dynamic>>>{};
  Future<http.Response?> Function(http.Request)? intercept;
  String userId = owner;

  /// 3 models a server without the block lifecycle migration: activation
  /// refuses header 4 and block rows have no duration clock column. 4 models
  /// the migrated server.
  int serverSchema = 3;

  /// The account's `minimum_training_schema`; null until it is first activated.
  int? accountSchema;

  int headerSchema(http.Request request) =>
      int.tryParse(request.headers['x-opengym-training-schema'] ?? '') ?? 0;

  http.Response failure(int status, String code, String message, [String? d]) =>
      http.Response(
        jsonEncode({'code': code, 'message': message, 'details': d}),
        status,
      );

  /// The PT426 fence every request passes through on the real server.
  http.Response? guard(http.Request request) {
    final minimum = accountSchema;
    if (request.url.path.startsWith('/rest/') &&
        minimum != null &&
        headerSchema(request) < minimum) {
      return failure(426, 'PT426', 'Update OpenGym to sync this account');
    }
    return null;
  }

  http.Response rpc(http.Request request) {
    final name = request.url.pathSegments.last;
    if (name == 'activate_training_schema') {
      final header = headerSchema(request);
      if (header < 1 || header > serverSchema) {
        return failure(426, 'PT426', 'Update OpenGym to prepare training data');
      }
      accountSchema = header > (accountSchema ?? 0) ? header : accountSchema;
      return http.Response('$header', 200);
    }
    if (name == 'delete_training_block') return deleteBlock(request);
    return http.Response('null', 200);
  }

  http.Response deleteBlock(http.Request request) {
    if ((accountSchema ?? 0) < 4) {
      return failure(426, 'PT426', 'Update OpenGym to delete training blocks');
    }
    final target = (jsonDecode(request.body) as Map)['target'];
    final blocks = tables.putIfAbsent('training_blocks', () => []);
    final weeks = tables.putIfAbsent('training_weeks', () => []);
    final found =
        blocks
            .where((b) => b['id'] == target && b['user_id'] == userId)
            .firstOrNull;
    if (found == null) return http.Response('null', 200);
    final mine = weeks.where((w) => w['block_id'] == target).toList();
    if (found['deleted_at'] == null) {
      final split = (tables['splits'] ?? []).where(
        (r) => r['id'] == found['split_id'],
      );
      if (split.any((r) => r['deleted_at'] != null)) {
        return failure(409, 'PT409', 'unavailable', 'split_deleted');
      }
      if (!blocks.any(
        (b) =>
            b['split_id'] == found['split_id'] &&
            b['deleted_at'] == null &&
            b['id'] != target,
      )) {
        return failure(409, 'PT409', 'keeps one block', 'last_block');
      }
      final ids = mine.map((w) => w['id']).toSet();
      final used =
          (tables['workout_sessions'] ?? []).any(
            (r) =>
                r['deleted_at'] == null && ids.contains(r['training_week_id']),
          ) ||
          (tables['workout_progress'] ?? []).any(
            (r) => r['deleted_at'] == null && ids.contains(r['active_week_id']),
          );
      if (used) return failure(409, 'PT409', 'in use', 'in_use');
      final at = DateTime.utc(2026, 11, 16, 12).toIso8601String();
      for (final row in [
        found,
        ...mine.where((w) => w['deleted_at'] == null),
      ]) {
        row['deleted_at'] = at;
        row['updated_at'] = at;
        row['server_seq'] = '${DateTime.utc(2026, 11, 16, 12, 0, 1)}'
            .replaceFirst(' ', 'T');
      }
    }
    return http.Response(
      jsonEncode({
        'block': found,
        'weeks': [...mine]
          ..sort((a, b) => (a['number'] as int) - (b['number'] as int)),
      }),
      200,
    );
  }

  /// `keep_newest_row` for blocks: the duration resolves on its own clock.
  Map<String, dynamic> mergeBlock(
    Map<String, dynamic> old,
    Map<String, dynamic> incoming,
  ) {
    DateTime clock(Map<String, dynamic> r) =>
        r['planned_week_count_updated_at'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
            : DateTime.parse(r['planned_week_count_updated_at'] as String);
    final row = Map<String, dynamic>.from(incoming);
    final oldCount = old['planned_week_count'] as int?;
    final newCount = row['planned_week_count'] as int?;
    if (newCount == null ||
        (oldCount != null && clock(old).isAfter(clock(row)))) {
      row['planned_week_count'] = oldCount;
      row['planned_week_count_updated_at'] =
          old['planned_week_count_updated_at'];
    } else if (oldCount != null && clock(old) == clock(row)) {
      row['planned_week_count'] = oldCount > newCount ? oldCount : newCount;
    }
    Map<String, dynamic> result;
    if (old['deleted_at'] != null && row['deleted_at'] == null) {
      result = Map<String, dynamic>.from(old);
    } else if (old['deleted_at'] == null && row['deleted_at'] != null) {
      result = row;
    } else if (DateTime.parse(
      row['updated_at'] as String,
    ).isBefore(DateTime.parse(old['updated_at'] as String))) {
      result = Map<String, dynamic>.from(old);
    } else {
      result = row;
    }
    result['planned_week_count'] = row['planned_week_count'];
    if (serverSchema >= 4) {
      result['planned_week_count_updated_at'] =
          row['planned_week_count_updated_at'];
    }
    return result;
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.path.endsWith('/user')) {
      return http.Response(
        jsonEncode({
          'id': userId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'a@example.com',
          'created_at': stamp.toIso8601String(),
          'app_metadata': {},
          'user_metadata': {},
        }),
        200,
      );
    }
    final override = await intercept?.call(request);
    if (override != null) return override;
    final fenced = guard(request);
    if (fenced != null) return fenced;
    if (request.url.path.contains('/rpc/')) return rpc(request);
    final table = request.url.pathSegments.last;
    final rows = tables.putIfAbsent(table, () => []);
    if (request.method == 'GET') {
      final q = request.url.queryParameters;
      var result = rows.where((r) => r['user_id'] == userId).toList();
      for (final key in ['id', 'user_id', 'block_id', 'server_seq']) {
        final filter = q[key];
        if (filter == null) continue;
        final dot = filter.indexOf('.');
        final op = filter.substring(0, dot);
        final value = filter.substring(dot + 1);
        result =
            result.where((r) {
              final cmp = '${r[key]}'.compareTo(value);
              return op == 'eq'
                  ? cmp == 0
                  : op == 'gt'
                  ? cmp > 0
                  : cmp >= 0;
            }).toList();
      }
      final or = q['or'];
      if (or != null) {
        final seq = RegExp(r'server_seq.gt.([^,]+)').firstMatch(or)?.group(1);
        final id = RegExp(r'id.gt.([^),]+)').firstMatch(or)?.group(1);
        if (seq != null && id != null) {
          result =
              result
                  .where(
                    (r) =>
                        '${r['server_seq']}'.compareTo(seq) > 0 ||
                        ('${r['server_seq']}' == seq &&
                            '${r['id']}'.compareTo(id) > 0),
                  )
                  .toList();
        }
      }
      final sort = q['order'] ?? 'id.asc';
      result.sort((a, b) {
        if (sort.startsWith('server_seq')) {
          final cmp = '${a['server_seq']}'.compareTo('${b['server_seq']}');
          if (cmp != 0) return sort.contains('server_seq.desc') ? -cmp : cmp;
        }
        final cmp = '${a['id'] ?? a['user_id']}'.compareTo(
          '${b['id'] ?? b['user_id']}',
        );
        return sort.contains('id.desc') || sort.contains('user_id.desc')
            ? -cmp
            : cmp;
      });
      final count = int.tryParse(q['limit'] ?? '') ?? 1000;
      return http.Response(jsonEncode(result.take(count).toList()), 200);
    }
    if (request.method == 'POST') {
      final value = jsonDecode(request.body);
      final incoming = value is List ? value : [value];
      final saved = <Map<String, dynamic>>[];
      for (final item in incoming) {
        final row = Map<String, dynamic>.from(item as Map);
        final key = table == 'split_preferences' ? 'user_id' : 'id';
        if ((request.headers['Prefer'] ?? '').contains(
              'resolution=ignore-duplicates',
            ) &&
            rows.any((r) => r[key] == row[key])) {
          continue;
        }
        var stored = row;
        if (table == 'training_blocks') {
          if (serverSchema < 4 &&
              row.containsKey('planned_week_count_updated_at')) {
            return failure(
              400,
              'PGRST204',
              "Could not find the 'planned_week_count_updated_at' column",
            );
          }
          final old = rows.where((r) => r[key] == row[key]).firstOrNull;
          if (old != null) stored = mergeBlock(old, row);
        }
        rows.removeWhere((r) => r[key] == row[key]);
        stored['server_seq'] =
            stamp.add(const Duration(days: 1)).toIso8601String();
        rows.add(stored);
        saved.add(stored);
      }
      return http.Response(jsonEncode(saved), 201);
    }
    return http.Response('[]', 200);
  }
}

void main() {
  final storage = HiveTestHarness();
  late ReplicaApi api;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        final response = await api.handle(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: {'content-type': 'application/json', ...response.headers},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    api = ReplicaApi();
    SyncService.instance.forgetNegotiatedSchemas();
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    await SupabaseService.auth.getSessionFromUrl(
      Uri.parse(
        'io.opengym.app://callback/#access_token=test&refresh_token=test&expires_in=3600&token_type=bearer&type=signup',
      ),
    );
    await HiveService.putSplitRaw(
      Split(
        id: splitId,
        name: 'A',
        userId: owner,
        createdAt: stamp,
        updatedAt: stamp,
        dirty: true,
      ),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: planId,
        name: 'Push',
        splitId: splitId,
        userId: owner,
        updatedAt: stamp,
        dirty: true,
        exercises: [],
      ),
    );
    await TrainingBlockMigration().normalize(ownerId: owner);
    api.requests.clear();
  });
  tearDown(() async {
    api.intercept = null;
    await SupabaseService.signOut();
    await storage.close();
  });

  test(
    'a partial catalog pull survives restart and resolves a later target',
    () async {
      const sourceId = '11111111-1111-4111-8111-111111111111';
      const targetId = '22222222-2222-4222-8222-222222222222';
      final week = HiveService.getAllTrainingWeeksRaw().single;
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'partial-catalog-log',
          date: stamp,
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: week.id,
          updatedAt: stamp,
          dirty: true,
          exercises: [
            Exercise(
              name: 'DB Press',
              exerciseId: sourceId,
              sets: [gym.Set(reps: 8, weight: 20)],
            ),
          ],
        ),
      );
      final source = ExerciseDefinition(
        id: sourceId,
        name: 'DB Press',
        mergedIntoId: targetId,
        userId: owner,
        updatedAt: stamp,
      );
      api.tables['exercise_definitions'] = [
        {
          'id': sourceId,
          'user_id': owner,
          'data': source.toJson(),
          'updated_at': stamp.toIso8601String(),
          'server_seq': stamp.add(const Duration(days: 1)).toIso8601String(),
        },
      ];
      // The server has only the first accepted row of an interrupted custom
      // merge upload. This replica also loses transport after persisting it.
      api.intercept =
          (request) async =>
              request.method == 'GET' &&
                      request.url.path.endsWith('/workout_plans')
                  ? http.Response('{"message":"offline","code":"OFFLINE"}', 503)
                  : null;
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.retryableError);
      expect(ExerciseCatalog.getById(sourceId)!.mergedIntoId, targetId);
      expect(ExerciseCatalog.getById(targetId), isNull);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastUserId', owner);
      await prefs.setBool('adopted_$owner', true);
      final directory =
          File(Hive.box<WorkoutPlan>(HiveService.plansBox).path!).parent.path;
      await Hive.close();
      Hive.init(directory);
      await ExerciseCatalog.open();
      await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
      await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
      await Hive.openBox<Split>(HiveService.splitsBox);
      await Hive.openBox<SplitPreference>(HiveService.splitPreferencesBox);
      await HiveService.openTrainingBoxes();
      final requestsBeforePreparation = api.requests.length;
      await AdoptLocalData.prepareLocalForUser(owner);
      // Startup and retry require no network to regain the saved logger.
      await TrainingBlockMigration().normalize(ownerId: owner);
      expect(api.requests, hasLength(requestsBeforePreparation));
      expect(ExerciseCatalog.canonicalId(sourceId), sourceId);
      expect(
        ExerciseCatalog.search('DB Press').map((d) => d.id),
        contains(sourceId),
      );
      expect(
        HiveService.getSessionById(
          'partial-catalog-log',
        )!.exercises.single.sets.single.weight,
        20,
      );
      expect(ExerciseCatalog.getById(targetId), isNull);

      api.intercept = null;
      final target = ExerciseDefinition(
        id: targetId,
        name: 'My dumbbell press',
        userId: owner,
        updatedAt: stamp,
      );
      api.tables['exercise_definitions']!.add({
        'id': targetId,
        'user_id': owner,
        'data': target.toJson(),
        'updated_at': stamp.toIso8601String(),
        'server_seq': stamp.add(const Duration(days: 2)).toIso8601String(),
      });
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(ExerciseCatalog.canonicalId(sourceId), targetId);
      expect(ExerciseCatalog.findByName('DB Press')!.id, targetId);
      final saved = HiveService.getSessionById('partial-catalog-log')!;
      expect(saved.exercises.single.exerciseId, sourceId);
      expect(saved.exercises.single.name, 'DB Press');
      expect(saved.exercises.single.sets.single.weight, 20);
      expect(const StatisticsAnalyticsService().exerciseDirectory([saved]), {
        targetId: 'My dumbbell press',
      });
    },
  );

  test('custom exercise definitions sync before workout references', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ExerciseCatalog.put(
      ExerciseDefinition(
        id: id,
        name: 'My press',
        userId: owner,
        updatedAt: stamp,
        dirty: true,
      ),
    );
    await SyncService.instance.syncNow();
    expect(ExerciseCatalog.getById(id)!.dirty, isFalse);
    final row = api.tables['exercise_definitions']!.single;
    expect(row['user_id'], owner);
    expect((row['data'] as Map)['id'], id);
    final writes =
        api.requests
            .where((r) => r.method == 'POST')
            .map((r) => r.url.pathSegments.last)
            .toList();
    expect(
      writes.indexOf('exercise_definitions'),
      lessThan(writes.indexOf('workout_plans')),
    );
  });

  test('a newer unmerged pull cannot erase a pending exercise merge', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    final merged = ExerciseDefinition(
      id: id,
      name: 'DB Press',
      mergedIntoId: 'builtin:dumbbell-press',
      userId: owner,
      updatedAt: stamp,
      dirty: true,
    );
    await ExerciseCatalog.put(merged);
    api.tables['exercise_definitions'] = [
      {
        'id': id,
        'user_id': owner,
        'updated_at': stamp.add(const Duration(days: 10)).toIso8601String(),
        'server_seq': stamp.add(const Duration(days: 11)).toIso8601String(),
        'data': {...merged.toJson(), 'mergedIntoId': null},
      },
    ];
    await SyncService.instance.syncNow();
    expect(ExerciseCatalog.canonicalId(id), 'builtin:dumbbell-press');
    expect(ExerciseCatalog.getById(id)!.dirty, isFalse);
    expect(
      (api.tables['exercise_definitions']!.single['data']
          as Map)['mergedIntoId'],
      'builtin:dumbbell-press',
    );
  });

  test('a remote merge wins over a newer local unmerged name edit', () async {
    const id = '11111111-1111-4111-8111-111111111111';
    final local = ExerciseDefinition(
      id: id,
      name: 'My press',
      userId: owner,
      updatedAt: stamp.add(const Duration(days: 10)),
      dirty: true,
    );
    await ExerciseCatalog.put(local);
    api.tables['exercise_definitions'] = [
      {
        'id': id,
        'user_id': owner,
        'updated_at': stamp.toIso8601String(),
        'server_seq': stamp.add(const Duration(days: 11)).toIso8601String(),
        'data': {...local.toJson(), 'mergedIntoId': 'builtin:dumbbell-press'},
      },
    ];
    await SyncService.instance.syncNow();
    expect(ExerciseCatalog.canonicalId(id), 'builtin:dumbbell-press');
    expect(ExerciseCatalog.getById(id)!.dirty, isFalse);
  });

  test(
    'sync round trips intended duration and only the completing plan available weeks',
    () async {
      final repo = TrainingBlockRepository(ownerId: () => owner);
      final block = await repo.createBlock(
        splitId: splitId,
        name: 'Build',
        weekCount: 4,
      );
      final first = repo.weeksForBlock(splitId, block.id).single;
      final progress = repo.progressForPlan(splitId, planId)!;
      await HiveService.putWorkoutProgressRaw(
        progress.copyWith(activeWeekId: first.id, availableWeekIds: [first.id]),
      );
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'lazy-log',
          planId: planId,
          planName: 'Push',
          splitId: splitId,
          userId: owner,
          trainingWeekId: first.id,
          date: stamp,
          isCompleted: false,
          startedAt: stamp,
          durationSeconds: 60,
          exercises: [],
        ),
      );
      await WorkoutProgressionService(
        ownerId: () => owner,
      ).complete('lazy-log');
      final weeks = repo.weeksForBlock(splitId, block.id);
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(SyncService.instance.status, SyncStatus.synced);
      final row = api.tables['training_blocks']!.singleWhere(
        (r) => r['id'] == block.id,
      );
      expect(row['planned_week_count'], 4);
      expect(api.tables['workout_progress']!.single['available_week_ids'], [
        first.id,
        weeks.last.id,
      ]);
      await HiveService.clearTrainingData();
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(HiveService.getTrainingBlockById(block.id)!.plannedWeekCount, 4);
      expect(repo.progressForPlan(splitId, planId)!.availableWeekIds, [
        first.id,
        weeks.last.id,
      ]);
    },
  );

  for (final prepared in [false, true]) {
    test(
      'partial v1 upload cannot shrink duration (prepared: $prepared)',
      () async {
        await SyncService.instance.syncNow(fullReconciliation: true);
        final repo = TrainingBlockRepository(ownerId: () => owner);
        final block = repo.blocksForSplit(splitId).single;
        final oldMetadata = block.toJson();
        for (var n = 2; n <= 4; n++) {
          await repo.appendWeek(splitId, block.id);
        }
        // V1 appended slots without editing/timestamping the parent block. The
        // upgraded server only knows Week 1 and has backfilled a duration of one.
        await HiveService.putTrainingBlockRaw(
          TrainingBlock.fromJson({...oldMetadata, 'plannedWeekCount': null}),
        );
        if (prepared) {
          await TrainingBlockMigration().normalize(ownerId: owner);
          expect(
            HiveService.getTrainingBlockById(block.id)!.plannedWeekCount,
            4,
          );
        }
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(HiveService.getTrainingBlockById(block.id)!.plannedWeekCount, 4);
        expect(api.tables['training_blocks']!.single['planned_week_count'], 4);
        expect(repo.weeksForBlock(splitId, block.id), hasLength(4));
      },
    );
  }

  test(
    'a newer rename retains a remotely extended intended duration',
    () async {
      await SyncService.instance.syncNow(fullReconciliation: true);
      final block = HiveService.blocksForSplit(splitId).single;
      api.tables['training_blocks']!.single['planned_week_count'] = 5;
      await HiveService.putTrainingBlockRaw(
        block.copyWith(
          name: 'Renamed',
          plannedWeekCount: 4,
          updatedAt: DateTime.utc(2026, 10, 29),
          dirty: true,
        ),
      );
      await SyncService.instance.syncNow(fullReconciliation: true);
      final saved = HiveService.getTrainingBlockById(block.id)!;
      expect(saved.name, 'Renamed');
      expect(saved.plannedWeekCount, 5);
      expect(api.tables['training_blocks']!.single['planned_week_count'], 5);
    },
  );

  test(
    'a successful but invalid capability response cannot authorize graph uploads',
    () async {
      api.intercept =
          (r) async =>
              r.url.path.contains('/rpc/activate_training_schema')
                  ? http.Response('[]', 200)
                  : null;
      await SyncService.instance.syncNow();
      expect(
        api.requests.where(
          (r) => r.method == 'POST' && !r.url.path.contains('/rpc/'),
        ),
        isEmpty,
      );
      expect(SyncService.instance.status, SyncStatus.retryableError);
    },
  );

  test(
    'split name conflicts retain the existing rename-and-retry behavior',
    () async {
      var rejected = false;
      api.intercept = (r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/splits') && !rejected) {
          rejected = true;
          return http.Response(
            '{"code":"23505","message":"duplicate split name"}',
            409,
          );
        }
        return null;
      };
      await SyncService.instance.syncNow();
      expect(HiveService.getSplitById(splitId)!.name, 'A (2)');
      expect(HiveService.getSplitById(splitId)!.dirty, isFalse);
    },
  );

  test(
    'parent failure defers graph uploads and retains dirty structure',
    () async {
      api.intercept =
          (r) async =>
              r.method == 'POST' && r.url.path.endsWith('/splits')
                  ? http.Response(
                    '{"code":"23514","message":"parent unavailable"}',
                    400,
                  )
                  : null;
      await SyncService.instance.syncNow();
      expect(
        api.requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/training_weeks'),
        ),
        isEmpty,
      );
      expect(HiveService.getAllTrainingWeeksRaw().single.dirty, isTrue);
    },
  );

  test(
    'an in-flight session edit is not acknowledged by an older upload',
    () async {
      final week = HiveService.getAllTrainingWeeksRaw().single;
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: '00000000-0000-4000-8000-000000000004',
          date: stamp,
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: week.id,
          exercises: [],
          updatedAt: stamp,
          dirty: true,
        ),
      );
      var edited = false;
      api.intercept = (r) async {
        if (!edited &&
            r.method == 'POST' &&
            r.url.path.endsWith('/workout_sessions')) {
          edited = true;
          final current = HiveService.getAllSessionsRaw().single;
          await HiveService.upsertSession(
            current.copyWith(durationSeconds: 99),
          );
        }
        return null;
      };
      await SyncService.instance.syncNow();
      expect(edited, isTrue);
      expect(HiveService.getAllSessionsRaw().single.durationSeconds, 99);
      expect(HiveService.getAllSessionsRaw().single.dirty, isTrue);
    },
  );

  Map<String, dynamic> remoteSession(
    String id, {
    String? sequence,
    String? weekId,
  }) {
    final week = HiveService.getAllTrainingWeeksRaw().first;
    final value = WorkoutSession(
      id: id,
      date: stamp,
      planName: 'Push',
      planId: planId,
      splitId: splitId,
      userId: owner,
      trainingWeekId: weekId ?? week.id,
      exercises: [],
      updatedAt: stamp,
    );
    return {
      'id': id,
      'user_id': owner,
      'split_id': splitId,
      'plan_id': planId,
      'training_week_id': value.trainingWeekId,
      'plan_name': 'Push',
      'week_number': week.number,
      'date': stamp.toIso8601String(),
      'updated_at': stamp.toIso8601String(),
      'deleted_at': null,
      'server_seq':
          sequence ?? stamp.add(const Duration(days: 2)).toIso8601String(),
      'data': value.toJson(),
    };
  }

  test(
    'pull paginates over equal timestamps without dropping duplicate-slot logs',
    () async {
      await SyncService.instance.syncNow();
      api.tables['workout_sessions'] = List.generate(
        1003,
        (i) => remoteSession(
          '10000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        ),
      );
      await SyncService.instance.syncNow();
      expect(HiveService.getAllSessionsRaw(), hasLength(1003));
      expect(
        api.requests.where(
          (r) =>
              r.url.path.endsWith('/workout_sessions') &&
              r.url.queryParameters.containsKey('or'),
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'manual full reconciliation repairs a late commit behind the cursor',
    () async {
      await SyncService.instance.syncNow();
      final frontier = remoteSession(
        'frontier',
        sequence: stamp.add(const Duration(days: 4)).toIso8601String(),
      );
      api.tables['workout_sessions'] = [frontier];
      await SyncService.instance.syncNow();
      api.tables['workout_sessions']!.add(
        remoteSession(
          'late',
          sequence: stamp.add(const Duration(days: 3)).toIso8601String(),
        ),
      );
      await SyncService.instance.syncNow();
      expect(HiveService.getSessionById('late'), isNull);
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(HiveService.getSessionById('late'), isNotNull);
    },
  );

  test(
    'failed relationship application keeps the cursor and retries the page',
    () async {
      await SyncService.instance.syncNow();
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString('sessions_last_pulled');
      api.tables['workout_sessions'] = [
        remoteSession('invalid', weekId: 'missing'),
      ];
      await SyncService.instance.syncNow();
      expect(prefs.getString('sessions_last_pulled'), before);
      expect(HiveService.getSessionById('invalid'), isNull);
      api.tables['workout_sessions'] = [remoteSession('invalid')];
      await SyncService.instance.syncNow();
      expect(HiveService.getSessionById('invalid'), isNotNull);
    },
  );

  test(
    'account switch during a response prevents writes into the next cache',
    () async {
      await SyncService.instance.syncNow();
      final started = Completer<void>();
      final response = Completer<void>();
      api.intercept = (r) async {
        if (r.method == 'GET' && r.url.path.endsWith('/splits')) {
          started.complete();
          await response.future;
          return http.Response(
            jsonEncode([
              {
                'id': 'stale-account-split',
                'user_id': owner,
                'name': 'Stale',
                'created_at': stamp.toIso8601String(),
                'updated_at': stamp.toIso8601String(),
                'server_seq': stamp.toIso8601String(),
              },
            ]),
            200,
          );
        }
        return null;
      };
      final cycle = SyncService.instance.syncNow();
      await started.future;
      api.userId = '00000000-0000-4000-8000-000000000099';
      await SupabaseService.auth.getSessionFromUrl(
        Uri.parse(
          'io.opengym.app://callback/#access_token=other&refresh_token=other&expires_in=3600&token_type=bearer&type=signup',
        ),
      );
      response.complete();
      await cycle;
      expect(HiveService.getSplitById('stale-account-split'), isNull);
    },
  );

  test(
    'a pulled append collision rebases a pending local week before normalization',
    () async {
      await SyncService.instance.syncNow();
      final block = HiveService.getAllTrainingBlocksRaw().single;
      final local = await TrainingBlockRepository(
        ownerId: () => owner,
      ).appendWeek(splitId, block.id);
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'local-draft',
          planId: planId,
          splitId: splitId,
          userId: owner,
          planName: 'Push',
          trainingWeekId: local.id,
          weekNumber: 2,
          date: stamp,
          exercises: [],
          isCompleted: false,
          startedAt: stamp,
          durationSeconds: 75,
          updatedAt: stamp,
          dirty: true,
        ),
      );
      api.tables['training_weeks']!.add({
        ...api.tables['training_weeks']!.first,
        'id': 'remote-append',
        'number': 2,
        'updated_at': stamp.toIso8601String(),
      });
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(HiveService.getTrainingWeekById(local.id)!.number, 3);
      expect(HiveService.getTrainingWeekById('remote-append')!.number, 2);
      final draft = HiveService.getSessionById('local-draft')!;
      expect(draft.trainingWeekId, local.id);
      expect(draft.weekNumber, 3);
      expect(draft.startedAt, stamp);
      expect(draft.durationSeconds, 75);
    },
  );

  test(
    'append collisions rebase the same week and snapshots with three total attempts',
    () async {
      await SyncService.instance.syncNow();
      final block = HiveService.getAllTrainingBlocksRaw().single;
      final week = await TrainingBlockRepository(
        ownerId: () => owner,
      ).appendWeek(splitId, block.id);
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'local-log',
          date: stamp,
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: week.id,
          weekNumber: 2,
          exercises: [],
          dirty: true,
          updatedAt: stamp,
        ),
      );
      var attempts = 0;
      api.intercept = (r) async {
        if (r.method == 'POST' &&
            r.url.path.endsWith('/training_weeks') &&
            (jsonDecode(r.body) as Map)['id'] == week.id) {
          attempts++;
          if (attempts < 3) {
            api.tables['training_weeks']!.add({
              ...api.tables['training_weeks']!.first,
              'id': 'competing-$attempts',
              'number': attempts + 1,
            });
            return http.Response(
              '{"code":"23505","message":"week conflict"}',
              409,
            );
          }
        }
        return null;
      };
      await SyncService.instance.syncNow();
      expect(attempts, 3);
      expect(
        HiveService.getAllTrainingWeeksRaw()
            .firstWhere((w) => w.id == week.id)
            .number,
        4,
      );
      expect(HiveService.getSessionById('local-log')!.trainingWeekId, week.id);
      expect(HiveService.getSessionById('local-log')!.weekNumber, 4);
    },
  );

  test(
    'append retry exhaustion retains dirty week and saved session',
    () async {
      await SyncService.instance.syncNow();
      final block = HiveService.getAllTrainingBlocksRaw().single;
      final week = await TrainingBlockRepository(
        ownerId: () => owner,
      ).appendWeek(splitId, block.id);
      var attempts = 0;
      api.intercept = (r) async {
        if (r.method == 'POST' && r.url.path.endsWith('/training_weeks')) {
          attempts++;
          return http.Response(
            '{"code":"23505","message":"week conflict"}',
            409,
          );
        }
        return null;
      };
      await SyncService.instance.syncNow();
      expect(attempts, 3);
      expect(
        HiveService.getAllTrainingWeeksRaw()
            .firstWhere((w) => w.id == week.id)
            .dirty,
        isTrue,
      );
      expect(SyncService.instance.status, SyncStatus.retryableError);
    },
  );

  test(
    'server bootstrap progress wins over a newer partial-replica bootstrap',
    () async {
      await SyncService.instance.syncNow();
      final block = HiveService.getAllTrainingBlocksRaw().single;
      final second = await TrainingBlockRepository(
        ownerId: () => owner,
      ).appendWeek(splitId, block.id);
      final progress = HiveService.getAllWorkoutProgressRaw().single;
      await HiveService.putWorkoutProgressRaw(
        progress.copyWith(
          activeWeekId: second.id,
          updatedAt: DateTime.utc(2030),
          dirty: true,
        ),
      );
      await SyncService.instance.syncNow();
      expect(
        HiveService.getAllWorkoutProgressRaw().single.activeWeekId,
        progress.activeWeekId,
      );
    },
  );

  test(
    'a remote week rebase updates dirty session snapshots without losing values',
    () async {
      await SyncService.instance.syncNow();
      final week = HiveService.getAllTrainingWeeksRaw().single;
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'dirty-log',
          date: stamp,
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: week.id,
          weekNumber: week.number,
          durationSeconds: 99,
          exercises: [],
          dirty: true,
          updatedAt: DateTime.utc(2030),
        ),
      );
      final server = api.tables['training_weeks']!.single;
      server['number'] = 2;
      server['updated_at'] = DateTime.utc(2031).toIso8601String();
      await SyncService.instance.syncNow();
      final saved = HiveService.getSessionById('dirty-log')!;
      expect(saved.weekNumber, 2);
      expect(saved.durationSeconds, 99);
      expect(api.tables['workout_sessions']!.single['week_number'], 2);
    },
  );

  test(
    'replacement releases a deleted split before retrying a full-capacity insert',
    () async {
      for (var i = 0; i < 4; i++) {
        await HiveService.putSplitRaw(
          Split(
            id: 'old-$i',
            name: 'Old $i',
            userId: owner,
            createdAt: stamp,
            updatedAt: stamp,
            dirty: true,
          ),
        );
      }
      await SyncService.instance.syncNow();
      final old = HiveService.getSplitById(splitId)!;
      final replacement = old.copyWith(
        id: 'replacement',
        name: 'Imported',
        dirty: true,
        updatedAt: DateTime.now(),
      );
      await HiveService.putSplitRaw(replacement);
      await HiveService.setActiveSplit(owner, replacement.id);
      for (final value in HiveService.getSplits().where(
        (s) => s.id != replacement.id,
      )) {
        await HiveService.putSplitRaw(
          value.copyWith(deletedAt: DateTime.now(), dirty: true),
        );
      }
      var rejected = false;
      api.intercept = (request) async {
        if (request.method == 'POST' &&
            request.url.pathSegments.last == 'splits') {
          final row = jsonDecode(request.body) as Map;
          if (row['id'] == replacement.id &&
              api.tables['splits']!
                      .where((r) => r['deleted_at'] == null)
                      .length >=
                  5) {
            rejected = true;
            return http.Response(
              '{"code":"23514","message":"A user can have at most 5 active splits"}',
              400,
            );
          }
        }
        return null;
      };
      await SyncService.instance.syncNow();
      expect(rejected, isTrue);
      expect(HiveService.getSplitById(replacement.id)!.dirty, isFalse);
      expect(
        api.tables['splits']!.singleWhere(
          (r) => r['id'] == splitId,
        )['deleted_at'],
        isNotNull,
      );
    },
  );

  test('pulled split tombstones win over newer local structure', () async {
    await SyncService.instance.syncNow();
    final server = api.tables['splits']!.single;
    server['deleted_at'] = stamp.add(const Duration(days: 2)).toIso8601String();
    server['updated_at'] = stamp.add(const Duration(days: 2)).toIso8601String();
    final block = HiveService.getAllTrainingBlocksRaw().single;
    await HiveService.putTrainingBlockRaw(
      block.copyWith(updatedAt: DateTime.utc(2030), dirty: true),
    );
    await SyncService.instance.syncNow();
    expect(HiveService.blocksForSplit(splitId), isEmpty);
    expect(
      HiveService.getAllTrainingWeeksRaw()
          .where((w) => w.splitId == splitId)
          .every((w) => w.deletedAt != null),
      isTrue,
    );
  });

  test(
    'newer split metadata cannot overwrite a renamed remote bootstrap block',
    () async {
      final localBlock = HiveService.getAllTrainingBlocksRaw().single;
      final localSplit = HiveService.getSplitById(splitId)!;
      await HiveService.putSplitRaw(
        localSplit.copyWith(
          name: 'Offline split edit',
          updatedAt: DateTime.utc(2030),
          dirty: true,
        ),
      );
      await HiveService.clearTrainingData();
      await TrainingBlockMigration().normalize(ownerId: owner);
      api.tables['splits'] = [
        {
          'id': splitId,
          'user_id': owner,
          'name': 'A',
          'created_at': stamp.toIso8601String(),
          'updated_at': stamp.toIso8601String(),
          'deleted_at': null,
          'server_seq': stamp.toIso8601String(),
        },
      ];
      api.tables['training_blocks'] = [
        {
          'id': localBlock.id,
          'user_id': owner,
          'split_id': splitId,
          'name': 'Renamed by device A',
          'position': 4,
          'created_at': stamp.toIso8601String(),
          'updated_at': stamp.add(const Duration(days: 1)).toIso8601String(),
          'deleted_at': null,
          'server_seq': stamp.toIso8601String(),
        },
      ];
      await SyncService.instance.syncNow();
      final saved = HiveService.getTrainingBlockById(localBlock.id)!;
      expect(saved.name, 'Renamed by device A');
      expect(saved.position, 4);
      expect(HiveService.getSplitById(splitId)!.name, 'Offline split edit');
    },
  );

  test(
    'bootstrap upload inserts only if absent when a remote edit races the first pull',
    () async {
      var raced = false;
      api.intercept = (r) async {
        if (!raced &&
            r.method == 'POST' &&
            r.url.path.endsWith('/training_blocks')) {
          raced = true;
          final incoming = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
          api.tables['training_blocks']!.add({
            ...incoming,
            'name': 'Remote race',
            'position': 3,
            'updated_at': stamp.toIso8601String(),
            'server_seq': stamp.toIso8601String(),
          });
        }
        return null;
      };
      await SyncService.instance.syncNow();
      expect(HiveService.getAllTrainingBlocksRaw().single.name, 'Remote race');
      final write = api.requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/training_blocks'),
      );
      expect(write.headers['Prefer'], contains('resolution=ignore-duplicates'));
    },
  );

  test(
    'an explicit local block edit keeps normal LWW after bootstrap',
    () async {
      final b = HiveService.getAllTrainingBlocksRaw().single;
      api.tables['training_blocks'] = [
        {
          'id': b.id,
          'user_id': owner,
          'split_id': splitId,
          'name': 'Older remote name',
          'position': 0,
          'created_at': stamp.toIso8601String(),
          'updated_at': stamp.toIso8601String(),
          'deleted_at': null,
          'server_seq': stamp.toIso8601String(),
        },
      ];
      await TrainingBlockRepository(
        ownerId: () => owner,
      ).renameBlock(splitId, b.id, 'Local edit');
      await SyncService.instance.syncNow();
      expect(HiveService.getTrainingBlockById(b.id)!.name, 'Local edit');
      expect(api.tables['training_blocks']!.single['name'], 'Local edit');
    },
  );

  test(
    'local split deletion syncs despite remote live children and old preference',
    () async {
      await SyncService.instance.syncNow();
      const replacement = '00000000-0000-4000-8000-000000000098';
      await HiveService.putSplitRaw(
        Split(
          id: replacement,
          name: 'Replacement',
          createdAt: stamp,
          updatedAt: stamp,
          userId: owner,
          dirty: true,
        ),
      );
      await HiveService.softDeleteSplit(
        userId: owner,
        splitId: splitId,
        replacementSplitId: replacement,
      );
      final deleted = HiveService.getSplitById(splitId)!.deletedAt!;
      for (final b in HiveService.getAllTrainingBlocksRaw().where(
        (b) => b.splitId == splitId,
      )) {
        await HiveService.putTrainingBlockRaw(
          b.copyWith(deletedAt: deleted, dirty: true),
        );
      }
      for (final w in HiveService.getAllTrainingWeeksRaw().where(
        (w) => w.splitId == splitId,
      )) {
        await HiveService.putTrainingWeekRaw(
          w.copyWith(deletedAt: deleted, dirty: true),
        );
      }
      for (final p in HiveService.getAllWorkoutProgressRaw().where(
        (p) => p.splitId == splitId,
      )) {
        await HiveService.putWorkoutProgressRaw(
          p.copyWith(deletedAt: deleted, dirty: true),
        );
      }
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(
        api.tables['splits']!.firstWhere(
          (r) => r['id'] == splitId,
        )['deleted_at'],
        isNotNull,
      );
      expect(
        api.tables['split_preferences']!.single['active_split_id'],
        replacement,
      );
      expect(HiveService.blocksForSplit(splitId), isEmpty);
    },
  );

  test(
    'sync replays a pending remote rebase before pulling or validating sessions',
    () async {
      await SyncService.instance.syncNow();
      final block = HiveService.getAllTrainingBlocksRaw().single;
      final week = await TrainingBlockRepository(
        ownerId: () => owner,
      ).appendWeek(splitId, block.id);
      await SyncService.instance.syncNow();
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'rebase-log',
          date: stamp,
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: week.id,
          weekNumber: 2,
          durationSeconds: 72,
          exercises: [],
          dirty: true,
          updatedAt: stamp,
        ),
      );
      final target = week.copyWith(
        number: 3,
        updatedAt: DateTime.utc(2030),
        dirty: false,
      );
      await Hive.box<dynamic>(
        HiveService.trainingOperationsBox,
      ).put('weekRebase', {
        'ownerId': owner,
        'previousNumber': 2,
        'week': target.toJson(),
        'dirty': false,
      });
      await HiveService.putTrainingWeekRaw(target);
      final remote = api.tables['training_weeks']!.firstWhere(
        (r) => r['id'] == week.id,
      );
      remote['number'] = 3;
      remote['updated_at'] = DateTime.utc(2030).toIso8601String();
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(HiveService.getSessionById('rebase-log')!.weekNumber, 3);
      expect(HiveService.getSessionById('rebase-log')!.durationSeconds, 72);
      expect(
        Hive.box<dynamic>(HiveService.trainingOperationsBox).get('weekRebase'),
        isNull,
      );
    },
  );

  for (final localDeleted in [true, false]) {
    test(
      'progress tombstone beats revision tie when localDeleted=$localDeleted',
      () async {
        await SyncService.instance.syncNow();
        final p = HiveService.getAllWorkoutProgressRaw().single;
        final time = DateTime.utc(2030);
        const low = '00000000-0000-4000-8000-000000000001';
        const high = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
        await HiveService.putWorkoutProgressRaw(
          p.copyWith(
            revision: localDeleted ? low : high,
            updatedAt: time,
            deletedAt: localDeleted ? time : null,
            dirty: false,
          ),
        );
        api.tables['workout_progress']![0] = {
          ...api.tables['workout_progress']!.single,
          'revision': localDeleted ? high : low,
          'updated_at': time.toIso8601String(),
          'deleted_at': localDeleted ? null : time.toIso8601String(),
        };
        await SyncService.instance.syncNow();
        expect(HiveService.getAllWorkoutProgressRaw().single.deletedAt, time);
      },
    );
  }

  test(
    'an incompatible API returns an explicit upgrade-required state',
    () async {
      api.intercept =
          (r) async => http.Response(
            '{"code":"PT426","message":"Upgrade required"}',
            426,
          );
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.upgradeRequired);
    },
  );

  List<String> writeOrder() =>
      api.requests
          .where((r) => r.method == 'POST')
          .map((r) => r.url.pathSegments.last)
          .toList();
  Iterable<http.Request> activations() => api.requests.where(
    (r) => r.url.path.endsWith('/rpc/activate_training_schema'),
  );
  Iterable<http.Request> restRequests() =>
      api.requests.where((r) => r.url.path.startsWith('/rest/'));
  Map<String, dynamic> serverBlock(String id) =>
      api.tables['training_blocks']!.singleWhere((r) => r['id'] == id);
  TrainingBlock localBlock(String id) => HiveService.getTrainingBlockById(id)!;
  final tServer = DateTime.utc(2026, 11, 16, 12);
  void serverDeletes(String blockId) {
    for (final row in [
      ...api.tables['training_blocks']!.where((r) => r['id'] == blockId),
      ...api.tables['training_weeks']!.where((r) => r['block_id'] == blockId),
    ]) {
      row['deleted_at'] = tServer.toIso8601String();
      row['updated_at'] = tServer.toIso8601String();
      row['server_seq'] = '2026-11-16T12:00:01.000Z';
    }
  }

  group('schema negotiation', () {
    test('an unmigrated server: header 4 is refused, 3 is used for everything '
        'after, and the clock column is never sent', () async {
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(activations().map((r) => r.headers['x-opengym-training-schema']), [
        '4',
        '3',
      ]);
      final afterNegotiation = restRequests().toList().sublist(2);
      expect(
        afterNegotiation.every(
          (r) => r.headers['x-opengym-training-schema'] == '3',
        ),
        isTrue,
      );
      final writes = writeOrder();
      expect(writes.first, 'activate_training_schema');
      expect(
        writes.indexOf('splits'),
        lessThan(writes.indexOf('training_blocks')),
      );
      expect(
        writes.indexOf('training_blocks'),
        lessThan(writes.indexOf('training_weeks')),
      );
      expect(
        writes.indexOf('training_weeks'),
        lessThan(writes.indexOf('workout_plans')),
      );
      expect(
        writes.indexOf('workout_plans'),
        lessThan(writes.indexOf('workout_progress')),
      );
      expect(HiveService.getAllWorkoutProgressRaw().single.dirty, isFalse);
      for (final row in api.tables['training_blocks']!) {
        expect(row.containsKey('planned_week_count_updated_at'), isFalse);
      }
      expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
      expect(SyncService.instance.blockLifecycleAvailable(null), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'training_schema_$owner',
        ),
        3,
      );
    });

    test(
      'a migrated server accepts 4 first and every request carries it',
      () async {
        api.serverSchema = 4;
        await SyncService.instance.syncNow();
        expect(SyncService.instance.status, SyncStatus.synced);
        expect(
          activations().map((r) => r.headers['x-opengym-training-schema']),
          ['4'],
        );
        expect(
          restRequests().every(
            (r) => r.headers['x-opengym-training-schema'] == '4',
          ),
          isTrue,
        );
        expect(api.accountSchema, 4);
        expect(
          api.tables['training_blocks']!.every(
            (r) => r.containsKey('planned_week_count_updated_at'),
          ),
          isTrue,
        );
        expect(SyncService.instance.blockLifecycleAvailable(owner), isTrue);
        expect(
          (await SharedPreferences.getInstance()).getInt(
            'training_schema_$owner',
          ),
          4,
        );
      },
    );

    test(
      'an account already at 4 keeps working and is fenced from header 3',
      () async {
        api.serverSchema = 4;
        api.accountSchema = 4;
        await SyncService.instance.syncNow();
        expect(SyncService.instance.status, SyncStatus.synced);
        expect(
          api.guard(
            http.Request('GET', Uri.parse('http://x/rest/v1/splits'))
              ..headers['x-opengym-training-schema'] = '3',
          ),
          isNotNull,
        );
      },
    );

    test(
      'a server migrated later turns the lifecycle on at the next sync',
      () async {
        await SyncService.instance.syncNow();
        expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
        api.serverSchema = 4;
        var notified = 0;
        final sub = SyncService.instance.changes.listen((_) => notified++);
        addTearDown(sub.cancel);
        await SyncService.instance.syncNow();
        await Future<void>.delayed(Duration.zero);
        expect(SyncService.instance.status, SyncStatus.synced);
        expect(SyncService.instance.blockLifecycleAvailable(owner), isTrue);
        expect(notified, greaterThan(0));
        // Its block rows now carry the clock.
        final created = await TrainingBlockRepository(
          ownerId: () => owner,
        ).createBlock(splitId: splitId, name: 'New', weekCount: 3);
        await SyncService.instance.syncNow();
        expect(
          serverBlock(created.id).containsKey('planned_week_count_updated_at'),
          isTrue,
        );
      },
    );

    test('an account that needs a newer app than this one still reports '
        'upgrade required, and uploads nothing', () async {
      api.serverSchema = 4;
      api.accountSchema = 5;
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.upgradeRequired);
      expect(activations().map((r) => r.headers['x-opengym-training-schema']), [
        '4',
        '3',
      ]);
      expect(
        writeOrder().where((w) => w != 'activate_training_schema'),
        isEmpty,
      );
      expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
    });

    test('a transport failure on header 4 does not fall back to 3', () async {
      api.intercept =
          (r) async =>
              r.url.path.endsWith('/rpc/activate_training_schema')
                  ? http.Response('{"message":"offline","code":"OFFLINE"}', 503)
                  : null;
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.retryableError);
      expect(activations(), hasLength(1));
    });

    test(
      'a remembered level answers before the first sync of a session',
      () async {
        SharedPreferences.setMockInitialValues({'training_schema_$owner': 4});
        expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
        await SyncService.instance.restoreNegotiatedSchemas();
        expect(SyncService.instance.blockLifecycleAvailable(owner), isTrue);
        expect(
          SyncService.instance.blockLifecycleAvailable('someone-else'),
          isFalse,
        );
      },
    );
  });

  group('block duration merge during sync', () {
    final c0 = DateTime.utc(2026, 3, 1);
    final c1 = DateTime.utc(2026, 4, 1);
    final c2 = DateTime.utc(2026, 5, 1);
    late TrainingBlockRepository repo;
    late TrainingBlock block;

    Future<void> migratedWithBlock({int count = 4}) async {
      api.serverSchema = 4;
      repo = TrainingBlockRepository(ownerId: () => owner);
      block = await repo.createBlock(
        splitId: splitId,
        name: 'Block',
        weekCount: count,
      );
      await HiveService.putTrainingBlockRaw(
        localBlock(block.id).copyWith(plannedWeekCountUpdatedAt: c0),
      );
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(serverBlock(block.id)['planned_week_count'], count);
      expect(
        DateTime.parse(
          serverBlock(block.id)['planned_week_count_updated_at'] as String,
        ),
        c0,
      );
    }

    void serverSets(
      int? count,
      DateTime? clock, {
      String? name,
      DateTime? updatedAt,
    }) {
      final row = serverBlock(block.id);
      row['planned_week_count'] = count;
      row['planned_week_count_updated_at'] = clock?.toIso8601String();
      if (name != null) row['name'] = name;
      if (updatedAt != null) row['updated_at'] = updatedAt.toIso8601String();
      row['server_seq'] = '2026-12-01T00:00:00.000Z';
    }

    test('a newer local rename keeps a remote extension, which wins the count '
        'by its clock', () async {
      await migratedWithBlock();
      await HiveService.putTrainingBlockRaw(
        localBlock(block.id).copyWith(
          name: 'Renamed',
          updatedAt: DateTime.utc(2026, 11, 1),
          dirty: true,
        ),
      );
      serverSets(6, c1, name: 'Remote', updatedAt: DateTime.utc(2026, 10, 1));
      await SyncService.instance.syncNow(fullReconciliation: true);
      final saved = localBlock(block.id);
      expect(saved.name, 'Renamed');
      expect(saved.plannedWeekCount, 6);
      expect(saved.plannedWeekCountUpdatedAt, c1);
      expect(serverBlock(block.id)['name'], 'Renamed');
      expect(serverBlock(block.id)['planned_week_count'], 6);
      expect(saved.dirty, isFalse);
    });

    test(
      'a newer remote rename keeps a local extension and uploads it',
      () async {
        await migratedWithBlock();
        await HiveService.putTrainingBlockRaw(
          localBlock(block.id).copyWith(
            plannedWeekCount: 6,
            plannedWeekCountUpdatedAt: c1,
            updatedAt: DateTime.utc(2026, 10, 1),
            dirty: true,
          ),
        );
        serverSets(4, c0, name: 'Remote', updatedAt: DateTime.utc(2026, 11, 1));
        await SyncService.instance.syncNow(fullReconciliation: true);
        final saved = localBlock(block.id);
        expect(saved.name, 'Remote');
        expect(saved.plannedWeekCount, 6);
        expect(saved.plannedWeekCountUpdatedAt, c1);
        expect(serverBlock(block.id)['planned_week_count'], 6);
        expect(saved.dirty, isFalse);
      },
    );

    test('a pulled shorten lowers a clean local count', () async {
      await migratedWithBlock(count: 6);
      serverSets(4, c2, updatedAt: DateTime.utc(2030));
      await SyncService.instance.syncNow(fullReconciliation: true);
      final saved = localBlock(block.id);
      expect(saved.plannedWeekCount, 4);
      expect(saved.plannedWeekCountUpdatedAt, c2);
      expect(saved.dirty, isFalse);
      expect(serverBlock(block.id)['planned_week_count'], 4);
    });

    test('a tie keeps the larger count on both sides', () async {
      await migratedWithBlock();
      await HiveService.putTrainingBlockRaw(
        localBlock(block.id).copyWith(
          plannedWeekCount: 6,
          plannedWeekCountUpdatedAt: c1,
          updatedAt: DateTime.utc(2026, 11, 1),
          dirty: true,
        ),
      );
      serverSets(4, c1, updatedAt: DateTime.utc(2026, 10, 1));
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(localBlock(block.id).plannedWeekCount, 6);
      expect(serverBlock(block.id)['planned_week_count'], 6);
      expect(localBlock(block.id).dirty, isFalse);
      // The other way round: the remote holds the larger tie.
      serverSets(8, c1, updatedAt: DateTime.utc(2026, 12, 1));
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(localBlock(block.id).plannedWeekCount, 8);
    });

    test(
      'a partly uploaded block (null remote count) keeps the local value',
      () async {
        await migratedWithBlock();
        serverSets(null, null, updatedAt: DateTime.utc(2030));
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(localBlock(block.id).plannedWeekCount, 4);
        expect(serverBlock(block.id)['planned_week_count'], 4);
      },
    );

    test('a replica ahead of a pulled shorten heals the count, keeps the '
        'clock, and both sides settle on the larger value', () async {
      await migratedWithBlock(count: 6);
      for (var n = 2; n <= 5; n++) {
        await repo.appendWeek(splitId, block.id);
      }
      // appendWeek keeps the count at 6 (it only grows), so allocate the
      // weeks and push them first.
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(repo.weeksForBlock(splitId, block.id), hasLength(5));
      serverSets(4, c2, updatedAt: DateTime.utc(2030));
      await SyncService.instance.syncNow(fullReconciliation: true);
      final saved = localBlock(block.id);
      expect(saved.plannedWeekCount, 5);
      expect(saved.plannedWeekCountUpdatedAt, c2);
      expect(serverBlock(block.id)['planned_week_count'], 5);
      expect(saved.dirty, isFalse);
      expect(
        DateTime.parse(
          serverBlock(block.id)['planned_week_count_updated_at'] as String,
        ),
        c2,
      );
    });

    test(
      'an unmigrated server is grow-only whatever the local clock says',
      () async {
        repo = TrainingBlockRepository(ownerId: () => owner);
        block = await repo.createBlock(
          splitId: splitId,
          name: 'Block',
          weekCount: 4,
        );
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
        // Another device (old app) extended it; this device stamped a clock.
        serverBlock(block.id)['planned_week_count'] = 7;
        serverBlock(block.id)['server_seq'] = '2026-12-01T00:00:00.000Z';
        expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNotNull);
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(localBlock(block.id).plannedWeekCount, 7);
        expect(serverBlock(block.id)['planned_week_count'], 7);
        expect(localBlock(block.id).dirty, isFalse);
      },
    );
  });

  group('a block deleted on another device', () {
    late TrainingBlockRepository repo;
    late TrainingBlock x;
    late TrainingBlock y;
    late TrainingWeek xWeek;

    Future<void> setUpBlocks() async {
      repo = TrainingBlockRepository(ownerId: () => owner);
      x = await repo.createBlock(splitId: splitId, name: 'X', weekCount: 4);
      y = await repo.createBlock(splitId: splitId, name: 'Y', weekCount: 3);
      await SyncService.instance.syncNow(fullReconciliation: true);
      xWeek = repo.weeksForBlock(splitId, x.id).single;
    }

    /// This replica, offline, moves the plan into X and logs a workout there.
    Future<void> useBlockXOffline() async {
      final progress = HiveService.getAllWorkoutProgressRaw().single;
      await HiveService.putWorkoutProgressRaw(
        progress.copyWith(
          activeWeekId: xWeek.id,
          availableWeekIds: [...?progress.availableWeekIds, xWeek.id],
          revision: 'moved-into-x',
          updatedAt: DateTime.utc(2026, 11, 10),
          dirty: true,
        ),
      );
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'logged-in-x',
          date: DateTime.utc(2026, 11, 10),
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: xWeek.id,
          weekNumber: 1,
          isCompleted: false,
          updatedAt: DateTime.utc(2026, 11, 10),
          dirty: true,
          exercises: [],
        ),
      );
    }

    for (final migrated in [true, false]) {
      test('work done offline in it is rescued into a successor and uploaded '
          'parents first (migrated: $migrated)', () async {
        api.serverSchema = migrated ? 4 : 3;
        await setUpBlocks();
        await useBlockXOffline();
        serverDeletes(x.id);
        api.requests.clear();
        await SyncService.instance.syncNow();
        expect(SyncService.instance.status, SyncStatus.synced);

        final successor = rescuedTrainingBlockId(x.id);
        final rescued = localBlock(successor);
        expect(rescued.deletedAt, isNull);
        expect(rescued.name, 'X');
        expect(rescued.plannedWeekCount, 4);
        expect(rescued.dirty, isFalse);
        expect(localBlock(x.id).deletedAt, isNotNull);
        final week =
            HiveService.getTrainingWeekById(
              lazyTrainingWeekId(splitId, successor, 1),
            )!;
        expect(week.deletedAt, isNull);
        expect(
          HiveService.getSessionById('logged-in-x')!.trainingWeekId,
          week.id,
        );
        expect(HiveService.getSessionById('logged-in-x')!.deletedAt, isNull);
        expect(
          HiveService.getAllWorkoutProgressRaw().single.activeWeekId,
          week.id,
        );
        expect(
          HiveService.readTrainingGraph(ownerId: owner).validate,
          returnsNormally,
        );

        // The server has the successor, its week, and the relinked work.
        expect(serverBlock(successor)['deleted_at'], isNull);
        expect(serverBlock(successor)['planned_week_count'], 4);
        final session = api.tables['workout_sessions']!.singleWhere(
          (r) => r['id'] == 'logged-in-x',
        );
        expect(session['training_week_id'], week.id);
        expect(
          api.tables['workout_progress']!.single['active_week_id'],
          week.id,
        );
        expect(serverBlock(x.id)['deleted_at'], isNotNull);

        final order = writeOrder();
        expect(
          order.indexOf('training_blocks'),
          lessThan(order.indexOf('training_weeks')),
        );
        expect(
          order.indexOf('training_weeks'),
          lessThan(order.indexOf('workout_sessions')),
        );
        expect(
          order.indexOf('workout_sessions'),
          lessThan(order.indexOf('workout_progress')),
        );

        // Nothing is left to do, and nothing else was lost.
        api.requests.clear();
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(
          writeOrder().where((w) => w != 'activate_training_schema'),
          isEmpty,
        );
        expect(HiveService.getSessionById('logged-in-x')!.deletedAt, isNull);
        expect(repo.blocksForSplit(splitId).map((b) => b.id), contains(y.id));
      });
    }

    test('a delete that lands between this replica\'s pull and push is retried '
        'and then rescued', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      await useBlockXOffline();
      var raced = false;
      api.intercept = (r) async {
        if (!raced &&
            r.method == 'POST' &&
            r.url.path.endsWith('/workout_progress')) {
          raced = true;
          serverDeletes(x.id);
          return http.Response(
            '{"code":"23514","message":"week is deleted"}',
            400,
          );
        }
        return null;
      };
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.retryableError);
      api.intercept = null;
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      final successor = rescuedTrainingBlockId(x.id);
      expect(localBlock(successor).deletedAt, isNull);
      expect(
        HiveService.getSessionById('logged-in-x')!.trainingWeekId,
        lazyTrainingWeekId(splitId, successor, 1),
      );
      expect(
        api.tables['workout_progress']!.single['active_week_id'],
        isNot(xWeek.id),
      );
    });

    test('a rename or extension made offline on a block with no work loses to '
        'the delete', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      await repo.renameBlock(splitId, x.id, 'Renamed offline');
      await repo.updateBlock(
        splitId: splitId,
        blockId: x.id,
        name: 'Renamed offline',
        weekCount: 9,
      );
      serverDeletes(x.id);
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(localBlock(x.id).deletedAt, isNotNull);
      expect(
        HiveService.getAllTrainingBlocksRaw().map((b) => b.id),
        isNot(contains(rescuedTrainingBlockId(x.id))),
      );
      expect(
        repo.blocksForSplit(splitId).map((b) => b.id),
        isNot(contains(x.id)),
      );
    });
  });

  group('deleting a block through the server', () {
    late TrainingBlockRepository repo;
    late TrainingBlock x;
    late TrainingWeek xWeek;

    Future<void> setUpBlocks({int schema = 4}) async {
      api.serverSchema = schema;
      repo = TrainingBlockRepository(ownerId: () => owner);
      x = await repo.createBlock(splitId: splitId, name: 'X', weekCount: 4);
      await repo.createBlock(splitId: splitId, name: 'Y', weekCount: 3);
      await SyncService.instance.syncNow(fullReconciliation: true);
      xWeek = repo.weeksForBlock(splitId, x.id).single;
    }

    String snapshot() => jsonEncode({
      'blocks':
          HiveService.getAllTrainingBlocksRaw().map((b) => b.toJson()).toList(),
      'weeks':
          HiveService.getAllTrainingWeeksRaw().map((w) => w.toJson()).toList(),
      'dirty': [
        ...HiveService.getAllTrainingBlocksRaw().map((b) => b.dirty),
        ...HiveService.getAllTrainingWeeksRaw().map((w) => w.dirty),
      ],
    });
    Iterable<http.Request> deleteCalls() => api.requests.where(
      (r) => r.url.path.endsWith('/rpc/delete_training_block'),
    );
    Matcher refused(TrainingBlockDeletionReason reason) =>
        isA<TrainingBlockDeletionException>().having(
          (e) => e.reason,
          'reason',
          reason,
        );

    test('success tombstones the block and its weeks, clean, with the '
        'server\'s stamp', () async {
      await setUpBlocks();
      api.requests.clear();
      await repo.deleteBlock(splitId: splitId, blockId: x.id);
      expect(jsonDecode(deleteCalls().single.body), {'target': x.id});
      expect(deleteCalls().single.headers['x-opengym-training-schema'], '4');
      final gone = localBlock(x.id);
      expect(gone.deletedAt, tServer);
      expect(gone.dirty, isFalse);
      expect(HiveService.getTrainingWeekById(xWeek.id)!.deletedAt, tServer);
      expect(HiveService.getTrainingWeekById(xWeek.id)!.dirty, isFalse);
      expect(serverBlock(x.id)['deleted_at'], isNotNull);
      expect(
        repo.blocksForSplit(splitId).map((b) => b.id),
        isNot(contains(x.id)),
      );
      expect(SyncService.instance.status, SyncStatus.synced);
      api.requests.clear();
      await SyncService.instance.syncNow();
      expect(
        writeOrder().where((w) => w != 'activate_training_schema'),
        isEmpty,
      );
    });

    test('is not offered against a server that has not reached schema 4, and '
        'sends nothing', () async {
      await setUpBlocks(schema: 3);
      expect(repo.lifecycleAvailable, isFalse);
      final before = snapshot();
      await expectLater(
        repo.deleteBlock(splitId: splitId, blockId: x.id),
        throwsA(refused(TrainingBlockDeletionReason.updateRequired)),
      );
      expect(deleteCalls(), isEmpty);
      expect(snapshot(), before);
    });

    test('a workout logged elsewhere is refused by the server as in use and '
        'nothing changes here', () async {
      await setUpBlocks();
      // Another device logged into X after this one last looked: the sessions
      // table (not pulled before the RPC check) has a live row.
      api.intercept = (r) async {
        if (r.url.path.endsWith('/rpc/delete_training_block')) {
          api.tables['workout_sessions'] = [
            {
              'id': 'elsewhere',
              'user_id': owner,
              'training_week_id': xWeek.id,
              'deleted_at': null,
            },
          ];
        }
        return null;
      };
      final before = snapshot();
      await expectLater(
        repo.deleteBlock(splitId: splitId, blockId: x.id),
        throwsA(refused(TrainingBlockDeletionReason.inUse)),
      );
      expect(snapshot(), before);
      expect(serverBlock(x.id)['deleted_at'], isNull);
    });

    for (final entry
        in {
          'last_block': TrainingBlockDeletionReason.lastBlock,
          'split_deleted': TrainingBlockDeletionReason.splitDeleted,
          'in_use': TrainingBlockDeletionReason.inUse,
          'something_new': TrainingBlockDeletionReason.inUse,
        }.entries) {
      test('PT409 ${entry.key} maps to ${entry.value.name} and leaves local '
          'data untouched', () async {
        await setUpBlocks();
        api.intercept =
            (r) async =>
                r.url.path.endsWith('/rpc/delete_training_block')
                    ? api.failure(409, 'PT409', 'refused', entry.key)
                    : null;
        final before = snapshot();
        await expectLater(
          repo.deleteBlock(splitId: splitId, blockId: x.id),
          throwsA(refused(entry.value)),
        );
        expect(snapshot(), before);
      });
    }

    test('PT426 from the procedure means update required', () async {
      await setUpBlocks();
      api.intercept =
          (r) async =>
              r.url.path.endsWith('/rpc/delete_training_block')
                  ? api.failure(426, 'PT426', 'Update OpenGym')
                  : null;
      final before = snapshot();
      await expectLater(
        repo.deleteBlock(splitId: splitId, blockId: x.id),
        throwsA(refused(TrainingBlockDeletionReason.updateRequired)),
      );
      expect(snapshot(), before);
    });

    test(
      'this device\'s own workouts are refused before the server is asked',
      () async {
        await setUpBlocks();
        await HiveService.putSessionRaw(
          WorkoutSession(
            id: 'mine',
            date: stamp,
            planName: 'Push',
            planId: planId,
            splitId: splitId,
            userId: owner,
            trainingWeekId: xWeek.id,
            weekNumber: 1,
            exercises: [],
            updatedAt: stamp,
            dirty: false,
          ),
        );
        api.requests.clear();
        await expectLater(
          repo.deleteBlock(splitId: splitId, blockId: x.id),
          throwsA(
            isA<TrainingBlockDeletionException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  TrainingBlockDeletionReason.inUse,
                )
                .having(
                  (e) => e.blocker,
                  'blocker',
                  BlockDeletionBlocker.hasWorkouts,
                ),
          ),
        );
        expect(deleteCalls(), isEmpty);
      },
    );

    test('a block the server never received is tombstoned locally and the '
        'tombstone uploads as an insert, blocks before weeks', () async {
      api.serverSchema = 4;
      await SyncService.instance.syncNow(fullReconciliation: true);
      repo = TrainingBlockRepository(ownerId: () => owner);
      // The first upload of the new block fails, so the server never has it.
      api.intercept =
          (r) async =>
              r.method == 'POST' && r.url.path.endsWith('/training_blocks')
                  ? http.Response('{"message":"offline","code":"OFFLINE"}', 503)
                  : null;
      final lonely = await repo.createBlock(
        splitId: splitId,
        name: 'Lonely',
        weekCount: 3,
      );
      await repo.appendWeek(splitId, lonely.id);
      await repo.createBlock(splitId: splitId, name: 'Other', weekCount: 3);
      await repo.deleteBlock(splitId: splitId, blockId: lonely.id);
      expect(
        api.tables['training_blocks']!.any((r) => r['id'] == lonely.id),
        isFalse,
      );
      expect(localBlock(lonely.id).deletedAt, isNotNull);
      expect(localBlock(lonely.id).dirty, isTrue);
      final weeks = HiveService.getAllTrainingWeeksRaw().where(
        (w) => w.blockId == lonely.id,
      );
      expect(weeks, hasLength(2));
      expect(
        weeks.every((w) => w.deletedAt != null && w.dirty == true),
        isTrue,
      );
      api.intercept = null;
      api.requests.clear();
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(serverBlock(lonely.id)['deleted_at'], isNotNull);
      expect(
        api.tables['training_weeks']!
            .where((r) => r['block_id'] == lonely.id)
            .every((r) => r['deleted_at'] != null),
        isTrue,
      );
      final order = writeOrder();
      expect(
        order.indexOf('training_blocks'),
        lessThan(order.indexOf('training_weeks')),
      );
    });

    test(
      'drains pending structural intents under the gate before checking',
      () async {
        await setUpBlocks();
        final pending = TrainingBlock(
          id: 'pending',
          splitId: splitId,
          name: 'Pending',
          position: 9,
          createdAt: stamp,
          plannedWeekCount: 2,
          userId: owner,
        );
        final pendingWeek = TrainingWeek(
          id: 'pending-week',
          splitId: splitId,
          blockId: 'pending',
          number: 1,
          createdAt: stamp,
          userId: owner,
        );
        await Hive.box<dynamic>(HiveService.trainingOperationsBox).put(
          'create',
          {
            'ownerId': owner,
            'block': pending.toJson(),
            'weeks': [pendingWeek.toJson()],
          },
        );
        await repo.deleteBlock(splitId: splitId, blockId: x.id);
        expect(localBlock('pending').deletedAt, isNull);
        expect(
          Hive.box<dynamic>(HiveService.trainingOperationsBox).isEmpty,
          isTrue,
        );
      },
    );

    test('a delete requested while a sync is in flight waits for it and '
        'does not deadlock', () async {
      await setUpBlocks();
      final release = Completer<void>();
      var held = false;
      api.intercept = (r) async {
        if (!held && r.method == 'GET' && r.url.path.endsWith('/splits')) {
          held = true;
          await release.future;
        }
        return null;
      };
      final inFlight = SyncService.instance.syncNow(fullReconciliation: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(held, isTrue);
      final deletion = repo.deleteBlock(splitId: splitId, blockId: x.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(deleteCalls(), isEmpty, reason: 'it waits for the sync');
      release.complete();
      await Future.wait([
        inFlight,
        deletion,
      ]).timeout(const Duration(seconds: 20));
      expect(localBlock(x.id).deletedAt, isNotNull);
      expect(localBlock(x.id).dirty, isFalse);
    });

    test('a local mutation running when a delete starts is not interleaved '
        'with it', () async {
      await setUpBlocks();
      final order = <String>[];
      final gate = Completer<void>();
      final mutation = SyncService.instance.runExclusiveLocalMutation(() async {
        order.add('mutation start');
        await gate.future;
        order.add('mutation end');
      });
      final deletion = repo
          .deleteBlock(splitId: splitId, blockId: x.id)
          .then((_) => order.add('delete'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.complete();
      await Future.wait([
        mutation,
        deletion,
      ]).timeout(const Duration(seconds: 20));
      expect(order, ['mutation start', 'mutation end', 'delete']);
    });
  });
}
