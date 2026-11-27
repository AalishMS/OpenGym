import 'package:shared_preferences/shared_preferences.dart';

/// Installation-local tutorial choices, separate from exported app settings.
class TutorialPreferences {
  static const String introPendingKey = 'intro_pending_v1';
  static const String tourPendingKey = 'guided_tour_pending_v1';
  static const String exerciseReorderTipKey = 'exercise_reorder_tip_v1';

  /// Called before Hive migration so existing installations stay opted out.
  static Future<bool> loadIntroPending() async {
    final prefs = await SharedPreferences.getInstance();
    final pending =
        prefs.getBool(introPendingKey) ??
        !prefs.containsKey('idkey_migration_v1_done');
    if (!prefs.containsKey(tourPendingKey)) {
      await _save(prefs, tourPendingKey, pending);
    }
    await _save(prefs, introPendingKey, pending);
    return pending;
  }

  static Future<void> finishIntro({bool skipTutorial = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (skipTutorial) await _save(prefs, tourPendingKey, false);
    await _save(prefs, introPendingKey, false);
  }

  static Future<bool> isTourPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(tourPendingKey) ?? false;
  }

  /// Consume before showing: Skip, Back, or closing the app all count as seen.
  static Future<void> markTourSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await _save(prefs, tourPendingKey, false);
  }

  /// Whether to mention that an exercise can be held and dragged, recording
  /// it as mentioned. It is said once, the first time an exercise is moved
  /// from its menu, the moment someone is looking for a way to reorder.
  static Future<bool> takeExerciseReorderTip() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(exerciseReorderTipKey) ?? false) return false;
    await _save(prefs, exerciseReorderTipKey, true);
    return true;
  }

  /// Someone who has dragged an exercise needs no tip about it.
  static Future<void> markExerciseReorderLearned() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(exerciseReorderTipKey) ?? false) return;
    await _save(prefs, exerciseReorderTipKey, true);
  }

  static Future<void> _save(
    SharedPreferences prefs,
    String key,
    bool value,
  ) async {
    if (!await prefs.setBool(key, value)) {
      throw StateError('Could not save tutorial preference.');
    }
  }
}
