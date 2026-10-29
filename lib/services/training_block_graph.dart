import 'package:uuid/uuid.dart';

import '../models/completion_transition.dart';
import '../models/split.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_plan.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../utils/training_block_identity.dart';
import 'training_week_choices.dart';

/// A validated value used by normalization, backup and replacement recovery.
/// It has no storage, cache, or notification responsibilities.
class TrainingBlockGraph {
  final String? ownerId;
  final String? activeSplitId;
  final List<Split> splits;
  final List<WorkoutPlan> plans;
  final List<WorkoutSession> sessions;
  final List<TrainingBlock> blocks;
  final List<TrainingWeek> weeks;
  final List<WorkoutProgress> progress;
  static const _uuid = Uuid();

  const TrainingBlockGraph({
    required this.ownerId,
    this.activeSplitId,
    required this.splits,
    required this.plans,
    required this.sessions,
    this.blocks = const [],
    this.weeks = const [],
    this.progress = const [],
  });

  TrainingBlockGraph copyWith({
    Object? ownerId = _unset,
    String? activeSplitId,
    List<Split>? splits,
    List<WorkoutPlan>? plans,
    List<WorkoutSession>? sessions,
    List<TrainingBlock>? blocks,
    List<TrainingWeek>? weeks,
    List<WorkoutProgress>? progress,
  }) => TrainingBlockGraph(
    ownerId: identical(ownerId, _unset) ? this.ownerId : ownerId as String?,
    activeSplitId: activeSplitId ?? this.activeSplitId,
    splits: splits ?? this.splits,
    plans: plans ?? this.plans,
    sessions: sessions ?? this.sessions,
    blocks: blocks ?? this.blocks,
    weeks: weeks ?? this.weeks,
    progress: progress ?? this.progress,
  );

  /// New explicit structure uses random IDs; legacy normalization alone owns
  /// deterministic block/week identities.
  TrainingBlockGraph ensureNewStructure(String splitId) {
    if (blocks.any((b) => b.splitId == splitId && b.deletedAt == null)) {
      return this;
    }
    final now = DateTime.now();
    final block = TrainingBlock(
      id: _uuid.v4(),
      splitId: splitId,
      name: 'Block 1',
      plannedWeekCount: 1,
      position: 0,
      createdAt: now,
      updatedAt: now,
      userId: ownerId,
      dirty: true,
    );
    return copyWith(
      blocks: [...blocks, block],
      weeks: [
        ...weeks,
        TrainingWeek(
          id: _uuid.v4(),
          splitId: splitId,
          blockId: block.id,
          number: 1,
          createdAt: now,
          updatedAt: now,
          userId: ownerId,
          dirty: true,
        ),
      ],
    );
  }

  TrainingBlockGraph withStartingWeek(String planId, String weekId) {
    final plan =
        plans.where((p) => p.id == planId && p.deletedAt == null).single;
    TrainingWeek? selected;
    for (final block in blocks.where(
      (b) => b.splitId == plan.splitId && b.deletedAt == null,
    )) {
      selected =
          plannedTrainingWeeks(block, weeks)
              .where(
                (w) =>
                    w.id == weekId ||
                    lazyTrainingWeekId(block.splitId, block.id, w.number) ==
                        weekId,
              )
              .firstOrNull;
      if (selected != null) break;
    }
    if (selected == null ||
        weeks.any((w) => w.id == selected!.id && w.deletedAt != null)) {
      throw StateError('The starting week is unavailable.');
    }
    final week = selected;
    final allocated = weeks.any((w) => w.id == week.id);
    final now = DateTime.now();
    return copyWith(
      weeks: [
        ...weeks,
        if (!allocated)
          week.copyWith(createdAt: now, updatedAt: now, dirty: true),
      ],
      progress: [
        for (final p in progress)
          if (p.planId == planId)
            p.copyWith(
              activeWeekId: week.id,
              state: WorkoutProgressState.ready,
              availableWeekIds: {...?p.availableWeekIds, week.id}.toList(),
            )
          else
            p,
      ],
    );
  }

  TrainingBlockGraph explicitPlanRevisions(Set<String> newPlanIds) {
    final now = DateTime.now();
    return copyWith(
      progress: [
        for (final p in progress)
          if (newPlanIds.contains(p.planId))
            p.copyWith(revision: _uuid.v4(), updatedAt: now, dirty: true)
          else
            p,
      ],
    );
  }

