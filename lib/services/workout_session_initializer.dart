import 'package:uuid/uuid.dart';

import 'exercise_catalog.dart';
import '../models/exercise.dart';
import '../models/exercise_template.dart';
import '../models/set.dart' as gym;
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/training_week.dart';

/// Builds a session only when the caller has no saved data for the requested
/// plan and week.
///
/// A new week starts from [initialize]'s `lastSession`, the plan's most recent
/// logged workout before it: the same exercises in the same order, including
/// any added, removed, replaced or reordered there. Edits made in the plan
/// since that workout was built still arrive, because the workout remembers
/// the plan lineup it started from (`WorkoutSession.planExerciseIds`):
///
/// - an exercise the plan gained since is added after its neighbour in the
///   plan, and one the plan lost since is dropped;
/// - when the plan's own order changed since, the plan's order wins and the
///   workout's own additions stay after the exercise they followed;
/// - anything the workout changed that the plan did not keeps the workout's
///   version.
///
/// A workout logged before lineups were recorded cannot tell those apart. Its
/// own lineup carries over as it is, and if the plan was saved after it, an
/// exercise only the plan has counts as added to the plan since, so a plan
/// edit is never left out of every later week.
///
/// With no earlier log the plan is the lineup. Set values come from
/// `previousSession` (the resolver's inheritance source) while `copySets` is
/// on, then from plan targets, then from the last workout; with `copySets` off
/// a plan exercise opens with its targets and any other with as many blank
/// sets as it had last time.
class WorkoutSessionInitializer {
  static WorkoutSession initialize({
    required WorkoutPlan plan,
    required TrainingWeek week,
    WorkoutSession? existingSession,
    WorkoutSession? previousSession,
    WorkoutSession? lastSession,
    bool copySets = true,
    DateTime? now,
  }) {
    if (existingSession != null) return existingSession;
    if (plan.splitId != week.splitId) {
      throw ArgumentError('The week belongs to another split.');
    }
    bool usable(WorkoutSession? s) =>
        s != null &&
        s.planId == plan.id &&
        s.splitId == plan.splitId &&
        s.isCompleted &&
        s.deletedAt == null;
    final setSource =
        copySets && usable(previousSession) ? previousSession : null;
    final last =
        usable(lastSession)
            ? lastSession
            : usable(previousSession)
            ? previousSession
            : null;

    final planKeys = [
      for (final t in plan.exercises)
        ExerciseCatalog.identity(t.name, t.exerciseId),
    ];
    final templates = <String, ExerciseTemplate>{
      for (final (i, key) in _occurrences(planKeys).indexed)
        key: plan.exercises[i],
    };
    final sets = _Occurrences(setSource?.exercises ?? const []);

    final List<_Entry> lineup =
        last == null
            ? [
              for (final (i, key) in _occurrences(planKeys).indexed)
                _Entry(key, template: plan.exercises[i]),
            ]
            : _carry(
              last,
              planKeys,
              templates,
              planSavedSince:
                  plan.updatedAt?.isAfter(last.updatedAt ?? last.date) ?? false,
            );

    final exercises = <Exercise>[
      for (final entry in lineup)
        _build(entry, templates[entry.key], sets.take(entry.key), copySets),
    ];
    return WorkoutSession(
      id: const Uuid().v4(),
      date: now ?? DateTime.now(),
      planName: plan.name,
      planId: plan.id,
      splitId: plan.splitId,
      userId: plan.userId,
      trainingWeekId: week.id,
      weekNumber: week.number,
      exercises: exercises,
      isCompleted: false,
      durationSeconds: 0,
      planExerciseIds: List.unmodifiable(planKeys),
    );
  }

