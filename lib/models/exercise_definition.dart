/// A reusable movement. Workout entries keep their own sets and name snapshot.
class ExerciseDefinition {
  final String id;
  final String name;
  final List<String> aliases;
  final String category;
  final bool builtIn;
  final String? mergedIntoId;
  final String? userId;
  final DateTime? updatedAt;
  final bool dirty;

  const ExerciseDefinition({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.category = 'Custom',
    this.builtIn = false,
    this.mergedIntoId,
    this.userId,
    this.updatedAt,
    this.dirty = false,
  });

  ExerciseDefinition copyWith({
    String? name,
    List<String>? aliases,
    String? mergedIntoId,
    String? userId,
    DateTime? updatedAt,
    bool? dirty,
  }) => ExerciseDefinition(
    id: id,
    name: name ?? this.name,
    aliases: aliases ?? this.aliases,
    category: category,
    builtIn: builtIn,
    mergedIntoId: mergedIntoId ?? this.mergedIntoId,
    userId: userId ?? this.userId,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'aliases': aliases,
    'category': category,
    'builtIn': builtIn,
    'mergedIntoId': mergedIntoId,
    'userId': userId,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'dirty': dirty,
  };

  factory ExerciseDefinition.fromJson(Map<String, dynamic> json) {
    final value = ExerciseDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      aliases: (json['aliases'] as List? ?? []).cast<String>(),
      category: json['category'] as String? ?? 'Custom',
      builtIn: json['builtIn'] as bool? ?? false,
      mergedIntoId: json['mergedIntoId'] as String?,
      userId: json['userId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      dirty: json['dirty'] as bool? ?? false,
    );
    if (value.id.trim().isEmpty ||
        value.name.trim().isEmpty ||
        value.mergedIntoId == value.id ||
        value.aliases.any((a) => a.trim().isEmpty)) {
      throw const FormatException('Invalid exercise definition.');
    }
    return value;
  }
}
