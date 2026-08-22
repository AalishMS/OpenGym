import 'dart:convert';
import 'package:uuid/uuid.dart';
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

  factory ImportResult.versionMismatch(int version) => ImportResult._(
      success: false,
      errorMessage: 'Unsupported backup version: $version',
      version: version);
}

class BackupService {
  static const int _currentVersion = 2;
  static const _uuid = Uuid();

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
    // Accept v1 (no ids) and v2 (with ids). v1 records are upgraded on import.
    if (version != 1 && version != _currentVersion) {
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
      final now = DateTime.now();
      final plans = plansRaw
          .map((p) => WorkoutPlan.fromJson(p as Map<String, dynamic>))
          .map((p) {
        p.id ??= _uuid.v4(); // v1 upgrade: assign id if missing
        p.updatedAt ??= now;
        p.dirty = true; // imported records need to sync up
        return p;
      }).toList();
      final sessions = sessionsRaw
          .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
          .map((s) {
        s.id ??= _uuid.v4();
        s.updatedAt ??= now;
        s.dirty = true;
        return s;
      }).toList();
      return ImportResult.success(plans, sessions, settingsMap);
    } catch (_) {
      return ImportResult.invalid('Invalid plan or session data');
    }
  }
}
