import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'coach_client.dart';

/// What the proxy last reported for a user: today's quota and the model that
/// answered. Kept so the Coach can show usage and the model as soon as it
/// opens, before this session has sent anything.
class CoachStatus {
  final CoachQuota? quota;
  final String? model;

  const CoachStatus({this.quota, this.model});

  Map<String, dynamic> toJson() => {
    if (quota != null) ...{
      'used': quota!.used,
      'limit': quota!.limit,
      if (quota!.resetsAt != null)
        'resetsAt': quota!.resetsAt!.toUtc().toIso8601String(),
    },
    if (model != null) 'model': model,
  };

  static CoachStatus fromJson(Object? json) {
    if (json is! Map) return const CoachStatus();
    final model = json['model'];
    return CoachStatus(
      quota: CoachQuota.tryParse(json),
      model: model is String && model.isNotEmpty ? model : null,
    );
  }
}

/// Reads and writes [CoachStatus] per user.
class CoachStatusStore {
  const CoachStatusStore();

  static String _key(String userId) => 'coach_status_$userId';

  Future<CoachStatus> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return const CoachStatus();
    try {
      return CoachStatus.fromJson(jsonDecode(raw));
    } on FormatException {
      return const CoachStatus();
    }
  }

  Future<void> save(String userId, CoachStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(status.toJson()));
  }
}
