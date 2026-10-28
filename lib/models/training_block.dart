import 'package:hive/hive.dart';

part 'training_block.g.dart';

@HiveType(typeId: 8)
class TrainingBlock extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String splitId;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final int position;

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

  TrainingBlock({
    required this.id,
    required this.splitId,
    required this.name,
    required this.position,
    required this.createdAt,
    this.userId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
  });

  TrainingBlock copyWith({
    String? id,
    String? splitId,
    String? name,
    int? position,
    DateTime? createdAt,
    Object? userId = _notProvided,
    Object? updatedAt = _notProvided,
    Object? deletedAt = _notProvided,
    Object? dirty = _notProvided,
  }) => TrainingBlock(
    id: id ?? this.id,
    splitId: splitId ?? this.splitId,
    name: name ?? this.name,
    position: position ?? this.position,
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
    'name': name,
    'position': position,
    'createdAt': createdAt.toIso8601String(),
    'userId': userId,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory TrainingBlock.fromJson(Map<String, dynamic> json) {
    return TrainingBlock(
      id: json['id'] as String,
      splitId: json['splitId'] as String,
      name: json['name'] as String,
      position: json['position'] as int,
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
