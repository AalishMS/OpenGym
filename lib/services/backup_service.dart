import 'dart:convert';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';

class ExportResult {
  final String jsonString;
  final String fileName;

  ExportResult({required this.jsonString, required this.fileName});
}

class ImportResult {
  final bool success;
  final String? errorMessage;
  final int? version;
  final List<WorkoutPlan>? plans;
  final List<WorkoutSession>? sessions;
  final Map<String, dynamic>? settings;

  ImportResult._(
      {required this.success,
      this.errorMessage,
      this.version,
      this.plans,
      this.sessions,
      this.settings});

  factory ImportResult.success(List<WorkoutPlan> plans,
          List<WorkoutSession> sessions, Map<String, dynamic> settingsMap) =>
      ImportResult._(
          success: true,
          plans: plans,
          sessions: sessions,
          settings: settingsMap);

  factory ImportResult.invalid(String message) =>
      ImportResult._(success: false, errorMessage: message);

  factory ImportResult.versionMismatch(int version) =>
      ImportResult._(
          success: false,
          errorMessage: 'Unsupported backup version: $version',
          version: version);
}

class BackupService {
  static const int _currentVersion = 1;

  static ExportResult exportData({
    required List<WorkoutPlan> plans,
    required List<WorkoutSession> sessions,
    required Map<String, dynamic> settings,
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final data = {
      'version': _currentVersion,
      'exportedAt': now.toIso8601String(),
      'settings': settings,
      'workoutPlans': plans.map((p) => p.toJson()).toList(),
      'workoutSessions': sessions.map((s) => s.toJson()).toList(),
    };

    return ExportResult(
      jsonString: const JsonEncoder.withIndent('  ').convert(data),
      fileName: 'gymapp_backup_$dateStr.json',
    );
  }

  static ImportResult importData(String jsonString) {
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return ImportResult.invalid('File is not valid JSON');
    }

    final version = parsed['version'];
    if (version is! int) {
      return ImportResult.invalid('File is not valid JSON');
    }
    if (version != _currentVersion) {
      return ImportResult.versionMismatch(version);
    }

    final plansRaw = parsed['workoutPlans'];
    final sessionsRaw = parsed['workoutSessions'];
    final settingsRaw = parsed['settings'];
    if (plansRaw is! List || sessionsRaw is! List || settingsRaw is! Map) {
      return ImportResult.invalid('Invalid plan or session data');
    }
    final settingsMap = settingsRaw.cast<String, dynamic>();

    try {
      final plans = plansRaw
          .map((p) => WorkoutPlan.fromJson(p as Map<String, dynamic>))
          .toList();
      final sessions = sessionsRaw
          .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
          .toList();
      return ImportResult.success(plans, sessions, settingsMap);
    } catch (_) {
      return ImportResult.invalid('Invalid plan or session data');
    }
  }
}
