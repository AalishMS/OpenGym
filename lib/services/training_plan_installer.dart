import '../models/split.dart';
import '../models/workout_plan.dart';
import 'hive_service.dart';
import 'training_block_migration.dart';
import 'training_block_restore.dart';

/// Called inside the caller's exclusive mutation. Explicit failures roll back;
/// interruption is recovered by the shared replacement journal at startup.
Future<void> installTrainingPlansUnderGate({
  required String ownerId,
  required Map<String, WorkoutPlan> plans,
  Map<String, String> startingWeekIds = const {},
  Split? split,
  int? initialBlockWeekCount,
  String? activeSplitId,
  Future<void> Function(String phase)? onPhase,
}) async {
  if (initialBlockWeekCount != null &&
      (split == null || initialBlockWeekCount < 1 || initialBlockWeekCount > 52)) {
    throw ArgumentError('An initial block needs a split and 1–52 weeks.');
  }
  await HiveService.recoverTrainingOperations(ownerId: ownerId);
  final current = HiveService.readTrainingGraph(ownerId: ownerId);
  if (initialBlockWeekCount != null &&
      (current.plans.any((p) => p.splitId == split!.id) ||
          current.sessions.any((s) => s.splitId == split!.id) ||
          current.progress.any((p) => p.splitId == split!.id))) {
    throw StateError('Only an unused split can set its initial block length.');
  }
  final planMap = {for (final p in current.plans) p.id!: p, ...plans};
  final splitMap = {
    for (final s in current.splits) s.id: s,
    if (split != null) split.id: split,
  };
  var input = current
      .copyWith(
        plans: planMap.values.toList(),
        splits: splitMap.values.toList(),
        activeSplitId: activeSplitId,
      )
      .ownedBy(ownerId);
  for (final p in plans.values.where((p) => p.deletedAt == null)) {
    input = input.ensureNewStructure(p.splitId!);
  }
  if (initialBlockWeekCount != null) {
    final block = input.blocks.singleWhere(
      (b) => b.splitId == split!.id && b.deletedAt == null,
    );
    input = input.copyWith(
      blocks: [
        for (final b in input.blocks)
          if (b.id == block.id)
            b.copyWith(
              plannedWeekCount: initialBlockWeekCount,
              updatedAt: DateTime.now(),
              dirty: true,
            )
          else
            b,
      ],
    );
  }
  var desired = TrainingBlockMigration.prepareGraph(
    input,
  ).explicitPlanRevisions(
    plans.keys.where((id) => !current.plans.any((p) => p.id == id)).toSet(),
  );
  for (final entry in startingWeekIds.entries) {
    final plan = plans[entry.key];
    if (plan == null || current.plans.any((p) => p.id == entry.key)) {
      throw StateError('Only added plans can choose a starting week.');
    }
    desired = desired.withStartingWeek(plan.id!, entry.value);
  }
  var started = false;
  final writer = TrainingBlockRestore(
    onPhase: (phase) async {
      started = true;
      await onPhase?.call(phase);
    },
  );
  try {
    await writer.replaceUnderGate(
      graph: desired,
      stampRecords: false,
      // onPhase is invoked only after a durable safety snapshot exists.
    );
  } catch (_) {
    // Validation before snapshot cannot have changed storage.
    // All staged callbacks run after that snapshot.
    if (started) await writer.rollbackUnderGate(ownerId);
    rethrow;
  }
}
