import 'package:hive/hive.dart';

part 'split.g.dart';

@HiveType(typeId: 6)
class Split extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  String? userId;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  DateTime? updatedAt;

  @HiveField(5)
  DateTime? deletedAt;

  @HiveField(6)
  bool? dirty;

  Split({
    required this.id,
    required this.name,
    required this.createdAt,
    this.userId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
  });

  Split copyWith({
    String? id,
    String? name,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? dirty,
  }) => Split(
    id: id ?? this.id,
    name: name ?? this.name,
    userId: userId ?? this.userId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    dirty: dirty ?? this.dirty,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Split.fromJson(Map<String, dynamic> json) => Split(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
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