  TrainingBlockGraph clearWorkouts({String? splitId}) {
    if (splitId != null &&
        !splits.any((s) => s.id == splitId && s.deletedAt == null)) {
      throw StateError('The split is unavailable.');
    }
    bool selected(String? id) => splitId == null || id == splitId;
    final now = DateTime.now();
    final blocks = [
      for (final b in this.blocks)
        if (selected(b.splitId) && b.deletedAt == null)
          b.copyWith(deletedAt: now, updatedAt: now, dirty: true)
        else
          b,
    ];
    final weeks = [
      for (final w in this.weeks)
        if (selected(w.splitId) && w.deletedAt == null)
          w.copyWith(deletedAt: now, updatedAt: now, dirty: true)
        else
          w,
    ];
    for (final split in splits.where(
      (s) => s.deletedAt == null && selected(s.id),
    )) {
      final block = TrainingBlock(
        id: _uuid.v4(),
        splitId: split.id,
        name: 'Block 1',
        position: 0,
        createdAt: now,
        updatedAt: now,
        userId: ownerId,
        dirty: true,
      );
      blocks.add(block);
      weeks.add(
        TrainingWeek(
          id: _uuid.v4(),
          splitId: split.id,
          blockId: block.id,
          number: 1,
          createdAt: now,
          updatedAt: now,
          userId: ownerId,
          dirty: true,
        ),
      );
    }
    return copyWith(
      blocks: blocks,
      weeks: weeks,
      plans: [
        for (final p in plans)
          if (selected(p.splitId) && p.deletedAt == null)
            p.copyWith(deletedAt: now, updatedAt: now, dirty: true)
          else
            p,
      ],
      sessions: [
        for (final s in sessions)
          if (selected(s.splitId) && s.deletedAt == null)
            s.copyWith(deletedAt: now, updatedAt: now, dirty: true)
          else
            s,
      ],
      progress: [
        for (final p in progress)
          if (selected(p.splitId) && p.deletedAt == null)
            p.copyWith(deletedAt: now, updatedAt: now, dirty: true)
          else
            p,
      ],
    );
  }

