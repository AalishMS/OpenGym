import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/auth/data_preparation_failure.dart';

void main() {
  testWidgets(
    'failed preparation offers retry and safety export without exposing logger',
    (tester) async {
      var retries = 0;
      var exports = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DataPreparationFailure(
            onRetry: () async {
              retries++;
            },
            onExport: () async {
              exports++;
            },
          ),
        ),
      );
      expect(find.text('Your training data needs recovery'), findsOneWidget);
      expect(find.text('Log workout'), findsNothing);
      await tester.tap(find.text('Export safety copy'));
      await tester.pumpAndSettle();
      expect(exports, 1);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retries, 1);
    },
  );
}
