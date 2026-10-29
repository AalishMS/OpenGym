import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/auth/data_preparation_failure.dart';
import 'package:gymapp/auth/training_data_gate.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:gymapp/services/training_block_migration.dart';

void main() {
  testWidgets('pending replacement failure hides pushed workout content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: TrainingDataGate(child: Text('Log workout'))),
    );
    expect(find.text('Log workout'), findsOneWidget);
    TrainingBlockRestore.recoveryFailure.value = TrainingPreparationException(
      StateError('interrupted'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Log workout'), findsNothing);
    expect(find.text('Export safety copy'), findsOneWidget);
    TrainingBlockRestore.recoveryFailure.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Log workout'), findsOneWidget);
  });

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