  void validate({
    bool allowLegacyLinks = false,
    bool allowLiveChildrenOfDeletedParents = false,
    bool allowUnowned = false,
  }) {
    void unique(Iterable<String?> ids, String label) {
      final values = ids.toList();
      if (values.any((id) => id == null || id.isEmpty) ||
          values.toSet().length != values.length) {
        throw FormatException('Invalid or duplicate $label IDs.');
      }
    }

    unique(splits.map((r) => r.id), 'split');
    unique(plans.map((r) => r.id), 'plan');
    unique(sessions.map((r) => r.id), 'session');
    unique(blocks.map((r) => r.id), 'block');
    unique(weeks.map((r) => r.id), 'week');
    unique(progress.map((r) => r.id), 'progress');
    final splitMap = {for (final r in splits) r.id: r};
    final planMap = {for (final r in plans) r.id: r};
    final blockMap = {for (final r in blocks) r.id: r};
    final weekMap = {for (final r in weeks) r.id: r};
    final liveSplits = splits.where((r) => r.deletedAt == null).toList();
    if (liveSplits.length > 5 ||
        liveSplits.map((s) => s.name.toLowerCase()).toSet().length !=
            liveSplits.length ||
        splits.any(
          (s) =>
              s.name.trim() != s.name || s.name.isEmpty || s.name.length > 24,
        )) {
      throw const FormatException('Invalid split names or count.');
    }
    if (activeSplitId != null &&
        (splitMap[activeSplitId] == null ||
            splitMap[activeSplitId]!.deletedAt != null)) {
      throw const FormatException('The active split is missing.');
    }
    bool deletedConflict(DateTime? child, DateTime? parent) =>
        !allowLiveChildrenOfDeletedParents && child == null && parent != null;
    void owner(String? value) {
      if (value != ownerId && !(allowUnowned && value == null)) {
        throw const FormatException(
          'The graph contains data from another owner.',
        );
      }
    }

    for (final s in splits) {
      owner(s.userId);
    }
    for (final p in plans) {
      owner(p.userId);
      final split = splitMap[p.splitId];
      if (split == null || deletedConflict(p.deletedAt, split.deletedAt)) {
        throw const FormatException('Conflicting plan split.');
      }
    }
    for (final b in blocks) {
      owner(b.userId);
      final split = splitMap[b.splitId];
      if (split == null ||
          deletedConflict(b.deletedAt, split.deletedAt) ||
          b.name.trim() != b.name ||
          b.name.isEmpty ||
          b.name.length > 40 ||
          (b.plannedWeekCount != null && b.plannedWeekCount! < 1)) {
        throw const FormatException('Conflicting training block.');
      }
    }
    for (final w in weeks) {
      owner(w.userId);
      final block = blockMap[w.blockId];
      if (w.number < 1 ||
          block == null ||
          block.splitId != w.splitId ||
          deletedConflict(w.deletedAt, block.deletedAt)) {
        throw const FormatException('Conflicting training week.');
      }
    }
    for (final s in sessions) {
      owner(s.userId);
      final split = splitMap[s.splitId];
      final plan = planMap[s.planId];
      if (split == null ||
          s.weekNumber < 1 ||
          deletedConflict(s.deletedAt, split.deletedAt) ||
          (plan != null && plan.splitId != s.splitId)) {
        throw const FormatException('Conflicting session split or plan.');
      }
      final week = weekMap[s.trainingWeekId];
      if (s.trainingWeekId == null) {
        if (!allowLegacyLinks) {
          throw const FormatException('Session has no training week.');
        }
      } else if (week == null ||
          week.splitId != s.splitId ||
          week.number != s.weekNumber ||
          deletedConflict(s.deletedAt, week.deletedAt)) {
        throw const FormatException('Conflicting session training week.');
      }
      if (s.completionTransition case final map?) {
        final transition = CompletionTransition.fromJson(map);
        final target = weekMap[transition.nextWeekId];
        if (!s.isCompleted ||
            transition.resultRevision != s.id ||
            transition.sourceWeekId != s.trainingWeekId ||
            week == null ||
            (transition.nextWeekId != null &&
                (target == null ||
                    target.blockId != week.blockId ||
                    target.splitId != week.splitId ||
                    target.id == week.id))) {
          throw const FormatException('Conflicting completion evidence.');
        }
      }
    }
    final liveProgressPlans = <String>{};
    for (final p in progress) {
      owner(p.userId);
      final plan = planMap[p.planId];
      final week = weekMap[p.activeWeekId];
      if (plan == null ||
          week == null ||
          plan.splitId != p.splitId ||
          week.splitId != p.splitId ||
          deletedConflict(p.deletedAt, plan.deletedAt) ||
          deletedConflict(p.deletedAt, week.deletedAt) ||
          ![
            WorkoutProgressState.ready,
            WorkoutProgressState.awaitingBoundary,
          ].contains(p.state)) {
        throw const FormatException('Conflicting workout progress.');
      }
      final available = p.availableWeekIds;
      if (available != null &&
          (!available.contains(p.activeWeekId) ||
              available.toSet().length != available.length ||
              available.any((id) => weekMap[id]?.splitId != p.splitId))) {
        throw const FormatException('Conflicting available training weeks.');
      }
      if (p.revision.isEmpty) {
        throw const FormatException('Missing progress revision.');
      }
      if (p.deletedAt == null && !liveProgressPlans.add(p.planId)) {
        throw const FormatException('Duplicate live workout progress.');
      }
    }
    if (!allowLegacyLinks) {
      if (plans.any(
        (p) => p.deletedAt == null && !liveProgressPlans.contains(p.id),
      )) {
        throw const FormatException('A live plan has no workout progress.');
      }
      final slots = <String>{};
      for (final week in weeks.where((w) => w.deletedAt == null)) {
        if (!slots.add('${week.blockId}:${week.number}')) {
          throw const FormatException('Duplicate live week number.');
        }
      }
      for (final split in liveSplits) {
        if (!blocks.any((b) => b.splitId == split.id && b.deletedAt == null)) {
          throw const FormatException('A split has no training block.');
        }
      }
      for (final block in blocks.where((b) => b.deletedAt == null)) {
        if (!weeks.any((w) => w.blockId == block.id && w.deletedAt == null)) {
          throw const FormatException('A training block has no weeks.');
        }
      }
    }
  }

  /// Snapshot metadata is explicit: the ordinary plan/session JSON intentionally
  /// omits owner and dirty flags, but recovery must preserve both.
  Map<String, dynamic> toJson() => {
    'ownerId': ownerId,
    'activeSplitId': activeSplitId,
    'splits': [
      for (final r in splits)
        {...r.toJson(), 'userId': r.userId, 'dirty': r.dirty},
    ],
    'plans': [
      for (final r in plans)
        {...r.toJson(), 'userId': r.userId, 'dirty': r.dirty},
    ],
    'sessions': [
      for (final r in sessions)
        {...r.toJson(), 'userId': r.userId, 'dirty': r.dirty},
    ],
    'blocks': [
      for (final r in blocks) {...r.toJson(), 'dirty': r.dirty},
    ],
    'weeks': [
      for (final r in weeks) {...r.toJson(), 'dirty': r.dirty},
    ],
    'progress': [
      for (final r in progress) {...r.toJson(), 'dirty': r.dirty},
    ],
  };

