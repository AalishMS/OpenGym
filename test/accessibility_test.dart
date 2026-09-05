import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:gymapp/widgets/workout/workout_dialogs.dart';
import 'package:provider/provider.dart';

void main() {
  Widget host({
    TextScaler textScaler = TextScaler.noScaling,
    void Function(int)? onAddSet,
    void Function(int)? onAddNote,
    void Function(int)? onDeleteExercise,
  }) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
      home: Scaffold(
        body: ExerciseCard(
          exercise: Exercise(
            name: 'Barbell bench press',
            sets: [gym.Set(weight: 70, reps: 8)],
          ),
          exerciseIndex: 4,
          accent: const Color(0xFF7C5CFF),

          onAddSet: onAddSet ?? (_) {},
          onEditSet: (_, __) {},
          onAddNote: onAddNote ?? (_) {},
          onRename: (_) {},
          onDeleteExercise: onDeleteExercise ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('workout controls expose at least 48 square hit regions', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    for (final label in [
      'Exercise note',
      'Delete exercise',
      'Add set',
      'Set 1 Kg',
      'Set 1 Reps',
    ]) {
      final control = find.bySemanticsLabel(label);
      expect(control, findsOneWidget);
      expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('card semantic actions invoke only their assigned callbacks', (
    tester,
  ) async {
    final calls = <String>[];
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        onAddSet: (i) => calls.add('add:$i'),
        onAddNote: (i) => calls.add('note:$i'),
        onDeleteExercise: (i) => calls.add('delete:$i'),
      ),
    );
    for (final action
        in <String, String>{
          'Exercise note': 'note:4',
          'Add set': 'add:4',
          'Delete exercise': 'delete:4',
        }.entries) {
      calls.clear();
      tester.semantics.tap(find.semantics.byLabel(action.key));
      await tester.pump();
      expect(calls, [action.value]);
    }
    semantics.dispose();
  });

  testWidgets('RPE choices expose 48 square hit regions', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => WorkoutDialogs.showAddSetDialog(
                          context,
                          onAdd: (_) {},
                        ),
                    child: const Text('[OPEN]'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('[OPEN]'));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 10; i++) {
      final choice = find.bySemanticsLabel('RPE $i');
      expect(choice, findsOneWidget);
      expect(tester.getSize(choice).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
    }
    semantics.dispose();
  });

  testWidgets('workout card does not overflow at 320px and 2x text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(textScaler: const TextScaler.linear(2)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
