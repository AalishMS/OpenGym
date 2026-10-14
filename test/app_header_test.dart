import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/screens/settings_screen.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';

import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/app_header.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

void main() {
  final harness = HiveTestHarness();
  final plan = WorkoutPlan(
    id: 'push',
    name: 'Push day',
    planColor: 4,
    exercises: [
      for (final name in ['Bench press', 'Incline press', 'Overhead press'])
        ExerciseTemplate(name: name, sets: 4),
    ],
  );
  final sessions = [
    for (var week = 1; week <= 8; week++)
      WorkoutSession(
        id: 'week-$week',
        planId: plan.id,
        planName: plan.name,
        date: DateTime(2026, 8, week * 3),
        weekNumber: week,
        isCompleted: true,
        exercises: [
          for (final template in plan.exercises)
            Exercise(
              name: template.name,
              sets: [
                for (var i = 0; i < 4; i++)
                  gym.Set(weight: 60.0 + week, reps: 8),
              ],
            ),
        ],
      ),
  ];

  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await harness.open(includeSplits: true);
    final box = Hive.box<WorkoutSession>(HiveService.sessionsBox);
    for (final session in sessions) {
      await box.put(session.id, session);
    }
  });

  tearDownAll(() async {
    await harness.close();
  });

  Widget host(Widget screen, Brightness brightness) => MultiProvider(
    key: UniqueKey(),
    providers: [
      ChangeNotifierProvider<SplitProvider>(
        create: (_) => SplitProvider(userIdProvider: () => null),
      ),
      ChangeNotifierProvider<WorkoutPlanProvider>(
        create: (_) => _Plans([plan]),
      ),
      ChangeNotifierProvider<WorkoutSessionProvider>(
        create: (_) => _Sessions(sessions),
      ),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
      ChangeNotifierProvider<UpdateProvider>(create: (_) => _Updates()),
    ],
    child: MaterialApp(
      theme: buildTheme(const Color(0xFF008D8D), brightness),
      home: screen,
    ),
  );

  Material headerMaterial(WidgetTester tester) => tester.widget<Material>(
    find
        .descendant(of: find.byType(AppBar), matching: find.byType(Material))
        .first,
  );

  void expectFlatHeader(WidgetTester tester, String reason) {
    final context = tester.element(find.byType(AppBar));
    final material = headerMaterial(tester);
    expect(material.color, backgroundColor(context), reason: reason);
    expect(material.elevation, 0, reason: reason);
    expect(material.surfaceTintColor, Colors.transparent, reason: reason);
    expect(
      material.shape,
      Border(bottom: BorderSide(color: borderColor(context))),
      reason: '$reason: permanent hairline',
    );
  }

  Color glyphColor(WidgetTester tester, Finder icon) =>
      tester
          .widget<RichText>(
            find.descendant(of: icon, matching: find.byType(RichText)),
          )
          .text
          .style!
          .color!;

  void expectBackArrow(WidgetTester tester, String reason) {
    final back = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(LucideIcons.arrowLeft),
    );
    expect(back, findsOneWidget, reason: reason);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(LucideIcons.chevronLeft),
      ),
      findsNothing,
      reason: reason,
    );
    expect(
      find.ancestor(of: back, matching: find.byTooltip('Back')),
      findsOneWidget,
      reason: '$reason: tooltip',
    );
    expect(
      glyphColor(tester, back),
      textPrimaryColor(tester.element(back)),
      reason: '$reason: neutral back',
    );
  }

  Future<void> scrollBody(WidgetTester tester) async {
    final scrollables = find.descendant(
      of: find.byType(Scaffold).first,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    );
    if (scrollables.evaluate().isEmpty) return;
    await tester.drag(scrollables.first, const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  final screens = <String, (Widget, bool)>{
    'History': (const HistoryScreen(), false),
    'Stats': (const StatsScreen(), false),
    'Settings': (const SettingsScreen(), false),
    'Workout details': (
      WorkoutDetailsScreen(sessionIdentity: sessions.last.id!),
      true,
    ),
    'Plan editor': (const PlanEditorScreen.create(), true),
    'Workout': (
      WorkoutScreen(plan: plan, planIndex: 0, initialWeekNumber: 8),
      true,
    ),
  };

  for (final MapEntry(key: name, value: (screen, hasBack)) in screens.entries) {
    testWidgets('$name uses the flat page-colour header', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 560);
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        final reason = '$name, ${brightness.name}';
        await tester.pumpWidget(host(screen, brightness));
        await pumpWithStorage(tester);

        expectFlatHeader(tester, '$reason before scrolling');
        if (hasBack) expectBackArrow(tester, reason);

        await scrollBody(tester);
        expectFlatHeader(tester, '$reason after scrolling');
      }
    });
  }

  testWidgets('header actions keep the accent', (tester) async {
    await tester.pumpWidget(
      host(
        WorkoutDetailsScreen(sessionIdentity: sessions.last.id!),
        Brightness.light,
      ),
    );
    await pumpWithStorage(tester);

    final edit = find.byIcon(LucideIcons.pencil);
    expect(glyphColor(tester, edit), accentColor(tester.element(edit)));
  });

  testWidgets('implied back buttons use the same arrow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF008D8D), Brightness.dark),
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => const Scaffold(
                              appBar: AppHeader(title: Text('Review changes')),
                            ),
                      ),
                    ),
                child: const Text('Open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expectBackArrow(tester, 'implied back');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('AppBackButton runs a custom leave flow', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppHeader(leading: AppBackButton(onPressed: () => pressed++)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Back'));
    expect(pressed, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppHeader(
            leading: AppBackButton(enabled: false, onPressed: () => pressed++),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Back'), warnIfMissed: false);
    expect(pressed, 1);
  });
}

class _Plans extends WorkoutPlanProvider {
  _Plans(this.values);

  final List<WorkoutPlan> values;

  @override
  List<WorkoutPlan> get plans => values;
}

class _Sessions extends WorkoutSessionProvider {
  _Sessions(this.values);

  final List<WorkoutSession> values;

  @override
  List<WorkoutSession> get sessions => values;

  @override
  Future<void> upsertSession(WorkoutSession session) async {}
}

class _Updates extends UpdateProvider {
  @override
  UpdateStatus get status => UpdateStatus.idle;

  @override
  Future<void> loadInstalledVersion() async {}
}
