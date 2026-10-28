import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
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
    if (request.url.path.contains('/rpc/')) return http.Response('1', 200);
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
        rows.removeWhere((r) => r[key] == row[key]);
        row['server_seq'] =
            stamp.add(const Duration(days: 1)).toIso8601String();
        rows.add(row);
        saved.add(row);
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
    'negotiates capability before graph uploads and sends the installed SDK header',
    () async {
      await SyncService.instance.syncNow();
      final rest =
          api.requests.where((r) => r.url.path.startsWith('/rest/')).toList();
      expect(
        rest.every((r) => r.headers['x-opengym-training-schema'] == '1'),
        isTrue,
      );
      final writes =
          rest
              .where((r) => r.method == 'POST')
              .map((r) => r.url.pathSegments.last)
              .toList();
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
}
