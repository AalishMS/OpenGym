import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

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

/// Hive queues retain the widget test zone that initiated a write. Drain and
/// close while that zone can still receive frames, before the next test starts.
Future<void> closeStorageWithFrames(
  WidgetTester tester,
  Future<void> Function() close,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  Object? failure;
  close().then(
    (_) => closed = true,
    onError: (Object error) {
      failure = error;
      closed = true;
    },
  );
  for (var attempt = 0; attempt < 100 && !closed; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (failure != null) throw failure!;
  expect(closed, isTrue, reason: 'Close storage before leaving the test zone.');
}
