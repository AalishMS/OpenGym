import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/set_row.dart';

void main() {
  Widget host(
    gym.Set set, {
    SetTemplate? target,
    bool touched = false,
    VoidCallback? onDecrementReps,
    VoidCallback? onIncrementReps,
    VoidCallback? onDecrementWeight,
    VoidCallback? onIncrementWeight,
    VoidCallback? onEdit,
  }) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF7C5CFF), Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const SetHeaderRow(),
              SetRow(
                setIndex: 0,
                set: set,
                exerciseIndex: 0,
                accent: const Color(0xFF7C5CFF),
                target: target,
                touched: touched,
                onDecrementReps: onDecrementReps ?? () {},
                onIncrementReps: onIncrementReps ?? () {},
                onDecrementWeight: onDecrementWeight ?? () {},
                onIncrementWeight: onIncrementWeight ?? () {},
                onEdit: onEdit ?? () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('keeps the set value on one line at every phone width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final set = gym.Set(weight: 137.5, reps: 12, rpe: 8);

    for (final width in [320.0, 360.0, 375.0, 412.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpWidget(host(set));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final value = find.descendant(
        of: find.byType(SetRow),
        matching: find.byType(RichText),
      );
      final text = tester.widget<RichText>(value.at(1));
      expect(text.text.toPlainText(), '137.5kg x 12 @8');
      expect(
        tester.getSize(find.byType(SetRow)).height,
        56,
        reason: 'set value wrapped at ${width}px',
      );
    }
  });

  testWidgets('draws the set value louder than the stepper controls', (
    tester,
  ) async {
    await tester.pumpWidget(host(gym.Set(weight: 70, reps: 8)));
    await tester.pumpAndSettle();

    final rows = find.descendant(
      of: find.byType(SetRow),
      matching: find.byType(RichText),
    );
    final value = tester.widget<RichText>(rows.at(1)).text.style!;
    final control =
        tester
            .widget<RichText>(rows.at(rows.evaluate().length - 1))
            .text
            .style!;

    expect(value.fontWeight, FontWeight.bold);
    expect(value.fontSize!, greaterThan(control.fontSize!));
    expect(value.color, isNot(control.color));
  });

  testWidgets('stepper semantics identify weight and reps callbacks', (
    tester,
  ) async {
    final calls = <String>[];
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        gym.Set(weight: 70, reps: 8),
        onDecrementWeight: () => calls.add('weight-'),
        onIncrementWeight: () => calls.add('weight+'),
        onDecrementReps: () => calls.add('reps-'),
        onIncrementReps: () => calls.add('reps+'),
      ),
    );

    for (final action
        in <String, String>{
          'Decrease weight': 'weight-',
          'Increase weight': 'weight+',
          'Decrease reps': 'reps-',
          'Increase reps': 'reps+',
        }.entries) {
      calls.clear();
      final node = tester.getSemantics(find.bySemanticsLabel(action.key));
      expect(
        node,
        matchesSemantics(label: action.key, isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel(action.key));
      await tester.pump();
      expect(calls, [action.value]);
      expect(
        tester.getSize(find.bySemanticsLabel(action.key)).width,
        greaterThanOrEqualTo(32),
      );
      expect(
        tester.getSize(find.bySemanticsLabel(action.key)).height,
        greaterThanOrEqualTo(32),
      );
    }
    semantics.dispose();
  });

  testWidgets('stepper controls use separate 48px layout slots', (
    tester,
  ) async {
    await tester.pumpWidget(host(gym.Set(weight: 70, reps: 8)));

    final weightDecrease = tester.getRect(
      find.bySemanticsLabel('Decrease weight'),
    );
    final weightIncrease = tester.getRect(
      find.bySemanticsLabel('Increase weight'),
    );
    final repsDecrease = tester.getRect(find.bySemanticsLabel('Decrease reps'));
    final repsIncrease = tester.getRect(find.bySemanticsLabel('Increase reps'));

    for (final rect in [
      weightDecrease,
      weightIncrease,
      repsDecrease,
      repsIncrease,
    ]) {
      expect(rect.size, const Size(48, 48));
    }
    expect(weightDecrease.right, lessThanOrEqualTo(weightIncrease.left));
    expect(weightIncrease.right, lessThanOrEqualTo(repsDecrease.left));
    expect(repsDecrease.right, lessThanOrEqualTo(repsIncrease.left));
  });

  testWidgets('tapping the live set value invokes edit', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      host(gym.Set(weight: 70, reps: 8), onEdit: () => edits++),
    );
    await tester.tap(find.textContaining('70kg x 8', findRichText: true));
    expect(edits, 1);
  });

  testWidgets('target hint is shown only while the set is untouched', (
    tester,
  ) async {
    final target = SetTemplate(reps: 8, weight: 70);
    await tester.pumpWidget(host(gym.Set(weight: 0, reps: 0), target: target));
    expect(find.textContaining('70×8', findRichText: true), findsOneWidget);

    await tester.pumpWidget(
      host(gym.Set(weight: 2.5, reps: 0), target: target, touched: true),
    );
    expect(find.textContaining('70×8', findRichText: true), findsNothing);
  });

  testWidgets('untouched state controls target hints rather than set values', (
    tester,
  ) async {
    final target = SetTemplate(reps: 8, weight: 70);
    await tester.pumpWidget(
      host(gym.Set(weight: 2.5, reps: 0), target: target),
    );
    expect(find.textContaining('70×8', findRichText: true), findsOneWidget);
  });
}
