import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/widgets/statistics/workout_heatmap.dart';

import 'support/test_fonts.dart';

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
        // Scrolls like the stats screen, so large text can grow downwards.
        body: ListView(
          children: [
            Center(
              child: SizedBox(
                width: 280,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: WorkoutHeatmap(sessions: sessions, now: now),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Rect> dayLabelRects(WidgetTester tester) => [
  for (final label in ['M', 'T', 'W', 'F', 'S'])
    ...tester.widgetList(find.text(label)).map(
      (widget) => tester.getRect(find.byWidget(widget)),
    ),
];

void main() {
  setUpAll(loadTestFonts);

  testWidgets('every weekday is labelled and stays put while scrolling', (
    tester,
  ) async {
    await pumpHeatmap(tester, now: DateTime(2026, 10, 6));
    expect(find.text('M'), findsOneWidget);
    expect(find.text('T'), findsNWidgets(2));
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('S'), findsNWidgets(2));

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.controller!.offset, 0);
    final before = dayLabelRects(tester);
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final currentMonth = tester.getRect(find.text('Oct').first);
    expect(currentMonth.left, greaterThanOrEqualTo(viewport.left));
    expect(currentMonth.right, lessThanOrEqualTo(viewport.right));
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(dayLabelRects(tester), before);
    expect(find.text('S').hitTestable(), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('days are marked trained or not, without a per-day count key', (
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
    expect(tooltips, contains('Monday, January 6, 2025: No workout'));
    expect(tooltips, hasLength(51 * 7 + 4));
    expect(tooltips.any((label) => label.contains('January 2, 2026')), isFalse);
    expect(find.text('Jan').first.hitTestable(), findsOneWidget);
    expect(find.text('Workouts per day'), findsNothing);
    expect(find.text('3+'), findsNothing);
    expect(find.text('Workout'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('summary counts workout days, the week streak and the average', (
    tester,
  ) async {
    // Wednesday. Weeks of Sep 21, Sep 28 and Oct 5 trained; Sep 14 did not.
    await pumpHeatmap(
      tester,
      now: DateTime(2026, 10, 7),
      sessions: [
        session(DateTime(2026, 10, 6)),
        session(DateTime(2026, 10, 6, 18)),
        session(DateTime(2026, 9, 30)),
        session(DateTime(2026, 9, 22)),
        session(DateTime(2026, 9, 8)),
      ],
    );
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3 weeks'), findsOneWidget);
    // Four days over the five weeks since Sep 7.
    expect(find.text('0.8'), findsOneWidget);
  });

  testWidgets('an untrained current week does not break the streak yet', (
    tester,
  ) async {
    await pumpHeatmap(
      tester,
      now: DateTime(2026, 10, 12),
      sessions: [session(DateTime(2026, 10, 6))],
    );
    expect(find.text('1 week'), findsOneWidget);
  });

  testWidgets('empty calendar and labels fit with larger text', (tester) async {
    await pumpHeatmap(tester, now: DateTime(2024, 3, 1), scale: 2);
    expect(find.text('Mar').first.hitTestable(), findsOneWidget);
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message!);
    expect(messages, contains('Thursday, February 29, 2024: No workout'));
    expect(messages.every((message) => message.endsWith('No workout')), isTrue);
    expect(find.text('0 weeks'), findsOneWidget);
    expect(find.text('M').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
