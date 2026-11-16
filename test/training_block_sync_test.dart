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
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/services/training_block_graph.dart';
import 'package:gymapp/services/training_block_lifecycle.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/training_block_restore.dart';
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

  /// What `now()` is inside the server's procedures.
  DateTime Function() serverNow = () => DateTime.utc(2026, 11, 16, 12);

  DateTime? ts(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
  Map<String, dynamic>? byId(String table, Object? id) =>
      (tables[table] ?? const <Map<String, dynamic>>[])
          .where((r) => r['id'] == id)
          .firstOrNull;

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
    final mine =
        weeks
            .where((w) => w['block_id'] == target && w['user_id'] == userId)
            .toList();
    if (found['deleted_at'] == null) {
      final split = (tables['splits'] ?? []).where(
        (r) => r['id'] == found['split_id'] && r['user_id'] == userId,
      );
      if (split.any((r) => r['deleted_at'] != null)) {
        return failure(409, 'PT409', 'unavailable', 'split_deleted');
      }
      if (!blocks.any(
        (b) =>
            b['split_id'] == found['split_id'] &&
            b['user_id'] == userId &&
            b['deleted_at'] == null &&
            b['id'] != target,
      )) {
        return failure(409, 'PT409', 'keeps one block', 'last_block');
      }
      final ids = mine.map((w) => w['id']).toSet();
      final used =
          (tables['workout_sessions'] ?? []).any(
            (r) =>
                r['user_id'] == userId &&
                r['deleted_at'] == null &&
                ids.contains(r['training_week_id']),
          ) ||
          (tables['workout_progress'] ?? []).any(
            (r) =>
                r['user_id'] == userId &&
                r['deleted_at'] == null &&
                ids.contains(r['active_week_id']),
          );
      if (used) return failure(409, 'PT409', 'in use', 'in_use');
      // deleted_at = stamp, updated_at = greatest(updated_at, stamp)
      final stamp = serverNow();
      for (final row in [
        found,
        ...mine.where((w) => w['deleted_at'] == null),
      ]) {
        final before = ts(row['updated_at']);
        row['deleted_at'] = stamp.toIso8601String();
        row['updated_at'] =
            (before != null && before.isAfter(stamp) ? before : stamp)
                .toIso8601String();
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

  /// `keep_newest_row` for blocks: the duration resolves on its own clock at
  /// schema 4 and by the larger count before it. Returns the row to store.
  /// An omitted clock column is the stored clock, so it ties. `kept` says the
  /// stored row won; the row returned is then a copy of it carrying the merged
  /// duration the real trigger writes onto it, so the caller must compare it
  /// with the stored row to know whether anything changed.
  ({Map<String, dynamic> row, bool kept}) mergeBlock(
    Map<String, dynamic> old,
    Map<String, dynamic> incoming,
  ) {
    final row = Map<String, dynamic>.from(incoming);
    // The tombstone is sticky and returns before the duration is merged.
    if (old['deleted_at'] != null && row['deleted_at'] == null) {
      return (row: old, kept: true);
    }
    final oldCount = old['planned_week_count'] as int?;
    final newCount = row['planned_week_count'] as int?;
    if (serverSchema >= 4) {
      if (!row.containsKey('planned_week_count_updated_at')) {
        row['planned_week_count_updated_at'] =
            old['planned_week_count_updated_at'];
      }
      final past = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      DateTime clock(Map<String, dynamic> r) =>
          ts(r['planned_week_count_updated_at']) ??
          past.subtract(const Duration(days: 365000));
      if (newCount == null ||
          (oldCount != null && clock(old).isAfter(clock(row)))) {
        row['planned_week_count'] = oldCount;
        row['planned_week_count_updated_at'] =
            old['planned_week_count_updated_at'];
      } else if (oldCount != null && clock(old) == clock(row)) {
        row['planned_week_count'] = oldCount > newCount ? oldCount : newCount;
      }
    } else {
      // greatest() ignores nulls.
      row['planned_week_count'] =
          oldCount == null
              ? newCount
              : newCount == null
              ? oldCount
              : (oldCount > newCount ? oldCount : newCount);
    }
    final kept =
        !(old['deleted_at'] == null && row['deleted_at'] != null) &&
        ts(row['updated_at'])!.isBefore(ts(old['updated_at'])!);
    final result = kept ? Map<String, dynamic>.from(old) : row;
    // The stored row carries the merged duration too when it is the row kept.
    result['planned_week_count'] = row['planned_week_count'];
    if (serverSchema >= 4) {
      result['planned_week_count_updated_at'] =
          row['planned_week_count_updated_at'];
    }
    return (row: result, kept: kept);
  }

  /// `keep_newest_row` for every other table: a stored tombstone is sticky, a
  /// tombstone wins over a live row, then the newer `updated_at` wins and
  /// progress adds its revision rules. Returns the row to store, which is
  /// [old] itself when the incoming write loses.
  ({Map<String, dynamic> row, bool kept}) keepNewest(
    String table,
    Map<String, dynamic> old,
    Map<String, dynamic> row,
  ) {
    if (table == 'split_preferences') {
      final loses = ts(row['updated_at'])!.isBefore(ts(old['updated_at'])!);
      return (row: loses ? old : row, kept: loses);
    }
    if (old['deleted_at'] != null && row['deleted_at'] == null) {
      return (row: old, kept: true);
    }
    if (old['deleted_at'] == null && row['deleted_at'] != null) {
      return (row: row, kept: false);
    }
    if (ts(row['updated_at'])!.isBefore(ts(old['updated_at'])!)) {
      return (row: old, kept: true);
    }
    if (table == 'workout_progress') {
      Map<String, dynamic> without(Map<String, dynamic> r) => {
        for (final e in r.entries)
          if (e.key != 'available_week_ids' && e.key != 'server_seq')
            e.key: e.value,
      };
      if (old['available_week_ids'] == null &&
          row['available_week_ids'] != null &&
          jsonEncode(without(row)) == jsonEncode(without(old))) {
        return (row: row, kept: false);
      }
      if (row['revision'] ==
          initialProgressRevision(
            row['split_id'] as String,
            row['plan_id'] as String,
          )) {
        return (row: old, kept: true);
      }
      if (ts(row['updated_at']) == ts(old['updated_at']) &&
          (row['revision'] as String).compareTo(old['revision'] as String) <
              0) {
        return (row: old, kept: true);
      }
    }
    return (row: row, kept: false);
  }

  /// A rejected write the way PostgREST reports a raised check_violation.
  http.Response checkViolation(String message) =>
      failure(400, '23514', message);

  /// `check_training_parent`: live children cannot sit under deleted parents,
  /// and every parent must exist and belong to the same account and split.
  String? parentViolation(String table, Map<String, dynamic> row) {
    if (table != 'training_blocks' &&
        table != 'training_weeks' &&
        table != 'workout_progress') {
      return null;
    }
    final live = row['deleted_at'] == null;
    final split = byId('splits', row['split_id']);
    if (split == null ||
        split['user_id'] != row['user_id'] ||
        (live && split['deleted_at'] != null)) {
      return 'Training split is unavailable';
    }
    if (table == 'training_weeks') {
      final block = byId('training_blocks', row['block_id']);
      if (block == null ||
          block['user_id'] != row['user_id'] ||
          block['split_id'] != row['split_id'] ||
          (live && block['deleted_at'] != null)) {
        return 'Training block is unavailable';
      }
    } else if (table == 'workout_progress') {
      final plan = byId('workout_plans', row['plan_id']);
      if (plan == null ||
          plan['user_id'] != row['user_id'] ||
          plan['split_id'] != row['split_id'] ||
          (live && plan['deleted_at'] != null)) {
        return 'Progress plan is unavailable';
      }
      final week = byId('training_weeks', row['active_week_id']);
      if (week == null ||
          week['user_id'] != row['user_id'] ||
          week['split_id'] != row['split_id'] ||
          (live && week['deleted_at'] != null)) {
        return 'Progress week is unavailable';
      }
    }
    return null;
  }

  /// `check_available_weeks`.
  String? availableViolation(Map<String, dynamic> row) {
    final ids = (row['available_week_ids'] as List?)?.cast<String?>();
    if (ids == null) return null;
    if (ids.contains(null) ||
        ids.length != ids.toSet().length ||
        !ids.contains(row['active_week_id'])) {
      return 'Invalid available training weeks';
    }
    for (final id in ids) {
      final week = byId('training_weeks', id);
      if (week == null ||
          week['split_id'] != row['split_id'] ||
          week['user_id'] != row['user_id']) {
        return 'Available weeks belong to another split or account';
      }
    }
    return null;
  }

  /// `link_session`, as amended: a tombstone is pinned to the stored link; when
  /// a live session moves out of a tombstoned week its incoming completion
  /// evidence replaces the stored one, but only if it is the stored evidence
  /// pointed at the new week; in every other update the stored evidence is
  /// kept. [storedForInsert] is the stored row the BEFORE INSERT pass looks up
  /// by id. Returns the row to store, or the reason it is rejected.
  (Map<String, dynamic>?, String?) linkSession(
    Map<String, dynamic>? old,
    Map<String, dynamic> row, {
    Map<String, dynamic>? storedForInsert,
  }) {
    if (accountSchema == null) return (row, null);
    String bad(String message) => message;
    row = Map<String, dynamic>.from(row);
    // A tombstone never moves a session: when a stored row already has a link
    // and the tombstone names another week (in the column or in its data), it
    // is pinned to the stored link, week number and evidence, in the BEFORE
    // INSERT pass of an upsert too, which looks the stored row up by id.
    final stored = old ?? storedForInsert;
    if (stored != null &&
        row['deleted_at'] != null &&
        stored['training_week_id'] != null) {
      final incomingData = row['data'] as Map;
      if (row['training_week_id'] != stored['training_week_id'] ||
          (incomingData['trainingWeekId'] != null &&
              incomingData['trainingWeekId'] != stored['training_week_id'])) {
        final storedData = stored['data'] as Map;
        final pinned = Map<String, dynamic>.from(incomingData);
        row['training_week_id'] = stored['training_week_id'];
        row['week_number'] = stored['week_number'];
        pinned['trainingWeekId'] = stored['training_week_id'];
        pinned['weekNumber'] = stored['week_number'];
        if (!storedData.containsKey('completionTransition')) {
          pinned.remove('completionTransition');
        } else {
          pinned['completionTransition'] = storedData['completionTransition'];
        }
        row['data'] = pinned;
      }
    }
    if ((row['week_number'] as int) < 1) {
      return (null, bad('Invalid legacy training week'));
    }
    final data = Map<String, dynamic>.from(row['data'] as Map);
    if ((data['trainingSchemaVersion'] ?? '1').toString() != '1') {
      return (null, bad('Unsupported training schema version'));
    }
    if (data['splitId'] != null && data['splitId'] != row['split_id']) {
      return (null, bad('Conflicting session split'));
    }
    if (data['planId'] != null && data['planId'] != row['plan_id']) {
      return (null, bad('Conflicting session plan'));
    }
    if (data['trainingWeekId'] != null) {
      if (row['training_week_id'] != null &&
          row['training_week_id'] != data['trainingWeekId']) {
        return (null, bad('Conflicting session week'));
      }
      row['training_week_id'] = data['trainingWeekId'];
    }
    final parent = byId('training_weeks', row['training_week_id']);
    if (parent == null) return (null, bad('No data found'));
    if (parent['user_id'] != row['user_id'] ||
        parent['split_id'] != row['split_id'] ||
        parent['number'] != row['week_number'] ||
        (row['deleted_at'] == null && parent['deleted_at'] != null)) {
      return (null, bad('Conflicting or deleted session week'));
    }
    if (row['plan_id'] != null) {
      final plan = byId('workout_plans', row['plan_id']);
      if (plan != null &&
          (plan['user_id'] != row['user_id'] ||
              plan['split_id'] != row['split_id'])) {
        return (null, bad('Conflicting session plan owner or split'));
      }
    }
    data['trainingSchemaVersion'] = 1;
    data['trainingWeekId'] = row['training_week_id'];
    data['splitId'] = row['split_id'];
    data['planId'] = row['plan_id'];
    if (old != null) {
      final oldData = old['data'] as Map?;
      final oldEvidence = oldData?['completionTransition'];
      final movedOutOfDeletedWeek =
          old['training_week_id'] != row['training_week_id'] &&
          byId('training_weeks', old['training_week_id'])?['deleted_at'] !=
              null;
      if (oldEvidence != null) {
        if (movedOutOfDeletedWeek && oldEvidence is Map) {
          // A rescue: the incoming evidence is kept, but only when it is the
          // stored evidence pointed at the new week.
          Object? weekless(Object? e) =>
              e is! Map
                  ? null
                  : jsonEncode(
                    Map.fromEntries(
                      e.entries
                          .where(
                            (x) =>
                                x.key != 'sourceWeekId' &&
                                x.key != 'nextWeekId',
                          )
                          .toList()
                        ..sort((a, b) => '${a.key}'.compareTo('${b.key}')),
                    ),
                  );
          final incoming = data['completionTransition'];
          if (incoming is! Map || weekless(incoming) != weekless(oldEvidence)) {
            return (null, bad('Invalid completion evidence'));
          }
        } else {
          data['completionTransition'] = oldEvidence;
        }
      }
    }
    final evidence = data['completionTransition'];
    if (evidence != null) {
      if (evidence is! Map ||
          evidence['sourceWeekId'] != row['training_week_id'] ||
          evidence['resultRevision'] != row['id'] ||
          evidence['expectedRevision'] == null ||
          evidence['committedAt'] == null ||
          (data['isCompleted'] ?? true) != true) {
        return (null, bad('Invalid completion evidence'));
      }
      if (evidence['nextWeekId'] != null) {
        final target = byId('training_weeks', evidence['nextWeekId']);
        if (target == null) return (null, bad('No data found'));
        if (target['block_id'] != parent['block_id'] ||
            target['split_id'] != parent['split_id'] ||
            target['id'] == parent['id']) {
          return (null, bad('Invalid completion target'));
        }
      }
    }
    return ({...row, 'data': data}, null);
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
        if (table == 'training_blocks' &&
            serverSchema < 4 &&
            row.containsKey('planned_week_count_updated_at')) {
          return failure(
            400,
            'PGRST204',
            "Could not find the 'planned_week_count_updated_at' column",
          );
        }
        final old = rows.where((r) => r[key] == row[key]).firstOrNull;
        // BEFORE INSERT: the incoming row is validated first, even when it
        // then loses last-write-wins or hits a conflict.
        var incoming = row;
        if (table == 'workout_sessions') {
          final (linked, reason) = linkSession(null, row, storedForInsert: old);
          if (reason != null) return checkViolation(reason);
          incoming = linked!;
        }
        final insertViolation =
            parentViolation(table, incoming) ??
            (table == 'workout_progress' ? availableViolation(incoming) : null);
        if (insertViolation != null) return checkViolation(insertViolation);
        if ((request.headers['Prefer'] ?? '').contains(
              'resolution=ignore-duplicates',
            ) &&
            old != null) {
          continue;
        }
        var stored = incoming;
        var changed = true;
        if (old != null) {
          // BEFORE UPDATE: a_training_lww first. A write which loses is a
          // silent no-op, and the parents are not checked again unless the
          // trigger's merged duration changed the stored row.
          // exercise_definitions has no such trigger and is overwritten.
          final result =
              table == 'training_blocks'
                  ? mergeBlock(old, incoming)
                  : table == 'exercise_definitions'
                  ? (row: incoming, kept: false)
                  : keepNewest(table, old, incoming);
          stored = result.row;
          changed = !result.kept || jsonEncode(stored) != jsonEncode(old);
          if (!changed) {
            saved.add(stored);
            continue;
          }
          // b_link_training_week, b_training_parent, c_available_weeks.
          if (table == 'workout_sessions') {
            final (linked, reason) = linkSession(old, stored);
            if (reason != null) return checkViolation(reason);
            stored = linked!;
          }
          final violation =
              parentViolation(table, stored) ??
              (table == 'workout_progress' ? availableViolation(stored) : null);
          if (violation != null) return checkViolation(violation);
        }
        stored = Map<String, dynamic>.from(stored);
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
        // Another device (old app) extended it.
        serverBlock(block.id)['planned_week_count'] = 7;
        serverBlock(block.id)['server_seq'] = '2026-12-01T00:00:00.000Z';
        // No clock exists below schema 4: it could only wait to beat a
        // clock-less write later.
        expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNull);
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

    WorkoutSession completedInX(
      String id,
      TrainingWeek from,
      TrainingWeek to,
    ) => WorkoutSession(
      id: id,
      date: DateTime.utc(2026, 11, 9),
      planName: 'Push',
      planId: planId,
      splitId: splitId,
      userId: owner,
      trainingWeekId: from.id,
      weekNumber: from.number,
      isCompleted: true,
      completionTransition: {
        'expectedRevision': '00000000-0000-4000-8000-0000000000e1',
        'sourceWeekId': from.id,
        'nextWeekId': to.id,
        'resultRevision': id,
        'committedAt': DateTime.utc(2026, 11, 9).toIso8601String(),
      },
      updatedAt: DateTime.utc(2026, 11, 9),
      dirty: true,
      exercises: [],
    );

    Map<String, dynamic> serverRow(String table, String id) =>
        api.tables[table]!.singleWhere((r) => r['id'] == id);

    test('F1: a session the server already holds live in the deleted block is '
        'relinked with its evidence and accepted, keeping its time', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      final week2 = await repo.appendWeek(splitId, x.id);
      const id = '00000000-0000-4000-8000-0000000000a1';
      await HiveService.putSessionRaw(completedInX(id, xWeek, week2));
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      final before = serverRow('workout_sessions', id)['updated_at'];
      // A restore elsewhere tombstoned the block and its weeks without
      // touching this session, which stays live on the server.
      serverDeletes(x.id);
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      final successor = rescuedTrainingBlockId(x.id);
      final to1 = lazyTrainingWeekId(splitId, successor, 1);
      final to2 = lazyTrainingWeekId(splitId, successor, 2);
      final row = serverRow('workout_sessions', id);
      expect(row['deleted_at'], isNull);
      expect(row['training_week_id'], to1);
      expect(row['updated_at'], before);
      final evidence = (row['data'] as Map)['completionTransition'] as Map;
      expect(evidence['sourceWeekId'], to1);
      expect(evidence['nextWeekId'], to2);
      expect(evidence['resultRevision'], id);
      expect(HiveService.getSessionById(id)!.dirty, isFalse);
      expect(HiveService.getSessionById(id)!.trainingWeekId, to1);
    });

    test('F1: a rescued progress row wins against the stored row it would '
        'otherwise lose to', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      const low = '00000000-0000-4000-8000-000000000001';
      const high = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
      final progress = HiveService.getAllWorkoutProgressRaw().single;
      await HiveService.putWorkoutProgressRaw(
        progress.copyWith(
          activeWeekId: xWeek.id,
          availableWeekIds: [...?progress.availableWeekIds, xWeek.id],
          revision: low,
          updatedAt: DateTime.utc(2026, 11, 10),
          dirty: true,
        ),
      );
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      // Another device wrote the same instant with a higher revision; this one
      // never sees it, because the block is deleted before the next pull.
      final stored = api.tables['workout_progress']!.single;
      stored['revision'] = high;
      stored['server_seq'] = '2026-12-01T00:00:00.000Z';
      serverDeletes(x.id);
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      final week = lazyTrainingWeekId(splitId, rescuedTrainingBlockId(x.id), 1);
      final row = api.tables['workout_progress']!.single;
      expect(row['active_week_id'], week);
      expect(row['revision'], isNot(high));
      expect(row['revision'], isNot(low));
      expect(HiveService.getAllWorkoutProgressRaw().single.dirty, isFalse);
      // Every replica derives the same values, so a second one agrees.
      api.requests.clear();
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(
        writeOrder().where((w) => w != 'activate_training_schema'),
        isEmpty,
      );
    });

    // --- Two replicas ----------------------------------------------------
    // The test owns one Hive store and one preferences store, so a replica is
    // a snapshot of both which is loaded before it syncs.
    Future<({TrainingBlockGraph graph, Map<String, Object> prefs})>
    snapshotDevice() async {
      final prefs = await SharedPreferences.getInstance();
      return (
        graph: TrainingBlockGraph.fromJson(
          HiveService.readTrainingGraph(ownerId: owner).toJson(),
        ),
        prefs: {for (final k in prefs.getKeys()) k: prefs.get(k)!},
      );
    }

    Future<void> loadDevice(
      ({TrainingBlockGraph graph, Map<String, Object> prefs}) device, {
      List<WorkoutProgress>? progress,
      List<WorkoutSession>? sessions,
    }) async {
      await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
      await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
      await Hive.box<TrainingBlock>(HiveService.trainingBlocksBox).clear();
      await Hive.box<TrainingWeek>(HiveService.trainingWeeksBox).clear();
      await Hive.box<WorkoutProgress>(HiveService.workoutProgressBox).clear();
      await Hive.box<Split>(HiveService.splitsBox).clear();
      final g = TrainingBlockGraph.fromJson(device.graph.toJson());
      for (final r in g.splits) {
        await HiveService.putSplitRaw(r);
      }
      for (final r in g.plans) {
        await HiveService.putPlanRaw(r);
      }
      for (final r in g.blocks) {
        await HiveService.putTrainingBlockRaw(r);
      }
      for (final r in g.weeks) {
        await HiveService.putTrainingWeekRaw(r);
      }
      for (final r in sessions ?? g.sessions) {
        await HiveService.putSessionRaw(r);
      }
      for (final r in progress ?? g.progress) {
        await HiveService.putWorkoutProgressRaw(r);
      }
      await HiveService.flushAllWorkoutData();
      SharedPreferences.setMockInitialValues(Map.of(device.prefs));
    }

    Future<void> cycles(int n) async {
      for (var i = 0; i < n; i++) {
        await SyncService.instance.syncNow();
        expect(SyncService.instance.status, isNot(SyncStatus.retryableError));
      }
    }

    /// The server's row is written by a device whose cursor this replica has
    /// already passed, so its pull never delivers it.
    void hidePastTheCursor(Map<String, dynamic> row) =>
        row['server_seq'] = '2025-12-01T00:00:00.000Z';

    Future<void> moveProgressIntoX(String revision, DateTime at) async {
      final progress = HiveService.getAllWorkoutProgressRaw().single;
      await HiveService.putWorkoutProgressRaw(
        progress.copyWith(
          activeWeekId: xWeek.id,
          availableWeekIds: [...?progress.availableWeekIds, xWeek.id],
          revision: revision,
          updatedAt: at,
          dirty: true,
        ),
      );
    }

    // R1 + R2: two replicas hold different versions of the progress row of a
    // deleted block. Whichever uploads first, the newer version's rescue wins
    // on the server and both end on it.
    for (final newerFirst in [false, true]) {
      test(
        'R1: replicas rescuing different versions of a progress row '
        'converge on the newer one (newer replica first: $newerFirst)',
        () async {
          api.serverSchema = 4;
          await setUpBlocks();
          final successor = rescuedTrainingBlockId(x.id);
          final t1 = DateTime.utc(2026, 11, 10);
          final t2 = DateTime.utc(2026, 11, 12);
          const v1 = '00000000-0000-4000-8000-0000000000a1';
          final r1 = rescuedProgressRevision(v1, successor);
          // Pick the newer version's revision so that its rescue sorts BELOW the
          // older one: only recency, never revision text, can make it win.
          var v2 = '';
          for (var i = 0; i < 200; i++) {
            v2 =
                '00000000-0000-4000-8000-${(0xb00 + i).toRadixString(16).padLeft(12, '0')}';
            if (rescuedProgressRevision(v2, successor).compareTo(r1) < 0) break;
          }
          final r2 = rescuedProgressRevision(v2, successor);
          expect(r2.compareTo(r1), lessThan(0));
          await moveProgressIntoX(v1, t1);
          await SyncService.instance.syncNow();
          final base = await snapshotDevice();
          final older = HiveService.getAllWorkoutProgressRaw().single;
          final newer = older.copyWith(
            revision: v2,
            updatedAt: t2,
            dirty: true,
          );
          serverDeletes(x.id);
          final rescuedWeek = lazyTrainingWeekId(splitId, successor, 1);

          Future<void> run(bool isNewer) async {
            await loadDevice(base, progress: [isNewer ? newer : older]);
            await cycles(2);
          }

          await run(!newerFirst);
          await run(newerFirst);
          await run(!newerFirst);
          await run(newerFirst);
          final server = api.tables['workout_progress']!.single;
          expect(server['revision'], r2);
          expect(
            DateTime.parse(server['updated_at'] as String),
            t2.add(const Duration(milliseconds: 1)),
          );
          expect(server['active_week_id'], rescuedWeek);
          // Both replicas hold it, clean.
          for (final isNewer in [false, true]) {
            await loadDevice(base, progress: [isNewer ? newer : older]);
            await cycles(2);
            final local = HiveService.getAllWorkoutProgressRaw().single;
            expect(local.revision, r2, reason: 'newer: $isNewer');
            expect(local.updatedAt, t2.add(const Duration(milliseconds: 1)));
            expect(local.activeWeekId, rescuedWeek);
            expect(local.dirty, isFalse);
          }
        },
      );
    }

    test('R2: a newer progress row under a deleted week reaches this replica '
        'although its pull never delivers it, and is rescued within two '
        'cycles on both replicas', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      final successor = rescuedTrainingBlockId(x.id);
      final t1 = DateTime.utc(2026, 11, 10);
      final t2 = DateTime.utc(2026, 11, 12);
      const v2 = '00000000-0000-4000-8000-0000000000c2';
      await moveProgressIntoX('moved-into-x', t1);
      await SyncService.instance.syncNow();
      final a0 = await snapshotDevice();
      final aProgress = HiveService.getAllWorkoutProgressRaw().single;
      final newer = aProgress.copyWith(
        revision: v2,
        updatedAt: t2,
        dirty: false,
      );
      // Another device wrote v2, then the block went.
      final stored = api.tables['workout_progress']!.single;
      stored['revision'] = v2;
      stored['updated_at'] = t2.toIso8601String();
      hidePastTheCursor(stored);
      serverDeletes(x.id);

      await loadDevice(a0);
      await cycles(2);
      final week = lazyTrainingWeekId(splitId, successor, 1);
      final server = api.tables['workout_progress']!.single;
      expect(server['revision'], rescuedProgressRevision(v2, successor));
      expect(
        DateTime.parse(server['updated_at'] as String),
        t2.add(const Duration(milliseconds: 1)),
      );
      expect(server['active_week_id'], week);
      final local = HiveService.getAllWorkoutProgressRaw().single;
      expect(local.revision, server['revision']);
      expect(local.activeWeekId, week);
      expect(local.dirty, isFalse);
      expect(
        HiveService.readTrainingGraph(ownerId: owner).validate,
        returnsNormally,
      );
      // The replica which wrote v2 converges too.
      await loadDevice(a0, progress: [newer]);
      await cycles(2);
      final other = HiveService.getAllWorkoutProgressRaw().single;
      expect(other.revision, server['revision']);
      expect(other.activeWeekId, week);
      expect(other.dirty, isFalse);
      // And nothing is left to upload.
      api.requests.clear();
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(
        writeOrder().where((w) => w != 'activate_training_schema'),
        isEmpty,
      );
    });

    test('R2: a newer session under a deleted week reaches this replica '
        'although its pull never delivers it, and is rescued within two '
        'cycles on both replicas', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      final successor = rescuedTrainingBlockId(x.id);
      final t2 = DateTime.utc(2026, 11, 12);
      const id = '00000000-0000-4000-8000-0000000000a2';
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: id,
          date: DateTime.utc(2026, 11, 10),
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: xWeek.id,
          weekNumber: 1,
          isCompleted: true,
          durationSeconds: 100,
          updatedAt: DateTime.utc(2026, 11, 10),
          dirty: true,
          exercises: [],
        ),
      );
      await SyncService.instance.syncNow();
      final a0 = await snapshotDevice();
      final v2 = HiveService.getSessionById(
        id,
      )!.copyWith(durationSeconds: 777, updatedAt: t2, dirty: false);
      final stored = serverRow('workout_sessions', id);
      stored['data'] = {...(stored['data'] as Map), 'durationSeconds': 777};
      stored['updated_at'] = t2.toIso8601String();
      hidePastTheCursor(stored);
      serverDeletes(x.id);

      await loadDevice(a0);
      await cycles(2);
      final week = lazyTrainingWeekId(splitId, successor, 1);
      final server = serverRow('workout_sessions', id);
      expect(server['training_week_id'], week);
      expect((server['data'] as Map)['durationSeconds'], 777);
      expect(DateTime.parse(server['updated_at'] as String), t2);
      final local = HiveService.getSessionById(id)!;
      expect(local.durationSeconds, 777);
      expect(local.trainingWeekId, week);
      expect(local.deletedAt, isNull);
      expect(local.dirty, isFalse);
      // The replica which wrote v2 converges too.
      await loadDevice(a0, sessions: [v2]);
      await cycles(2);
      final other = HiveService.getSessionById(id)!;
      expect(other.durationSeconds, 777);
      expect(other.trainingWeekId, week);
      expect(other.dirty, isFalse);
      api.requests.clear();
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(
        writeOrder().where((w) => w != 'activate_training_schema'),
        isEmpty,
      );
    });

    test('R2: live rows under a deleted week with no live local row are '
        'still skipped', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      final progress = HiveService.getAllWorkoutProgressRaw().single;
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'tombstoned-here',
          date: DateTime.utc(2026, 11, 10),
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: xWeek.id,
          weekNumber: 1,
          isCompleted: true,
          updatedAt: DateTime.utc(2026, 11, 10),
          deletedAt: DateTime.utc(2026, 11, 11),
          dirty: false,
          exercises: [],
        ),
      );
      await SyncService.instance.syncNow();
      // Another device's rows, live and newer, under the week which is then
      // deleted. One has no local row at all, one a local tombstone, and a
      // progress row has no local counterpart either.
      final template = {
        'user_id': owner,
        'split_id': splitId,
        'plan_id': planId,
        'training_week_id': xWeek.id,
        'plan_name': 'Push',
        'week_number': 1,
        'date': DateTime.utc(2026, 11, 12).toIso8601String(),
        'data': {'trainingWeekId': xWeek.id},
        'updated_at': DateTime.utc(2026, 11, 12).toIso8601String(),
        'deleted_at': null,
        'server_seq': '2026-11-16T12:00:05.000Z',
      };
      final table = api.tables['workout_sessions']!;
      table.removeWhere((r) => r['id'] == 'tombstoned-here');
      table.add({...template, 'id': 'never-seen-here'});
      table.add({...template, 'id': 'tombstoned-here'});
      const ghostProgress = '00000000-0000-4000-8000-0000000000d1';
      api.tables['workout_progress']!.add({
        'id': ghostProgress,
        'user_id': owner,
        'split_id': splitId,
        'plan_id': planId,
        'active_week_id': xWeek.id,
        'available_week_ids': [xWeek.id],
        'state': 'ready',
        'revision': '00000000-0000-4000-8000-0000000000d2',
        'updated_at': DateTime.utc(2026, 11, 12).toIso8601String(),
        'deleted_at': null,
        'server_seq': '2026-11-16T12:00:05.000Z',
      });
      serverDeletes(x.id);
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(HiveService.getSessionById('never-seen-here'), isNull);
      expect(
        HiveService.getSessionById('tombstoned-here')!.deletedAt,
        isNotNull,
      );
      expect(HiveService.getWorkoutProgressById(ghostProgress), isNull);
      expect(HiveService.getAllWorkoutProgressRaw().single.id, progress.id);
    });

    test('R5: a stale delete of a session which was rescued into another '
        'week meanwhile is accepted and ends clean', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      final week2 = await repo.appendWeek(splitId, x.id);
      const id = '00000000-0000-4000-8000-0000000000a5';
      await HiveService.putSessionRaw(completedInX(id, xWeek, week2));
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      final d0 = await snapshotDevice();
      // Another device rescues S after the block's deletion.
      serverDeletes(x.id);
      await SyncService.instance.syncNow();
      final successor = rescuedTrainingBlockId(x.id);
      final rescuedWeek = lazyTrainingWeekId(splitId, successor, 1);
      final rescuedNext = lazyTrainingWeekId(splitId, successor, 2);
      expect(
        serverRow('workout_sessions', id)['training_week_id'],
        rescuedWeek,
      );
      // Device D never saw that. It deletes S in W and syncs.
      await loadDevice(d0);
      await HiveService.softDeleteSession(id);
      await cycles(1);
      expect(SyncService.instance.status, SyncStatus.synced);
      final server = serverRow('workout_sessions', id);
      expect(server['deleted_at'], isNotNull);
      expect(server['training_week_id'], rescuedWeek);
      final evidence = (server['data'] as Map)['completionTransition'] as Map;
      expect(evidence['sourceWeekId'], rescuedWeek);
      expect(evidence['nextWeekId'], rescuedNext);
      // The acknowledged row names the week it was rescued into; the client
      // takes it over and is clean, not pushing the old week again.
      final local = HiveService.getSessionById(id)!;
      expect(local.deletedAt, isNotNull);
      expect(local.dirty, isFalse);
      expect(local.trainingWeekId, rescuedWeek);
      expect(local.completionTransition!['sourceWeekId'], rescuedWeek);
      expect(
        HiveService.readTrainingGraph(ownerId: owner).validate,
        returnsNormally,
      );
      api.requests.clear();
      await SyncService.instance.syncNow(fullReconciliation: true);
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(
        writeOrder().where((w) => w != 'activate_training_schema'),
        isEmpty,
      );
      expect(serverRow('workout_sessions', id)['deleted_at'], isNotNull);
    });

    void serverDeletesPlan(String id) {
      for (final table in ['workout_plans', 'workout_progress']) {
        for (final row in api.tables[table]!.where(
          (r) => r['id'] == id || r['plan_id'] == id,
        )) {
          row['deleted_at'] = tServer.toIso8601String();
          row['updated_at'] = tServer.toIso8601String();
          row['server_seq'] = '2026-11-16T12:00:01.000Z';
        }
      }
    }

    test('F2: a live workout of a plan another device deleted survives the '
        'block\'s deletion in a rescued block', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      await useBlockXOffline();
      // The phone deletes the plan, then the block; the server sees nothing
      // live in it.
      serverDeletesPlan(planId);
      serverDeletes(x.id);
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      final successor = rescuedTrainingBlockId(x.id);
      final week = lazyTrainingWeekId(splitId, successor, 1);
      final saved = HiveService.getSessionById('logged-in-x')!;
      expect(saved.deletedAt, isNull);
      expect(saved.trainingWeekId, week);
      expect(HiveService.getPlanById(planId)!.deletedAt, isNotNull);
      expect(
        HiveService.getAllWorkoutProgressRaw().single.deletedAt,
        isNotNull,
      );
      final row = serverRow('workout_sessions', 'logged-in-x');
      expect(row['deleted_at'], isNull);
      expect(row['training_week_id'], week);
      expect(
        HiveService.readTrainingGraph(ownerId: owner).validate,
        returnsNormally,
      );
    });

    test(
      'F2: after a remote Clear All Data a workout logged offline survives '
      'in a rescued copy of its block, which validates and uploads',
      () async {
        api.serverSchema = 4;
        await setUpBlocks();
        await useBlockXOffline();
        // Clear All Data on another device: every row is tombstoned and a fresh
        // block takes over.
        for (final table in [
          'training_blocks',
          'training_weeks',
          'workout_plans',
          'workout_progress',
          'workout_sessions',
        ]) {
          for (final row
              in api.tables[table] ?? const <Map<String, dynamic>>[]) {
            row['deleted_at'] = tServer.toIso8601String();
            row['updated_at'] = tServer.toIso8601String();
            row['server_seq'] = '2026-11-16T12:00:01.000Z';
          }
        }
        const fresh = '00000000-0000-4000-8000-0000000000f1';
        api.tables['training_blocks']!.add({
          'id': fresh,
          'user_id': owner,
          'split_id': splitId,
          'name': 'Block 1',
          'position': 0,
          'planned_week_count': 4,
          'created_at': tServer.toIso8601String(),
          'updated_at': tServer.toIso8601String(),
          'deleted_at': null,
          'server_seq': '2026-11-16T12:00:02.000Z',
        });
        api.tables['training_weeks']!.add({
          'id': '00000000-0000-4000-8000-0000000000f2',
          'user_id': owner,
          'split_id': splitId,
          'block_id': fresh,
          'number': 1,
          'created_at': tServer.toIso8601String(),
          'updated_at': tServer.toIso8601String(),
          'deleted_at': null,
          'server_seq': '2026-11-16T12:00:02.000Z',
        });
        await SyncService.instance.syncNow();
        expect(SyncService.instance.status, SyncStatus.synced);
        final successor = rescuedTrainingBlockId(x.id);
        final week = lazyTrainingWeekId(splitId, successor, 1);
        final saved = HiveService.getSessionById('logged-in-x')!;
        expect(saved.deletedAt, isNull);
        expect(saved.trainingWeekId, week);
        expect(saved.dirty, isFalse);
        expect(
          serverRow('workout_sessions', 'logged-in-x')['deleted_at'],
          isNull,
        );
        expect(serverBlock(successor)['deleted_at'], isNull);
        expect(
          HiveService.readTrainingGraph(ownerId: owner).validate,
          returnsNormally,
        );
        api.requests.clear();
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(
          writeOrder().where((w) => w != 'activate_training_schema'),
          isEmpty,
        );
      },
    );

    test('F2: Clear All Data on this device rescues nothing', () async {
      api.serverSchema = 4;
      await setUpBlocks();
      await useBlockXOffline();
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      await HiveService.softDeleteAllWorkoutData();
      await SyncService.instance.syncNow();
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(
        HiveService.getAllTrainingBlocksRaw().map((b) => b.id),
        isNot(contains(rescuedTrainingBlockId(x.id))),
      );
      expect(HiveService.getSessionById('logged-in-x')!.deletedAt, isNotNull);
      expect(
        serverRow('workout_sessions', 'logged-in-x')['deleted_at'],
        isNotNull,
      );
      expect(
        api.tables['training_blocks']!.map((b) => b['id']),
        isNot(contains(rescuedTrainingBlockId(x.id))),
      );
    });

    test(
      'F2: restoring an older backup on this device rescues nothing',
      () async {
        api.serverSchema = 4;
        // A backup of a plan that had already been trained: its progress is no
        // longer the bootstrap row, which the server would never let overwrite
        // a stored row.
        final base = HiveService.readTrainingGraph(ownerId: owner);
        final older = base.copyWith(
          progress: [
            for (final p in base.progress)
              p.copyWith(revision: '00000000-0000-4000-8000-0000000000b1'),
          ],
        );
        await setUpBlocks();
        await useBlockXOffline();
        await SyncService.instance.syncNow();
        expect(SyncService.instance.status, SyncStatus.synced);
        await TrainingBlockRestore().replace(graph: older);
        await SyncService.instance.syncNow();
        expect(SyncService.instance.status, SyncStatus.synced);
        expect(
          HiveService.getAllTrainingBlocksRaw().map((b) => b.id),
          isNot(contains(rescuedTrainingBlockId(x.id))),
        );
        expect(HiveService.getSessionById('logged-in-x')!.deletedAt, isNotNull);
        expect(localBlock(x.id).deletedAt, isNotNull);
      },
    );

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

    test(
      'a block the server never received is not deleted: the call fails, '
      'local data is untouched, and it works once the block has uploaded',
      () async {
        api.serverSchema = 4;
        await SyncService.instance.syncNow(fullReconciliation: true);
        repo = TrainingBlockRepository(ownerId: () => owner);
        // The first upload of the new block fails, so the server never has it.
        api.intercept =
            (r) async =>
                r.method == 'POST' && r.url.path.endsWith('/training_blocks')
                    ? http.Response(
                      '{"message":"offline","code":"OFFLINE"}',
                      503,
                    )
                    : null;
        final lonely = await repo.createBlock(
          splitId: splitId,
          name: 'Lonely',
          weekCount: 3,
        );
        await repo.appendWeek(splitId, lonely.id);
        await repo.createBlock(splitId: splitId, name: 'Other', weekCount: 3);
        final before = snapshot();
        await expectLater(
          repo.deleteBlock(splitId: splitId, blockId: lonely.id),
          throwsA(isNot(isA<TrainingBlockDeletionException>())),
        );
        expect(deleteCalls(), hasLength(1));
        expect(snapshot(), before);
        expect(localBlock(lonely.id).deletedAt, isNull);
        // Nothing in the gate is left held.
        api.intercept = null;
        await repo.deleteBlock(splitId: splitId, blockId: lonely.id);
        expect(localBlock(lonely.id).deletedAt, isNotNull);
        expect(localBlock(lonely.id).dirty, isFalse);
        expect(serverBlock(lonely.id)['deleted_at'], isNotNull);
      },
    );

    test('local-only data still deletes purely locally', () async {
      const localSplit = '00000000-0000-4000-8000-0000000000aa';
      await HiveService.putSplitRaw(
        Split(
          id: localSplit,
          name: 'Local',
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      final local = TrainingBlockRepository(ownerId: () => null);
      await local.createBlock(splitId: localSplit, name: 'Keep', weekCount: 3);
      final extra = await local.createBlock(
        splitId: localSplit,
        name: 'Extra',
        weekCount: 3,
      );
      expect(local.lifecycleAvailable, isTrue);
      await local.deleteBlock(splitId: localSplit, blockId: extra.id);
      expect(localBlock(extra.id).deletedAt, isNotNull);
      expect(localBlock(extra.id).dirty, isTrue);
      expect(
        HiveService.getAllTrainingWeeksRaw()
            .where((w) => w.blockId == extra.id)
            .every((w) => w.deletedAt != null && w.dirty == true),
        isTrue,
      );
      expect(deleteCalls(), isEmpty);
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

  group('duration clocks exist only where they mean something', () {
    final c0 = DateTime.utc(2026, 3, 1);

    test('F3: a client at schema 3 extends offline, an old client extends '
        'further, then the account reaches 4: both end at 8', () async {
      final repo = TrainingBlockRepository(ownerId: () => owner);
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
      final block = await repo.createBlock(
        splitId: splitId,
        name: 'Block',
        weekCount: 4,
      );
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(serverBlock(block.id)['planned_week_count'], 4);
      // This client extends offline: no clock, because none can matter yet.
      await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Block',
        weekCount: 5,
      );
      expect(localBlock(block.id).plannedWeekCount, 5);
      expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNull);
      // An older app extends to 8 and syncs, without the clock column.
      final stored = serverBlock(block.id);
      stored['planned_week_count'] = 8;
      stored['updated_at'] = DateTime.utc(2030).toIso8601String();
      stored['server_seq'] = '2026-12-01T00:00:00.000Z';
      // The account then reaches schema 4.
      api.serverSchema = 4;
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(localBlock(block.id).plannedWeekCount, 8);
      expect(serverBlock(block.id)['planned_week_count'], 8);
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(localBlock(block.id).plannedWeekCount, 8);
      expect(serverBlock(block.id)['planned_week_count'], 8);
    });

    test('F3: every length change below schema 4 leaves the clock null and '
        'carries no earlier one forward', () async {
      api.serverSchema = 4;
      final repo = TrainingBlockRepository(ownerId: () => owner);
      await SyncService.instance.syncNow(fullReconciliation: true);
      final block = await repo.createBlock(
        splitId: splitId,
        name: 'Block',
        weekCount: 4,
      );
      expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNotNull);
      // The account is now known to be below 4.
      SyncService.instance.setNegotiatedSchema(owner, 3);
      await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Block',
        weekCount: 6,
      );
      expect(localBlock(block.id).plannedWeekCount, 6);
      expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNull);
      await repo.appendWeek(splitId, block.id);
      await repo.appendWeek(splitId, block.id);
      expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNull);
    });

    test(
      'F3: a clock stamped while data was local-only is dropped on the '
      'first cycle that negotiates 3, and kept on one that negotiates 4',
      () async {
        final repo = TrainingBlockRepository(ownerId: () => owner);
        final block = await repo.createBlock(
          splitId: splitId,
          name: 'Adopted',
          weekCount: 4,
        );
        // What adoption of local-only data leaves: a meaningful clock.
        await HiveService.putTrainingBlockRaw(
          localBlock(block.id).copyWith(plannedWeekCountUpdatedAt: c0),
        );
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(SyncService.instance.status, SyncStatus.synced);
        expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
        expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNull);
        expect(
          serverBlock(block.id).containsKey('planned_week_count_updated_at'),
          isFalse,
        );
        // Reaching 4 later does not resurrect a clock.
        api.serverSchema = 4;
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(localBlock(block.id).plannedWeekCountUpdatedAt, isNull);

        // On an account which negotiates 4 it is kept and sent.
        SyncService.instance.forgetNegotiatedSchemas();
        final other = await repo.createBlock(
          splitId: splitId,
          name: 'Kept',
          weekCount: 4,
        );
        await HiveService.putTrainingBlockRaw(
          localBlock(other.id).copyWith(plannedWeekCountUpdatedAt: c0),
        );
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(localBlock(other.id).plannedWeekCountUpdatedAt, c0);
        expect(
          DateTime.parse(
            serverBlock(other.id)['planned_week_count_updated_at'] as String,
          ),
          c0,
        );
      },
    );
  });

  group('F4/F5 the delete call and the remembered level', () {
    late TrainingBlockRepository repo;
    late TrainingBlock x;
    final savedTimeout = SyncService.blockDeleteTimeout;
    tearDown(() => SyncService.blockDeleteTimeout = savedTimeout);

    test(
      'F4: a delete call which never answers fails, frees the gate, leaves '
      'local data alone, and a later pull of the tombstones converges',
      () async {
        api.serverSchema = 4;
        repo = TrainingBlockRepository(ownerId: () => owner);
        x = await repo.createBlock(splitId: splitId, name: 'X', weekCount: 4);
        await repo.createBlock(splitId: splitId, name: 'Y', weekCount: 3);
        await SyncService.instance.syncNow(fullReconciliation: true);
        SyncService.instance.setNegotiatedSchema(owner, 4);
        SyncService.blockDeleteTimeout = const Duration(milliseconds: 200);
        final never = Completer<http.Response?>();
        api.intercept =
            (r) =>
                r.url.path.endsWith('/rpc/delete_training_block')
                    ? never.future
                    : Future.value(null);
        final before = jsonEncode([
          for (final b in HiveService.getAllTrainingBlocksRaw()) b.toJson(),
          for (final w in HiveService.getAllTrainingWeeksRaw()) w.toJson(),
        ]);
        await expectLater(
          repo.deleteBlock(splitId: splitId, blockId: x.id),
          throwsA(isA<TimeoutException>()),
        );
        expect(
          jsonEncode([
            for (final b in HiveService.getAllTrainingBlocksRaw()) b.toJson(),
            for (final w in HiveService.getAllTrainingWeeksRaw()) w.toJson(),
          ]),
          before,
        );
        // The gate is free: another mutation runs at once.
        expect(
          await SyncService.instance
              .runExclusiveLocalMutation(() async => 'free')
              .timeout(const Duration(seconds: 2)),
          'free',
        );
        // The server had committed; the next cycle brings its tombstones.
        api.intercept = null;
        serverDeletes(x.id);
        await SyncService.instance.syncNow(fullReconciliation: true);
        expect(SyncService.instance.status, SyncStatus.synced);
        expect(localBlock(x.id).deletedAt, tServer);
        expect(localBlock(x.id).dirty, isFalse);
        expect(
          repo.blocksForSplit(splitId).map((b) => b.id),
          isNot(contains(x.id)),
        );
      },
    );

    test('R4: a delete call which times out schedules a sync, which brings '
        'the tombstones if the server did commit', () async {
      api.serverSchema = 4;
      repo = TrainingBlockRepository(ownerId: () => owner);
      x = await repo.createBlock(splitId: splitId, name: 'X', weekCount: 4);
      await repo.createBlock(splitId: splitId, name: 'Y', weekCount: 3);
      await SyncService.instance.syncNow(fullReconciliation: true);
      SyncService.instance.setNegotiatedSchema(owner, 4);
      SyncService.blockDeleteTimeout = const Duration(milliseconds: 100);
      final never = Completer<http.Response?>();
      api.intercept =
          (r) =>
              r.url.path.endsWith('/rpc/delete_training_block')
                  ? never.future
                  : Future.value(null);
      await expectLater(
        repo.deleteBlock(splitId: splitId, blockId: x.id),
        throwsA(isA<TimeoutException>()),
      );
      // The server had committed. Nobody syncs by hand: the scheduled sync
      // (a two second debounce) does.
      api.intercept = null;
      serverDeletes(x.id);
      for (var i = 0; i < 80 && localBlock(x.id).deletedAt == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(localBlock(x.id).deletedAt, tServer);
      expect(localBlock(x.id).dirty, isFalse);
    });

    test('F5: the persisted level is the last negotiated one, so a server '
        'which falls back to 3 turns the lifecycle off, now and after a '
        'restart', () async {
      api.serverSchema = 4;
      await SyncService.instance.syncNow();
      expect(SyncService.instance.blockLifecycleAvailable(owner), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'training_schema_$owner',
        ),
        4,
      );
      // The server is rolled back to a state which only offers 3.
      api.serverSchema = 3;
      api.accountSchema = 3;
      await SyncService.instance.syncNow();
      expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'training_schema_$owner',
        ),
        3,
      );
      SyncService.instance.forgetNegotiatedSchemas();
      await SyncService.instance.restoreNegotiatedSchemas();
      expect(SyncService.instance.blockLifecycleAvailable(owner), isFalse);
    });
  });

  group('the fake server follows the SQL', () {
    Future<http.Response> post(String table, Map<String, dynamic> row) =>
        api.handle(
          http.Request(
              'POST',
              Uri.parse('https://x.supabase.co/rest/v1/$table'),
            )
            ..headers['x-opengym-training-schema'] = '4'
            ..body = jsonEncode(row),
        );
    Map<String, dynamic> blockRow(
      String id, {
      String? deleted,
      int count = 3,
    }) => {
      'id': id,
      'user_id': owner,
      'split_id': splitId,
      'name': id,
      'position': 0,
      'planned_week_count': count,
      'created_at': stamp.toIso8601String(),
      'updated_at': stamp.toIso8601String(),
      'deleted_at': deleted,
    };
    Map<String, dynamic> weekRow(String id, String block, {String? deleted}) =>
        {
          'id': id,
          'user_id': owner,
          'split_id': splitId,
          'block_id': block,
          'number': 1,
          'created_at': stamp.toIso8601String(),
          'updated_at': stamp.toIso8601String(),
          'deleted_at': deleted,
        };
    final dead = DateTime.utc(2026, 5, 1).toIso8601String();

    setUp(() {
      api.serverSchema = 4;
      api.accountSchema = 4;
      api.tables['splits'] = [
        {'id': splitId, 'user_id': owner, 'deleted_at': null},
      ];
      api.tables['workout_plans'] = [
        {
          'id': planId,
          'user_id': owner,
          'split_id': splitId,
          'deleted_at': null,
        },
      ];
    });

    test('a live week under a deleted block, and live progress on a deleted '
        'week, are rejected; tombstones are accepted', () async {
      expect(
        (await post(
          'training_blocks',
          blockRow('b', deleted: dead),
        )).statusCode,
        201,
      );
      expect((await post('training_weeks', weekRow('w', 'b'))).statusCode, 400);
      expect(
        (await post(
          'training_weeks',
          weekRow('w', 'b', deleted: dead),
        )).statusCode,
        201,
      );
      final progress = {
        'id': 'p',
        'user_id': owner,
        'split_id': splitId,
        'plan_id': planId,
        'active_week_id': 'w',
        'available_week_ids': ['w'],
        'state': 'ready',
        'revision': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        'updated_at': stamp.toIso8601String(),
        'deleted_at': null,
      };
      expect((await post('workout_progress', progress)).statusCode, 400);
      expect(
        (await post('workout_progress', {
          ...progress,
          'deleted_at': dead,
        })).statusCode,
        201,
      );
    });

    test('a live session in a deleted week is rejected', () async {
      await post('training_blocks', blockRow('b'));
      await post('training_weeks', weekRow('w', 'b', deleted: dead));
      final session = {
        'id': 's',
        'user_id': owner,
        'split_id': splitId,
        'plan_id': planId,
        'training_week_id': 'w',
        'plan_name': 'Push',
        'week_number': 1,
        'date': stamp.toIso8601String(),
        'data': {'trainingWeekId': 'w'},
        'updated_at': stamp.toIso8601String(),
        'deleted_at': null,
      };
      expect((await post('workout_sessions', session)).statusCode, 400);
    });

    test('a stored tombstone is sticky and a losing upsert is a silent no-op '
        'returning the stored row', () async {
      await post('training_blocks', blockRow('b', deleted: dead));
      final revived = await post('training_blocks', blockRow('b', count: 9));
      expect(revived.statusCode, 201);
      expect((jsonDecode(revived.body) as List).single['deleted_at'], dead);
      expect(
        (jsonDecode(revived.body) as List).single['planned_week_count'],
        3,
      );
      await post('training_blocks', blockRow('c'));
      await post('training_weeks', weekRow('w', 'c'));
      final stale = await post('training_weeks', {
        ...weekRow('w', 'c'),
        'updated_at': DateTime.utc(2020).toIso8601String(),
        'number': 7,
      });
      expect(stale.statusCode, 201);
      expect((jsonDecode(stale.body) as List).single['number'], 1);
    });

    test('an omitted clock column is the stored clock, a tie, which keeps '
        'the larger count', () async {
      await post('training_blocks', {
        ...blockRow('b', count: 6),
        'planned_week_count_updated_at':
            DateTime.utc(2026, 3).toIso8601String(),
      });
      final smaller = await post('training_blocks', blockRow('b', count: 4));
      expect(
        (jsonDecode(smaller.body) as List).single['planned_week_count'],
        6,
      );
    });

    Map<String, dynamic> numbered(Map<String, dynamic> week, int n) => {
      ...week,
      'number': n,
    };

    test('R5: an incoming live row is validated by the INSERT pass even when '
        'it would then lose last-write-wins', () async {
      await post('training_blocks', blockRow('b'));
      await post('training_weeks', weekRow('w', 'b'));
      await post('training_weeks', weekRow('w2', 'b'));
      Map<String, dynamic> progress(String week, String updated) => {
        'id': 'p',
        'user_id': owner,
        'split_id': splitId,
        'plan_id': planId,
        'active_week_id': week,
        'available_week_ids': [week],
        'state': 'ready',
        'revision': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        'updated_at': updated,
        'deleted_at': null,
      };
      final newer = DateTime.utc(2026, 2).toIso8601String();
      final older = DateTime.utc(2026, 1, 2).toIso8601String();
      expect(
        (await post('workout_progress', progress('w', newer))).statusCode,
        201,
      );
      await post('training_weeks', weekRow('w', 'b', deleted: dead));
      // Losing on time does not excuse a live row under a deleted week.
      expect(
        (await post('workout_progress', progress('w', older))).statusCode,
        400,
      );
      // Under a live week it is a silent no-op returning the stored row.
      final lost = await post('workout_progress', progress('w2', older));
      expect(lost.statusCode, 201);
      final row = (jsonDecode(lost.body) as List).single as Map;
      expect(row['active_week_id'], 'w');
      expect(row['updated_at'], newer);
    });

    Map<String, dynamic> sessionRow(
      String week,
      String next, {
      Map<String, dynamic>? evidence,
      String? deleted,
      String updated = '2026-01-01T00:00:00.000Z',
      int number = 1,
    }) => {
      'id': 's',
      'user_id': owner,
      'split_id': splitId,
      'plan_id': planId,
      'training_week_id': week,
      'plan_name': 'Push',
      'week_number': number,
      'date': stamp.toIso8601String(),
      'data': {
        'trainingWeekId': week,
        'isCompleted': true,
        'weekNumber': number,
        'completionTransition':
            evidence ??
            {
              'expectedRevision': '00000000-0000-4000-8000-0000000000e1',
              'sourceWeekId': week,
              'nextWeekId': next,
              'resultRevision': 's',
              'committedAt': stamp.toIso8601String(),
            },
      },
      'updated_at': updated,
      'deleted_at': deleted,
    };

    Future<void> twoBlocksWithASession() async {
      for (final b in ['b', 'c']) {
        await post('training_blocks', blockRow(b));
        await post('training_weeks', weekRow('${b}1', b));
        await post('training_weeks', numbered(weekRow('${b}2', b), 2));
      }
      expect(
        (await post('workout_sessions', sessionRow('b1', 'b2'))).statusCode,
        201,
      );
      await post('training_weeks', weekRow('b1', 'b', deleted: dead));
      await post(
        'training_weeks',
        numbered(weekRow('b2', 'b', deleted: dead), 2),
      );
    }

    test('R5: a session moves out of a deleted week only with the stored '
        'evidence pointed at the new week', () async {
      await twoBlocksWithASession();
      Map<String, dynamic> moved(Map<String, dynamic> evidence) =>
          sessionRow('c1', 'c2', evidence: evidence);
      Map<String, dynamic> stored() => {
        'expectedRevision': '00000000-0000-4000-8000-0000000000e1',
        'resultRevision': 's',
        'committedAt': stamp.toIso8601String(),
        'sourceWeekId': 'c1',
        'nextWeekId': 'c2',
      };
      // Changed evidence, or none, is refused.
      expect(
        (await post(
          'workout_sessions',
          moved({
            ...stored(),
            'expectedRevision': '00000000-0000-4000-8000-0000000000e2',
          }),
        )).statusCode,
        400,
      );
      expect(
        (await post('workout_sessions', {
          ...sessionRow('c1', 'c2'),
          'data': {
            'trainingWeekId': 'c1',
            'isCompleted': true,
            'weekNumber': 1,
          },
        })).statusCode,
        400,
      );
      expect(
        (await post('workout_sessions', {
          ...sessionRow('c1', 'c2'),
          'data': {
            'trainingWeekId': 'c1',
            'isCompleted': true,
            'weekNumber': 1,
            'completionTransition': 'x',
          },
        })).statusCode,
        400,
      );
      expect(api.tables['workout_sessions']!.single['training_week_id'], 'b1');
      // Only the two week ids differ: accepted, and the incoming copy is kept.
      expect((await post('workout_sessions', moved(stored()))).statusCode, 201);
      final row = api.tables['workout_sessions']!.single;
      expect(row['training_week_id'], 'c1');
      expect(
        ((row['data'] as Map)['completionTransition'] as Map)['sourceWeekId'],
        'c1',
      );
    });

    test(
      'R5: a stale tombstone naming the week a session has since left is '
      're-pointed at the stored link and keeps the stored evidence',
      () async {
        await twoBlocksWithASession();
        final rescued = sessionRow('c1', 'c2');
        expect((await post('workout_sessions', rescued)).statusCode, 201);
        final stale = sessionRow(
          'b1',
          'b2',
          deleted: DateTime.utc(2026, 3).toIso8601String(),
          updated: DateTime.utc(2026, 3).toIso8601String(),
        );
        final response = await post('workout_sessions', stale);
        expect(response.statusCode, 201);
        final ack = (jsonDecode(response.body) as List).single as Map;
        expect(ack['deleted_at'], isNotNull);
        expect(ack['training_week_id'], 'c1');
        expect(ack['week_number'], 1);
        final data = ack['data'] as Map;
        expect(data['trainingWeekId'], 'c1');
        expect((data['completionTransition'] as Map)['sourceWeekId'], 'c1');
        expect((data['completionTransition'] as Map)['nextWeekId'], 'c2');
        // A tombstone for the week it is in is untouched by the rule.
        final again = await post('workout_sessions', {
          ...sessionRow('c1', 'c2'),
          'deleted_at': DateTime.utc(2026, 4).toIso8601String(),
          'updated_at': DateTime.utc(2026, 4).toIso8601String(),
        });
        expect(again.statusCode, 201);
      },
    );

    test('the delete procedure stamps greatest(updated_at, now())', () async {
      await post('training_blocks', blockRow('a'));
      await post('training_blocks', {
        ...blockRow('b'),
        'updated_at': DateTime.utc(2030).toIso8601String(),
      });
      for (final id in ['b']) {
        final result = await api.handle(
          http.Request(
              'POST',
              Uri.parse(
                'https://x.supabase.co/rest/v1/rpc/delete_training_block',
              ),
            )
            ..headers['x-opengym-training-schema'] = '4'
            ..body = jsonEncode({'target': id}),
        );
        final block = (jsonDecode(result.body) as Map)['block'] as Map;
        expect(DateTime.parse(block['deleted_at'] as String), api.serverNow());
        expect(
          DateTime.parse(block['updated_at'] as String),
          DateTime.utc(2030),
        );
      }
    });
  });
}
