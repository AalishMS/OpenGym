import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';

import 'support/hive_test_harness.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/breakpoints.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';
import 'package:gymapp/widgets/app_nav_rail.dart';

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  Widget shellHost(double width, {double textScale = 1}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF00A2FF), Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const AppShell(),
        ),
      ),
    );
  }

  Widget bottomNavHost({double textScale = 1}) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF00A2FF), Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
        ),
      ),
    );
  }

  testWidgets('compact shell exposes four phone destinations', (tester) async {
    await tester.pumpWidget(shellHost(Breakpoints.medium - 1));
    await tester.pumpAndSettle();

    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.byType(AppNavRail), findsNothing);
    for (final label in ['Plans', 'History', 'Stats', 'Settings']) {
      expect(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('medium shell exposes the desktop rail and dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(shellHost(Breakpoints.medium));
    await tester.pumpAndSettle();

    expect(find.byType(AppNavRail), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppNavRail),
        matching: find.text('Dashboard'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('active destinations expose selected semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(bottomNavHost());
    final plansSemantics = tester.getSemantics(find.text('Plans'));
    expect(plansSemantics.label, contains('Plans'));
    expect(
      plansSemantics.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      plansSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.pumpWidget(shellHost(Breakpoints.medium));
    await tester.pumpAndSettle();
    final dashboardDestination = find.descendant(
      of: find.byType(AppNavRail),
      matching: find.text('Dashboard'),
    );
    final dashboardSemantics = tester.getSemantics(dashboardDestination);
    expect(dashboardSemantics.label, contains('Dashboard'));
    expect(
      dashboardSemantics.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      dashboardSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    semantics.dispose();
  });

  testWidgets('selected destination uses restrained accent emphasis', (
    tester,
  ) async {
    await tester.pumpWidget(bottomNavHost());
    final context = tester.element(find.byType(AppBottomNav));
    final selected = tester.widget<Text>(find.text('Plans')).style!;
    final unselected = tester.widget<Text>(find.text('History')).style!;

    expect(selected.color, accentColor(context));
    expect(selected.fontWeight, FontWeight.w700);
    expect(unselected.color, textSecondaryColor(context));
    expect(unselected.fontWeight, FontWeight.w500);
  });

  testWidgets('every navigation destination is at least 48 pixels high', (
    tester,
  ) async {
    await tester.pumpWidget(bottomNavHost());
    for (final inkWell in find.byType(InkWell).evaluate()) {
      expect(
        tester.getSize(find.byWidget(inkWell.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }

    await tester.pumpWidget(shellHost(Breakpoints.medium));
    await tester.pumpAndSettle();
    final rail = find.byType(AppNavRail);
    for (final inkWell
        in find
            .descendant(of: rail, matching: find.byType(InkWell))
            .evaluate()) {
      expect(
        tester.getSize(find.byWidget(inkWell.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('compact bottom destinations are at least 48 pixels wide', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(bottomNavHost());

    for (final inkWell in find.byType(InkWell).evaluate()) {
      final size = tester.getSize(find.byWidget(inkWell.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('compact navigation does not overflow at 2x text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(bottomNavHost(textScale: 2));
    await tester.pump();

    expect(tester.view.physicalSize.width, 320);
    expect(tester.takeException(), isNull);
  });
}
