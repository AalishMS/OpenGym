import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_catalog.dart';
import 'exercise_rename_service.dart';
import 'hive_service.dart';

/// Keeps the names people gave bundled movements before a movement had one
/// name.
///
/// Every occurrence now shows its movement's catalog name
/// (`ExerciseCatalog.label`). Before that, a plan or workout showed the name
/// stored on the occurrence, and renaming a bundled movement could only
/// rewrite those stored names: bundled catalog names were permanent. Without
/// this step such a rename would seem to undo itself after the update.
///
/// Once per account, each bundled movement whose plans call it something else
/// takes that name (from the most recently saved plan, or the latest workout
/// when no plan has it). The account copy is stamped with the epoch, so any
/// rename made on purpose, on any device, wins over it. Movements the account
/// has already renamed or merged, custom movements (whose catalog name every
/// rename already kept up to date), and names another movement goes by are
/// left alone.
abstract final class ExerciseNameAdoption {
  /// Whether [name] is what a movement merged into [id] was called. Plans
  /// keep a merged movement's name until they are saved again; it is the
  /// name the user merged away from, not one they gave [id].
  static bool _mergedName(String id, String name) {
    final key = ExerciseCatalog.normalize(name);
    return ExerciseCatalog.all.any(
      (d) =>
          d.id != id &&
          ExerciseCatalog.canonicalId(d.id) == id &&
          [
            d.name,
            ...d.aliases,
          ].any((a) => ExerciseCatalog.normalize(a) == key),
    );
  }

  static String _doneKey(String? userId) =>
      'exercise_names_adopted_${userId ?? 'local'}';

  /// Runs [adopt] once for [userId]. It stays pending until the account has a
  /// plan on this device, so a fresh install adopts after its first pull.
  /// Failures are logged and retried at the next start.
  static Future<void> run({required String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_doneKey(userId)) == true) return;
      final hasPlans = HiveService.getAllPlansRaw().any(
        (p) => p.userId == userId && p.deletedAt == null,
      );
      if (!hasPlans) return;
      await adopt(userId: userId);
      await prefs.setBool(_doneKey(userId), true);
    } catch (error) {
      debugPrint('Could not keep exercise names: $error');
    }
  }

  /// Gives each bundled movement the name [userId]'s plans use for it, and
  /// returns how many were renamed.
  static Future<int> adopt({required String? userId}) async {
    final overridden = {for (final d in ExerciseCatalog.stored) d.id};
    final named = <String, ({String name, DateTime at})>{};
    void consider(String id, String name, DateTime at) {
      final current = named[id];
      if (current == null || at.isAfter(current.at)) {
        named[id] = (name: name, at: at);
      }
    }

    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final plan in HiveService.getAllPlansRaw()) {
      if (plan.userId != userId || plan.deletedAt != null) continue;
      for (final e in plan.exercises) {
        consider(
          ExerciseCatalog.identity(e.name, e.exerciseId),
          e.name,
          plan.updatedAt ?? epoch,
        );
      }
    }
    final fromPlans = {...named.keys};
    for (final session in HiveService.getAllSessionsRaw()) {
      if (session.userId != userId || session.deletedAt != null) continue;
      for (final e in session.exercises) {
        final id = ExerciseCatalog.identity(e.name, e.exerciseId);
        if (!fromPlans.contains(id)) consider(id, e.name, session.date);
      }
    }

    var renamed = 0;
    for (final MapEntry(key: id, value: (:name, at: _)) in named.entries) {
      final definition = ExerciseCatalog.getById(id);
      final wanted = ExerciseRenameService.canonicalName(name);
      if (definition == null ||
          !definition.builtIn ||
          overridden.contains(id) ||
          ExerciseCatalog.canonicalId(id) != id ||
          ExerciseRenameService.validationMessage(wanted) != null ||
          ExerciseCatalog.normalize(wanted) ==
              ExerciseCatalog.normalize(definition.name) ||
          ExerciseCatalog.nameOwner(id, wanted) != null ||
          _mergedName(id, wanted)) {
        continue;
      }
      try {
        await ExerciseCatalog.rename(
          id,
          wanted,
          userId: userId,
          updatedAt: epoch,
        );
        renamed++;
      } on Object catch (error) {
        // One movement that cannot be renamed never holds up the others.
        debugPrint('Could not keep the name $wanted for $id: $error');
      }
    }
    return renamed;
  }
}
