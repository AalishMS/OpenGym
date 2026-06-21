import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise_template.dart';
import '../models/exercise.dart';
import '../models/set.dart';
import '../data/plan_colors.dart';
import '../services/hive_service.dart';

class SampleDataSeeder {
  static Future<void> seedIfEmpty() async {
    final plans = HiveService.getPlans();
    if (plans.isNotEmpty) return;

    await seedSampleData();
  }

  static Future<void> seedSampleData() async {
    await _createSamplePlans();
    await _createSampleSessions();
  }

  static Future<void> _createSamplePlans() async {
    final plans = [
      WorkoutPlan(
        name: 'Push Day',
        planColor: kPlanColors[0],
        exercises: [
          ExerciseTemplate(name: 'Bench Press', sets: 4),
          ExerciseTemplate(name: 'Incline Dumbbell Press', sets: 3),
          ExerciseTemplate(name: 'Overhead Press', sets: 3),
          ExerciseTemplate(name: 'Lateral Raise', sets: 3),
          ExerciseTemplate(name: 'Tricep Pushdown', sets: 3),
          ExerciseTemplate(name: 'Dumbbell Fly', sets: 2),
        ],
      ),
      WorkoutPlan(
        name: 'Pull Day',
        planColor: kPlanColors[1],
        exercises: [
          ExerciseTemplate(name: 'Deadlift', sets: 4),
          ExerciseTemplate(name: 'Barbell Row', sets: 4),
          ExerciseTemplate(name: 'Lat Pulldown', sets: 3),
          ExerciseTemplate(name: 'Seated Cable Row', sets: 3),
          ExerciseTemplate(name: 'Face Pull', sets: 3),
          ExerciseTemplate(name: 'Bicep Curl', sets: 3),
          ExerciseTemplate(name: 'Hammer Curl', sets: 2),
        ],
      ),
      WorkoutPlan(
        name: 'Leg Day',
        planColor: kPlanColors[2],
        exercises: [
          ExerciseTemplate(name: 'Squat', sets: 4),
          ExerciseTemplate(name: 'Romanian Deadlift', sets: 3),
          ExerciseTemplate(name: 'Leg Press', sets: 3),
          ExerciseTemplate(name: 'Leg Extension', sets: 3),
          ExerciseTemplate(name: 'Leg Curl', sets: 3),
          ExerciseTemplate(name: 'Calf Raise', sets: 4),
          ExerciseTemplate(name: 'Hip Thrust', sets: 3),
        ],
      ),
      WorkoutPlan(
        name: 'Upper Body',
        planColor: kPlanColors[3],
        exercises: [
          ExerciseTemplate(name: 'Bench Press', sets: 4),
          ExerciseTemplate(name: 'Barbell Row', sets: 4),
          ExerciseTemplate(name: 'Overhead Press', sets: 3),
          ExerciseTemplate(name: 'Pull-ups', sets: 3),
          ExerciseTemplate(name: 'Dumbbell Fly', sets: 3),
          ExerciseTemplate(name: 'Shrugs', sets: 3),
        ],
      ),
      WorkoutPlan(
        name: 'Full Body',
        planColor: kPlanColors[4],
        exercises: [
          ExerciseTemplate(name: 'Squat', sets: 3),
          ExerciseTemplate(name: 'Bench Press', sets: 3),
          ExerciseTemplate(name: 'Deadlift', sets: 3),
          ExerciseTemplate(name: 'Overhead Press', sets: 3),
          ExerciseTemplate(name: 'Barbell Row', sets: 3),
          ExerciseTemplate(name: 'Lateral Raise', sets: 2),
        ],
      ),
    ];

    for (var plan in plans) {
      await HiveService.addPlan(plan);
    }
  }

