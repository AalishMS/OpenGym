import 'package:hive_flutter/hive_flutter.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise_template.dart';
import '../models/exercise.dart';
import '../models/set.dart';

class HiveService {
  static const String plansBox = 'workout_plans';
  static const String sessionsBox = 'workout_sessions';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());

    // Open boxes
    await Hive.openBox<WorkoutPlan>(plansBox);
    await Hive.openBox<WorkoutSession>(sessionsBox);
  }

  // Workout Plan operations
  static Box<WorkoutPlan> get _plansBox => Hive.box<WorkoutPlan>(plansBox);

  static List<WorkoutPlan> getPlans() {
    return _plansBox.values.toList();
  }

  static Future<void> addPlan(WorkoutPlan plan) async {
    await _plansBox.add(plan);
  }

  static Future<void> updatePlan(int index, WorkoutPlan plan) async {
    await _plansBox.putAt(index, plan);
  }

  static Future<void> deletePlan(int index) async {
    await _plansBox.deleteAt(index);
  }

  // Workout Session operations
  static Box<WorkoutSession> get _sessionsBox =>
      Hive.box<WorkoutSession>(sessionsBox);

  static List<WorkoutSession> getSessions() {
    return _sessionsBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static Future<void> addSession(WorkoutSession session) async {
    await _sessionsBox.add(session);
  }

  static Future<void> deleteSession(int index) async {
    await _sessionsBox.deleteAt(index);
  }

  static WorkoutSession? getLastSessionForExercise(String exerciseName) {
    final sessions = getSessions();
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
          return session;
        }
      }
    }
    return null;
  }

  static Exercise? getLastExerciseData(String exerciseName) {
    final session = getLastSessionForExercise(exerciseName);
    if (session == null) return null;
    for (var exercise in session.exercises) {
      if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
        return exercise;
      }
    }
    return null;
  }

  static List<WorkoutSession> getSessionsForPlan(String planName) {
    return getSessions()
        .where((s) => s.planName.toLowerCase() == planName.toLowerCase())
        .toList();
  }

  static List<int> getWeeksForPlan(String planName) {
    final sessions = getSessionsForPlan(planName);
    final weeks = sessions.map((s) => s.weekNumber).toSet().toList();
    weeks.sort();
    return weeks;
  }

  static WorkoutSession? getSessionForPlanAndWeek(
      String planName, int weekNumber) {
    final sessions = getSessionsForPlan(planName);
    for (var session in sessions) {
      if (session.weekNumber == weekNumber) {
        return session;
      }
    }
    return null;
  }

  static Set? getLastSetForExercise(String exerciseName) {
    final exercise = getLastExerciseData(exerciseName);
    if (exercise == null || exercise.sets.isEmpty) return null;
    return exercise.sets.last;
  }

  static double getExercisePR(String exerciseName) {
    final sessions = getSessions();
    double maxWeight = 0;
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
          for (var set in exercise.sets) {
            if (set.weight > maxWeight) {
              maxWeight = set.weight;
            }
          }
        }
      }
    }
    return maxWeight;
  }

  static List<String> getAllExerciseNames() {
    final sessions = getSessions();
    final names = <String>{};
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        names.add(exercise.name);
      }
    }
    return names.toList()..sort();
  }

  static Map<String, double> getAllExercisePRs() {
    final names = getAllExerciseNames();
    final prs = <String, double>{};
    for (var name in names) {
      prs[name] = getExercisePR(name);
    }
    return prs;
  }

  static List<Map<String, dynamic>> getExerciseProgression(
      String exerciseName) {
    final sessions = getSessions();
    final progression = <Map<String, dynamic>>[];

    for (var session in sessions) {
      for (var exercise in session.exercises) {
        if (exercise.name.toLowerCase() == exerciseName.toLowerCase() &&
            exercise.sets.isNotEmpty) {
          double maxWeight = 0;
          int totalVolume = 0;
          for (var set in exercise.sets) {
            if (set.weight > maxWeight) maxWeight = set.weight;
            totalVolume += (set.weight * set.reps).round();
          }
          progression.add({
            'date': session.date,
            'maxWeight': maxWeight,
            'totalVolume': totalVolume,
            'week': session.weekNumber,
          });
        }
      }
    }
    progression.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return progression;
  }

  static int getWorkoutsThisWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startDate =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    return getSessions().where((s) => s.date.isAfter(startDate)).length;
  }

  static Map<int, int> getWorkoutFrequency(int weeksBack) {
    final frequency = <int, int>{};
    final now = DateTime.now();

    for (int i = 0; i < weeksBack; i++) {
      frequency[i] = 0;
    }

    for (var session in getSessions()) {
      final daysDiff = now.difference(session.date).inDays;
      final weekIndex = daysDiff ~/ 7;
      if (weekIndex < weeksBack) {
        frequency[weekIndex] = (frequency[weekIndex] ?? 0) + 1;
      }
    }

    return frequency;
  }

  static Future<void> updateSession(int index, WorkoutSession session) async {
    await _sessionsBox.putAt(index, session);
  }

  static Future<void> clearAllPlans() async {
    await _plansBox.clear();
  }

  static Future<void> clearAllSessions() async {
    await _sessionsBox.clear();
  }

  static Future<void> renameSessionWeek(
      String planName, int oldWeek, int newWeek) async {
    final sessions = getSessionsForPlan(planName);
    for (var session in sessions) {
      if (session.weekNumber == oldWeek) {
        final index = _sessionsBox.values.toList().indexOf(session);
        await _sessionsBox.putAt(index, session.copyWith(weekNumber: newWeek));
      }
    }
  }

  static Future<void> replaceAllPlans(List<WorkoutPlan> plans) async {
    await _plansBox.clear();
    for (final plan in plans) {
      await _plansBox.add(plan);
    }
  }

  static Future<void> replaceAllSessions(List<WorkoutSession> sessions) async {
    await _sessionsBox.clear();
    for (final session in sessions) {
      await _sessionsBox.add(session);
    }
  }

  static Future<void> deleteSessionForPlanAndWeek(
      String planName, int weekNumber) async {
    final sessions = _sessionsBox.values
        .where((s) =>
            s.planName.toLowerCase() == planName.toLowerCase() &&
            s.weekNumber == weekNumber)
        .toList();
    for (var session in sessions) {
      await session.delete();
    }
  }
}
