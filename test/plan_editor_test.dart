import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';

void main() {
  testWidgets('add exercise sheet survives being closed', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 880);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PlanEditorScreen.create()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('[+ ADD EXERCISE]'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The search field must outlive the sheet's exit animation: disposing its
    // controller on pop used to throw, and the ErrorWidget that replaced it
    // blew the sheet's Column out by ~100,000px.
    await tester.enterText(find.widgetWithText(TextField, 'Search exercises'),
        'press');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('[DONE]'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
