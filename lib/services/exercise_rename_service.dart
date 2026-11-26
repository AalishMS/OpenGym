import '../models/exercise_definition.dart';
import 'exercise_catalog.dart';
import 'hive_service.dart';
import 'sync_service.dart';

/// How much of the account's training uses one movement.
class ExerciseUsage {
  /// Live plans with at least one occurrence of the movement.
  final int plans;

  /// Live workouts, drafts and logs alike, with at least one occurrence.
  final int workouts;

  const ExerciseUsage({this.plans = 0, this.workouts = 0});

  bool get isEmpty => plans == 0 && workouts == 0;
}

/// Renames and merges movements for the whole account.
///
/// A movement has one name, kept in the catalog (see `docs/exercises.md`).
/// Plans, workouts, history and Stats show that name for every occurrence
/// through `ExerciseCatalog.label`, so renaming writes one catalog row and no
/// plan or workout: the occurrences keep their `exerciseId`, sets and stored
/// name snapshot, and simply show the new name.
///
/// A name another movement already goes by means the two are the same
/// movement, so the caller offers [merge] instead: the source redirects to
/// the target, every occurrence of either shows the target's name, and their
/// history, records and Previous values combine. A merge cannot be undone.
class ExerciseRenameService {
  ExerciseRenameService._();

  /// Saved names drop surrounding and repeated whitespace.
  static String canonicalName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Null when [to] is an acceptable name.
  static String? validationMessage(String to) {
    final name = canonicalName(to);
    if (name.isEmpty) return 'Enter an exercise name.';
    if (name.length > 100) return 'Use an exercise name of 1–100 characters.';
    return null;
  }

  /// The movement other than [exerciseId] that already goes by [to].
  static ExerciseDefinition? nameOwner(String exerciseId, String to) =>
      ExerciseCatalog.nameOwner(exerciseId, canonicalName(to));

  /// How many of [userId]'s live plans and workouts use [exerciseId].
  static ExerciseUsage usage(String exerciseId, {String? userId}) =>
      usageByExercise(userId: userId)[ExerciseCatalog.canonicalId(
        exerciseId,
      )] ??
      const ExerciseUsage();

  /// Usage of every movement [userId] trains, by canonical ID, across all
  /// splits.
  static Map<String, ExerciseUsage> usageByExercise({String? userId}) {
    final plans = <String, int>{}, workouts = <String, int>{};
    for (final plan in HiveService.getAllPlansRaw()) {
      if (plan.deletedAt != null || plan.userId != userId) continue;
      for (final id in {
        for (final e in plan.exercises)
          ExerciseCatalog.identity(e.name, e.exerciseId),
      }) {
        plans[id] = (plans[id] ?? 0) + 1;
      }
    }
    for (final session in HiveService.getAllSessionsRaw()) {
      if (session.deletedAt != null || session.userId != userId) continue;
      for (final id in {
        for (final e in session.exercises)
          ExerciseCatalog.identity(e.name, e.exerciseId),
      }) {
        workouts[id] = (workouts[id] ?? 0) + 1;
      }
    }
    return {
      for (final id in {...plans.keys, ...workouts.keys})
        id: ExerciseUsage(plans: plans[id] ?? 0, workouts: workouts[id] ?? 0),
    };
  }

  /// Renames movement [exerciseId] to [to] everywhere. [currentName] is what
  /// the occurrence is called, used only to record a movement the catalog
  /// does not know yet before renaming it.
  ///
  /// Throws a [FormatException] for an invalid name or one another movement
  /// already goes by (see [nameOwner]).
  static Future<void> rename({
    required String exerciseId,
    required String currentName,
    required String to,
    String? userId,
  }) async {
    if (validationMessage(to) case final message?) {
      throw FormatException(message);
    }
    final name = canonicalName(to);
    await SyncService.instance.runExclusiveLocalMutation(() async {
      final id = ExerciseCatalog.canonicalId(exerciseId);
      await ExerciseCatalog.ensure(currentName, exerciseId: id, userId: userId);
      await ExerciseCatalog.rename(id, name, userId: userId);
    });
    SyncService.instance.notifyLocalChange();
  }

  /// Merges movement [sourceId] into [targetId]: [sourceId] redirects there
  /// for good, so both show the target's name and share one history.
  static Future<void> merge({
    required String sourceId,
    required String targetId,
    String? userId,
  }) async {
    await SyncService.instance.runExclusiveLocalMutation(() async {
      await ExerciseCatalog.merge(sourceId, targetId, userId: userId);
    });
    SyncService.instance.notifyLocalChange();
  }
}
