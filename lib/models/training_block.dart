import 'package:hive/hive.dart';

part 'training_block.g.dart';

/// How many weeks a new block is planned for unless the user chooses another
/// length. Shared by the create dialog and the preset installer.
const int kDefaultBlockWeeks = 4;

/// The longest a block can be created or extended to by choice. A block can
/// still pass this by appending weeks as it is trained.
const int kMaxBlockWeeks = 52;

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

  /// Intended duration; null identifies a pre-lazy block needing normalization.
  @HiveField(9)
  final int? plannedWeekCount;

  /// When [plannedWeekCount] last changed on purpose (create, extend, shorten).
  /// It is the duration's own clock: the newer clock wins, a tie keeps the
  /// larger count, and null means "before this field existed". Renames and
  /// reorders never touch it.
  @HiveField(10)
  final DateTime? plannedWeekCountUpdatedAt;

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
    this.plannedWeekCount,
    this.plannedWeekCountUpdatedAt,
  });

  TrainingBlock copyWith({
    String? id,
    String? splitId,
    String? name,
    int? position,
    DateTime? createdAt,
    int? plannedWeekCount,
    Object? plannedWeekCountUpdatedAt = _notProvided,
    Object? userId = _notProvided,
    Object? updatedAt = _notProvided,
    Object? deletedAt = _notProvided,
    Object? dirty = _notProvided,
  }) => TrainingBlock(
    id: id ?? this.id,
    splitId: splitId ?? this.splitId,
    name: name ?? this.name,
    plannedWeekCount: plannedWeekCount ?? this.plannedWeekCount,
    plannedWeekCountUpdatedAt:
        identical(plannedWeekCountUpdatedAt, _notProvided)
            ? this.plannedWeekCountUpdatedAt
            : plannedWeekCountUpdatedAt as DateTime?,
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
    'plannedWeekCount': plannedWeekCount,
    'plannedWeekCountUpdatedAt': plannedWeekCountUpdatedAt?.toIso8601String(),
    'position': position,
    'createdAt': createdAt.toIso8601String(),
    'userId': userId,
    'updatedAt': updatedAt?.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory TrainingBlock.fromJson(Map<String, dynamic> json) {
    if (json['plannedWeekCount'] != null &&
        (json['plannedWeekCount'] is! int ||
            (json['plannedWeekCount'] as int) < 1)) {
      throw const FormatException('Invalid planned block length.');
    }
    return TrainingBlock(
      id: json['id'] as String,
      splitId: json['splitId'] as String,
      name: json['name'] as String,
      plannedWeekCount: json['plannedWeekCount'] as int?,
      plannedWeekCountUpdatedAt:
          json['plannedWeekCountUpdatedAt'] == null
              ? null
              : DateTime.parse(json['plannedWeekCountUpdatedAt'] as String),
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

/// A block's length with the time it was last chosen.
typedef BlockDuration = ({int? count, DateTime? changedAt});

/// Resolves two versions of a block's duration, mirroring the server's
/// `keep_newest_row`: the newer clock wins; on a tie (including null against
/// null) the larger count wins; a null count never replaces a value. The
/// result is symmetric and idempotent, so replicas converge.
BlockDuration mergeBlockDuration(BlockDuration a, BlockDuration b) {
  if (a.count == null) {
    // Nothing to resolve; settle the clock the same way from either side.
    return b.count == null && _compareClock(a.changedAt, b.changedAt) >= 0
        ? a
        : b;
  }
  if (b.count == null) return a;
  final int cmp = _compareClock(a.changedAt, b.changedAt);
  if (cmp > 0) return a;
  if (cmp < 0) return b;
  return (
    count: a.count! >= b.count! ? a.count : b.count,
    changedAt: a.changedAt ?? b.changedAt,
  );
}

int _compareClock(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}

const Object _notProvided = Object();
