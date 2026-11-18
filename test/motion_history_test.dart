import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/history/history_journal_widgets.dart';

import 'support/hive_test_harness.dart';
import 'support/test_fonts.dart';

class _Sessions extends WorkoutSessionProvider {
  _Sessions(this._sessions);

  final List<WorkoutSession> _sessions;

  @override
  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  @override
  String? get activeSplitId => 'a';
}

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await hiveHarness.open(includeSplits: true);
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  WorkoutSession session(String id, String name, int day) => WorkoutSession(
    id: id,
    planName: name,
    date: DateTime(2026, 9, day),
    splitId: 'a',
    isCompleted: true,
    exercises: [
      Exercise(name: 'Bench Press', sets: [Set(weight: 80, reps: 5)]),
    ],
  );

  Widget host({bool reduced = false}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<WorkoutSessionProvider>.value(
        value: _Sessions([
          session('a', 'Push Day', 1),
          session('b', 'Pull Day', 3),
        ]),
      ),
      ChangeNotifierProvider<SettingsProvider>.value(value: SettingsProvider()),
    ],
    child: MaterialApp(
      theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
      home: Builder(
        builder:
            (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: const HistoryScreen(),
            ),
      ),
    ),
  );

  final field = find.byKey(const ValueKey('history-search-field'));
  final count = find.textContaining(RegExp(r'^\d+ matching workout'));
  SizeTransition fold(WidgetTester tester) => tester.widget<SizeTransition>(
    find.ancestor(of: count, matching: find.byType(SizeTransition)),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the match count folds open once and changes in place', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(count, findsNothing);
    final ledger = tester.getTopLeft(find.text('Push Day')).dy;

    await tester.enterText(field, 'Day');
    await tester.pump();
    // The count is there from the first frame, folding open from the top.
    expect(find.text('2 matching workouts'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fold(tester).sizeFactor.value, inExclusiveRange(0, 1));
    final midway = tester.getTopLeft(find.text('Push Day')).dy;
    await tester.pumpAndSettle();
    final open = tester.getTopLeft(find.text('Push Day')).dy;
    // The ledger moves down rather than jumping.
    expect(midway, greaterThan(ledger));
    expect(midway, lessThan(open));

    // Typing more only changes the number.
    await tester.enterText(field, 'Push');
    await tester.pump();
    expect(find.text('1 matching workout'), findsOneWidget);
    expect(fold(tester).sizeFactor.value, 1);

    await tester.enterText(field, '');
    await tester.pump();
    // Folding away, the count stays until it has gone.
    expect(count, findsOneWidget);
    await tester.pumpAndSettle();
    expect(count, findsNothing);
  });

  testWidgets('results and "No matching workouts" cross without replaying', (
    tester,
  ) async {
    phone(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.enterText(field, 'zzz');
    await tester.pump();
    expect(find.text('No matching workouts'), findsOneWidget);
    // The leaving ledger takes no taps and says nothing while it fades.
    expect(find.text('Push Day'), findsOneWidget);
    expect(find.text('Push Day').hitTestable(), findsNothing);
    expect(find.semantics.byLabel('Push Day'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Push Day'), findsNothing);

    // Typing more within "nothing matches" replays nothing.
    await tester.enterText(field, 'zzzz');
    await tester.pump();
    expect(find.byType(HistoryEmptyState), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pump();
    expect(find.text('Push Day').hitTestable(), findsOneWidget);
    expect(find.text('Clear search').hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(HistoryEmptyState), findsNothing);
    semantics.dispose();
  });

  testWidgets('under reduced motion search changes land at once', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(host(reduced: true));
    await tester.pumpAndSettle();

    await tester.enterText(field, 'Push');
    await tester.pump();
    expect(fold(tester).sizeFactor.value, 1);

    await tester.enterText(field, 'zzz');
    await tester.pump();
    expect(find.text('Push Day'), findsNothing);
    expect(count, findsNothing);
    expect(find.text('No matching workouts'), findsOneWidget);
  });
}
