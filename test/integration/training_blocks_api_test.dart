import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/supabase_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../support/hive_test_harness.dart';

/// The Python API suite seeds this owner in the named, loopback-only database.
/// The JWT below is signed with its public test secret; it is not an app key.
const _owner = '00000000-0000-4000-8000-000000000011';
const _token =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMTEiLCJyb2xlIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MjA4Mjc1ODQwMH0.h6xn_q7kaQN04XEGjDbvroFjvY5fG1NxWn-9w4a1_cA';

void main() {
  test('installed Flutter SDK syncs the real isolated PostgREST graph', () async {
    final storage = HiveTestHarness();
    final native = http.Client();
    final headers = <String?>[];
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
          headers.add(r.headers['x-opengym-training-schema']);
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
    try {
      await SupabaseService.auth.getSessionFromUrl(
        Uri.parse(
          'io.opengym.app://callback/#access_token=$_token&refresh_token=local&expires_in=3600&token_type=bearer&type=signup',
        ),
      );
      await SyncService.instance.syncNow(fullReconciliation: true);
      expect(SyncService.instance.status, SyncStatus.synced);
      expect(HiveService.getAllTrainingBlocksRaw(), isNotEmpty);
      expect(HiveService.getAllTrainingWeeksRaw(), isNotEmpty);
      expect(HiveService.getAllWorkoutProgressRaw(), isNotEmpty);
      expect(HiveService.getAllSessionsRaw(), isNotEmpty);
      expect(headers.every((h) => h == '2'), isTrue);
      final beforeCount = HiveService.getAllSessionsRaw().length;
      final template = HiveService.getAllSessionsRaw().first;
      final batch = List.generate(1003, (i) {
        final session = template.copyWith(
          id: const Uuid().v4(),
          completionTransition: null,
        );
        return {
          'id': session.id,
          'user_id': _owner,
          'split_id': session.splitId,
          'plan_id': session.planId,
          'training_week_id': session.trainingWeekId,
          'plan_name': session.planName,
          'week_number': session.weekNumber,
          'date': session.date.toUtc().toIso8601String(),
          'updated_at': session.updatedAt!.toUtc().toIso8601String(),
          'data': session.toJson(),
        };
      });
      final inserted = await native.post(
        Uri.parse('http://127.0.0.1:55440/workout_sessions'),
        headers: {
          'Authorization': 'Bearer $_token',
          'x-opengym-training-schema': '2',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode(batch),
      );
      expect(inserted.statusCode, 201, reason: inserted.body);
      await SyncService.instance.syncNow();
      expect(HiveService.getAllSessionsRaw(), hasLength(beforeCount + 1003));
      final log = HiveService.getAllSessionsRaw().first;
      await HiveService.upsertSession(log.copyWith(durationSeconds: 155));
      await SyncService.instance.syncNow();
      expect(HiveService.getSessionById(log.id!)!.durationSeconds, 155);
      expect(HiveService.getSessionById(log.id!)!.dirty, isFalse);
    } finally {
      await Supabase.instance.dispose();
      native.close();
      await storage.close();
    }
  }, skip: !const bool.fromEnvironment('OPENGYM_LOCAL_API_TESTS'));
}
