import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/widgets/statistics/workout_heatmap.dart';

WorkoutSession session(
  DateTime date, {
  bool completed = true,
  bool deleted = false,
}) => WorkoutSession(
  date: date,
  planName: 'Workout',
  exercises: [],
  isCompleted: completed,
  deletedAt: deleted ? date : null,
);

Future<void> pumpHeatmap(
  WidgetTester tester, {
  required DateTime now,
  List<WorkoutSession> sessions = const [],
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: WorkoutHeatmap(sessions: sessions, now: now),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('weekdays remain visible at both ends of a narrow scroll', (
    tester,
  ) async {
    await pumpHeatmap(tester, now: DateTime(2026, 10, 6));
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.controller!.offset, 0);
    final before = tester.getRect(find.text('Mon'));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final currentMonth = tester.getRect(find.text('Oct').first);
    expect(currentMonth.left, greaterThanOrEqualTo(viewport.left));
    expect(currentMonth.right, lessThanOrEqualTo(viewport.right));
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Mon')), before);
    expect(find.text('Wed').hitTestable(), findsOneWidget);
    expect(find.text('Fri').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar counts exclude drafts, deletions and future dates', (
    tester,
  ) async {
    final now = DateTime(2026, 1, 1);
    final semantics = tester.ensureSemantics();
    await pumpHeatmap(
      tester,
      now: now,
      sessions: [
        session(now),
        session(DateTime(2026, 1, 1, 23, 59)),
        session(now.toUtc()),
        session(now, completed: false),
        session(now, deleted: true),
        session(DateTime(2026, 1, 2)),
        session(DateTime(2025, 1, 1)),
      ],
    );
    final tooltips =
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((t) => t.message!)
            .toList();
    expect(tooltips, contains('Thursday, January 1, 2026: 3 workouts'));
    expect(
      find.bySemanticsLabel('Thursday, January 1, 2026: 3 workouts'),
      findsOneWidget,
    );
    expect(tooltips, contains('Monday, January 6, 2025: 0 workouts'));
    expect(tooltips, hasLength(51 * 7 + 4));
    expect(tooltips.any((label) => label.contains('January 2, 2026')), isFalse);
    expect(find.text('Jan').first.hitTestable(), findsOneWidget);
    expect(find.text('3+'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('empty calendar and labels fit with larger text', (tester) async {
    await pumpHeatmap(tester, now: DateTime(2024, 3, 1), scale: 2);
    expect(find.text('Mar').first.hitTestable(), findsOneWidget);
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message!);
    expect(messages, contains('Thursday, February 29, 2024: 0 workouts'));
    expect(messages.every((message) => message.endsWith('0 workouts')), isTrue);
    expect(find.text('Mon').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
