import '../data/exercise_library.dart';
import '../models/exercise.dart';
import '../models/exercise_template.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import 'hive_service.dart';
import 'sync_service.dart';

/// What renaming an exercise everywhere in a split would touch.
class ExerciseRenameImpact {
  /// Live plans with at least one matching exercise.
  final int plans;

  /// Live workouts, drafts and logs alike, with at least one matching exercise.
  final int workouts;

  /// The new name already exists in the split, so the two histories combine.
  final bool merges;

  const ExerciseRenameImpact({
    required this.plans,
    required this.workouts,
    required this.merges,
  });

  bool get isEmpty => plans == 0 && workouts == 0;
}

/// Renames an exercise across one split.
///
/// Exercises are identified by name, so renaming one inside a single workout
/// splits its history, its *Previous* values and its records. This rewrites
/// the name in every live plan and every live workout of the split instead.
/// Renaming to a name the split already uses is a merge: the histories
/// combine simply because they now share a name. A plan or workout holding
/// both names keeps both entries, which the app already supports by
/// occurrence.
class ExerciseRenameService {
  ExerciseRenameService._();

  /// Case-insensitive, ignoring surrounding and repeated whitespace.
  static String normalize(String name) => canonicalName(name).toLowerCase();

  /// Keep saved names consistent with the identity used by merge previews.
  static String canonicalName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// A rename keeps existing set values, so it cannot change their unit.
  /// Timed identity currently comes from the catalog name; changing to or
  /// from a timed name would reinterpret seconds as reps (or vice versa).
  static String? validationMessage({required String from, required String to}) {
    if (canonicalName(to).isEmpty) return 'Enter an exercise name.';
    if (ExerciseLibrary.isTimed(from) != ExerciseLibrary.isTimed(to)) {
      return 'Timed exercises need a timed exercise name. '
          'Use Replace exercise to change how an exercise is measured.';
    }
    return null;
  }

  /// Counts what [rename] would change without writing anything.
  static ExerciseRenameImpact impact({
    required String splitId,
    required String from,
    required String to,
  }) {
    final source = normalize(from);
    final target = normalize(to);
    final plans = _livePlans(splitId);
    final sessions = _liveSessions(splitId);
    final merges =
        target != source &&
        (plans.any(
              (p) => p.exercises.any((e) => normalize(e.name) == target),
            ) ||
            sessions.any(
              (s) => s.exercises.any((e) => normalize(e.name) == target),
            ));
    return ExerciseRenameImpact(
      plans:
          plans
              .where((p) => p.exercises.any((e) => normalize(e.name) == source))
              .length,
      workouts:
          sessions
              .where((s) => s.exercises.any((e) => normalize(e.name) == source))
              .length,
      merges: merges,
    );
  }

  /// Rewrites [from] to [to] in every live plan and workout of [splitId].
  ///
  /// Tombstones and other splits are left alone. Changed records are marked
  /// dirty with a fresh `updatedAt` and a sync is scheduled. The write runs
  /// under the sync gate so a pull cannot interleave with it. Returns what
  /// was changed.
  static Future<ExerciseRenameImpact> rename({
    required String splitId,
    required String from,
    required String to,
  }) async {
    final name = canonicalName(to);
    final error = validationMessage(from: from, to: name);
    if (error != null) throw ArgumentError(error);
    final source = normalize(from);
    final result = await SyncService.instance.runExclusiveLocalMutation(
      () async {
        final before = impact(splitId: splitId, from: from, to: name);
        final now = DateTime.now();
        final plans = <String, WorkoutPlan>{};
        for (final plan in _livePlans(splitId)) {
          if (!plan.exercises.any((e) => normalize(e.name) == source)) {
            continue;
          }
          plans[plan.id!] = plan.copyWith(
            exercises: [
              for (final exercise in plan.exercises)
                normalize(exercise.name) == source
                    ? ExerciseTemplate(
                      name: name,
                      sets: exercise.sets,
                      setTargets: exercise.setTargets,
                      note: exercise.note,
                    )
                    : exercise,
            ],
            updatedAt: now,
            dirty: true,
          );
        }
        final sessions = <String, WorkoutSession>{};
        for (final session in _liveSessions(splitId)) {
          if (!session.exercises.any((e) => normalize(e.name) == source)) {
            continue;
          }
          sessions[session.id!] = session.copyWith(
            exercises: [
              for (final exercise in session.exercises)
                normalize(exercise.name) == source
                    ? Exercise(
                      name: name,
                      sets: exercise.sets,
                      note: exercise.note,
                    )
                    : exercise,
            ],
            updatedAt: now,
            dirty: true,
          );
        }
        await HiveService.putPlansRaw(plans);
        await HiveService.putSessionsRaw(sessions);
        return before;
      },
    );
    if (!result.isEmpty) SyncService.instance.scheduleSync();
    return result;
  }

  static List<WorkoutPlan> _livePlans(String splitId) =>
      HiveService.getAllPlansRaw()
          .where(
            (p) => p.id != null && p.deletedAt == null && p.splitId == splitId,
          )
          .toList();

  static List<WorkoutSession> _liveSessions(String splitId) =>
      HiveService.getAllSessionsRaw()
          .where(
            (s) => s.id != null && s.deletedAt == null && s.splitId == splitId,
          )
          .toList();
}
