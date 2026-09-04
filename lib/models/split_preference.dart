import 'package:hive/hive.dart';

part 'split_preference.g.dart';

@HiveType(typeId: 7)
class SplitPreference extends HiveObject {
  @HiveField(0)
  final String userId;

  @HiveField(1)
  String activeSplitId;

  @HiveField(2)
  DateTime? updatedAt;

  @HiveField(3)
  bool? dirty;

  SplitPreference({
    required this.userId,
    required this.activeSplitId,
    this.updatedAt,
    this.dirty,
  });
}
