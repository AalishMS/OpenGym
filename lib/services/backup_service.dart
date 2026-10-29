import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/split.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_plan.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../utils/split_identity.dart';
import 'training_block_graph.dart';
import 'training_block_migration.dart';

class ExportResult {
  final String jsonString;
  final String fileName;
  ExportResult({required this.jsonString, required this.fileName});
}

class ImportResult {
  final bool success;
  final String? errorMessage;
  final int? version;
  final TrainingBlockGraph? graph;
  final Map<String, dynamic>? settings;
  final String? operationId;
  final String? sourceAccountId;
  List<Split>? get splits => graph?.splits;
  String? get activeSplitId => graph?.activeSplitId;
  List<WorkoutPlan>? get plans => graph?.plans;
  List<WorkoutSession>? get sessions => graph?.sessions;
  List<TrainingBlock>? get blocks => graph?.blocks;
  List<TrainingWeek>? get weeks => graph?.weeks;
  List<WorkoutProgress>? get progress => graph?.progress;

  ImportResult._({
    required this.success,
    this.errorMessage,
    this.version,
    this.graph,
    this.settings,
    this.operationId,
    this.sourceAccountId,
  });
  factory ImportResult.success({
    required TrainingBlockGraph graph,
    required Map<String, dynamic> settings,
    required int version,
    String? sourceAccountId,
  }) => ImportResult._(
    success: true,
    graph: graph,
    settings: settings,
    version: version,
    sourceAccountId: sourceAccountId,
    operationId: const Uuid().v4(),
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
  static const currentVersion = 5;
  static const _uuid = Uuid();

  static ExportResult exportData({
    String? sourceAccountId,
    required List<Split> splits,
    required String activeSplitId,
    required List<WorkoutPlan> plans,
    required List<WorkoutSession> sessions,
    List<TrainingBlock> blocks = const [],
    List<TrainingWeek> weeks = const [],
    List<WorkoutProgress> progress = const [],
    required Map<String, dynamic> settings,
  }) {
    final owners =
        [
          ...splits.map((r) => r.userId),
          ...plans.map((r) => r.userId),
          ...sessions.map((r) => r.userId),
          ...blocks.map((r) => r.userId),
          ...weeks.map((r) => r.userId),
          ...progress.map((r) => r.userId),
        ].whereType<String>().toSet();
    if (owners.length > 1 ||
        (sourceAccountId != null &&
            owners.any((id) => id != sourceAccountId))) {
      throw const FormatException('Cannot export mixed account data.');
    }
    final graph = TrainingBlockMigration.prepareGraph(
      TrainingBlockGraph(
        ownerId: sourceAccountId ?? owners.firstOrNull,
        activeSplitId: activeSplitId,
        splits: splits,
        plans: plans,
        sessions: sessions,
        blocks: blocks,
        weeks: weeks,
        progress: progress,
      ).ownedBy(sourceAccountId ?? owners.firstOrNull),
    );
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return ExportResult(
      jsonString: const JsonEncoder.withIndent('  ').convert({
        'version': currentVersion,
        'exportedAt': now.toIso8601String(),
        'sourceAccountId': sourceAccountId,
        'activeSplitId': activeSplitId,
        'splits': graph.splits.map((r) => r.toJson()).toList(),
        'workoutPlans': graph.plans.map((r) => r.toJson()).toList(),
        'workoutSessions': graph.sessions.map((r) => r.toJson()).toList(),
        'trainingBlocks': graph.blocks.map((r) => r.toJson()).toList(),
        'trainingWeeks': graph.weeks.map((r) => r.toJson()).toList(),
        'workoutProgress': graph.progress.map((r) => r.toJson()).toList(),
        'settings': settings,
      }),
      fileName: 'gymapp_backup_$date.json',
    );
  }

  static ImportResult importData(String jsonString, {required String? userId}) {
    try {
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
      final version = parsed['version'];
      if (version is! int) {
        return ImportResult.invalid('File is not valid JSON');
      }
      if (version < 1 || version > currentVersion) {
        return ImportResult.versionMismatch(version);
      }
      final source = parsed['sourceAccountId'] as String?;
      List<Map<String, dynamic>> rows(String key, {bool optional = false}) {
        final value = parsed[key];
        if (optional && value == null) return [];
        if (value is! List) throw FormatException('Invalid $key data.');
        return value.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }

      if (parsed['settings'] is! Map) {
        return ImportResult.invalid('Invalid settings data');
      }
      final now = DateTime.now();
      final splits =
          version < 3
              ? [
                Split(
                  id: defaultSplitIdForUser(source ?? 'legacy-import'),
                  name: 'My Split',
                  createdAt: now,
                  userId: source,
                ),
              ]
              : rows('splits').map(Split.fromJson).toList();
      if (splits.isEmpty) {
        throw const FormatException('Backup must contain a split.');
      }
      final active =
          version < 3 ? splits.single.id : parsed['activeSplitId'] as String;
      final planRows = rows('workoutPlans');
      final sessionRows = rows('workoutSessions');
      final blockRows = rows('trainingBlocks', optional: version < 4);
      final weekRows = rows('trainingWeeks', optional: version < 4);
      final progressRows = rows('workoutProgress', optional: version < 4);
      final suppliedOwners = <String>{
        for (final r in [
          ...rows('splits', optional: version < 3),
          ...planRows,
          ...sessionRows,
          ...blockRows,
          ...weekRows,
          ...progressRows,
        ])
          if (r['userId'] is String) r['userId'] as String,
      };
      if (suppliedOwners.length > 1 ||
          (source != null && suppliedOwners.any((id) => id != source))) {
        throw const FormatException('Conflicting account ownership.');
      }
      final inputOwner = source ?? suppliedOwners.firstOrNull;
      final plans =
          planRows.map((r) {
            final plan = WorkoutPlan.fromJson(r);
            plan.id ??= _uuid.v4();
            if (version < 3) plan.splitId = active;
            return plan;
          }).toList();
      final byPlan = {for (final p in plans) p.id: p};
      final sessions =
          sessionRows.map((r) {
            final session = WorkoutSession.fromJson(r);
            session.id ??= _uuid.v4();
            if (version < 3) {
              session.splitId = active;
            } else if (version < 4 && session.splitId == null) {
              session.splitId = byPlan[session.planId]?.splitId ?? active;
            }
            return session;
          }).toList();
      var graph = TrainingBlockGraph(
        ownerId: inputOwner,
        activeSplitId: active,
        splits: splits,
        plans: plans,
        sessions: sessions,
        blocks: blockRows.map(TrainingBlock.fromJson).toList(),
        weeks: weekRows.map(TrainingWeek.fromJson).toList(),
        progress: progressRows.map(WorkoutProgress.fromJson).toList(),
      ).ownedBy(inputOwner);
      if (version < 5) {
        graph = TrainingBlockMigration.prepareGraph(graph);
      } else {
        if (graph.blocks.any((b) => b.plannedWeekCount == null) ||
            graph.progress.any((p) => p.availableWeekIds == null)) {
          throw const FormatException(
            'Backup is missing block duration or available weeks.',
          );
        }
        graph.validate();
      }
      if (source == null || source != userId) {
        graph = graph.remap(ownerId: userId);
      } else {
        graph = graph.ownedBy(userId);
      }
      graph.validate();
      return ImportResult.success(
        graph: graph,
        settings: Map<String, dynamic>.from(parsed['settings'] as Map),
        version: version,
        sourceAccountId: source,
      );
    } catch (error) {
      return ImportResult.invalid(
        error is FormatException
            ? error.message.toString()
            : 'Invalid plan, session, or training structure data',
      );
    }
  }
}
