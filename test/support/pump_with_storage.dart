import 'package:flutter_test/flutter_test.dart';

/// Allows real filesystem futures to finish between frames. Widget tests use
/// fake time, so pumpAndSettle alone cannot drain Hive's underlying I/O.
Future<void> pumpWithStorage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('The screen did not settle after allowing storage writes to finish.');
}