  factory TrainingBlockGraph.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
    return TrainingBlockGraph(
      ownerId: json['ownerId'] as String?,
      activeSplitId: json['activeSplitId'] as String?,
      splits: [
        for (final r in rows('splits'))
          Split.fromJson(r)
            ..userId = (r['userId'] as String?)
            ..dirty = r['dirty'] as bool?,
      ],
      plans: [
        for (final r in rows('plans'))
          WorkoutPlan.fromJson(r)
            ..userId = (r['userId'] as String?)
            ..dirty = r['dirty'] as bool?,
      ],
      sessions: [
        for (final r in rows('sessions'))
          WorkoutSession.fromJson(r)
            ..userId = (r['userId'] as String?)
            ..dirty = r['dirty'] as bool?,
      ],
      blocks: [
        for (final r in rows('blocks'))
          TrainingBlock.fromJson(r).copyWith(dirty: r['dirty'] as bool?),
      ],
      weeks: [
        for (final r in rows('weeks'))
          TrainingWeek.fromJson(r).copyWith(dirty: r['dirty'] as bool?),
      ],
      progress: [
        for (final r in rows('progress'))
          WorkoutProgress.fromJson(r).copyWith(dirty: r['dirty'] as bool?),
      ],
    );
  }

  TrainingBlockGraph ownedBy(String? owner) => copyWith(
    ownerId: owner,
    splits: [for (final r in splits) r.copyWith()..userId = owner],
    plans: [for (final r in plans) r.copyWith()..userId = owner],
    sessions: [for (final r in sessions) r.copyWith(userId: owner)],
    blocks: [for (final r in blocks) r.copyWith(userId: owner)],
    weeks: [for (final r in weeks) r.copyWith(userId: owner)],
    progress: [for (final r in progress) r.copyWith(userId: owner)],
  );

  /// Copies an imported graph into another account without borrowing any
  /// destination IDs. Historical dangling plan references remain dangling.
  TrainingBlockGraph remap({required String? ownerId}) {
    final splitIds = {for (final r in splits) r.id: _uuid.v4()};
    final planIds = {for (final r in plans) r.id!: _uuid.v4()};
    final sessionIds = {for (final r in sessions) r.id!: _uuid.v4()};
    final blockIds = {for (final r in blocks) r.id: _uuid.v4()};
    final weekIds = {for (final r in weeks) r.id: _uuid.v4()};
    final revisions = <String, String>{...sessionIds};
    for (final plan in plans) {
      revisions[initialProgressRevision(
        plan.splitId!,
        plan.id!,
      )] = initialProgressRevision(splitIds[plan.splitId]!, planIds[plan.id]!);
    }
    String revision(String value) =>
        revisions.putIfAbsent(value, () => _uuid.v4());
    String? planReference(String? id) =>
        id == null ? null : planIds.putIfAbsent(id, () => _uuid.v4());
    final copied = copyWith(
      ownerId: ownerId,
      activeSplitId: activeSplitId == null ? null : splitIds[activeSplitId],
      splits: [
        for (final r in splits)
          r.copyWith(id: splitIds[r.id])..userId = ownerId,
      ],
      plans: [
        for (final r in plans)
          r.copyWith(id: planIds[r.id], splitId: splitIds[r.splitId])
            ..userId = ownerId,
      ],
      blocks: [
        for (final r in blocks)
          r.copyWith(
            id: blockIds[r.id],
            splitId: splitIds[r.splitId],
            userId: ownerId,
          ),
      ],
      weeks: [
        for (final r in weeks)
          r.copyWith(
            id: weekIds[r.id],
            splitId: splitIds[r.splitId],
            blockId: blockIds[r.blockId],
            userId: ownerId,
          ),
      ],
      sessions: [
        for (final r in sessions)
          r.copyWith(
            id: sessionIds[r.id],
            splitId: splitIds[r.splitId],
            planId: planReference(r.planId),
            trainingWeekId: weekIds[r.trainingWeekId],
            userId: ownerId,
            completionTransition:
                r.completionTransition == null
                    ? null
                    : _remapTransition(
                      CompletionTransition.fromJson(r.completionTransition!),
                      sessionIds[r.id]!,
                      weekIds,
                      revision,
                    ).toJson(),
          ),
      ],
      progress: [
        for (final r in progress)
          r.copyWith(
            id: workoutProgressId(splitIds[r.splitId]!, planIds[r.planId]!),
            splitId: splitIds[r.splitId],
            planId: planIds[r.planId],
            activeWeekId: weekIds[r.activeWeekId],
            availableWeekIds:
                r.availableWeekIds?.map((id) => weekIds[id]!).toList(),
            revision: revision(r.revision),
            userId: ownerId,
          ),
      ],
    );
    return TrainingBlockGraph.fromJson(copied.toJson());
  }

  CompletionTransition _remapTransition(
    CompletionTransition value,
    String sessionId,
    Map<String, String> weeks,
    String Function(String) revision,
  ) => CompletionTransition(
    expectedRevision: revision(value.expectedRevision),
    sourceWeekId: weeks[value.sourceWeekId]!,
    nextWeekId: value.nextWeekId == null ? null : weeks[value.nextWeekId]!,
    resultRevision: sessionId,
    committedAt: value.committedAt,
  );
}

const _unset = Object();