  static Future<void> _createSampleSessions() async {
    final now = DateTime.now();

    final sessions = [
      // Week 1 sessions
      WorkoutSession(
        date: now.subtract(const Duration(days: 34)),
        planName: 'Push Day',
        weekNumber: 1,
        exercises: [
          Exercise(name: 'Bench Press', sets: [
            Set(reps: 8, weight: 60, rpe: 7, note: 'First workout back'),
            Set(reps: 8, weight: 60, rpe: 7),
            Set(reps: 8, weight: 60, rpe: 8),
            Set(reps: 7, weight: 60, rpe: 9),
          ]),
          Exercise(name: 'Incline Dumbbell Press', sets: [
            Set(reps: 10, weight: 24, rpe: 7),
            Set(reps: 10, weight: 24, rpe: 8),
            Set(reps: 9, weight: 24, rpe: 9),
          ]),
          Exercise(name: 'Overhead Press', sets: [
            Set(reps: 8, weight: 40, rpe: 7),
            Set(reps: 8, weight: 40, rpe: 8),
            Set(reps: 7, weight: 40, rpe: 9),
          ]),
          Exercise(name: 'Lateral Raise', sets: [
            Set(reps: 12, weight: 8, rpe: 7),
            Set(reps: 12, weight: 8, rpe: 8),
            Set(reps: 11, weight: 8, rpe: 9),
          ]),
          Exercise(name: 'Tricep Pushdown', sets: [
            Set(reps: 12, weight: 25, rpe: 6),
            Set(reps: 12, weight: 25, rpe: 7),
            Set(reps: 11, weight: 25, rpe: 8),
          ]),
          Exercise(name: 'Dumbbell Fly', sets: [
            Set(reps: 12, weight: 16, rpe: 7),
            Set(reps: 12, weight: 16, rpe: 8),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 33)),
        planName: 'Pull Day',
        weekNumber: 1,
        exercises: [
          Exercise(name: 'Deadlift', sets: [
            Set(reps: 5, weight: 100, rpe: 7),
            Set(reps: 5, weight: 100, rpe: 8),
            Set(reps: 5, weight: 100, rpe: 9),
            Set(reps: 4, weight: 100, rpe: 10),
          ]),
          Exercise(name: 'Barbell Row', sets: [
            Set(reps: 8, weight: 60, rpe: 7),
            Set(reps: 8, weight: 60, rpe: 8),
            Set(reps: 7, weight: 60, rpe: 9),
            Set(reps: 7, weight: 60, rpe: 9),
          ]),
          Exercise(name: 'Lat Pulldown', sets: [
            Set(reps: 10, weight: 50, rpe: 7),
            Set(reps: 10, weight: 50, rpe: 7),
            Set(reps: 9, weight: 50, rpe: 8),
          ]),
          Exercise(name: 'Seated Cable Row', sets: [
            Set(reps: 10, weight: 45, rpe: 7),
            Set(reps: 10, weight: 45, rpe: 8),
            Set(reps: 9, weight: 45, rpe: 8),
          ]),
          Exercise(name: 'Face Pull', sets: [
            Set(reps: 15, weight: 15, rpe: 6),
            Set(reps: 15, weight: 15, rpe: 6),
            Set(reps: 15, weight: 15, rpe: 7),
          ]),
          Exercise(name: 'Bicep Curl', sets: [
            Set(reps: 12, weight: 12, rpe: 7),
            Set(reps: 12, weight: 12, rpe: 7),
            Set(reps: 11, weight: 12, rpe: 8),
          ]),
          Exercise(name: 'Hammer Curl', sets: [
            Set(reps: 10, weight: 10, rpe: 7),
            Set(reps: 10, weight: 10, rpe: 7),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 31)),
        planName: 'Leg Day',
        weekNumber: 1,
        exercises: [
          Exercise(name: 'Squat', sets: [
            Set(reps: 6, weight: 80, rpe: 7),
            Set(reps: 6, weight: 80, rpe: 8),
            Set(reps: 6, weight: 80, rpe: 9),
            Set(reps: 5, weight: 80, rpe: 9),
          ]),
          Exercise(name: 'Romanian Deadlift', sets: [
            Set(reps: 8, weight: 60, rpe: 7),
            Set(reps: 8, weight: 60, rpe: 8),
            Set(reps: 7, weight: 60, rpe: 9),
          ]),
          Exercise(name: 'Leg Press', sets: [
            Set(reps: 10, weight: 120, rpe: 7),
            Set(reps: 10, weight: 120, rpe: 8),
            Set(reps: 9, weight: 120, rpe: 9),
          ]),
          Exercise(name: 'Leg Extension', sets: [
            Set(reps: 12, weight: 40, rpe: 7),
            Set(reps: 12, weight: 40, rpe: 7),
            Set(reps: 11, weight: 40, rpe: 8),
          ]),
          Exercise(name: 'Leg Curl', sets: [
            Set(reps: 12, weight: 30, rpe: 6),
            Set(reps: 12, weight: 30, rpe: 7),
            Set(reps: 11, weight: 30, rpe: 7),
          ]),
          Exercise(name: 'Calf Raise', sets: [
            Set(reps: 15, weight: 60, rpe: 7),
            Set(reps: 15, weight: 60, rpe: 7),
            Set(reps: 15, weight: 60, rpe: 8),
            Set(reps: 14, weight: 60, rpe: 8),
          ]),
          Exercise(name: 'Hip Thrust', sets: [
            Set(reps: 10, weight: 80, rpe: 7),
            Set(reps: 10, weight: 80, rpe: 7),
            Set(reps: 10, weight: 80, rpe: 8),
          ]),
        ],
      ),
      // Week 2 sessions
      WorkoutSession(
        date: now.subtract(const Duration(days: 27)),
        planName: 'Push Day',
        weekNumber: 2,
        exercises: [
          Exercise(name: 'Bench Press', sets: [
            Set(reps: 8, weight: 62.5, rpe: 7),
            Set(reps: 8, weight: 62.5, rpe: 8),
            Set(reps: 7, weight: 62.5, rpe: 9),
            Set(reps: 6, weight: 62.5, rpe: 9, note: 'Getting stronger'),
          ]),
          Exercise(name: 'Incline Dumbbell Press', sets: [
            Set(reps: 10, weight: 26, rpe: 7),
            Set(reps: 10, weight: 26, rpe: 8),
            Set(reps: 9, weight: 26, rpe: 9),
          ]),
          Exercise(name: 'Overhead Press', sets: [
            Set(reps: 8, weight: 42.5, rpe: 7),
            Set(reps: 8, weight: 42.5, rpe: 8),
            Set(reps: 7, weight: 42.5, rpe: 9),
          ]),
          Exercise(name: 'Lateral Raise', sets: [
            Set(reps: 12, weight: 10, rpe: 7),
            Set(reps: 12, weight: 10, rpe: 8),
            Set(reps: 11, weight: 10, rpe: 9),
          ]),
          Exercise(name: 'Tricep Pushdown', sets: [
            Set(reps: 12, weight: 27.5, rpe: 7),
            Set(reps: 12, weight: 27.5, rpe: 7),
            Set(reps: 12, weight: 27.5, rpe: 8),
          ]),
          Exercise(name: 'Dumbbell Fly', sets: [
            Set(reps: 12, weight: 18, rpe: 7),
            Set(reps: 12, weight: 18, rpe: 8),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 26)),
        planName: 'Pull Day',
        weekNumber: 2,
        exercises: [
          Exercise(name: 'Deadlift', sets: [
            Set(reps: 5, weight: 105, rpe: 7, note: 'PR attempt'),
            Set(reps: 5, weight: 105, rpe: 8),
            Set(reps: 5, weight: 105, rpe: 9),
            Set(reps: 4, weight: 105, rpe: 10),
          ]),
          Exercise(name: 'Barbell Row', sets: [
            Set(reps: 8, weight: 62.5, rpe: 7),
            Set(reps: 8, weight: 62.5, rpe: 8),
            Set(reps: 7, weight: 62.5, rpe: 9),
            Set(reps: 7, weight: 62.5, rpe: 9),
          ]),
          Exercise(name: 'Lat Pulldown', sets: [
            Set(reps: 10, weight: 52.5, rpe: 7),
            Set(reps: 10, weight: 52.5, rpe: 8),
            Set(reps: 9, weight: 52.5, rpe: 8),
          ]),
          Exercise(name: 'Seated Cable Row', sets: [
            Set(reps: 10, weight: 47.5, rpe: 7),
            Set(reps: 10, weight: 47.5, rpe: 8),
            Set(reps: 9, weight: 47.5, rpe: 8),
          ]),
          Exercise(name: 'Face Pull', sets: [
            Set(reps: 15, weight: 17.5, rpe: 6),
            Set(reps: 15, weight: 17.5, rpe: 6),
            Set(reps: 15, weight: 17.5, rpe: 7),
          ]),
          Exercise(name: 'Bicep Curl', sets: [
            Set(reps: 12, weight: 14, rpe: 7),
            Set(reps: 12, weight: 14, rpe: 7),
            Set(reps: 11, weight: 14, rpe: 8),
          ]),
          Exercise(name: 'Hammer Curl', sets: [
            Set(reps: 10, weight: 12, rpe: 7),
            Set(reps: 10, weight: 12, rpe: 7),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 24)),
        planName: 'Leg Day',
        weekNumber: 2,
        exercises: [
          Exercise(name: 'Squat', sets: [
            Set(reps: 6, weight: 85, rpe: 7),
            Set(reps: 6, weight: 85, rpe: 8),
            Set(reps: 6, weight: 85, rpe: 9),
            Set(reps: 5, weight: 85, rpe: 9),
          ]),
          Exercise(name: 'Romanian Deadlift', sets: [
            Set(reps: 8, weight: 65, rpe: 7),
            Set(reps: 8, weight: 65, rpe: 8),
            Set(reps: 7, weight: 65, rpe: 9),
          ]),
          Exercise(name: 'Leg Press', sets: [
            Set(reps: 10, weight: 130, rpe: 7),
            Set(reps: 10, weight: 130, rpe: 8),
            Set(reps: 9, weight: 130, rpe: 9),
          ]),
          Exercise(name: 'Leg Extension', sets: [
            Set(reps: 12, weight: 45, rpe: 7),
            Set(reps: 12, weight: 45, rpe: 7),
            Set(reps: 11, weight: 45, rpe: 8),
          ]),
          Exercise(name: 'Leg Curl', sets: [
            Set(reps: 12, weight: 32.5, rpe: 6),
            Set(reps: 12, weight: 32.5, rpe: 7),
            Set(reps: 11, weight: 32.5, rpe: 7),
          ]),
          Exercise(name: 'Calf Raise', sets: [
            Set(reps: 15, weight: 65, rpe: 7),
            Set(reps: 15, weight: 65, rpe: 7),
            Set(reps: 15, weight: 65, rpe: 8),
            Set(reps: 14, weight: 65, rpe: 8),
          ]),
          Exercise(name: 'Hip Thrust', sets: [
            Set(reps: 10, weight: 90, rpe: 7),
            Set(reps: 10, weight: 90, rpe: 7),
            Set(reps: 10, weight: 90, rpe: 8),
          ]),
        ],
      ),
      // Week 3 sessions
      WorkoutSession(
        date: now.subtract(const Duration(days: 20)),
        planName: 'Push Day',
        weekNumber: 3,
        exercises: [
          Exercise(name: 'Bench Press', sets: [
            Set(reps: 8, weight: 65, rpe: 7, note: 'New PR!'),
            Set(reps: 8, weight: 65, rpe: 8),
            Set(reps: 7, weight: 65, rpe: 9),
            Set(reps: 6, weight: 65, rpe: 10),
          ]),
          Exercise(name: 'Incline Dumbbell Press', sets: [
            Set(reps: 10, weight: 28, rpe: 7),
            Set(reps: 10, weight: 28, rpe: 8),
            Set(reps: 9, weight: 28, rpe: 9),
          ]),
          Exercise(name: 'Overhead Press', sets: [
            Set(reps: 8, weight: 45, rpe: 7),
            Set(reps: 8, weight: 45, rpe: 8),
            Set(reps: 7, weight: 45, rpe: 9),
          ]),
          Exercise(name: 'Lateral Raise', sets: [
            Set(reps: 12, weight: 10, rpe: 8),
            Set(reps: 12, weight: 10, rpe: 8),
            Set(reps: 10, weight: 10, rpe: 9),
          ]),
          Exercise(name: 'Tricep Pushdown', sets: [
            Set(reps: 12, weight: 30, rpe: 7),
            Set(reps: 12, weight: 30, rpe: 7),
            Set(reps: 12, weight: 30, rpe: 8),
          ]),
          Exercise(name: 'Dumbbell Fly', sets: [
            Set(reps: 12, weight: 20, rpe: 7),
            Set(reps: 12, weight: 20, rpe: 8),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 19)),
        planName: 'Pull Day',
        weekNumber: 3,
        exercises: [
          Exercise(name: 'Deadlift', sets: [
            Set(reps: 5, weight: 110, rpe: 8, note: 'New PR!'),
            Set(reps: 5, weight: 110, rpe: 8),
            Set(reps: 4, weight: 110, rpe: 9),
            Set(reps: 3, weight: 110, rpe: 10),
          ]),
          Exercise(name: 'Barbell Row', sets: [
            Set(reps: 8, weight: 65, rpe: 7),
            Set(reps: 8, weight: 65, rpe: 8),
            Set(reps: 7, weight: 65, rpe: 9),
            Set(reps: 6, weight: 65, rpe: 9),
          ]),
          Exercise(name: 'Lat Pulldown', sets: [
            Set(reps: 10, weight: 55, rpe: 7),
            Set(reps: 10, weight: 55, rpe: 8),
            Set(reps: 9, weight: 55, rpe: 8),
          ]),
          Exercise(name: 'Seated Cable Row', sets: [
            Set(reps: 10, weight: 50, rpe: 7),
            Set(reps: 10, weight: 50, rpe: 8),
            Set(reps: 9, weight: 50, rpe: 8),
          ]),
          Exercise(name: 'Face Pull', sets: [
            Set(reps: 15, weight: 20, rpe: 6),
            Set(reps: 15, weight: 20, rpe: 7),
            Set(reps: 15, weight: 20, rpe: 7),
          ]),
          Exercise(name: 'Bicep Curl', sets: [
            Set(reps: 12, weight: 14, rpe: 7),
            Set(reps: 12, weight: 14, rpe: 8),
            Set(reps: 10, weight: 14, rpe: 9),
          ]),
          Exercise(name: 'Hammer Curl', sets: [
            Set(reps: 10, weight: 12, rpe: 7),
            Set(reps: 10, weight: 12, rpe: 8),
          ]),
        ],
      ),
      // Week 4 sessions
      WorkoutSession(
        date: now.subtract(const Duration(days: 13)),
        planName: 'Push Day',
        weekNumber: 4,
        exercises: [
          Exercise(name: 'Bench Press', sets: [
            Set(reps: 8, weight: 67.5, rpe: 7, note: 'Felt amazing'),
            Set(reps: 8, weight: 67.5, rpe: 8),
            Set(reps: 7, weight: 67.5, rpe: 9),
            Set(reps: 6, weight: 67.5, rpe: 9),
          ]),
          Exercise(name: 'Incline Dumbbell Press', sets: [
            Set(reps: 10, weight: 30, rpe: 7),
            Set(reps: 10, weight: 30, rpe: 8),
            Set(reps: 8, weight: 30, rpe: 9),
          ]),
          Exercise(name: 'Overhead Press', sets: [
            Set(reps: 8, weight: 47.5, rpe: 7),
            Set(reps: 8, weight: 47.5, rpe: 8),
            Set(reps: 6, weight: 47.5, rpe: 9),
          ]),
          Exercise(name: 'Lateral Raise', sets: [
            Set(reps: 12, weight: 12, rpe: 7),
            Set(reps: 12, weight: 12, rpe: 8),
            Set(reps: 10, weight: 12, rpe: 9),
          ]),
          Exercise(name: 'Tricep Pushdown', sets: [
            Set(reps: 12, weight: 32.5, rpe: 7),
            Set(reps: 12, weight: 32.5, rpe: 7),
            Set(reps: 11, weight: 32.5, rpe: 8),
          ]),
          Exercise(name: 'Dumbbell Fly', sets: [
            Set(reps: 12, weight: 20, rpe: 7),
            Set(reps: 12, weight: 20, rpe: 8),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 12)),
        planName: 'Leg Day',
        weekNumber: 4,
        exercises: [
          Exercise(name: 'Squat', sets: [
            Set(reps: 6, weight: 90, rpe: 8, note: 'Almost hit PR'),
            Set(reps: 6, weight: 90, rpe: 8),
            Set(reps: 5, weight: 90, rpe: 9),
            Set(reps: 4, weight: 90, rpe: 10),
          ]),
          Exercise(name: 'Romanian Deadlift', sets: [
            Set(reps: 8, weight: 70, rpe: 7),
            Set(reps: 8, weight: 70, rpe: 8),
            Set(reps: 6, weight: 70, rpe: 9),
          ]),
          Exercise(name: 'Leg Press', sets: [
            Set(reps: 10, weight: 140, rpe: 7),
            Set(reps: 10, weight: 140, rpe: 8),
            Set(reps: 8, weight: 140, rpe: 9),
          ]),
          Exercise(name: 'Leg Extension', sets: [
            Set(reps: 12, weight: 50, rpe: 7),
            Set(reps: 12, weight: 50, rpe: 7),
            Set(reps: 10, weight: 50, rpe: 8),
          ]),
          Exercise(name: 'Leg Curl', sets: [
            Set(reps: 12, weight: 35, rpe: 6),
            Set(reps: 12, weight: 35, rpe: 7),
            Set(reps: 10, weight: 35, rpe: 7),
          ]),
          Exercise(name: 'Calf Raise', sets: [
            Set(reps: 15, weight: 70, rpe: 7),
            Set(reps: 15, weight: 70, rpe: 7),
            Set(reps: 15, weight: 70, rpe: 8),
            Set(reps: 13, weight: 70, rpe: 8),
          ]),
          Exercise(name: 'Hip Thrust', sets: [
            Set(reps: 10, weight: 100, rpe: 7),
            Set(reps: 10, weight: 100, rpe: 7),
            Set(reps: 10, weight: 100, rpe: 8),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 10)),
        planName: 'Pull Day',
        weekNumber: 4,
        exercises: [
          Exercise(name: 'Deadlift', sets: [
            Set(reps: 5, weight: 115, rpe: 8),
            Set(reps: 5, weight: 115, rpe: 8),
            Set(reps: 4, weight: 115, rpe: 9),
            Set(reps: 3, weight: 115, rpe: 10),
          ]),
          Exercise(name: 'Barbell Row', sets: [
            Set(reps: 8, weight: 67.5, rpe: 7),
            Set(reps: 8, weight: 67.5, rpe: 8),
            Set(reps: 6, weight: 67.5, rpe: 9),
          ]),
          Exercise(name: 'Lat Pulldown', sets: [
            Set(reps: 10, weight: 57.5, rpe: 7),
            Set(reps: 10, weight: 57.5, rpe: 8),
            Set(reps: 8, weight: 57.5, rpe: 9),
          ]),
          Exercise(name: 'Bicep Curl', sets: [
            Set(reps: 12, weight: 16, rpe: 7),
            Set(reps: 12, weight: 16, rpe: 8),
            Set(reps: 10, weight: 16, rpe: 9),
          ]),
        ],
      ),
      // Week 5 sessions
      WorkoutSession(
        date: now.subtract(const Duration(days: 6)),
        planName: 'Push Day',
        weekNumber: 5,
        exercises: [
          Exercise(name: 'Bench Press', sets: [
            Set(reps: 8, weight: 70, rpe: 8, note: 'New PR!'),
            Set(reps: 8, weight: 70, rpe: 8),
            Set(reps: 7, weight: 70, rpe: 9),
            Set(reps: 5, weight: 70, rpe: 10),
          ]),
          Exercise(name: 'Incline Dumbbell Press', sets: [
            Set(reps: 10, weight: 32, rpe: 7),
            Set(reps: 10, weight: 32, rpe: 8),
            Set(reps: 8, weight: 32, rpe: 9),
          ]),
          Exercise(name: 'Overhead Press', sets: [
            Set(reps: 8, weight: 50, rpe: 7),
            Set(reps: 8, weight: 50, rpe: 8),
            Set(reps: 6, weight: 50, rpe: 9),
          ]),
          Exercise(name: 'Lateral Raise', sets: [
            Set(reps: 12, weight: 12, rpe: 7),
            Set(reps: 12, weight: 12, rpe: 8),
            Set(reps: 10, weight: 12, rpe: 9),
          ]),
          Exercise(name: 'Tricep Pushdown', sets: [
            Set(reps: 12, weight: 35, rpe: 7),
            Set(reps: 12, weight: 35, rpe: 7),
            Set(reps: 12, weight: 35, rpe: 8),
          ]),
          Exercise(name: 'Dumbbell Fly', sets: [
            Set(reps: 12, weight: 22, rpe: 7),
            Set(reps: 12, weight: 22, rpe: 8),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 3)),
        planName: 'Pull Day',
        weekNumber: 5,
        exercises: [
          Exercise(name: 'Deadlift', sets: [
            Set(reps: 5, weight: 120, rpe: 8, note: 'New PR!'),
            Set(reps: 5, weight: 120, rpe: 9),
            Set(reps: 3, weight: 120, rpe: 10),
          ]),
          Exercise(name: 'Barbell Row', sets: [
            Set(reps: 8, weight: 70, rpe: 7),
            Set(reps: 8, weight: 70, rpe: 8),
            Set(reps: 6, weight: 70, rpe: 9),
          ]),
          Exercise(name: 'Lat Pulldown', sets: [
            Set(reps: 10, weight: 60, rpe: 7),
            Set(reps: 10, weight: 60, rpe: 8),
            Set(reps: 8, weight: 60, rpe: 9),
          ]),
          Exercise(name: 'Bicep Curl', sets: [
            Set(reps: 12, weight: 16, rpe: 7),
            Set(reps: 12, weight: 16, rpe: 8),
            Set(reps: 10, weight: 16, rpe: 9),
          ]),
        ],
      ),
      WorkoutSession(
        date: now.subtract(const Duration(days: 1)),
        planName: 'Leg Day',
        weekNumber: 5,
        exercises: [
          Exercise(name: 'Squat', sets: [
            Set(reps: 6, weight: 95, rpe: 8, note: 'New PR!'),
            Set(reps: 6, weight: 95, rpe: 9),
            Set(reps: 4, weight: 95, rpe: 10),
          ]),
          Exercise(name: 'Romanian Deadlift', sets: [
            Set(reps: 8, weight: 75, rpe: 7),
            Set(reps: 8, weight: 75, rpe: 8),
            Set(reps: 6, weight: 75, rpe: 9),
          ]),
          Exercise(name: 'Leg Press', sets: [
            Set(reps: 10, weight: 150, rpe: 7),
            Set(reps: 10, weight: 150, rpe: 8),
            Set(reps: 8, weight: 150, rpe: 9),
          ]),
          Exercise(name: 'Calf Raise', sets: [
            Set(reps: 15, weight: 75, rpe: 7),
            Set(reps: 15, weight: 75, rpe: 7),
            Set(reps: 15, weight: 75, rpe: 8),
          ]),
        ],
      ),
    ];

    for (var session in sessions) {
      await HiveService.addSession(session);
    }
  }

  static Future<void> clearAllData() async {
    await HiveService.clearAllPlans();
    await HiveService.clearAllSessions();
  }
}
