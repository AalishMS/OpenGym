import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/split_repository.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    hiveDirectory = await Directory.systemTemp.createTemp('opengym_split_ui_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('header menu switches the complete visible workspace', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(harness.host(const HomeScreen()));
    expect(find.text('[PPL]'), findsOneWidget);
    expect(find.text('Ppl Plan'), findsOneWidget);
    expect(find.text('Ul Plan'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('split-switcher-button')))
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('split-menu')), findsOneWidget);
    final selectedSplit = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'PPL split',
      ),
    );
    expect(selectedSplit.properties.button, isTrue);
    expect(selectedSplit.properties.selected, isTrue);

    await tester.tap(find.text('UL'));
    await tester.pumpAndSettle();
    expect(find.text('[UL]'), findsOneWidget);
    expect(find.text('Ppl Plan'), findsNothing);
    expect(find.text('Ul Plan'), findsOneWidget);
    expect(harness.sessions.sessions.single.splitId, 'ul');
    semantics.dispose();
  });

  testWidgets('history and stats follow the selected split', (tester) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await harness.splits.setActiveSplit('ul');

    await tester.pumpWidget(harness.host(const HistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('UL PLAN'), findsOneWidget);
    expect(find.text('PPL PLAN'), findsNothing);

    await tester.pumpWidget(harness.host(const StatsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[EXERCISE]'));
    await tester.pumpAndSettle();
    expect(find.textContaining('UL ONLY'), findsWidgets);
    expect(find.textContaining('PPL ONLY'), findsNothing);
  });

  testWidgets('new split dialog validates names and selects the result', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen()));

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[+ NEW SPLIT]'));
    await tester.pumpAndSettle();
    expect(find.text('> NEW SPLIT'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('split-name-field')),
      'ppl',
    );
    await tester.tap(find.text('[CREATE]'));
    await tester.pump();
    expect(find.text('A split with that name already exists.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('split-name-field')),
      ' Full Body ',
    );
    await tester.tap(find.text('[CREATE]'));
    await tester.pumpAndSettle();
    expect(harness.splits.activeSplit?.name, 'Full Body');
    expect(find.text('[FULL BODY]'), findsOneWidget);
    expect(harness.plans.plans, isEmpty);
  });

  testWidgets('five-split limit disables creation with an explanation', (
    tester,
  ) async {
    final harness =
        (await tester.runAsync(
          () => _createHarness(
            splitNames: const ['PPL', 'UL', 'Full Body', 'Power', 'Travel'],
          ),
        ))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen()));
    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();

    expect(find.text('LIMIT REACHED · 5/5 ACTIVE'), findsOneWidget);
    final action = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('new-split-action')),
        matching: find.byType(InkWell),
      ),
    );
    expect(action.onTap, isNull);
  });

  testWidgets('manage supports rename and guarded active deletion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen()));

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[MANAGE SPLITS]'));
    await tester.pumpAndSettle();
    expect(find.text('> MANAGE SPLITS'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename PPL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('split-name-field')),
      'Push Pull Legs',
    );
    await tester.tap(find.text('[SAVE]'));
    await tester.pumpAndSettle();
    expect(find.text('Push Pull Legs'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Push Pull Legs'));
    await tester.pumpAndSettle();
    expect(find.text('> DELETE SPLIT?'), findsOneWidget);
    expect(find.textContaining('removes 1 plan and 1 session'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '[DELETE]'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('[SELECT]'));
    await tester.pump();
    await tester.tap(find.text('[DELETE]'));
    await tester.pumpAndSettle();
    expect(harness.splits.splits.map((split) => split.name), ['UL']);
    expect(harness.splits.activeSplitId, 'ul');
    expect(harness.plans.plans.single.name, 'UL Plan');
    expect(harness.sessions.sessions.single.planName, 'UL Plan');
    semantics.dispose();
  });

  testWidgets('switcher remains readable across themes, widths, and scaling', (
    tester,
  ) async {
    final harness =
        (await tester.runAsync(
          () => _createHarness(
            splitNames: const ['A Very Long Training Split Name', 'UL'],
          ),
        ))!;
    addTearDown(harness.dispose);
    for (final brightness in Brightness.values) {
      for (final size in [const Size(320, 640), const Size(1100, 800)]) {
        await tester.pumpWidget(
          harness.host(
            const HomeScreen(),
            brightness: brightness,
            size: size,
            textScale: 1.6,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$brightness $size');
      }
    }
  });

  testWidgets('menu dismisses outside and honors reduced motion', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.host(const HomeScreen(), disableAnimations: true),
    );

    final switcherAnimation = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byKey(const ValueKey('split-switcher-button')),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcherAnimation.duration, Duration.zero);

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('split-menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('split-menu-barrier')));
    await tester.pump();
    expect(find.byKey(const ValueKey('split-menu')), findsNothing);
  });
}

Future<_Harness> _createHarness({
  List<String> splitNames = const ['PPL', 'UL'],
}) async {
  final now = DateTime(2026);
  final splitValues = [
    for (var index = 0; index < splitNames.length; index++)
      gym.Split(
        id: index == 0 ? 'ppl' : (index == 1 ? 'ul' : 'split-$index'),
        name: splitNames[index],
        userId: 'user-1',
        createdAt: now.add(Duration(minutes: index)),
      ),
  ];
  final repository = _FakeSplitRepository(splitValues, splitValues.first.id);

  if (splitValues.length >= 2) {
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: 'ppl-plan',
        splitId: splitValues[0].id,
        name: 'PPL Plan',
        exercises: [],
      ),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: 'ul-plan',
        splitId: splitValues[1].id,
        name: 'UL Plan',
        exercises: [],
      ),
    );
    await HiveService.putSessionRaw(
      _session('ppl-session', splitValues[0].id, 'PPL Plan', 'PPL Only'),
    );
    await HiveService.putSessionRaw(
      _session('ul-session', splitValues[1].id, 'UL Plan', 'UL Only'),
    );
  }
  final splits = SplitProvider(
    repository: repository,
    userIdProvider: () => 'user-1',
  );
  final plans = WorkoutPlanProvider(splits);
  final sessions = WorkoutSessionProvider(splits);
  return _Harness(splits, plans, sessions);
}

