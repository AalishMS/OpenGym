import 'package:hive/hive.dart';

part 'training_week.g.dart';

@HiveType(typeId: 9)
class TrainingWeek extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String splitId;

  @HiveField(2)
  final String blockId;

  @HiveField(3)
  final int number;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  String? userId;

  @HiveField(6)
  DateTime? updatedAt;

  @HiveField(7)
  DateTime? deletedAt;

  @HiveField(8)
  bool? dirty;

  TrainingWeek({
    required this.id,
    required this.splitId,
    required this.blockId,
    required this.number,
    required this.createdAt,
    this.userId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
  }) : assert(number > 0);

  TrainingWeek copyWith({
    String? id,
    String? splitId,
    String? blockId,
    int? number,
    DateTime? createdAt,
    Object? userId = _notProvided,
    Object? updatedAt = _notProvided,
    Object? deletedAt = _notProvided,
    Object? dirty = _notProvided,
  }) => TrainingWeek(
    id: id ?? this.id,
    splitId: splitId ?? this.splitId,
    blockId: blockId ?? this.blockId,
    number: number ?? this.number,
    createdAt: createdAt ?? this.createdAt,
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
    'blockId': blockId,
    'number': number,
    'createdAt': createdAt.toIso8601String(),
    'userId': userId,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory TrainingWeek.fromJson(Map<String, dynamic> json) {
    if (json['number'] is! int || (json['number'] as int) < 1) {
      throw const FormatException('Invalid training week number.');
    }
    return TrainingWeek(
      id: json['id'] as String,
      splitId: json['splitId'] as String,
      blockId: json['blockId'] as String,
      number: json['number'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
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
