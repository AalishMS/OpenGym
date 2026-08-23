import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/set_row.dart';

void main() {
  Widget host(gym.Set set) {
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
                onDecrementReps: () {},
                onIncrementReps: () {},
                onDecrementWeight: () {},
                onIncrementWeight: () {},
                onEdit: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('keeps the set value on one line at every phone width',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The widest realistic value: three-digit weight, half-kilo, two-digit
    // reps, and an RPE. This used to wrap its `@8` onto a second line below
    // 375px, pushing every row under it down the card.
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
      // 40px is one line of the 17px number plus the row's own padding; a wrap
      // took it to 52.
      expect(tester.getSize(find.byType(SetRow)).height, 40,
          reason: 'set value wrapped at ${width}px');
    }
  });

  testWidgets('draws the set value louder than the stepper controls',
      (tester) async {
    await tester.pumpWidget(host(gym.Set(weight: 70, reps: 8)));
    await tester.pumpAndSettle();

    final rows = find.descendant(
      of: find.byType(SetRow),
      matching: find.byType(RichText),
    );
    final value = tester.widget<RichText>(rows.at(1)).text.style!;
    // The last two RichTexts in the row are the reps stepper's − and +.
    final control =
        tester.widget<RichText>(rows.at(rows.evaluate().length - 1)).text.style!;

    expect(value.fontWeight, FontWeight.bold);
    expect(value.fontSize!, greaterThan(control.fontSize!));
    expect(value.color, isNot(control.color));
  });
}