WorkoutSession _session(
  String id,
  String splitId,
  String planName,
  String exerciseName,
) => WorkoutSession(
  id: id,
  splitId: splitId,
  date: DateTime(2026),
  planName: planName,
  exercises: [
    Exercise(name: exerciseName, sets: [Set(reps: 5, weight: 50)]),
  ],
);

class _Harness {
  final SplitProvider splits;
  final WorkoutPlanProvider plans;
  final WorkoutSessionProvider sessions;

  const _Harness(this.splits, this.plans, this.sessions);

  Widget host(
    Widget child, {
    Brightness brightness = Brightness.dark,
    Size size = const Size(390, 800),
    double textScale = 1,
    bool disableAnimations = false,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SplitProvider>.value(value: splits),
      ChangeNotifierProvider<WorkoutPlanProvider>.value(value: plans),
      ChangeNotifierProvider<WorkoutSessionProvider>.value(value: sessions),
    ],
    child: MaterialApp(
      key: UniqueKey(),
      theme: buildTheme(const Color(0xFF00A8FF), brightness),
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );

  void dispose() {
    sessions.dispose();
    plans.dispose();
    splits.dispose();
  }
}

class _FakeSplitRepository extends SplitRepository {
  final List<gym.Split> values;
  SplitPreference preference;

  _FakeSplitRepository(this.values, String activeSplitId)
    : preference = SplitPreference(
        userId: 'user-1',
        activeSplitId: activeSplitId,
      );

  @override
  List<gym.Split> getSplits() => List.of(values);

  @override
  SplitPreference? getPreference(String userId) => preference;

  @override
  Future<void> upsertSplit(gym.Split split) async {
    final index = values.indexWhere((value) => value.id == split.id);
    if (index < 0) {
      values.add(split);
    } else {
      values[index] = split;
    }
  }

  @override
  Future<void> setActive(String userId, String splitId) async {
    preference = SplitPreference(userId: userId, activeSplitId: splitId);
  }

  @override
  Future<void> deleteSplit({
    required String userId,
    required String splitId,
    required String replacementSplitId,
  }) async {
    values.removeWhere((split) => split.id == splitId);
    if (preference.activeSplitId == splitId) {
      preference = SplitPreference(
        userId: userId,
        activeSplitId: replacementSplitId,
      );
    }
    final deletedAt = DateTime(2026, 1, 2);
    for (final plan in HiveService.getAllPlansRaw()) {
      if (plan.splitId == splitId) plan.deletedAt = deletedAt;
    }
    for (final session in HiveService.getAllSessionsRaw()) {
      if (session.splitId == splitId) session.deletedAt = deletedAt;
    }
  }
}
