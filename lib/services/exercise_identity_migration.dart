import '../data/exercise_library.dart';
import '../models/exercise_definition.dart';
import 'exercise_catalog.dart';
import 'training_block_graph.dart';

/// Pure and repeatable: migration/import never consults another account's live
/// catalog, and never changes weights, repetitions, order, names, or timestamps.
class ExerciseIdentityMigration {
  static TrainingBlockGraph prepare(TrainingBlockGraph graph) {
    final definitions = {
      for (final d in ExerciseLibrary.definitions) d.id: d,
      for (final d in graph.exerciseDefinitions) d.id: d,
    };
    final stored = {for (final d in graph.exerciseDefinitions) d.id: d};
    final names = <String, Set<String>>{};
    void index(ExerciseDefinition d) {
      for (final name in [d.name, ...d.aliases]) {
        names.putIfAbsent(ExerciseCatalog.normalize(name), () => {}).add(d.id);
      }
    }

    definitions.values.forEach(index);
    String resolve(String name, String? id) {
      if (id == null) {
        final matches = names[ExerciseCatalog.normalize(name)];
        if (matches?.length == 1) id = matches!.single;
      }
      id ??= ExerciseCatalog.legacyId(name);
      if (!definitions.containsKey(id)) {
        final d = ExerciseDefinition(
          id: id,
          name: name.trim(),
          userId: graph.ownerId,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          dirty: true,
        );
        definitions[id] = d;
        stored[id] = d;
        index(d);
      }
      return id;
    }

    final plans = [
      for (final p in graph.plans)
        p.copyWith(
          dirty: p.exercises.any((e) => e.exerciseId == null) ? true : p.dirty,
          exercises: [
            for (final e in p.exercises)
              e.copyWith(exerciseId: resolve(e.name, e.exerciseId)),
          ],
        ),
    ];
    final sessions = [
      for (final s in graph.sessions)
        s.copyWith(
          dirty: s.exercises.any((e) => e.exerciseId == null) ? true : s.dirty,
          exercises: [
            for (final e in s.exercises)
              e.copyWith(exerciseId: resolve(e.name, e.exerciseId)),
          ],
        ),
    ];
    return graph.copyWith(
      plans: plans,
      sessions: sessions,
      exerciseDefinitions: stored.values.toList(),
    );
  }
}
