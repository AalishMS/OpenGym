import 'package:uuid/uuid.dart';

import '../../data/plan_colors.dart';
import '../../models/coach_proposal.dart';
import '../../models/workout_plan.dart';
import '../hive_service.dart';
import '../split_install_target.dart';
import '../sync_service.dart';

/// Points between writes where a test can inject a failure.
enum CoachApplyStage {
  /// Edited and new plans are written.
  plansWritten,

  /// Removed plans are tombstoned. Active-split proposals only.
  tombstonesWritten,

  /// The new split is written. New-split proposals only.
  splitWritten,

  /// The new split is active. New-split proposals only.
  preferenceWritten,
}

typedef CoachApplyHook = Future<void> Function(CoachApplyStage stage);

/// What applying a proposal did. Failures other than staleness throw.
sealed class CoachApplyOutcome {
  const CoachApplyOutcome();
}

/// The proposal was written, and the plans live in [splitId].
class CoachApplied extends CoachApplyOutcome {
  final String splitId;
  final String splitName;

  /// True when a new-split proposal reused the untouched `My Split`.
  final bool reusedDefaultSplit;

  const CoachApplied({
    required this.splitId,
    required this.splitName,
    this.reusedDefaultSplit = false,
  });
}

enum CoachStaleReason { activeSplitChanged, plansChanged }

/// The plans changed after the Coach saw them. Nothing was written; the UI
/// offers to ask again with the latest plans.
class CoachApplyStale extends CoachApplyOutcome {
  final CoachStaleReason reason;

  const CoachApplyStale(this.reason);
}

/// Writes a [ValidatedProposal] to Hive in one exclusive mutation, rolling
/// every write back if any of them fails. Never touches sessions: plan
/// targets are display-only.
class CoachApplier {
  static const Uuid _uuid = Uuid();

  final CoachApplyHook? applyHook;

  const CoachApplier({this.applyHook});

  Future<CoachApplyOutcome> apply(
    ValidatedProposal proposal, {
    required String userId,
  }) async {
    final outcome = await SyncService.instance.runExclusiveLocalMutation(() {
      final stale = staleReason(proposal.snapshot, userId: userId);
      if (stale != null) return Future.value(CoachApplyStale(stale));
      return switch (proposal.target) {
        CoachTarget.activeSplit => _applyToActiveSplit(proposal, userId),
        CoachTarget.newSplit => _applyToNewSplit(proposal, userId),
      };
    });
    if (outcome is CoachApplied) SyncService.instance.scheduleSync();
    return outcome;
  }

  /// Why [snapshot] no longer matches Hive, or null when it still does: the
  /// active split must be the same, with the same live plans at the same
  /// `updatedAt`.
  static CoachStaleReason? staleReason(
    CoachSnapshot snapshot, {
    required String userId,
  }) {
    if (HiveService.getActiveSplitId(userId) != snapshot.splitId) {
      return CoachStaleReason.activeSplitChanged;
    }
    final live = HiveService.getPlans(splitId: snapshot.splitId);
    final versions = snapshot.planVersions;
    if (live.length != versions.length ||
        live.any(
          (plan) =>
              !versions.containsKey(plan.id) ||
              versions[plan.id] != plan.updatedAt,
        )) {
      return CoachStaleReason.plansChanged;
    }
    return null;
  }

