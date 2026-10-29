import 'package:hive/hive.dart';

part 'workout_progress.g.dart';

abstract final class WorkoutProgressState {
  static const ready = 'ready';
  static const awaitingBoundary = 'awaitingBoundary';
}

@HiveType(typeId: 10)
class WorkoutProgress extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String splitId;

  @HiveField(2)
  final String planId;

  @HiveField(3)
  final String activeWeekId;

  @HiveField(4)
  final String state;

  @HiveField(5)
  final String revision;

  @HiveField(6)
  String? userId;

  @HiveField(7)
  DateTime? updatedAt;

  @HiveField(8)
  DateTime? deletedAt;

  @HiveField(9)
  bool? dirty;

  /// Durable reached slots, independent of the split-wide allocated weeks.
  @HiveField(10)
  final List<String>? availableWeekIds;

  WorkoutProgress({
    required this.id,
    required this.splitId,
    required this.planId,
    required this.activeWeekId,
    required this.state,
    required this.revision,
    this.userId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
    this.availableWeekIds,
  }) : assert(
         state == WorkoutProgressState.ready ||
             state == WorkoutProgressState.awaitingBoundary,
       );

  WorkoutProgress copyWith({
    String? id,
    String? splitId,
    String? planId,
    String? activeWeekId,
    String? state,
    String? revision,
    List<String>? availableWeekIds,
    Object? userId = _notProvided,
    Object? updatedAt = _notProvided,
    Object? deletedAt = _notProvided,
    Object? dirty = _notProvided,
  }) => WorkoutProgress(
    id: id ?? this.id,
    splitId: splitId ?? this.splitId,
    planId: planId ?? this.planId,
    activeWeekId: activeWeekId ?? this.activeWeekId,
    availableWeekIds: availableWeekIds ?? this.availableWeekIds,
    state: state ?? this.state,
    revision: revision ?? this.revision,
    userId: identical(userId, _notProvided) ? this.userId : userId as String?,
    updatedAt:
        identical(updatedAt, _notProvided)
            ? this.updatedAt
            : updatedAt as DateTime?,
    deletedAt:
        identical(deletedAt, _notProvided)
            ? this.deletedAt
            : deletedAt as DateTime?,
    dirty: identical(dirty, _notProvided) ? this.dirty : dirty as bool?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'splitId': splitId,
    'planId': planId,
    'activeWeekId': activeWeekId,
    'availableWeekIds': availableWeekIds,
    'state': state,
    'revision': revision,
    'userId': userId,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory WorkoutProgress.fromJson(Map<String, dynamic> json) {
    if (![
      WorkoutProgressState.ready,
      WorkoutProgressState.awaitingBoundary,
    ].contains(json['state'])) {
      throw const FormatException('Invalid progress state.');
    }
    return WorkoutProgress(
      id: json['id'] as String,
      splitId: json['splitId'] as String,
      planId: json['planId'] as String,
      activeWeekId: json['activeWeekId'] as String,
      availableWeekIds: (json['availableWeekIds'] as List?)?.cast<String>(),
      state: json['state'] as String,
      revision: json['revision'] as String,
      userId: json['userId'] as String?,
      updatedAt:
          json['updatedAt'] == null
              ? null
              : DateTime.parse(json['updatedAt'] as String),
      deletedAt:
          json['deletedAt'] == null
              ? null
              : DateTime.parse(json['deletedAt'] as String),
    );
  }
}

const Object _notProvided = Object();
