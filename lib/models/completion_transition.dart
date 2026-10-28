/// Durable evidence stored with a completed session, replayed at its original
/// revision and time. Hive stores the primitive map rather than a new adapter.
class CompletionTransition {
  final String expectedRevision;
  final String sourceWeekId;
  final String? nextWeekId;
  final String resultRevision;
  final DateTime committedAt;

  const CompletionTransition({
    required this.expectedRevision,
    required this.sourceWeekId,
    required this.nextWeekId,
    required this.resultRevision,
    required this.committedAt,
  });

  Map<String, dynamic> toJson() => {
    'expectedRevision': expectedRevision,
    'sourceWeekId': sourceWeekId,
    'nextWeekId': nextWeekId,
    'resultRevision': resultRevision,
    'committedAt': committedAt.toIso8601String(),
  };

  factory CompletionTransition.fromJson(Map<String, dynamic> json) {
    for (final key in [
      'expectedRevision',
      'sourceWeekId',
      'resultRevision',
      'committedAt',
    ]) {
      if (json[key] is! String || (json[key] as String).isEmpty) {
        throw FormatException('Invalid completion transition: $key');
      }
    }
    if (json['nextWeekId'] != null &&
        (json['nextWeekId'] is! String ||
            (json['nextWeekId'] as String).isEmpty)) {
      throw const FormatException('Invalid completion target.');
    }
    return CompletionTransition(
      expectedRevision: json['expectedRevision'] as String,
      sourceWeekId: json['sourceWeekId'] as String,
      nextWeekId: json['nextWeekId'] as String?,
      resultRevision: json['resultRevision'] as String,
      committedAt: DateTime.parse(json['committedAt'] as String),
    );
  }
}
