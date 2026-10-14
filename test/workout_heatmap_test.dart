import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/theme/app_theme.dart';
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
  double width = 280,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Scrolls like the stats screen, so large text can grow downwards.
        body: ListView(
          children: [
            Center(
              child: SizedBox(
                width: width,
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

void main() {
  setUpAll(loadTestFonts);

  testWidgets('the grid fits the width and its label names the weeks shown', (
    tester,
  ) async {
    await pumpHeatmap(tester, now: DateTime(2026, 10, 6));
    expect(find.text('M'), findsOneWidget);
    expect(find.text('T'), findsNWidgets(2));
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('S'), findsNWidgets(2));
    expect(find.text('S').hitTestable(), findsNWidgets(2));

    // No scrolling: every week is laid out inside the 280px panel.
    expect(find.byType(Scrollable), findsOneWidget); // The host ListView.
    expect(find.byType(Scrollbar), findsNothing);
    final panel = tester.getRect(find.byType(WorkoutHeatmap));
    final cells = find.byType(Tooltip);
    for (final cell in [cells.first, cells.last]) {
      final rect = tester.getRect(cell);
      expect(rect.left, greaterThanOrEqualTo(panel.left - 0.01));
      expect(rect.right, lessThanOrEqualTo(panel.right + 0.01));
    }
    final currentMonth = tester.getRect(find.text('Oct').first);
    expect(currentMonth.right, lessThanOrEqualTo(panel.right));

    // The caption counts the columns that are drawn: whole weeks plus the
    // current one up to today (a Tuesday).
    final label = tester.widget<Text>(find.textContaining('Last ')).data!;
    final weeks = int.parse(RegExp(r'Last (\d+) weeks').firstMatch(label)![1]!);
    expect(weeks, inInclusiveRange(12, 52));
    expect(cells, findsNWidgets((weeks - 1) * 7 + 2));
    expect(label, 'Days you trained · Last $weeks weeks');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the window grows with the width, between 12 and 52 weeks', (
    tester,
  ) async {
    int shown() {
      final label = tester.widget<Text>(find.textContaining('Last ')).data!;
      return int.parse(RegExp(r'Last (\d+) weeks').firstMatch(label)![1]!);
    }

    await pumpHeatmap(tester, now: DateTime(2026, 10, 6), width: 120);
    expect(shown(), 12);
    await pumpHeatmap(tester, now: DateTime(2026, 10, 6), width: 400);
    expect(shown(), greaterThan(12));
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHeatmap(tester, now: DateTime(2026, 10, 6), width: 2000);
    expect(shown(), 52);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty days use the page colour, not the border colour', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 6);
    await pumpHeatmap(
      tester,
      now: now,
      sessions: [session(DateTime(2026, 10, 5))],
    );
    final context = tester.element(find.byType(WorkoutHeatmap));
    final colours =
        tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(Tooltip),
                matching: find.byType(Container),
              ),
            )
            .map((box) => (box.decoration! as BoxDecoration).color)
            .toSet();
    expect(colours, {backgroundColor(context), accentFillColor(context)});
    expect(colours, isNot(contains(borderColor(context))));
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
    final weeks = int.parse(
      RegExp(r'Last (\d+) weeks').firstMatch(
        tester.widget<Text>(find.textContaining('Last ')).data!,
      )![1]!,
    );
    expect(tooltips, hasLength((weeks - 1) * 7 + 4));
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
