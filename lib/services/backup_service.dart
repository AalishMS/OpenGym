import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/split.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../utils/split_identity.dart';

class ExportResult {
  final String jsonString;
  final String fileName;

  ExportResult({required this.jsonString, required this.fileName});
}

class ImportResult {
  final bool success;
  final String? errorMessage;
  final int? version;
  final List<Split>? splits;
  final String? activeSplitId;
  final List<WorkoutPlan>? plans;
  final List<WorkoutSession>? sessions;
  final Map<String, dynamic>? settings;

  ImportResult._({
    required this.success,
    this.errorMessage,
    this.version,
    this.splits,
    this.activeSplitId,
    this.plans,
    this.sessions,
    this.settings,
  });

  factory ImportResult.success({
    required List<Split> splits,
    required String activeSplitId,
    required List<WorkoutPlan> plans,
    required List<WorkoutSession> sessions,
    required Map<String, dynamic> settings,
  }) => ImportResult._(
    success: true,
    splits: splits,
    activeSplitId: activeSplitId,
    plans: plans,
    sessions: sessions,
    settings: settings,
  );

  factory ImportResult.invalid(String message) =>
      ImportResult._(success: false, errorMessage: message);

  factory ImportResult.versionMismatch(int version) => ImportResult._(
    success: false,
    errorMessage: 'Unsupported backup version: $version',
    version: version,
  );
}

class BackupService {
  static const int currentVersion = 3;
  static const Uuid _uuid = Uuid();

  static ExportResult exportData({
    required List<Split> splits,
    required String activeSplitId,
    required List<WorkoutPlan> plans,
    required List<WorkoutSession> sessions,
    required Map<String, dynamic> settings,
  }) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final data = {
      'version': currentVersion,
      'exportedAt': now.toIso8601String(),
      'activeSplitId': activeSplitId,
      'splits': splits.map((split) => split.toJson()).toList(),
      'settings': settings,
      'workoutPlans': plans.map((plan) => plan.toJson()).toList(),
      'workoutSessions': sessions.map((session) => session.toJson()).toList(),
    };
    return ExportResult(
      jsonString: const JsonEncoder.withIndent('  ').convert(data),
      fileName: 'gymapp_backup_$date.json',
    );
  }

  static ImportResult importData(String jsonString, {required String userId}) {
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return ImportResult.invalid('File is not valid JSON');
    }

    final version = parsed['version'];
    if (version is! int) return ImportResult.invalid('File is not valid JSON');
    if (version < 1 || version > currentVersion) {
      return ImportResult.versionMismatch(version);
    }

    final plansRaw = parsed['workoutPlans'];
    final sessionsRaw = parsed['workoutSessions'];
    final settingsRaw = parsed['settings'];
    if (plansRaw is! List || sessionsRaw is! List || settingsRaw is! Map) {
      return ImportResult.invalid('Invalid plan or session data');
    }

    try {
      final now = DateTime.now();
      late final List<Split> splits;
      late final String activeSplitId;
      if (version < 3) {
        activeSplitId = defaultSplitIdForUser(userId);
        splits = [
          Split(
            id: activeSplitId,
            name: 'My Split',
            userId: userId,
            createdAt: now,
            updatedAt: now,
            dirty: true,
          ),
        ];
      } else {
        final rawSplits = parsed['splits'];
        if (rawSplits is! List || rawSplits.isEmpty || rawSplits.length > 5) {
          return ImportResult.invalid('Backup must contain 1–5 splits');
        }
        splits =
            rawSplits
                .map(
                  (value) =>
                      Split.fromJson(Map<String, dynamic>.from(value as Map)),
                )
                .map(
                  (split) => split.copyWith(
                    userId: userId,
                    updatedAt: now,
                    dirty: true,
                  ),
                )
                .toList();
        final names = splits.map((s) => s.name.trim().toLowerCase()).toSet();
        if (names.length != splits.length ||
            splits.any((s) => s.name.trim().isEmpty || s.name.length > 24)) {
          return ImportResult.invalid('Backup contains invalid split names');
        }
        activeSplitId = parsed['activeSplitId'] as String;
        if (!splits.any((split) => split.id == activeSplitId)) {
          return ImportResult.invalid('Backup active split is missing');
        }
      }

      final validIds = splits.map((split) => split.id).toSet();
      final plans =
          plansRaw.map((value) {
            final plan = WorkoutPlan.fromJson(
              Map<String, dynamic>.from(value as Map),
            );
            plan.id ??= _uuid.v4();
            plan.userId = userId;
            plan.splitId = version < 3 ? activeSplitId : plan.splitId;
            if (!validIds.contains(plan.splitId)) {
              throw const FormatException('Plan references an unknown split');
            }
            plan.updatedAt = now;
            plan.deletedAt = null;
            plan.dirty = true;
            return plan;
          }).toList();
      final planSplitById = {for (final plan in plans) plan.id!: plan.splitId!};
      final sessions =
          sessionsRaw.map((value) {
            final session = WorkoutSession.fromJson(
              Map<String, dynamic>.from(value as Map),
            );
            session.id ??= _uuid.v4();
            session.userId = userId;
            session.splitId =
                version < 3
                    ? activeSplitId
                    : (planSplitById[session.planId] ?? session.splitId);
            if (!validIds.contains(session.splitId)) {
              throw const FormatException(
                'Session references an unknown split',
              );
            }
            session.updatedAt = now;
            session.deletedAt = null;
            session.dirty = true;
            return session;
          }).toList();

      return ImportResult.success(
        splits: splits,
        activeSplitId: activeSplitId,
        plans: plans,
        sessions: sessions,
        settings: settingsRaw.cast<String, dynamic>(),
      );
    } catch (_) {
      return ImportResult.invalid('Invalid plan, session, or split data');
    }
  }
}
