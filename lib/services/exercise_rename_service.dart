import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import 'exercise_catalog.dart';
import 'hive_service.dart';
import 'sync_service.dart';

/// What renaming one movement's labels across a split would touch.
class ExerciseRenameImpact {
  /// Live plans with at least one occurrence of the movement.
  final int plans;

  /// Live workouts, drafts and logs alike, with at least one occurrence.
  final int workouts;

  /// The catalog label of a *different* movement the new name already
  /// belongs to, if any. Renaming never merges identities; that is an
  /// explicit catalog merge in Settings → Manage exercises.
  final String? otherMovement;

  const ExerciseRenameImpact({
    required this.plans,
    required this.workouts,
    this.otherMovement,
  });

  bool get isEmpty => plans == 0 && workouts == 0;
}

/// Renames the label of one movement across a split.
///
/// Identity is the occurrence's stable `exerciseId` (see `docs/exercises.md`),
/// never its name snapshot. Renaming an occurrence therefore never splits its
/// history, Previous values, records or timed measurement; this service only
/// keeps the visible labels consistent. It rewrites the name snapshot of every
/// live plan and workout occurrence in the split that resolves to the same
/// canonical ID, keeping each `exerciseId` (filling a legacy null with the
/// resolved identity). A custom catalog movement owned by the account is also
/// relabelled through `ExerciseCatalog.rename`, so the picker and Stats agree;
/// bundled labels are permanent and keep their catalog name.
class ExerciseRenameService {
  ExerciseRenameService._();

  /// Saved labels drop surrounding and repeated whitespace.
  static String canonicalName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Null when [to] is an acceptable label.
  static String? validationMessage(String to) {
    final name = canonicalName(to);
    if (name.isEmpty) return 'Enter an exercise name.';
    if (name.length > 100) return 'Use an exercise name of 1–100 characters.';
    return null;
  }

  /// The canonical identity of an occurrence.
  static String identityOf(String name, String? exerciseId) =>
      ExerciseCatalog.identity(name, exerciseId);

  /// Counts what [rename] would change without writing anything.
  static ExerciseRenameImpact impact({
    required String splitId,
    required String exerciseId,
    required String to,
  }) {
    final id = ExerciseCatalog.canonicalId(exerciseId);
    final other = ExerciseCatalog.findByName(canonicalName(to));
    return ExerciseRenameImpact(
      plans:
          _livePlans(splitId)
              .where(
                (p) =>
                    p.exercises.any((e) => _matches(e.name, e.exerciseId, id)),
              )
              .length,
      workouts:
          _liveSessions(splitId)
              .where(
                (s) =>
                    s.exercises.any((e) => _matches(e.name, e.exerciseId, id)),
              )
              .length,
      otherMovement:
          other == null || ExerciseCatalog.canonicalId(other.id) == id
              ? null
              : other.name,
    );
  }

  /// Rewrites the label of movement [exerciseId] to [to] in every live plan
  /// and workout of [splitId], then relabels an owned custom catalog entry.
  ///
  /// Tombstones, other splits, sets, notes and targets are untouched. Changed
  /// rows are marked dirty with a fresh `updatedAt` under the sync gate, and a
  /// sync is scheduled. Returns what was changed.
  static Future<ExerciseRenameImpact> rename({
    required String splitId,
    required String exerciseId,
    required String to,
    String? userId,
  }) async {
    final error = validationMessage(to);
    if (error != null) throw ArgumentError(error);
    final name = canonicalName(to);
    final id = ExerciseCatalog.canonicalId(exerciseId);
    final result = await SyncService.instance.runExclusiveLocalMutation(
      () async {
        final before = impact(splitId: splitId, exerciseId: id, to: name);
        final now = DateTime.now();
        final plans = <String, WorkoutPlan>{};
        for (final plan in _livePlans(splitId)) {
          if (!plan.exercises.any((e) => _matches(e.name, e.exerciseId, id))) {
            continue;
          }
          plans[plan.id!] = plan.copyWith(
            exercises: [
              for (final e in plan.exercises)
                _matches(e.name, e.exerciseId, id)
                    ? e.copyWith(name: name, exerciseId: e.exerciseId ?? id)
                    : e,
            ],
            updatedAt: now,
            dirty: true,
          );
        }
        final sessions = <String, WorkoutSession>{};
        for (final session in _liveSessions(splitId)) {
          if (!session.exercises.any(
            (e) => _matches(e.name, e.exerciseId, id),
          )) {
            continue;
          }
          sessions[session.id!] = session.copyWith(
            exercises: [
              for (final e in session.exercises)
                _matches(e.name, e.exerciseId, id)
                    ? e.copyWith(name: name, exerciseId: e.exerciseId ?? id)
                    : e,
            ],
            updatedAt: now,
            dirty: true,
          );
        }
        await HiveService.putPlansRaw(plans);
        await HiveService.putSessionsRaw(sessions);
        await _renameCatalogEntry(id, name, userId);
        return before;
      },
    );
    SyncService.instance.scheduleSync();
    return result;
  }

  /// Relabels an owned, unmerged custom definition. Bundled labels are
  /// permanent, and a name another movement already uses stays with it.
  static Future<void> _renameCatalogEntry(
    String id,
    String name,
    String? userId,
  ) async {
    final definition = ExerciseCatalog.getById(id);
    if (definition == null ||
        definition.builtIn ||
        definition.userId != userId ||
        definition.mergedIntoId != null ||
        ExerciseCatalog.normalize(definition.name) ==
            ExerciseCatalog.normalize(name)) {
      return;
    }
    try {
      await ExerciseCatalog.rename(id, name, userId: userId);
    } on FormatException {
      // Another movement owns this label. Plans and logs keep the new
      // snapshot; identities stay separate until the user merges them.
    } on StateError {
      // The catalog changed hands or the entry was merged meanwhile. The
      // snapshots are still renamed; the catalog keeps its own label.
    }
  }

  static bool _matches(String name, String? exerciseId, String id) =>
      ExerciseCatalog.identity(name, exerciseId) == id;

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
