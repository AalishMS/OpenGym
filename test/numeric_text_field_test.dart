import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/widgets/numeric_text_field.dart';

void main() {
  testWidgets('uses integer and decimal keyboards and selects on focus', (
    tester,
  ) async {
    final reps = TextEditingController(text: '12');
    final weight = TextEditingController(text: '62.5');
    addTearDown(reps.dispose);
    addTearDown(weight.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              NumericTextField(
                controller: reps,
                valueType: NumericValueType.integer,
              ),
              NumericTextField(
                controller: weight,
                valueType: NumericValueType.decimal,
              ),
            ],
          ),
        ),
      ),
    );

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(
      fields[0].keyboardType,
      const TextInputType.numberWithOptions(decimal: false),
    );
    expect(
      fields[1].keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(fields.every((field) => field.selectAllOnFocus == true), isTrue);

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(
      weight.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );

    await tester.enterText(find.byType(TextField).last, '70.25');
    expect(weight.selection, const TextSelection.collapsed(offset: 5));

    final fieldRect = tester.getRect(find.byType(TextField).last);
    await tester.tapAt(Offset(fieldRect.left + 8, fieldRect.center.dy));
    await tester.pump();
    expect(weight.selection.isCollapsed, isTrue);
  });
}
