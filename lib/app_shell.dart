import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/workout_session.dart';
import 'providers/split_provider.dart';
import 'providers/update_provider.dart';
import 'providers/workout_session_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'screens/workout_screen.dart';
import 'services/hive_service.dart';
import 'services/workout_timer_notification_service.dart';
import 'theme/breakpoints.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_nav_rail.dart';
import 'widgets/update_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  // Index into [_screens]. Dashboard is index 0 (desktop-only); the phone
  // bottom bar addresses screens 1–4.
  int _currentIndex = 0;

  /// Guards against a second prompt if this State is rebuilt.
  bool _updatePromptShown = false;
  StreamSubscription<WorkoutTimerNotificationEvent>? _timerSubscription;
  int? _handledTimerIntentRevision;

  final List<Widget> _screens = const [
    DashboardScreen(),
    HomeScreen(),
    HistoryScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timerSubscription = WorkoutTimerNotificationService.instance.events.listen(
      _handleTimerEvent,
    );
    // Deliberately not awaited. The check runs after the first frame so it
    // cannot delay startup, and AppShell is the first widget that is past both
    // Hive init and the auth gate — so the prompt never lands on the splash or
    // the login screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      _restoreTimerNotification();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileCurrentTimer();
    }
  }

  Future<void> _restoreTimerNotification() async {
    await WorkoutTimerNotificationService.instance.restore();
    await _reconcileCurrentTimer();
    final event =
        await WorkoutTimerNotificationService.instance.consumeIntent();
    if (event != null) await _handleTimerEvent(event);
  }

  Future<void> _reconcileCurrentTimer() async {
    final snapshot = await WorkoutTimerNotificationService.instance.snapshot();
    if (snapshot != null) await _reconcileTimer(snapshot);
  }

  Future<WorkoutSession?> _reconcileTimer(
    WorkoutTimerNotificationSnapshot snapshot,
  ) async {
    final current = HiveService.getSessionById(snapshot.sessionId);
    if (current == null || current.isCompleted || current.deletedAt != null) {
      await WorkoutTimerNotificationService.instance.dismiss();
      return null;
    }
    final reconciled = current.copyWith(
      timerStartedAt: snapshot.isRunning ? snapshot.runningSince : null,
      durationSeconds: snapshot.accumulatedSeconds,
    );
    final timerChanged =
        current.timerStartedAt != reconciled.timerStartedAt ||
        current.durationSeconds != reconciled.durationSeconds;
    if (timerChanged && mounted) {
      await context.read<WorkoutSessionProvider>().upsertSession(reconciled);
    }
    return reconciled;
  }

  Future<void> _handleTimerEvent(WorkoutTimerNotificationEvent event) async {
    final session = await _reconcileTimer(event.snapshot);
    if (!mounted || session == null || !event.openWorkout) return;
    if (_handledTimerIntentRevision == event.snapshot.actionRevision) return;
    _handledTimerIntentRevision = event.snapshot.actionRevision;

    final planId = session.planId;
    final plan = planId == null ? null : HiveService.getPlanById(planId);
    if (plan == null || plan.deletedAt != null) {
      await WorkoutTimerNotificationService.instance.dismiss();
      return;
    }
    final splitId = plan.splitId;
    final splitProvider = context.read<SplitProvider>();
    if (splitId != null && splitProvider.activeSplitId != splitId) {
      try {
        await splitProvider.setActiveSplit(splitId);
      } catch (_) {
        // The workout can still be opened directly if an offline account does
        // not currently permit changing the saved split preference.
      }
    }
    if (!mounted) return;
    final plans = HiveService.getPlans(splitId: splitId);
    final planIndex = plans.indexWhere((candidate) => candidate.id == plan.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => WorkoutScreen(
              plan: plan,
              planIndex: planIndex < 0 ? 0 : planIndex,
              initialWeekNumber: session.weekNumber,
              showLogConfirmationOnOpen: event.requestLogConfirmation,
            ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    final updates = context.read<UpdateProvider>();
    await updates.checkOnStartup();
    if (!mounted || _updatePromptShown) return;
    if (!updates.isUpdateAvailable) return;
    _updatePromptShown = true;
    await showUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Breakpoints.isWide(context);

    // Dashboard (index 0) is desktop-only. On the narrow bottom-bar layout it's
    // unreachable, so clamp the rendered/highlighted screen to Plans (index 1).
    // This is a render-time clamp — `_currentIndex` is left untouched so that
    // widening the window back returns the user to the Dashboard.
    final effectiveIndex =
        isWide ? _currentIndex : (_currentIndex == 0 ? 1 : _currentIndex);

    final stack = IndexedStack(index: effectiveIndex, children: _screens);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            AppNavRail(
              currentIndex: effectiveIndex,
              onTap: (i) => setState(() => _currentIndex = i),
            ),
            Expanded(child: stack),
          ],
        ),
      );
    }

    return Scaffold(
      body: stack,
      bottomNavigationBar: AppBottomNav(
        // Bottom bar slots [PLANS, HISTORY, STATS, SETTINGS] map to screens 1–4.
        currentIndex: (effectiveIndex - 1).clamp(0, 3),
        onTap: (i) => setState(() => _currentIndex = i + 1),
      ),
    );
  }
}
