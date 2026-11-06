import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'models/workout_session.dart';
import 'navigation/open_workout.dart';
import 'navigation/tab_swipe_recognizer.dart';
import 'navigation/workout_destination.dart';
import 'providers/coach_provider.dart';
import 'providers/update_provider.dart';
import 'providers/workout_plan_provider.dart';
import 'providers/workout_session_provider.dart';
import 'screens/coach_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/hive_service.dart';
import 'services/tutorial_preferences.dart';
import 'services/workout_timer_notification_service.dart';
import 'theme/breakpoints.dart';
import 'utils/scroll_to_top.dart';
import 'widgets/active_workout_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_nav_rail.dart';
import 'widgets/coach/coach_button.dart';
import 'widgets/guided_tour.dart';
import 'widgets/history/history_journal_data.dart';
import 'widgets/update_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Index into [_screens]. Dashboard is index 0 (desktop-only); the phone
  // bottom bar addresses screens 1–4.
  int _currentIndex = 0;
  int _weeklyTrainingRequest = 0;
  int _statsVisit = 0;
  int _homeResetRequest = 0;
  final GlobalKey<StatsScreenState> _statsKey = GlobalKey<StatsScreenState>();

  /// Tapping the tab that is already showing scrolls it back to the top.
  int _historyTopRequest = 0;
  int _statsTopRequest = 0;
  int _settingsTopRequest = 0;

  /// Fades the incoming tab in, so a tap or swipe reads as a move rather than
  /// a cut. The IndexedStack underneath still keeps every tab's state.
  late final AnimationController _tabFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );
  double _tabDragDistance = 0;
  TabSwipeGestureRecognizer? _tabSwipeRecognizer;
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

  /// The Coach covers Home inside its tab, so the navigation stays visible.
  bool _coachOpen = false;

  /// Guards against a second prompt if this State is rebuilt.
  // Update prompt bookkeeping. The provider decides whether an offer is due;
  // the shell decides whether now is a good moment for a dialog.
  UpdateProvider? _updates;
  bool _updateCheckStarted = false;
  bool _updateCheckRunning = false;
  bool _updatePromptOpen = false;
  StreamSubscription<void>? _updateOpenSubscription;

  /// A workout timer is running or paused, so no dialog may cover it and no
  /// update may close the app.
  bool _workoutLive = false;
  StreamSubscription<WorkoutTimerNotificationEvent>? _timerSubscription;
  int? _handledTimerIntentRevision;
  Future<void> _timerEvents = Future<void>.value();

  List<Widget> _screens({required bool coachShown, required int showing}) => [
    const DashboardScreen(),
    CoachHost(
      open: _openCoach,
      child: IndexedStack(
        index: coachShown ? 1 : 0,
        children: [
          HomeScreen(
            active: showing == 1 && !coachShown,
            resetRequest: _homeResetRequest,
            tutorialPlanKey: _planTourKey,
            tutorialStartKey: _startTourKey,
            tutorialScrollController: _homeScrollController,
            tutorialActive: _tourActive,
            onOpenWeeklyTraining: _openWeeklyTraining,
            onOpenLastWorkout: _openLastWorkout,
          ),
          if (coachShown)
            CoachScreen(onClose: _closeCoach)
          else
            const SizedBox.shrink(),
        ],
      ),
    ),
    HistoryScreen(scrollToTopRequest: _historyTopRequest),
    StatsScreen(
      key: _statsKey,
      weeklyTrainingRequest: _weeklyTrainingRequest,
      visitRequest: _statsVisit,
      scrollToTopRequest: _statsTopRequest,
    ),
    SettingsScreen(
      onReplayTutorial: _replayTutorial,
      scrollToTopRequest: _settingsTopRequest,
    ),
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
      _coachOpen = false;
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
          icon: LucideIcons.palette,
          label: 'Your style',
          title: 'Make OpenGym yours',
          body:
              'In Settings → Appearance, pick an accent color and choose a light or dark theme, or follow your device. You can replay this tour from Settings anytime.',
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

  void _openCoach() {
    setState(() {
      _coachOpen = true;
      _currentIndex = 1;
    });
  }

  void _closeCoach() {
    if (_coachOpen) setState(() => _coachOpen = false);
  }

  /// A tap on the tab that is already showing closes the Coach over Home and
  /// scrolls that tab back to the top.
  void _selectTab(int index, {required int showing}) {
    final reselected = index == showing;
    if (!reselected) {
      HapticFeedback.selectionClick();
      if (MediaQuery.disableAnimationsOf(context)) {
        _tabFade.value = 1;
      } else {
        _tabFade.forward(from: 0);
      }
    }
    setState(() {
      if (index == 1) _homeResetRequest++;
      if (reselected) {
        switch (index) {
          case 1:
            _coachOpen = false;
            scrollToTop(context, _homeScrollController);
          case 2:
            _historyTopRequest++;
          case 3:
            _statsTopRequest++;
          case 4:
            _settingsTopRequest++;
        }
      }
      // Stats reopens at the top whenever it is entered from another tab.
      if (index == 3 && showing != 3) _statsVisit++;
      _currentIndex = index;
    });
  }

  void _resumeWorkout(WorkoutSession session) {
    final id = session.id;
    if (id == null) return;
    unawaited(
      openWorkoutDestination(
        context,
        WorkoutDestination.session(id),
        requireIncomplete: true,
      ),
    );
  }

  /// The resume strip, rebuilt on every session write so it appears when a
  /// timer starts and disappears when the workout is finished or deleted.
  Widget _liveWorkoutStrip() {
    return ValueListenableBuilder(
      valueListenable: HiveService.sessionsListenable(),
      builder: (context, _, _) {
        final session = HiveService.getLiveSession();
        if (session == null) return const SizedBox.shrink();
        return ActiveWorkoutBar(
          session: session,
          onTap: () => _resumeWorkout(session),
        );
      },
    );
  }

  void _finishTabSwipe(DragEndDetails details, {required int showing}) {
    final distance = _tabDragDistance;
    _tabDragDistance = 0;
    // A drag that wandered too far up or down was a scroll, not a swipe.
    if (!(_tabSwipeRecognizer?.isMostlyHorizontal ?? true)) return;
    final velocity = details.primaryVelocity ?? 0;
    // Require a deliberate drag, or a short, fast flick. Vertical scrolling
    // competes with this horizontal recognizer in Flutter's gesture arena.
    final isDrag = distance.abs() >= 64;
    final isFlick =
        distance.abs() >= 20 &&
        velocity.abs() >= 500 &&
        velocity.sign == distance.sign;
    if (!isDrag && !isFlick) return;

    final forward =
        Directionality.of(context) == TextDirection.ltr
            ? distance < 0
            : distance > 0;
    if (showing == 3 &&
        (_statsKey.currentState?.handleSectionSwipe(forward: forward) ??
            false)) {
      return;
    }
    final next = showing + (forward ? 1 : -1);
    if (next == 3) {
      _statsKey.currentState?.handleSectionSwipe(
        forward: forward,
        entering: true,
      );
    }
    if (next >= 1 && next <= 4) _selectTab(next, showing: showing);
  }

  Widget _withTutorial(
    Widget shell, {
    required bool coachInView,
    required int showing,
  }) {
    return PopScope(
      canPop: !_tourActive && !coachInView && showing < 2,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_tourActive) {
          _closeTutorial();
        } else if (coachInView) {
          _closeCoach();
        } else if (showing >= 2) {
          _coachOpen = false;
          _selectTab(1, showing: showing);
        }
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
      unawaited(_restoreTimerNotification());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerSubscription?.cancel();
    _updateOpenSubscription?.cancel();
    _updates?.canInterrupt = () async => true;
    _homeScrollController.dispose();
    _tabFade.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_onResumed());
  }

  Future<void> _onResumed() async {
    await _reconcileCurrentTimer();
    // Only once the launch check has run: the tour defers it on first run.
    if (mounted && _updateCheckStarted) await _checkForUpdate();
  }

  Future<void> _restoreTimerNotification() async {
    await WorkoutTimerNotificationService.instance.restore();
    await _reconcileCurrentTimer();
    // The update check waits for this so it knows whether a workout is live,
    // but not for the timer's intent below, which can hold a pushed workout
    // route open for as long as the session lasts.
    if (mounted && !_tourActive) unawaited(_checkForUpdate());
    final event =
        await WorkoutTimerNotificationService.instance.consumeIntent();
    if (event != null) await _handleTimerEvent(event);
  }

  Future<void> _reconcileCurrentTimer() async {
    final snapshot = await WorkoutTimerNotificationService.instance.snapshot();
    final session = snapshot == null ? null : await _reconcileTimer(snapshot);
    _workoutLive = session != null;
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

  Future<void> _handleTimerEvent(WorkoutTimerNotificationEvent event) {
    // Do not let two intents both decide to push before the first route builds.
    _timerEvents = _timerEvents
        .then((_) => _openTimerWorkout(event))
        .catchError((Object error) {
          debugPrint('Could not open the timer workout: $error');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open your workout. Try again.'),
            ),
          );
        });
    return _timerEvents;
  }

  Future<void> _openTimerWorkout(WorkoutTimerNotificationEvent event) async {
    if (!mounted) return;
    final session = await _reconcileTimer(event.snapshot);
    if (!mounted || session == null || !event.openWorkout) return;
    if (_handledTimerIntentRevision == event.snapshot.actionRevision) return;
    if (_tourActive) _closeTutorial();
    _handledTimerIntentRevision = event.snapshot.actionRevision;

    await openWorkoutDestination(
      context,
      WorkoutDestination.session(session.id!),
      requestLogConfirmation: event.requestLogConfirmation,
      requireIncomplete: true,
    );
  }

  /// Runs the launch check the first time and the resume check after that,
  /// then opens the prompt if an offer is due and the moment is right.
  Future<void> _checkForUpdate() async {
    if (_updateCheckRunning) return;
    _updateCheckRunning = true;
    try {
      final updates = _updates ??= context.read<UpdateProvider>();
      // Read live, not from the last resume: a workout can start while a
      // download the user asked for is still coming down.
      updates.canInterrupt = () async {
        if (!mounted) return false;
        await _reconcileCurrentTimer();
        return !_workoutLive;
      };
      _updateOpenSubscription ??= updates.openRequests.listen(
        (_) => unawaited(_showUpdatePrompt()),
      );
      if (_updateCheckStarted) {
        await updates.checkOnResume();
      } else {
        _updateCheckStarted = true;
        await updates.checkOnStartup();
      }
      if (!mounted || !_mayPromptNow) return;

      final whatsNew = updates.takeWhatsNew();
      if (whatsNew != null) {
        _updatePromptOpen = true;
        try {
          await showWhatsNewDialog(context, whatsNew);
        } finally {
          _updatePromptOpen = false;
        }
        return;
      }

      if (!await updates.shouldPromptAutomatically()) return;
      if (!mounted || !_mayPromptNow) return;
      await updates.markPrompted();
      await _showUpdatePrompt();
    } finally {
      _updateCheckRunning = false;
    }
  }

  /// Whether a dialog may open by itself: not over the tour, a workout, or a
  /// screen the user pushed (a workout, a plan editor), and not twice.
  bool get _mayPromptNow =>
      !_updatePromptOpen &&
      !_tourActive &&
      !_replayingTutorial &&
      !_workoutLive &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  /// Opens the update dialog. Also the answer to tapping "Update ready to
  /// install", which the user asked for, so only the tour holds it back.
  Future<void> _showUpdatePrompt() async {
    if (!mounted || _updatePromptOpen || _tourActive) return;
    _updatePromptOpen = true;
    try {
      await showUpdateDialog(context);
    } finally {
      _updatePromptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Breakpoints.isWide(context);
    // Select, not watch: download progress ticks twice a second.
    final updatePending = context.select<UpdateProvider?, bool>(
      (updates) => updates?.hasPendingUpdate ?? false,
    );

    // Dashboard (index 0) is desktop-only. On the narrow bottom-bar layout it's
    // unreachable, so clamp the rendered/highlighted screen to Plans (index 1).
    // This is a render-time clamp — `_currentIndex` is left untouched so that
    // widening the window back returns the user to the Dashboard.
    final effectiveIndex =
        isWide ? _currentIndex : (_currentIndex == 0 ? 1 : _currentIndex);

    // Signing out hides the Coach even if it was open.
    final coachShown =
        _coachOpen &&
        context.select<CoachProvider?, bool>(
          (coach) => coach?.available ?? false,
        );
    final coachInView = coachShown && effectiveIndex == 1;

    final stack = FadeTransition(
      opacity: CurvedAnimation(parent: _tabFade, curve: Curves.easeOut),
      child: IndexedStack(
        index: effectiveIndex,
        children: _screens(coachShown: coachShown, showing: effectiveIndex),
      ),
    );

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
                badgedIndex: updatePending ? 4 : null,
                onTap: (i) => _selectTab(i, showing: effectiveIndex),
              ),
              Expanded(
                child: Column(
                  children: [Expanded(child: stack), _liveWorkoutStrip()],
                ),
              ),
            ],
          ),
        ),
        coachInView: coachInView,
        showing: effectiveIndex,
      );
    }

    return _withTutorial(
      Scaffold(
        body: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          gestures: {
            if (!coachInView)
              TabSwipeGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                TabSwipeGestureRecognizer
              >(() => TabSwipeGestureRecognizer(debugOwner: this), (
                recognizer,
              ) {
                _tabSwipeRecognizer = recognizer;
                recognizer.onStart = (_) => _tabDragDistance = 0;
                recognizer.onUpdate = (details) {
                  _tabDragDistance += details.primaryDelta ?? 0;
                };
                recognizer.onEnd = (details) {
                  _finishTabSwipe(details, showing: effectiveIndex);
                };
                recognizer.onCancel = () => _tabDragDistance = 0;
              }),
          },
          child: stack,
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _liveWorkoutStrip(),
            AppBottomNav(
              destinationKeys: {
                1: _historyTourKey,
                2: _statsTourKey,
                3: _settingsTourKey,
              },
              // Bottom bar slots [PLANS, HISTORY, STATS, SETTINGS] map to
              // screens 1–4.
              currentIndex: (effectiveIndex - 1).clamp(0, 3),
              badgedIndex: updatePending ? 3 : null,
              onTap: (i) => _selectTab(i + 1, showing: effectiveIndex),
            ),
          ],
        ),
      ),
      coachInView: coachInView,
      showing: effectiveIndex,
    );
  }
}
