import 'package:hive/hive.dart';
import 'exercise.dart';

part 'workout_session.g.dart';

@HiveType(typeId: 4)
class WorkoutSession extends HiveObject {
  @HiveField(0)
  final DateTime date;

  @HiveField(1)
  final String planName;

  @HiveField(2)
  final List<Exercise> exercises;

  @HiveField(3)
  final int weekNumber;

  // --- Sync / identity metadata (nullable + non-final; see WorkoutPlan) ---
  @HiveField(4)
  String? id;

  @HiveField(5)
  String? userId;

  @HiveField(6)
  String? planId;

  @HiveField(7)
  DateTime? updatedAt;

  @HiveField(8)
  DateTime? deletedAt;

  @HiveField(9)
  bool? dirty;

  @HiveField(10)
  String? splitId;

  /// Missing values belong to sessions written before drafts existed.
  @HiveField(11, defaultValue: true)
  final bool isCompleted;

  @HiveField(12)
  final DateTime? startedAt;

  @HiveField(13)
  final DateTime? timerStartedAt;

  /// Null means that a legacy completed session has no recorded duration.
  @HiveField(14)
  final int? durationSeconds;

  WorkoutSession({
    required this.date,
    required this.planName,
    required this.exercises,
    this.weekNumber = 1,
    this.id,
    this.userId,
    this.planId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
    this.splitId,
    this.isCompleted = true,
    this.startedAt,
    this.timerStartedAt,
    this.durationSeconds,
  });

  bool get isTimerRunning => !isCompleted && timerStartedAt != null;

  bool get hasStarted => startedAt != null;

  int elapsedSeconds([DateTime? now]) {
    final accumulated = durationSeconds ?? 0;
    final runningSince = timerStartedAt;
    if (runningSince == null) return accumulated;
    final delta = (now ?? DateTime.now()).difference(runningSince).inSeconds;
    return accumulated + (delta < 0 ? 0 : delta);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'planName': planName,
    'planId': planId,
    'weekNumber': weekNumber,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'splitId': splitId,
    'isCompleted': isCompleted,
    'startedAt': startedAt?.toIso8601String(),
    'timerStartedAt': timerStartedAt?.toIso8601String(),
    'durationSeconds': durationSeconds,
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String?,
    date: DateTime.parse(json['date'] as String),
    planName: json['planName'] as String,
    planId: json['planId'] as String?,
    weekNumber: json['weekNumber'] as int? ?? 1,
    exercises:
        (json['exercises'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
    updatedAt:
        json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
    deletedAt:
        json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
    splitId: json['splitId'] as String?,
    isCompleted: json['isCompleted'] as bool? ?? true,
    startedAt:
        json['startedAt'] == null
            ? null
            : DateTime.parse(json['startedAt'] as String),
    timerStartedAt:
        json['timerStartedAt'] == null
            ? null
            : DateTime.parse(json['timerStartedAt'] as String),
    durationSeconds: json['durationSeconds'] as int?,
  );

  WorkoutSession copyWith({
    DateTime? date,
    String? planName,
    List<Exercise>? exercises,
    int? weekNumber,
    String? id,
    String? userId,
    String? planId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? dirty,
    String? splitId,
    bool? isCompleted,
    Object? startedAt = _notProvided,
    Object? timerStartedAt = _notProvided,
    Object? durationSeconds = _notProvided,
  }) {
    return WorkoutSession(
      date: date ?? this.date,
      planName: planName ?? this.planName,
      exercises: exercises ?? this.exercises,
      weekNumber: weekNumber ?? this.weekNumber,
      id: id ?? this.id,
      userId: userId ?? this.userId,
      planId: planId ?? this.planId,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
      splitId: splitId ?? this.splitId,
      isCompleted: isCompleted ?? this.isCompleted,
      startedAt:
          identical(startedAt, _notProvided)
              ? this.startedAt
              : startedAt as DateTime?,
      timerStartedAt:
          identical(timerStartedAt, _notProvided)
              ? this.timerStartedAt
              : timerStartedAt as DateTime?,
      durationSeconds:
          identical(durationSeconds, _notProvided)
              ? this.durationSeconds
              : durationSeconds as int?,
    );
  }
}

const Object _notProvided = Object();
