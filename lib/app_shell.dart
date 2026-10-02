import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'models/workout_session.dart';
import 'providers/split_provider.dart';
import 'providers/update_provider.dart';
import 'providers/workout_plan_provider.dart';
import 'providers/workout_session_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'screens/workout_screen.dart';
import 'services/hive_service.dart';
import 'services/tutorial_preferences.dart';
import 'services/workout_timer_notification_service.dart';
import 'theme/breakpoints.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_nav_rail.dart';
import 'widgets/guided_tour.dart';
import 'widgets/history/history_journal_data.dart';
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
  int _weeklyTrainingRequest = 0;
  bool _openingHistoryWorkout = false;
  final ScrollController _homeScrollController = ScrollController();
  final GlobalKey _planTourKey = GlobalKey(debugLabel: 'tutorial-plan');
  final GlobalKey _startTourKey = GlobalKey(debugLabel: 'tutorial-start');
  final GlobalKey _historyTourKey = GlobalKey(debugLabel: 'tutorial-history');
  final GlobalKey _statsTourKey = GlobalKey(debugLabel: 'tutorial-stats');
  final GlobalKey _settingsTourKey = GlobalKey(debugLabel: 'tutorial-settings');
  List<GuidedTourStep> _tourSteps = const [];
  bool _tourActive = false;
  bool _replayingTutorial = false;

  /// Guards against a second prompt if this State is rebuilt.
  bool _updatePromptShown = false;
  StreamSubscription<WorkoutTimerNotificationEvent>? _timerSubscription;
  int? _handledTimerIntentRevision;

  List<Widget> get _screens => [
    const DashboardScreen(),
    HomeScreen(
      tutorialPlanKey: _planTourKey,
      tutorialStartKey: _startTourKey,
      tutorialScrollController: _homeScrollController,
      tutorialActive: _tourActive,
      onOpenWeeklyTraining: _openWeeklyTraining,
      onOpenLastWorkout: _openLastWorkout,
    ),
    const HistoryScreen(),
    StatsScreen(weeklyTrainingRequest: _weeklyTrainingRequest),
    SettingsScreen(onReplayTutorial: _replayTutorial),
  ];

  Future<void> _maybeStartTutorial() async {
    try {
      if (await TutorialPreferences.isTourPending() && mounted) {
        await _startTutorial();
      }
    } catch (error) {
      debugPrint('Could not start tutorial: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the tutorial. Try Replay tutorial in Settings.',
          ),
        ),
      );
    }
  }

  Future<void> _startTutorial() async {
    await TutorialPreferences.markTourSeen();
    if (!mounted) return;
    final hasPlans = context.read<WorkoutPlanProvider>().plans.isNotEmpty;
    setState(() {
      _currentIndex = 1;
      _tourSteps = [
        GuidedTourStep(
          target: _planTourKey,
          icon: LucideIcons.clipboardList,
          label: 'Build your routine',
          title: hasPlans ? 'Make a plan' : 'Plan your first workout',
          body:
              hasPlans
                  ? 'Use New plan to group your exercises into a workout you can repeat. You can also choose a ready-made routine from the split menu.'
                  : 'Tap Create plan to pick your exercises, or use Choose a split below for a ready-made routine.',
          scrollController: _homeScrollController,
          scrollToEnd: hasPlans,
        ),
        if (hasPlans)
          GuidedTourStep(
            target: _startTourKey,
            icon: LucideIcons.play,
            label: 'At the gym',
            title: 'Log as you lift',
            body:
                'Start workout opens your exercise list. Tap Start to run the timer, log your weight and reps for each set, then Finish workout to save it to History.',
            scrollController: _homeScrollController,
          ),
        GuidedTourStep(
          target: _historyTourKey,
          icon: LucideIcons.history,
          label: 'Look back',
          title: 'Find past workouts',
          body:
              'Your finished workouts land in History. Open a workout to check your sets, weights, and notes before your next session.',
          scrollController: _homeScrollController,
        ),
        GuidedTourStep(
          target: _statsTourKey,
          icon: LucideIcons.trendingUp,
          label: 'Keep building',
          title: 'See your progress',
          body:
              'See your training consistency and personal records. As you log workouts, your numbers here grow with you.',
        ),
        GuidedTourStep(
          target: _settingsTourKey,
          icon: LucideIcons.databaseBackup,
          label: 'Keep your training safe',
          title: 'Save a backup',
          body:
              'In Settings → Data, use Export data to save a backup and Import data to restore it. You can replay this tour from Settings anytime.',
        ),
      ];
      _tourActive = true;
    });
  }

  void _closeTutorial() {
    if (!_tourActive) return;
    setState(() => _tourActive = false);
    unawaited(_checkForUpdate());
  }

  Future<void> _replayTutorial() async {
    if (_replayingTutorial || _tourActive) return;
    _replayingTutorial = true;
    try {
      final continueToTour = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder:
              (introContext) => IntroScreen(
                onFinish: () async => Navigator.of(introContext).pop(true),
                onSkip: () async => Navigator.of(introContext).pop(false),
              ),
        ),
      );
      if (continueToTour == true && mounted) await _startTutorial();
    } finally {
      _replayingTutorial = false;
    }
  }

  Widget _withTutorial(Widget shell) {
    return PopScope(
      canPop: !_tourActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _tourActive) _closeTutorial();
      },
      child: Stack(
        children: [
          ExcludeSemantics(
            excluding: _tourActive,
            child: ExcludeFocus(
              excluding: _tourActive,
              child: AbsorbPointer(absorbing: _tourActive, child: shell),
            ),
          ),
          if (_tourActive)
            Positioned.fill(
              child: FocusScope(
                autofocus: true,
                child: GuidedTour(steps: _tourSteps, onClose: _closeTutorial),
              ),
            ),
        ],
      ),
    );
  }

  void _openWeeklyTraining() {
    setState(() {
      _currentIndex = 3;
      _weeklyTrainingRequest++;
    });
  }

  void _openLastWorkout(WorkoutSession session) {
    if (_openingHistoryWorkout) return;
    _openingHistoryWorkout = true;
    setState(() => _currentIndex = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => WorkoutDetailsScreen(
                sessionIdentity: historySessionIdentity(session),
              ),
        ),
      );
      _openingHistoryWorkout = false;
    });
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeStartTutorial();
      if (!mounted) return;
      if (!_tourActive) unawaited(_checkForUpdate());
      unawaited(_restoreTimerNotification());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerSubscription?.cancel();
    _homeScrollController.dispose();
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
    if (_tourActive) _closeTutorial();
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
    if (!mounted || _updatePromptShown || _tourActive || _replayingTutorial) {
      return;
    }
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
      return _withTutorial(
        Scaffold(
          body: Row(
            children: [
              AppNavRail(
                destinationKeys: {
                  2: _historyTourKey,
                  3: _statsTourKey,
                  4: _settingsTourKey,
                },
                currentIndex: effectiveIndex,
                onTap: (i) => setState(() => _currentIndex = i),
              ),
              Expanded(child: stack),
            ],
          ),
        ),
      );
    }

    return _withTutorial(
      Scaffold(
        body: stack,
        bottomNavigationBar: AppBottomNav(
          destinationKeys: {
            1: _historyTourKey,
            2: _statsTourKey,
            3: _settingsTourKey,
          },
          // Bottom bar slots [PLANS, HISTORY, STATS, SETTINGS] map to screens 1–4.
          currentIndex: (effectiveIndex - 1).clamp(0, 3),
          onTap: (i) => setState(() => _currentIndex = i + 1),
        ),
      ),
    );
  }
}