  Future<CoachApplyOutcome> _applyToActiveSplit(
    ValidatedProposal proposal,
    String userId,
  ) async {
    final splitId = proposal.snapshot.splitId;
    final now = DateTime.now();
    final live = HiveService.getPlans(splitId: splitId);
    final removedIds = {for (final plan in proposal.removedPlans) plan.id!};

    // Copies, not the live objects: Hive hands out the same instances the
    // snapshot holds, and rollback must put back exactly what was there.
    final originals = <String, WorkoutPlan>{};
    final written = <String, WorkoutPlan>{};
    final newIds = <String>[];

    var nextPosition = _nextPosition(live);
    final usedSlots = {
      for (final plan in live)
        if (!removedIds.contains(plan.id) && plan.planColor != null)
          planSlotOf(plan.planColor!),
    };
    var planCount = live.length - removedIds.length;

    for (final coachPlan in proposal.plans) {
      final existing = coachPlan.existing;
      final exercises = [
        for (final exercise in coachPlan.exercises) exercise.toTemplate(),
      ];
      if (existing != null) {
        final current = HiveService.getPlanById(existing.id!)!;
        originals[current.id!] = current.copyWith();
        written[current.id!] =
            current.copyWith(name: coachPlan.name, exercises: exercises)
              ..updatedAt = now
              ..dirty = true;
        continue;
      }
      final slot = _colorSlot(usedSlots, planCount);
      usedSlots.add(slot);
      planCount++;
      final id = _uuid.v4();
      newIds.add(id);
      written[id] = WorkoutPlan(
        id: id,
        userId: userId,
        splitId: splitId,
        updatedAt: now,
        dirty: true,
        name: coachPlan.name,
        position: nextPosition,
        planColor: kPlanColors[slot],
        exercises: exercises,
      );
      if (nextPosition != null) nextPosition++;
    }

    final tombstones = <String, WorkoutPlan>{};
    for (final id in removedIds) {
      final current = HiveService.getPlanById(id)!;
      originals[id] = current.copyWith();
      tombstones[id] =
          current.copyWith()
            ..deletedAt = now
            ..updatedAt = now
            ..dirty = true;
    }

    try {
      await HiveService.putPlansRaw(written);
      await applyHook?.call(CoachApplyStage.plansWritten);
      await HiveService.putPlansRaw(tombstones);
      await applyHook?.call(CoachApplyStage.tombstonesWritten);
    } catch (error) {
      await HiveService.deletePlansRaw(newIds);
      await HiveService.putPlansRaw(originals);
      rethrow;
    }

    return CoachApplied(
      splitId: splitId,
      splitName:
          HiveService.getSplitById(splitId)?.name ??
          proposal.snapshot.splitName,
    );
  }

  Future<CoachApplyOutcome> _applyToNewSplit(
    ValidatedProposal proposal,
    String userId,
  ) async {
    final target = SplitInstallTarget.prepare(
      requestedName: proposal.newSplitName!,
      userId: userId,
      maxSplits: proposal.snapshot.maxSplits,
      now: DateTime.now(),
    );

    final usedSlots = <int>{};
    final planMap = <String, WorkoutPlan>{};
    for (var index = 0; index < proposal.plans.length; index++) {
      final coachPlan = proposal.plans[index];
      final slot = _colorSlot(usedSlots, index);
      usedSlots.add(slot);
      final id = _uuid.v4();
      planMap[id] = WorkoutPlan(
        id: id,
        userId: userId,
        splitId: target.splitId,
        updatedAt: target.now,
        dirty: true,
        name: coachPlan.name,
        position: index,
        planColor: kPlanColors[slot],
        exercises: [
          for (final exercise in coachPlan.exercises) exercise.toTemplate(),
        ],
      );
    }

    try {
      await HiveService.putPlansRaw(planMap);
      await applyHook?.call(CoachApplyStage.plansWritten);
      await target.writeSplit();
      await applyHook?.call(CoachApplyStage.splitWritten);
      await target.writePreference();
      await applyHook?.call(CoachApplyStage.preferenceWritten);
    } catch (error) {
      await HiveService.deletePlansRaw(planMap.keys);
      await target.rollback();
      rethrow;
    }

    return CoachApplied(
      splitId: target.splitId,
      splitName: target.splitName,
      reusedDefaultSplit: target.reusedDefaultSplit,
    );
  }

  /// One past the split's highest position, 0 for an empty split, or null
  /// when any plan has no position. That matches the plan editor: a split
  /// still in legacy order keeps it, and new plans sort after every plan
  /// that has a position.
  static int? _nextPosition(List<WorkoutPlan> plans) {
    if (plans.isEmpty) return 0;
    if (plans.any((plan) => plan.position == null)) return null;
    return plans.map((plan) => plan.position!).reduce((a, b) => a > b ? a : b) +
        1;
  }

  /// The first colour slot not in [used], or, once every slot is taken, the
  /// slot after the last one handed out ([planCount] modulo the slot count).
  static int _colorSlot(Set<int> used, int planCount) {
    for (var slot = 0; slot < kPlanColors.length; slot++) {
      if (!used.contains(slot)) return slot;
    }
    return planCount % kPlanColors.length;
  }
}