  /// The last workout's lineup with the plan's edits since applied.
  static List<_Entry> _carry(
    WorkoutSession last,
    List<String> planKeys,
    Map<String, ExerciseTemplate> templates, {
    required bool planSavedSince,
  }) {
    final plan = _occurrences(planKeys);
    final lastKeys = _occurrences([
      for (final e in last.exercises)
        ExerciseCatalog.identity(e.name, e.exerciseId),
    ]);
    final List<String> base;
    if (last.planExerciseIds case final recorded?) {
      base = _occurrences([
        for (final id in recorded) ExerciseCatalog.canonicalId(id),
      ]);
    } else if (planSavedSince) {
      // No recorded lineup, and the plan has been saved since: an exercise
      // only the plan has may have been added to it, so it is taken as new
      // rather than left out of every week from here on.
      final had = lastKeys.toSet();
      base = plan.where(had.contains).toList();
    } else {
      // No recorded lineup and an untouched plan: nothing changed since.
      base = plan;
    }
    final carried = <_Entry>[];
    final planSet = plan.toSet(), baseSet = base.toSet();
    for (final (i, key) in lastKeys.indexed) {
      // Dropped from the plan since this workout was built.
      if (baseSet.contains(key) && !planSet.contains(key)) continue;
      carried.add(_Entry(key, carried: last.exercises[i]));
    }
    final have = {for (final e in carried) e.key};
    // Added to the plan since, and not already in the workout.
    final added = [
      for (final key in plan)
        if (!baseSet.contains(key) && !have.contains(key)) key,
    ];

    final shared = baseSet.intersection(planSet);
    final reordered =
        !_sameOrder(
          base.where(shared.contains).toList(),
          plan.where(shared.contains).toList(),
        );
    if (!reordered) {
      for (final key in added) {
        // After its nearest plan neighbour still in the lineup, wherever the
        // workout moved that neighbour to; first when none of them is left.
        var index = -1;
        for (var at = plan.indexOf(key) - 1; at >= 0 && index < 0; at--) {
          index = carried.indexWhere((e) => e.key == plan[at]);
        }
        carried.insert(index + 1, _Entry(key, template: templates[key]));
      }
      return carried;
    }

    // The plan was reordered since: plan exercises take the plan's order, and
    // each exercise only this workout has follows the one it followed here.
    final byKey = {for (final e in carried) e.key: e};
    final ordered = <_Entry>[
      for (final key in plan)
        if (byKey[key] case final entry?)
          entry
        else if (added.contains(key))
          _Entry(key, template: templates[key]),
    ];
    final inPlan = {for (final e in ordered) e.key};
    String? anchor;
    final following = <String?, List<_Entry>>{};
    for (final entry in carried) {
      if (inPlan.contains(entry.key)) {
        anchor = entry.key;
      } else {
        following.putIfAbsent(anchor, () => []).add(entry);
      }
    }
    return [
      ...?following[null],
      for (final entry in ordered) ...[entry, ...?following[entry.key]],
    ];
  }

  static Exercise _build(
    _Entry entry,
    ExerciseTemplate? template,
    Exercise? setSource,
    bool copySets,
  ) {
    final carried = entry.carried;
    final List<gym.Set> sets;
    if (setSource != null && setSource.sets.isNotEmpty) {
      sets = _copy(setSource.sets);
    } else if (template != null) {
      sets = List.generate(template.sets, (i) {
        final target = template.targetAt(i);
        return gym.Set(
          reps: target?.reps ?? 0,
          weight: target?.weight ?? 0,
          rpe: target?.rpe,
        );
      });
    } else if (carried != null && copySets) {
      sets = _copy(carried.sets);
    } else {
      sets = [
        for (var i = 0; i < (carried?.sets.length ?? 0); i++)
          gym.Set(reps: 0, weight: 0),
      ];
    }
    final guidance = template?.note;
    return Exercise(
      name: ExerciseCatalog.displayName(
        entry.id,
        template?.name ?? carried?.name ?? '',
      ),
      exerciseId: carried?.exerciseId ?? template?.exerciseId ?? entry.id,
      // The plan's guidance wins; a note on an exercise it gives none for
      // carries over with the exercise.
      note:
          guidance != null && guidance.trim().isNotEmpty
              ? guidance
              : carried?.note,
      sets: sets,
    );
  }

  /// Values only: past set notes are not inherited.
  static List<gym.Set> _copy(List<gym.Set> sets) => [
    for (final set in sets)
      gym.Set(reps: set.reps, weight: set.weight, rpe: set.rpe),
  ];

  /// Keys each repeat of an identity apart: `id#0`, `id#1`, …
  static List<String> _occurrences(List<String> keys) {
    final seen = <String, int>{};
    return [
      for (final key in keys) '$key#${seen[key] = (seen[key] ?? -1) + 1}',
    ];
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One exercise of the new week, keyed by identity and occurrence, built
/// either from the last workout or from a plan template.
class _Entry {
  final String key;
  final Exercise? carried;
  final ExerciseTemplate? template;

  _Entry(this.key, {this.carried, this.template});

  /// The canonical identity without the occurrence suffix.
  String get id => key.substring(0, key.lastIndexOf('#'));
}

/// A set source's exercises by identity and occurrence.
class _Occurrences {
  final Map<String, Exercise> _byKey;

  _Occurrences(List<Exercise> exercises)
    : _byKey = {
        for (final (i, key)
            in WorkoutSessionInitializer._occurrences([
              for (final e in exercises)
                ExerciseCatalog.identity(e.name, e.exerciseId),
            ]).indexed)
          key: exercises[i],
      };

  Exercise? take(String key) => _byKey[key];
}
