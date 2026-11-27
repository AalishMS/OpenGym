import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../services/exercise_catalog.dart';
import '../data/plan_colors.dart';
import '../models/exercise.dart';
import '../models/statistics.dart';
import '../models/set.dart' as gym;
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_plan.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../navigation/app_navigation_observer.dart';
import '../navigation/workout_destination.dart';
import '../providers/settings_provider.dart';
import '../providers/training_block_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../repositories/training_block_repository.dart';
import '../services/hive_service.dart';
import '../services/plan_exercise_swap.dart';
import '../services/statistics_analytics_service.dart';
import '../services/sync_service.dart';
import '../services/tutorial_preferences.dart';
import '../services/workout_progression_service.dart';
import '../services/workout_session_initializer.dart';
import '../services/workout_timer_notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/format.dart';
import '../utils/haptics.dart';
import '../utils/set_history.dart';
import '../utils/workout_context.dart';
import '../widgets/action_progress.dart';
import '../widgets/app_header.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/exercise_rename_dialog.dart';
import '../widgets/motion/app_modals.dart';
import '../widgets/motion/collapsible.dart';
import '../widgets/motion/page_switcher.dart';
import '../widgets/motion/patient_progress.dart';
import '../widgets/persistence_dialog.dart';
import '../widgets/plan_title_hero.dart';
import '../widgets/underline_tab_strip.dart';
import '../widgets/workout/exercise_card.dart';
import '../widgets/workout/exercise_reorder.dart';
import '../widgets/workout/plan_swipe_region.dart';
import '../widgets/workout/set_entry_table.dart';
import '../widgets/workout/training_block_dialogs.dart';
import '../widgets/workout/training_block_strip.dart';
import '../widgets/workout/training_boundary_sheet.dart';
import '../widgets/workout/workout_dialogs.dart';
import '../widgets/workout/workout_time_dialog.dart';
import 'workout_summary_screen.dart';

class WorkoutScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final int planIndex;
  final WorkoutDestination? destination;
  final bool showLogConfirmationOnOpen;

  /// Set when opened from Home's Next up card; the plan name flies in.
  final String? heroTag;

  const WorkoutScreen({
    super.key,
    required this.plan,
    required this.planIndex,
    this.destination,
    this.showLogConfirmationOnOpen = false,
    this.heroTag,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen>
    with TickerProviderStateMixin, AppRouteParticipant<WorkoutScreen>
    implements WorkoutNavigationTarget {
  @override
  Future<void> leaveRoute() => _handleBack();

  @override
  WorkoutNavigationTarget get workoutTarget => this;

  @override
  bool displaysSession(String sessionId) =>
      _weeks.isNotEmpty && _savedSessionForWeek(_currentWeek)?.id == sessionId;

  @override
  bool get canHandleNotification =>
      mounted && !_isSaving && !_isNavigating && _timerAction == null;

  @override
  Future<bool> handleNotification({
    required bool requestLogConfirmation,
  }) async {
    if (!canHandleNotification) return false;
    if (requestLogConfirmation) await _stopWorkout();
    return true;
  }

  List<String> _weeks = [];
  Map<String, TrainingWeek> _weekById = {};
  List<TrainingBlock> _blocks = [];
  Map<String, List<TrainingWeek>> _weeksByBlock = {};
  final Map<String, String> _viewedWeekByBlock = {};
  late final TrainingBlockProvider _training;
  late final bool _ownsTraining;
  late final TrainingBlockRepository _structure;
  late final WorkoutProgressionService _progression;
  bool _boundaryShowing = false;
  bool _progressError = false;
  final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now());
  List<WorkoutSession> _previousRows = [];
  final Map<String, List<gym.Set>> _previousSets = {};
  RecordJudge? _recordCache;

  /// Record sets already felt, so each new one buzzes once. Null until the
  /// week's log is first shown, so records it opened with stay quiet.
  Set<String>? _celebratedRecords;
  int _currentWeekIndex = 0;
  final Map<String, WorkoutSession> _weekSessions = {};
  bool _hasUnsavedChanges = false;
  int _draftRevision = 0;
  Future<bool>? _saveFuture;
  bool _isNavigating = false;
  bool _isSaving = false;
  String? _saveError;

  /// The last save error shown, kept while its line folds away.
  String? _shownSaveError;
  String? _timerAction;
  bool _confirmingFinish = false;
  Timer? _ticker;
  WorkoutSessionProvider? _sessionProvider;
  bool _didShowInitialLogConfirmation = false;

  /// The log's own sideways motion: following a plan swipe, settling back,
  /// and leaving when the plan changes.
  late final _LogMotion _log = _LogMotion(this);

  /// True from the moment a plan switch starts until it fails: the log is
  /// on its way out, so it leaves the semantics tree.
  bool _leaving = false;

  /// True once the chosen plan's workout has been pushed over this one. The
  /// work feedback that stays in place (the progress line, a save error) is
  /// hidden then, so none of it shows through the arriving page.
  bool _handedOver = false;

  /// Scrolls the plan tabs. A switch starts the next workout's strip where
  /// this one stands, so the tabs hold still through it.
  ScrollController? _planTabs;

  @override
  void initState() {
    super.initState();
    final provided = context.read<TrainingBlockProvider?>();
    _ownsTraining = provided == null || provided.splitId != widget.plan.splitId;
    _training =
        !_ownsTraining
            ? provided!
            : TrainingBlockProvider(
              splitIdProvider: () => widget.plan.splitId,
              ownerId: () => widget.plan.userId,
            );
    _structure = TrainingBlockRepository(ownerId: () => widget.plan.userId);
    _progression = WorkoutProgressionService(
      ownerId: () => widget.plan.userId,
      writeSession:
          (session) =>
              context.read<WorkoutSessionProvider>().upsertSession(session),
    );
    _loadStructure(initial: true);
    _training.addListener(_onTrainingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _sessionProvider =
          context.read<WorkoutSessionProvider>()
            ..addListener(_reloadCurrentSession);
      await _prepareEntry();
      if (!mounted) return;
      if (widget.showLogConfirmationOnOpen && !_didShowInitialLogConfirmation) {
        _didShowInitialLogConfirmation = true;
        _stopWorkout();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _planTabs ??= ScrollController(
      initialScrollOffset: _PlanSwitchArrival.maybeOf(context)?.tabOffset ?? 0,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _now.dispose();
    _training.removeListener(_onTrainingChanged);
    if (_ownsTraining) _training.dispose();
    _sessionProvider?.removeListener(_reloadCurrentSession);
    _log.dispose();
    _planTabs?.dispose();
    super.dispose();
  }

  void _reloadCurrentSession() {
    if (!mounted || _hasUnsavedChanges || _isSaving || _timerAction != null) {
      return;
    }
    _training.reload();
  }

  void _onTrainingChanged() {
    if (!mounted || _hasUnsavedChanges || _isSaving || _timerAction != null) {
      return;
    }
    _loadStructure();
    setState(() {});
  }

  void _loadStructure({bool initial = false}) {
    final selected = _weeks.isEmpty ? null : _currentWeek;
    _blocks = _training.blocks;
    _weekById = _training.weekById;
    _weeksByBlock = _training.weeksByBlockForPlan(widget.plan.id ?? '');
    _weeks = [
      for (final block in _blocks)
        for (final week in _weeksByBlock[block.id] ?? <TrainingWeek>[]) week.id,
    ];
    if (_weeks.isEmpty) return;
    if (!_hasUnsavedChanges) {
      _weekSessions.removeWhere(
        (_, session) =>
            session.id != null &&
            HiveService.getSessionById(session.id!) == null,
      );
    }
    final intent = widget.destination;
    final exact =
        intent?.sessionId == null
            ? null
            : HiveService.getSessionById(intent!.sessionId!);
    final requested =
        initial ? exact?.trainingWeekId ?? intent?.weekId : selected;
    final destination =
        requested != null && _weeks.contains(requested)
            ? requested
            : _training.progressByPlan[widget.plan.id]?.activeWeekId;
    _currentWeekIndex =
        destination != null && _weeks.contains(destination)
            ? _weeks.indexOf(destination)
            : 0;
    if (initial &&
        exact != null &&
        exact.deletedAt == null &&
        exact.trainingWeekId == _currentWeek) {
      _weekSessions[_currentWeek] = exact;
    }
    _loadSessionForCurrentWeek();
  }

  void _loadSessionForCurrentWeek() {
    if (_weeks.isEmpty) return;
    _viewedWeekByBlock[_selectedWeek.blockId] = _currentWeek;
    final saved = _savedSessionForWeek(_currentWeek);
    if (saved != null) {
      _weekSessions[_currentWeek] = saved;
      _syncTicker(saved);
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    _previousRows =
        widget.plan.id == null
            ? []
            : _training.previous(
              widget.plan.id!,
              _currentWeek,
              excludingSessionId: saved?.id,
            );
    _previousSets.clear();
    _recordCache = null;
    _celebratedRecords = null;
  }

  Set<String> _recordSetsIn(WorkoutSession session) {
    if (session.isCompleted) return {};
    return {
      for (final MapEntry(key: exercise, value: sets)
          in _liveRecords(session).entries)
        for (final set in sets) '$exercise#$set',
    };
  }

  /// Runs when a value entry closes: a set that has just become a record
  /// gets the record haptic along with its PR mark.
  void _celebrateNewRecords() {
    final current = _recordSetsIn(_getOrCreateSession());
    final before = _celebratedRecords ?? current;
    if (current.difference(before).isNotEmpty) Haptics.celebrate();
    _celebratedRecords = current;
  }

  /// Bests from the workouts this one is judged against: the split's other
  /// logs ordered before it, exactly the window Finish judges it in - by
  /// date, then by ID for logs at the same time. A logged workout being
  /// edited therefore never has a record hidden by a later session.
  RecordJudge get _recordJudge =>
      _recordCache ??= () {
        final current = _weekSessions[_currentWeek];
        final currentId = current?.id;
        return const StatisticsAnalyticsService().recordJudge(
          HiveService.getCompletedSessions(splitId: widget.plan.splitId).where(
            (session) =>
                session.deletedAt == null &&
                session.id != currentId &&
                (current == null ||
                    StatisticsAnalyticsService.isLoggedBefore(
                      session,
                      current,
                    )),
          ),
        );
      }();

  /// Set indexes, by exercise index, that would be heaviest-weight records if
  /// [session] were logged as entered. Judged by the app's one record
  /// definition, so a live mark is exactly a record the summary, History and
  /// Stats will show: none on a lift's first workout, one per lift, and none
  /// for timed holds.
  Map<int, Set<int>> _liveRecords(WorkoutSession session) {
    final marks = <int, Set<int>>{};
    for (final event in _recordJudge.recordsFor(session)) {
      for (final achievement in event.achievements) {
        if (achievement.type != RecordType.heaviestWeight) continue;
        final exercise = achievement.exerciseIndex;
        final set = achievement.setIndex;
        if (exercise == null || set == null) continue;
        marks.putIfAbsent(exercise, () => {}).add(set);
      }
    }
    return marks;
  }

  WorkoutSession? _savedSessionForWeek(String week) {
    final selected = _weekSessions[week];
    if (selected != null) {
      final latest =
          selected.id == null ? null : HiveService.getSessionById(selected.id!);
      return latest ?? selected;
    }
    if (widget.plan.id == null) return null;
    return _training.destination(widget.plan.id!, week);
  }

  List<gym.Set> _previousFor(String name) => _previousSets.putIfAbsent(
    name.trim().toLowerCase(),
    () => exerciseSetsFromOrderedHistory(_previousRows, name),
  );

  void _syncTicker(WorkoutSession session) {
    if (session.isTimerRunning) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) _now.value = DateTime.now();
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  gym.Set? _getLastSetForExerciseInPlan(String name) =>
      _previousFor(name).lastOrNull;

  Future<void> _onWeekChanged(String weekId) async {
    await _saveBeforeNavigation(() {
      _training.reload();
      if (!_weeks.contains(weekId)) return;
      setState(() => _currentWeekIndex = _weeks.indexOf(weekId));
      _loadSessionForCurrentWeek();
    });
  }

  Future<bool> _autoSave() =>
      _saveFuture ??= _persistDraft().whenComplete(() => _saveFuture = null);

  Future<bool> _persistDraft() async {
    final provider = context.read<WorkoutSessionProvider>();
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      while (mounted) {
        var session = _getOrCreateSession();
        if (!_hasUnsavedChanges) return true;
        final saved =
            session.id == null ? null : HiveService.getSessionById(session.id!);
        if (saved != null &&
            (saved.deletedAt != null ||
                (saved.isCompleted && !session.isCompleted))) {
          // A synced deletion/completion must also survive Back's autosave.
          // Edits to a log that is already completed here save normally.
          _weekSessions[_currentWeek] = saved;
          _hasUnsavedChanges = false;
          return true;
        }
        if (!_hasUnsavedChanges && saved == null) return true;
        final hasSets = session.exercises.any((e) => e.sets.isNotEmpty);
        if (!hasSets && !_hasUnsavedChanges) return true;
        final revision = _draftRevision;
        final week = _currentWeek;
        // Keep the identity assigned by the first write for subsequent edits.
        session = session.copyWith(
          planId: widget.plan.id,
          // A log keeps the name it was recorded under if the plan is renamed.
          planName: session.isCompleted ? session.planName : widget.plan.name,
          weekNumber: _weekById[week]!.number,
          trainingWeekId: week,
          splitId: widget.plan.splitId,
        );
        _weekSessions[week] = session;
        await provider.upsertSession(session);
        if (revision == _draftRevision) {
          _hasUnsavedChanges = false;
          // A structural reload may have been deferred while this edit was
          // unsaved. Rebuild from the canonical row after persisting its values.
          if (!identical(_weekById, _training.weekById)) {
            _loadStructure();
          }
          return true;
        }
        // Edits made during that write must be flushed before navigation.
      }
    } catch (exception) {
      debugPrint('Failed to save workout draft: $exception');
      _hasUnsavedChanges = true;
      if (mounted) {
        setState(
          () =>
              _saveError =
                  'Could not save the workout. Your edits are still here.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save the workout. Your edits are still here. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
    return false;
  }

  Future<void> _saveBeforeNavigation(
    VoidCallback navigate, {
    bool leavesScreen = false,
  }) async {
    if (_isNavigating || _timerAction != null || !mounted) return;
    setState(() => _isNavigating = true);
    final saved = await _autoSave();
    if (!mounted) return;
    if (saved) navigate();
    if (!saved || !leavesScreen) {
      setState(() => _isNavigating = false);
    }
  }

  Future<void> _handleBack() async {
    if (_isNavigating || _timerAction != null || !mounted) return;
    // The keypad owns a LocalHistoryEntry. A pop consumes that entry without
    // leaving this route, so it must not set the screen's navigation lock.
    if (ModalRoute.of(context)?.willHandlePopInternally ?? false) {
      Navigator.pop(context);
      return;
    }
    await _saveBeforeNavigation(
      () => Navigator.pop(context),
      leavesScreen: true,
    );
  }

  int _currentPlanIndex(List<WorkoutPlan> plans) => plans.indexWhere(
    (plan) =>
        identical(plan, widget.plan) ||
        (widget.plan.id != null && plan.id == widget.plan.id) ||
        (widget.plan.key != null && plan.key == widget.plan.key),
  );

  void _updatePlanSwipe(double distance) {
    if (MediaQuery.disableAnimationsOf(context) || _leaving) return;
    final plans = context.read<WorkoutPlanProvider>().plans;
    final index = _currentPlanIndex(plans);
    _log.follow(
      distance,
      towardPlan: distance < 0 ? index < plans.length - 1 : index > 0,
    );
  }

  /// Springs the log back to rest after a plan swipe that didn't switch, or
  /// a switch whose save failed, carrying the finger's release [velocity].
  void _settlePlanSwipe([double velocity = 0]) {
    if (!mounted) return;
    if (_leaving) setState(() => _leaving = false);
    if (MediaQuery.disableAnimationsOf(context)) {
      _log.rest();
    } else {
      _log.settle(velocity);
    }
  }

  /// Switches to [plan], the plan at [index]: the current workout is saved,
  /// then the chosen plan's workout replaces this one. A swipe passes the
  /// finger's release [velocity] for the log to carry on out with; a tab tap
  /// starts it from rest.
  Future<void> _switchPlan(
    WorkoutPlan plan,
    int index, [
    double velocity = 0,
  ]) async {
    final currentIndex = _currentPlanIndex(
      context.read<WorkoutPlanProvider>().plans,
    );
    if (index == currentIndex) return;
    if (_isNavigating || _timerAction != null) {
      // Busy, so nothing switches; a log that followed the finger goes back.
      _settlePlanSwipe(velocity);
      return;
    }
    final direction = index > currentIndex ? 1.0 : -1.0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) {
      // The log leaves at once, before the save, so the hand's motion never
      // stalls; the chosen plan's log comes in over it when it is pushed.
      setState(() => _leaving = true);
      _log.leave(
        direction: direction,
        velocity: velocity,
        distance: AppMotion.swipeShift(MediaQuery.sizeOf(context).width),
      );
    }
    final replaced = ModalRoute.of(context);
    final tabs = _planTabs;
    await _saveBeforeNavigation(() {
      setState(() => _handedOver = true);
      Navigator.pushReplacement(
        context,
        _PlanSwitchRoute(
          direction: direction,
          replacing: replaced,
          reduceMotion: reduceMotion,
          fromIndex: currentIndex,
          tabOffset: tabs != null && tabs.hasClients ? tabs.offset : 0,
          builder: (_) => WorkoutScreen(plan: plan, planIndex: index),
        ),
      );
    }, leavesScreen: true);
    // A failed save pushes nothing: the log comes back.
    if (mounted && !_isNavigating) _settlePlanSwipe();
  }

  String get _currentWeek => _weeks[_currentWeekIndex];
  TrainingWeek get _selectedWeek => _weekById[_currentWeek]!;
  WorkoutProgress? get _progress => _training.progressByPlan[widget.plan.id];
  bool get _activeSlot =>
      _progress?.activeWeekId == _currentWeek &&
      _progress?.state == WorkoutProgressState.ready;
  String get _contextLabel =>
      '${_blocks.firstWhere((b) => b.id == _selectedWeek.blockId).name} · Week ${_selectedWeek.number}';
  bool _canUseTimer(WorkoutSession session) =>
      _activeSlot ||
      (widget.destination?.sessionId == session.id &&
          session.id != null &&
          session.hasStarted);

  /// The plan as saved now. A sync from another device can rewrite the saved
  /// plan while this screen is open, so a week opened afterwards must not be
  /// built from the copy this screen was pushed with.
  WorkoutPlan get _livePlan => _savedPlan ?? widget.plan;

  /// The plan in storage, or null once it has been deleted or has left this
  /// split. Anything that writes the plan must start from this and never
  /// from [_livePlan]'s fallback, which would save the copy this screen was
  /// pushed with over a deletion.
  WorkoutPlan? get _savedPlan {
    final id = widget.plan.id;
    final saved = id == null ? null : HiveService.getPlanById(id);
    return saved != null &&
            saved.deletedAt == null &&
            saved.splitId == widget.plan.splitId
        ? saved
        : null;
  }

  WorkoutSession _getOrCreateSession() {
    if (_weekSessions[_currentWeek] case final session?) return session;
    final session = _initializeSession(
      existingSession: _savedSessionForWeek(_currentWeek),
    );
    _weekSessions[_currentWeek] = session;
    return session;
  }

  /// Builds the selected week's workout, or returns [existingSession] when it
  /// is saved. A week with no saved data carries over the exercises of this
  /// plan's last logged workout, with the plan's edits since applied, and
  /// starts from the previous week's logged sets while *Start from last week's
  /// sets* is on, or from the plan's targets while it is off. Saved drafts and
  /// logs are never changed.
  WorkoutSession _initializeSession({WorkoutSession? existingSession}) {
    final startFromLastWeek =
        context.read<SettingsProvider?>()?.autoFillLast ?? true;
    final planId = widget.plan.id;
    return WorkoutSessionInitializer.initialize(
      plan: _livePlan,
      week: _selectedWeek,
      existingSession: existingSession,
      previousSession:
          planId == null ? null : _training.source(planId, _currentWeek),
      lastSession:
          planId == null
              ? null
              : _training.previous(planId, _currentWeek).firstOrNull,
      copySets: startFromLastWeek,
    );
  }

  void _updateSession(WorkoutSession session) {
    if (_getOrCreateSession().deletedAt != null) return;
    _weekSessions[_currentWeek] = session;
    _hasUnsavedChanges = true;
    _draftRevision++;
    setState(() {});
  }

  Future<void> _toggleTimer() async {
    if (_timerAction != null || _isNavigating || _isSaving) return;
    final current = _getOrCreateSession();
    if (current.isCompleted) return;
    setState(
      () =>
          _timerAction =
              current.isTimerRunning ? 'Pausing workout' : 'Starting workout',
    );
    try {
      await _persistTimerChange(current);
    } catch (error) {
      debugPrint('Failed to change workout timer: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not change the timer. Your workout is still here. Try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _timerAction = null);
    }
  }

  Future<void> _persistTimerChange(WorkoutSession current) async {
    // Save entered sets first. Timer state is published only after its write.
    if (!await _autoSave() || !mounted) return;
    current = _getOrCreateSession();
    if (!_canUseTimer(current)) return;
    if (current.isCompleted || current.deletedAt != null) return;
    final week = _currentWeek;
    if (current.id != null && HiveService.getSessionById(current.id!) == null) {
      // Start is an explicit draft-creation action. Persist its stable identity
      // before asking about another timer, then re-read it after confirmation.
      _hasUnsavedChanges = true;
      _draftRevision++;
      if (!await _autoSave() || !mounted) return;
      current = _getOrCreateSession();
    }

    if (current.isTimerRunning) {
      final paused = current.copyWith(
        timerStartedAt: null,
        durationSeconds: current.elapsedSeconds(),
      );
      await context.read<WorkoutSessionProvider>().upsertSession(paused);
      _weekSessions[week] = paused;
      _syncTicker(paused);
      _hasUnsavedChanges = false;
      await _updateTimerNotification(
        () => WorkoutTimerNotificationService.instance.pause(paused),
      );
      if (mounted) setState(() {});
      return;
    }

    var other = await _otherRunningSession(current.id);
    if (!mounted) return;
    while (other != null) {
      final conflict = other;
      final switchWorkout = await showAppDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Start this workout?'),
              content: Text(
                '${conflict.planName}, ${workoutContext(conflict)} still has a saved '
                'running timer. Pause it and start this workout? '
                'Its sets will be kept.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Pause and start'),
                ),
              ],
            ),
      );
      if (switchWorkout != true || !mounted) return;
      // Read again after the dialog so a notification action or sync cannot
      // make us write an older copy of the other workout's sets.
      final latest = HiveService.getSessionById(conflict.id!);
      if (latest != null && latest.deletedAt == null && latest.isTimerRunning) {
        final paused = latest.copyWith(
          timerStartedAt: null,
          durationSeconds: latest.elapsedSeconds(),
        );
        await context.read<WorkoutSessionProvider>().upsertSession(paused);
        await _updateTimerNotification(
          () => WorkoutTimerNotificationService.instance.pause(paused),
        );
      }
      if (!mounted) return;
      other = await _otherRunningSession(current.id);
      if (!mounted) return;
    }

    // The current draft can also change through sync while confirmation is
    // open. Never overwrite newer sets or restart a finished/deleted session.
    if (current.id != null) {
      final latest = HiveService.getSessionById(current.id!);
      if ((latest == null && current.hasStarted) || latest?.deletedAt != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This workout was deleted. Reopen it from Home.'),
          ),
        );
        return;
      }
      if (latest != null) {
        current = latest;
        _weekSessions[week] = latest;
        _syncTicker(latest);
      }
      if (latest?.isCompleted == true || latest?.isTimerRunning == true) {
        setState(() {});
        return;
      }
    }

    final now = DateTime.now();
    final started = current.copyWith(
      date: current.startedAt == null ? now : current.date,
      startedAt: current.startedAt ?? now,
      timerStartedAt: now,
      durationSeconds: current.durationSeconds ?? 0,
      planId: widget.plan.id,
      splitId: widget.plan.splitId,
    );
    await context.read<WorkoutSessionProvider>().upsertSession(started);
    _weekSessions[week] = started;
    _syncTicker(started);
    _hasUnsavedChanges = false;
    Haptics.confirm();
    await _updateTimerNotification(() async {
      final notificationsAllowed =
          current.hasStarted ||
          await WorkoutTimerNotificationService.instance.requestPermission();
      await WorkoutTimerNotificationService.instance.show(started);
      if (!notificationsAllowed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow notifications to use workout timer controls outside the app.',
            ),
          ),
        );
      }
    });
    if (mounted) setState(() {});
  }

  Future<WorkoutSession?> _otherRunningSession(String? currentId) async {
    final other = HiveService.getRunningSession(excludingId: currentId);
    if (other == null) return null;
    WorkoutTimerNotificationSnapshot? snapshot;
    try {
      snapshot = await WorkoutTimerNotificationService.instance.snapshot();
    } catch (error) {
      // Hive still supports timers when notification controls are unavailable.
      debugPrint('Could not read workout timer notification: $error');
    }
    if (!mounted) return null;
    if (snapshot?.sessionId == other.id && !snapshot!.isRunning) {
      // Pause/Stop can run in Android while Flutter is suspended. Apply that
      // state before deciding whether an old Hive flag should block Start.
      final latest = HiveService.getSessionById(other.id!);
      if (latest != null && latest.deletedAt == null && latest.isTimerRunning) {
        await context.read<WorkoutSessionProvider>().upsertSession(
          latest.copyWith(
            timerStartedAt: null,
            durationSeconds: snapshot.accumulatedSeconds,
          ),
        );
      }
    }
    return HiveService.getRunningSession(excludingId: currentId);
  }

  Future<void> _updateTimerNotification(Future<void> Function() update) async {
    try {
      await update();
    } catch (error) {
      debugPrint('Failed to update timer notification: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Workout saved. Notification controls could not be updated. Use the timer here.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _stopWorkout() async {
    if (_timerAction != null || _isNavigating || _isSaving) return;
    final draft = _getOrCreateSession();
    if (draft.isCompleted || !draft.hasStarted) return;
    final duration = formatDuration(draft.elapsedSeconds());
    setState(() {
      _timerAction = 'Logging workout';
      _confirmingFinish = true;
    });
    try {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Log workout?'),
              content: Text(
                'Record this workout with a duration of $duration?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Log workout'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) {
        await WorkoutTimerNotificationService.instance.acknowledgeStop();
        return;
      }
      setState(() => _confirmingFinish = false);

      try {
        final provider = context.read<WorkoutSessionProvider>();
        if (!await _autoSave() || !mounted) return;
        if (!_canUseTimer(draft)) return;
        final result = await _progression.complete(draft.id!);
        provider.loadSessions();
        _training.reload();
        SyncService.instance.scheduleSync();
        _weekSessions[_currentWeek] = result.session;
        _progressError = result.progressPending;
        // The listener defers structural updates while logging is in progress.
        // Reveal newly available weeks while keeping the completed log selected.
        _loadStructure();
        await _updateTimerNotification(
          WorkoutTimerNotificationService.instance.dismiss,
        );
        if (!mounted) return;
        setState(() {});
        Haptics.celebrate();
        unawaited(
          Navigator.of(context).push(
            WorkoutSummaryScreen.route(
              session: result.session,
              records: result.personalRecords,
            ),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Workout could not be logged. Your draft is unchanged.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _timerAction = null;
          _confirmingFinish = false;
        });
      }
    }
  }

  Future<bool> _confirmDiscard(WorkoutSession draft) async {
    final duration = formatDuration(draft.elapsedSeconds());
    return await showAppDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('Discard workout?'),
                content: Text(
                  'Entered sets and $duration of elapsed time will be removed. '
                  'This workout will not affect history or personal records.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: errorColor(context),
                      foregroundColor: onColor(errorColor(context)),
                    ),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Discard'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _discardCurrentWorkout() async {
    if (_timerAction != null || _isNavigating || _isSaving) return;
    final draft = _getOrCreateSession();
    if (draft.isCompleted || !await _confirmDiscard(draft) || !mounted) return;
    _ticker?.cancel();
    _ticker = null;
    if (draft.id != null) {
      await context.read<WorkoutSessionProvider>().deleteSession(draft.id!);
      final notification =
          await WorkoutTimerNotificationService.instance.snapshot();
      if (notification?.sessionId == draft.id) {
        await WorkoutTimerNotificationService.instance.dismiss();
      }
    }
    // The discarded draft is gone, so the week opens exactly as it would on a
    // fresh visit: the same starting values reopening it later would show.
    final clean = _initializeSession();
    setState(() {
      _weekSessions[_currentWeek] = clean;
      _hasUnsavedChanges = false;
    });
  }

  void _addEmptyExercise() {
    final session = _getOrCreateSession();
    showExercisePickerSheet(
      context,
      selectedExerciseNames: const <String>[],
      alreadyAddedExerciseNames: session.exercises.map(
        (exercise) => exercise.name,
      ),
      userId: session.userId,
      alreadyAddedExerciseIds: session.exercises.map(
        (e) => ExerciseCatalog.identity(e.name, e.exerciseId),
      ),
      onAdd: (_) {},
      onRemove: (_) {},
      onAddIdentified: (name, exerciseId) {
        final currentSession = _getOrCreateSession();
        final normalizedName = exerciseId;
        if (currentSession.exercises.any(
          (exercise) =>
              ExerciseCatalog.identity(exercise.name, exercise.exerciseId) ==
              normalizedName,
        )) {
          return;
        }
        final updatedExercises = List<Exercise>.from(currentSession.exercises);
        updatedExercises.add(
          Exercise(name: name, exerciseId: exerciseId, sets: [], note: null),
        );
        _updateSession(currentSession.copyWith(exercises: updatedExercises));
        _autoSave();
      },
      onRemoveIdentified: (name, exerciseId) {
        final currentSession = _getOrCreateSession();
        final normalizedName = exerciseId;
        final updatedExercises =
            currentSession.exercises
                .where(
                  (exercise) =>
                      ExerciseCatalog.identity(
                        exercise.name,
                        exercise.exerciseId,
                      ) !=
                      normalizedName,
                )
                .toList();
        _updateSession(currentSession.copyWith(exercises: updatedExercises));
        _autoSave();
      },
    );
  }

  /// Renames the movement everywhere, or merges it into the movement that
  /// already has the typed name. Nothing in this workout is rewritten: every
  /// occurrence shows its movement's catalog name, so the new name appears
  /// here, in other weeks and in past logs at once.
  Future<void> _showExerciseRenameDialog(int exerciseIndex) async {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final outcome = await showExerciseRenameDialog(
      context,
      exerciseId: ExerciseCatalog.identity(exercise.name, exercise.exerciseId),
      currentName: ExerciseCatalog.label(exercise.name, exercise.exerciseId),
      userId: session.userId ?? widget.plan.userId,
    );
    if (outcome == null || !mounted) return;
    // A merge changes which history Previous values and records come from.
    _previousSets.clear();
    _recordCache = null;
    _celebratedRecords = null;
    setState(() {});
    if (outcome case ExerciseMerged(:final into)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Merged into ${into.name}')));
    }
  }

  /// Swaps another movement into this workout, keeping the set count. Like
  /// any lineup change, the next week carries the swap over. The plan keeps
  /// its own lineup unless the user also changes it in the prompt that
  /// follows (see [_offerPlanSwap]).
  ///
  /// Sets take the new movement's latest logged weights and reps in this
  /// split, or weight 0 with the replaced exercise's reps when it has none.
  /// RPE, set notes and the exercise note are cleared. The replacement gets
  /// the chosen catalog identity, so its own history and measurement apply.
  Future<void> _replaceExercise(int exerciseIndex) async {
    final session = _getOrCreateSession();
    if (session.isCompleted) return;
    final replaced = session.exercises[exerciseIndex];
    String key(Exercise e) => ExerciseCatalog.identity(e.name, e.exerciseId);
    final replacedId = key(replaced);
    final picked = await pickSingleExercise(
      context,
      title:
          'Replace ${ExerciseCatalog.label(replaced.name, replaced.exerciseId)}',
      unavailableExerciseIds: session.exercises.map(key),
      userId: session.userId,
    );
    if (picked == null || !mounted) return;
    final current = _getOrCreateSession();
    final pickedId = ExerciseCatalog.canonicalId(picked.exerciseId);
    if (current.isCompleted ||
        exerciseIndex >= current.exercises.length ||
        key(current.exercises[exerciseIndex]) != replacedId) {
      return;
    }
    if (current.exercises.any((e) => key(e) == pickedId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${picked.name} is already in this workout.')),
      );
      return;
    }
    final history = previousExerciseSets(
      HiveService.getCompletedSessions(splitId: widget.plan.splitId),
      // A catalog ID resolves exactly like a stored occurrence identity.
      picked.exerciseId,
      splitId: widget.plan.splitId,
      excludingSessionId: current.id,
    );
    final updated = List<Exercise>.from(current.exercises);
    updated[exerciseIndex] = Exercise(
      name: picked.name,
      exerciseId: picked.exerciseId,
      sets: [
        for (var i = 0; i < replaced.sets.length; i++)
          history.isEmpty
              ? gym.Set(weight: 0, reps: replaced.sets[i].reps)
              : gym.Set(
                weight: history[math.min(i, history.length - 1)].weight,
                reps: history[math.min(i, history.length - 1)].reps,
              ),
      ],
    );
    // Which listing of the movement this was, for a plan that has it twice.
    final occurrence =
        current.exercises
            .take(exerciseIndex)
            .where((e) => key(e) == replacedId)
            .length;
    _updateSession(current.copyWith(exercises: updated));
    if (!await _autoSave() || !mounted) return;
    await _offerPlanSwap(
      from: replacedId,
      fromName: ExerciseCatalog.label(replaced.name, replaced.exerciseId),
      to: picked.exerciseId,
      toName: picked.name,
      occurrence: occurrence,
      history: history,
    );
  }

  /// After a swap in the workout, asks whether the plan should have it too.
  ///
  /// The workout, and the weeks that carry it over, already have the swap;
  /// the plan keeps its own lineup unless the user says otherwise here.
  /// Nothing is asked when the plan has no such exercise to swap (it was
  /// added in a workout) or already lists the replacement.
  Future<void> _offerPlanSwap({
    required String from,
    required String fromName,
    required String to,
    required String toName,
    required int occurrence,
    required List<gym.Set> history,
  }) async {
    bool applies(WorkoutPlan? plan) =>
        plan != null &&
        PlanExerciseSwap.canApply(
          plan,
          from: from,
          to: to,
          occurrence: occurrence,
        );
    final offered = _savedPlan;
    if (offered == null || !applies(offered)) return;
    final plans = context.read<WorkoutPlanProvider>();
    final planName = offered.name;
    final changed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => PersistenceDialog(
            title: 'Also change the plan?',
            content: Text(
              '$toName replaced $fromName in this workout. Change it in the '
              '$planName plan too?',
            ),
            cancelLabel: 'Keep plan',
            actionLabel: 'Change plan',
            progressLabel: 'Changing plan',
            failureMessage:
                'Could not change the plan. Try again or keep the plan.',
            onPersist:
                // Read and written under the sync gate. A sync may have
                // changed or deleted the plan while this was open, and one
                // landing between the check and the write would be undone.
                () => SyncService.instance.runExclusiveLocalMutation(() async {
                  final plan = _savedPlan;
                  if (plan == null || !applies(plan)) {
                    throw StateError('The plan changed.');
                  }
                  await plans.updatePlan(
                    PlanExerciseSwap.apply(
                      plan,
                      from: from,
                      to: to,
                      name: toName,
                      occurrence: occurrence,
                      history: history,
                    ),
                  );
                }),
          ),
    );
    if (changed != true || !mounted) return;
    // This workout has now seen the plan's swap. Recording it keeps the next
    // week from reading the replacement as an exercise the plan gained since.
    final session = _getOrCreateSession();
    final lineup = PlanExerciseSwap.inLineup(
      session.planExerciseIds,
      from: from,
      to: to,
      occurrence: occurrence,
    );
    if (!session.isCompleted &&
        lineup != null &&
        !listEquals(lineup, session.planExerciseIds)) {
      _updateSession(session.copyWith(planExerciseIds: lineup));
      await _autoSave();
      if (!mounted) return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$planName plan now has $toName')));
  }

  void _addSet(int exerciseIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];

    // Duplicate the last set's values, or fall back to defaults.
    final gym.Set newSet;
    if (exercise.sets.isNotEmpty) {
      final last = exercise.sets.last;
      newSet = gym.Set(reps: last.reps, weight: last.weight, rpe: last.rpe);
    } else {
      final planSet = _getLastSetForExerciseInPlan(
        ExerciseCatalog.identity(exercise.name, exercise.exerciseId),
      );
      newSet = gym.Set(reps: planSet?.reps ?? 8, weight: planSet?.weight ?? 0);
    }

    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      exerciseId: exercise.exerciseId,
      sets: [...exercise.sets, newSet],
      note: exercise.note,
    );
    _updateSession(session.copyWith(exercises: updatedExercises));
    _autoSave();
  }

  void _deleteSet(int exerciseIndex, int setIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final updatedSets = List<gym.Set>.from(exercise.sets)..removeAt(setIndex);
    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      exerciseId: exercise.exerciseId,
      sets: updatedSets,
      note: exercise.note,
    );
    _updateSession(session.copyWith(exercises: updatedExercises));
    _autoSave();
  }

  void _addExerciseNote(int exerciseIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];

    WorkoutDialogs.showExerciseNoteDialog(
      context,
      currentNote: exercise.note,
      onSave: (note) {
        final updatedExercises = List<Exercise>.from(session.exercises);
        updatedExercises[exerciseIndex] = Exercise(
          name: exercise.name,
          exerciseId: exercise.exerciseId,
          sets: exercise.sets,
          note: note,
        );
        _updateSession(session.copyWith(exercises: updatedExercises));
        _autoSave();
      },
    );
  }

  void _changeSetValues(
    int exerciseIndex,
    int setIndex,
    double weight,
    int reps,
  ) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];

    final updatedSets = List<gym.Set>.from(exercise.sets);
    final updatedSet = gym.Set(
      reps: reps,
      weight: weight,
      rpe: set.rpe,
      note: set.note,
    );
    updatedSets[setIndex] = updatedSet;
    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      exerciseId: exercise.exerciseId,
      sets: updatedSets,
      note: exercise.note,
    );

    _updateSession(session.copyWith(exercises: updatedExercises));
    // Persist once entry closes so PR dialogs never interrupt typing.
  }

  void _changeSetRpe(int exerciseIndex, int setIndex, int? rpe) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];
    final updatedSets = List<gym.Set>.from(exercise.sets);
    updatedSets[setIndex] = gym.Set(
      reps: set.reps,
      weight: set.weight,
      rpe: rpe,
      note: set.note,
    );
    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      exerciseId: exercise.exerciseId,
      sets: updatedSets,
      note: exercise.note,
    );
    _updateSession(session.copyWith(exercises: updatedExercises));
    // Persist once entry closes, matching weight and rep edits.
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    final session = _getOrCreateSession();
    final exerciseCount = session.exercises.length;
    if (oldIndex < 0 || oldIndex >= exerciseCount) return;
    // The final drop slot can land after the non-draggable Add exercise tile.
    if (newIndex < 0 || newIndex > exerciseCount) return;
    final exercises = List<Exercise>.from(session.exercises);
    final exercise = exercises.removeAt(oldIndex);
    exercises.insert(newIndex.clamp(0, exercises.length), exercise);
    if (oldIndex == exercises.indexOf(exercise)) return;
    _updateSession(session.copyWith(exercises: exercises));
    _autoSave();
  }

  /// Move up or Move down from an exercise's menu. Someone reaching for these
  /// is looking for a way to reorder, so the first time, say that the name
  /// can be held and dragged instead.
  void _moveExercise(int oldIndex, int newIndex) {
    _reorderExercises(oldIndex, newIndex);
    unawaited(_offerReorderTip());
  }

  Future<void> _offerReorderTip() async {
    try {
      if (!await TutorialPreferences.takeExerciseReorderTip()) return;
    } catch (error) {
      debugPrint('Could not read the reorder tip preference: $error');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Tip: hold an exercise\'s name and drag it to reorder.',
          ),
        ),
      );
  }

  /// An exercise dragged into a new place, by holding its name.
  void _dragExercise(int oldIndex, int newIndex) {
    _reorderExercises(oldIndex, newIndex);
    TutorialPreferences.markExerciseReorderLearned().catchError(
      (Object error) =>
          debugPrint('Could not save the reorder tip preference: $error'),
    );
  }

  Future<void> _prepareEntry() async {
    if (_weeks.isEmpty) return;
    try {
      await _progression.replay();
      if (!mounted) return;
      _training.reload();
      _loadStructure(initial: true);
      setState(() => _progressError = false);
      if (!widget.showLogConfirmationOnOpen &&
          (widget.destination?.isActive ?? true)) {
        await _maybeBoundaryPrompt();
      }
    } catch (_) {
      if (mounted) setState(() => _progressError = true);
    }
  }

  Future<T> _structureMutation<T>(
    Future<T> Function() write, {
    String label = 'Saving blocks',
  }) async {
    if (_timerAction != null || !await _autoSave() || !mounted) {
      throw StateError('Save the workout before changing blocks.');
    }
    setState(() => _timerAction = label);
    try {
      final result = await write();
      if (!mounted) return result;
      _training.reload();
      _loadStructure();
      SyncService.instance.scheduleSync();
      return result;
    } finally {
      if (mounted) setState(() => _timerAction = null);
    }
  }

  Future<void> _createBlock() async {
    final result = await TrainingBlockDialogs.create(
      context,
      onSave:
          (name, count) => _structureMutation(
            () => _structure.createBlock(
              splitId: widget.plan.splitId!,
              name: name,
              weekCount: count,
            ),
          ),
    );
    if (result == null || !mounted) return;
    final first = _weeksByBlock[result.id]?.firstOrNull;
    if (first != null) await _onWeekChanged(first.id);
  }

  Future<void> _selectBlock(String blockId) async {
    final weeks = _weeksByBlock[blockId] ?? <TrainingWeek>[];
    if (weeks.isEmpty) return;
    final remembered = _viewedWeekByBlock[blockId];
    final destination =
        weeks.where((week) => week.id == remembered).firstOrNull ?? weeks.first;
    await _onWeekChanged(destination.id);
  }

  /// Add week is the next step from any week once the block is finished: the
  /// plus goes to the finished week before offering the choices.
  bool get _canAddWeek =>
      _progress?.state == WorkoutProgressState.awaitingBoundary;

  /// The plus always answers. At a finished block it opens the boundary
  /// choices, going to the finished week first if another one is on screen;
  /// before that it says which log unlocks the next week.
  Future<void> _addWeek(String blockId) async {
    final progress = _progress;
    final active = progress == null ? null : _weekById[progress.activeWeekId];
    if (progress == null || active == null || !_weeks.contains(active.id)) {
      _showWeekMessage('Weeks unlock as you log workouts.');
      return;
    }
    if (progress.state != WorkoutProgressState.awaitingBoundary) {
      _explainLockedWeeks(active);
      return;
    }
    if (active.id != _currentWeek) {
      await _onWeekChanged(active.id);
      if (!mounted || active.id != _currentWeek) return;
    } else if (!await _autoSave() || !mounted) {
      return;
    }
    await _maybeBoundaryPrompt();
  }

  void _explainLockedWeeks(TrainingWeek active) {
    final block = _training.blockById[active.blockId];
    final planned =
        block?.plannedWeekCount ??
        _training.weeksByBlock[active.blockId]?.lastOrNull?.number ??
        active.number;
    final number = active.number;
    final inBlock = block == null ? '' : ' in ${block.name}';
    final logged = _savedSessionForWeek(active.id)?.isCompleted ?? false;
    final message =
        logged
            ? 'Week $number is logged. Tap Continue to unlock the next week.'
            : number < planned
            ? 'Week $number of $planned$inBlock. '
                'Log Week $number to unlock Week ${number + 1}.'
            : 'Week $number is the last planned week$inBlock. '
                'Log it to add a week or move on.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action:
              active.id == _currentWeek
                  ? null
                  : SnackBarAction(
                    label: 'Go to Week $number',
                    textColor: accentColor(context),
                    onPressed: () => _onWeekChanged(active.id),
                  ),
        ),
      );
  }

  Future<void> _editBlock(String blockId) async {
    final block = _blocks.where((b) => b.id == blockId).firstOrNull;
    if (block == null) return;
    final splitId = widget.plan.splitId!;
    final lifecycle = TrainingBlockLifecycle.of(
      _structure,
      splitId: splitId,
      delete:
          (block) => _structureMutation(
            () => _structure.deleteBlock(splitId: splitId, blockId: block.id),
            label: 'Deleting block',
          ),
    );
    final lifecycleOn = lifecycle.available();
    final blocker = lifecycleOn ? lifecycle.deleteBlocker(block) : null;
    final viewed = _weeks.isEmpty ? null : _currentWeek;
    final result = await TrainingBlockDialogs.edit(
      context,
      block,
      currentWeekCount: trainingBlockLength(
        block,
        _training.weeksByBlock[blockId] ?? const <TrainingWeek>[],
      ),
      minimumWeekCount: lifecycleOn ? lifecycle.minimumWeekCount(block) : null,
      onSave:
          (name, count) => _structureMutation(
            () => _structure.updateBlock(
              splitId: splitId,
              blockId: blockId,
              name: name,
              weekCount: count,
            ),
          ),
      onDelete: lifecycleOn ? () => lifecycle.delete(block) : null,
      deleteUnavailableReason:
          blocker == null ? null : TrainingBlockDialogs.blockerMessage(blocker),
    );
    if (!mounted || result is! TrainingBlockDeleted) return;
    _viewedWeekByBlock.remove(blockId);
    // A workout can view a block other than the one its progress is in. When
    // that block is deleted, return to the workout's active week.
    if (viewed != null && !_weeks.contains(viewed)) _selectProgress();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${result.name} deleted')));
  }

  Future<void> _reorderBlocks() => TrainingBlockDialogs.reorder(
    context,
    _blocks,
    onSave:
        (ids) => _structureMutation(
          () => _structure.reorderBlocks(widget.plan.splitId!, ids),
        ),
  );

  void _showWeekActions(String weekId) {
    final week = _weekById[weekId];
    if (week == null) return;
    WorkoutDialogs.showWeekActions(
      context,
      week: week.number,
      blockName: _blocks.firstWhere((b) => b.id == week.blockId).name,
      onDelete: () => _deleteWeek(weekId),
    );
  }

  void _showWeekMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Deletes this workout's logs in a week and hides its tab. The week itself
  /// is shared across the split, so other workouts keep theirs.
  Future<void> _deleteWeek(String weekId) async {
    final planId = widget.plan.id;
    if (planId == null || _timerAction != null || _isNavigating) return;
    // An autosave still in flight would write the week back after the delete.
    final pendingSave = _saveFuture;
    if (pendingSave != null) await pendingSave;
    if (!mounted) return;
    _training.reload();
    final week = _training.weekById[weekId];
    if (week == null) return;
    final reached = _training.reachedWeekIds(planId);
    if (!reached.contains(weekId)) {
      _showWeekMessage('Week ${week.number} has no workout to delete.');
      return;
    }
    if (reached.length == 1) {
      _showWeekMessage("You can't delete the only week.");
      return;
    }
    final sessions = _training.sessionsForSlot(planId, weekId);
    final deletingSelected = weekId == _currentWeek;
    final unsavedEdits = deletingSelected && _hasUnsavedChanges;
    // An empty week has nothing to lose, so it goes without a dialog.
    if (sessions.isNotEmpty || unsavedEdits) {
      final confirmed = await WorkoutDialogs.showDeleteWeekDialog(
        context,
        week: week.number,
        logged: sessions.any((s) => s.isCompleted),
      );
      if (!confirmed || !mounted) return;
    }
    if (deletingSelected) {
      // Drop the deleted draft's edits so they can't be saved back.
      setState(() {
        _hasUnsavedChanges = false;
        _draftRevision++;
        _saveError = null;
      });
    }
    try {
      await _structureMutation(() async {
        await _progression.removeWeek(planId: planId, weekId: weekId);
        _weekSessions.remove(weekId);
      }, label: 'Deleting week');
    } catch (_) {
      if (mounted) _showWeekMessage("Couldn't delete the week. Try again.");
      return;
    }
    if (!mounted) return;
    // A block left with no reached weeks still offers its first week as a
    // browsing entry, so the deleted tab can survive the reload. Follow
    // progress instead of leaving the deleted week on screen.
    if (deletingSelected) _selectProgress();
    context.read<WorkoutSessionProvider>().loadSessions();
    // Only an unfinished draft can own the running timer notification.
    final drafts = sessions.where((s) => !s.isCompleted).map((s) => s.id);
    if (drafts.isEmpty) return;
    final notification =
        await WorkoutTimerNotificationService.instance.snapshot();
    if (drafts.contains(notification?.sessionId)) {
      await WorkoutTimerNotificationService.instance.dismiss();
    }
  }

  void _selectProgress() {
    if (!mounted) return;
    _training.reload();
    _loadStructure();
    final active = _progress?.activeWeekId;
    if (active != null && _weeks.contains(active)) {
      _currentWeekIndex = _weeks.indexOf(active);
      _loadSessionForCurrentWeek();
    }
    if (mounted) setState(() {});
  }

  Future<void> _continueCompleted() async {
    final session = _getOrCreateSession();
    final revision = _progress?.revision;
    if (revision == null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder:
          (dialog) => AlertDialog(
            title: const Text('Continue from this workout?'),
            content: const Text(
              'Keep this completed log and choose the next supplied week.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Continue'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _progression.continueCompleted(
        sessionId: session.id!,
        expectedRevision: revision,
      );
      if (mounted) _selectProgress();
      SyncService.instance.scheduleSync();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Training progress changed. Open the workout again.'),
          ),
        );
      }
    }
  }

  Future<void> _maybeBoundaryPrompt() async {
    if (!mounted ||
        _weeks.isEmpty ||
        _boundaryShowing ||
        _progress?.state != WorkoutProgressState.awaitingBoundary ||
        _progress?.activeWeekId != _currentWeek) {
      return;
    }
    _boundaryShowing = true;
    final revision = _progress!.revision;
    var saving = false;
    String? error;
    try {
      await showAppSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder:
            (sheet) => StatefulBuilder(
              builder:
                  (sheet, setSheetState) => ListenableBuilder(
                    listenable: _training,
                    builder: (sheet, _) {
                      final current = _progress;
                      final source =
                          current == null
                              ? null
                              : _weekById[current.activeWeekId];
                      final supplied =
                          source == null
                              ? <TrainingWeek>[]
                              : (_training.weeksByBlock[source.blockId] ??
                                      <TrainingWeek>[])
                                  .where(
                                    (w) =>
                                        w.number == source.number + 1 &&
                                        w.number <=
                                            (_training
                                                    .blockById[source.blockId]
                                                    ?.plannedWeekCount ??
                                                w.number),
                                  )
                                  .toList();
                      final planned =
                          source != null &&
                          supplied.isEmpty &&
                          (_training
                                      .blockById[source.blockId]
                                      ?.plannedWeekCount ??
                                  0) >
                              source.number;
                      final blockIndex =
                          source == null
                              ? -1
                              : _blocks.indexWhere(
                                (b) => b.id == source.blockId,
                              );
                      final nextBlock =
                          blockIndex >= 0 && blockIndex + 1 < _blocks.length
                              ? _blocks[blockIndex + 1]
                              : null;
                      final nextWeek =
                          nextBlock == null
                              ? null
                              : _weeksByBlock[nextBlock.id]?.firstOrNull;
                      final stale =
                          current?.revision != revision ||
                          current?.state !=
                              WorkoutProgressState.awaitingBoundary;
                      Future<void> choose(
                        Future<void> Function() action,
                      ) async {
                        if (saving) return;
                        setSheetState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await action();
                          if (sheet.mounted) Navigator.pop(sheet);
                          if (mounted) _selectProgress();
                          SyncService.instance.scheduleSync();
                        } catch (_) {
                          if (mounted) _training.reload();
                          if (sheet.mounted) {
                            setSheetState(
                              () =>
                                  error =
                                      'Training choices changed or could not be saved. Try again.',
                            );
                          }
                        } finally {
                          if (sheet.mounted) {
                            setSheetState(() => saving = false);
                          }
                        }
                      }

                      final blockName =
                          source == null
                              ? null
                              : _training.blockById[source.blockId]?.name;
                      Future<void> createBlock() async {
                        final block = await TrainingBlockDialogs.create(
                          sheet,
                          onSave:
                              (name, count) => _progression.createBoundary(
                                planId: widget.plan.id!,
                                expectedRevision: revision,
                                name: name,
                                weekCount: count,
                              ),
                        );
                        if (block != null && sheet.mounted) {
                          Navigator.pop(sheet);
                          if (mounted) _selectProgress();
                          SyncService.instance.scheduleSync();
                        }
                      }

                      return PopScope(
                        canPop: !saving,
                        child: SafeArea(
                          child: TrainingBoundarySheet(
                            message:
                                source == null || blockName == null
                                    ? 'Choose where ${widget.plan.name} '
                                        'goes next.'
                                    : 'You finished Week ${source.number} of '
                                        '$blockName. Choose where '
                                        '${widget.plan.name} goes next.',
                            staleMessage:
                                stale
                                    ? 'Training progress changed. Close and '
                                        'open the workout again.'
                                    : null,
                            saving: saving,
                            error: error,
                            onDismiss: () => Navigator.pop(sheet),
                            options: [
                              if (supplied.isNotEmpty)
                                TrainingBoundaryOption(
                                  icon: LucideIcons.arrowRight,
                                  title:
                                      'Continue to Week ${supplied.first.number}',
                                  detail:
                                      'Week ${supplied.first.number} is ready'
                                      '${blockName == null ? '' : ' in $blockName'}.',
                                  onTap:
                                      () => choose(
                                        () => _progression.chooseBoundary(
                                          planId: widget.plan.id!,
                                          expectedRevision: revision,
                                          destinationWeekId: supplied.first.id,
                                        ),
                                      ),
                                )
                              else
                                TrainingBoundaryOption(
                                  icon:
                                      planned
                                          ? LucideIcons.arrowRight
                                          : LucideIcons.plus,
                                  // The block was made longer after this
                                  // workout reached its end: the next week is
                                  // already planned, just not allocated yet.
                                  title:
                                      planned
                                          ? 'Continue to Week '
                                              '${source.number + 1}'
                                          : 'Add week',
                                  detail:
                                      source == null || blockName == null
                                          ? 'Keep going in this block.'
                                          : 'Keep going in $blockName with '
                                              'Week ${source.number + 1}.',
                                  onTap:
                                      () => choose(
                                        () => _progression.extendBoundary(
                                          planId: widget.plan.id!,
                                          expectedRevision: revision,
                                        ),
                                      ),
                                ),
                              if (supplied.isEmpty && nextWeek != null)
                                TrainingBoundaryOption(
                                  icon: LucideIcons.chevronsRight,
                                  title: 'Move to ${nextBlock!.name}',
                                  detail:
                                      'Start Week ${nextWeek.number} of '
                                      '${nextBlock.name}.',
                                  onTap:
                                      () => choose(
                                        () => _progression.chooseBoundary(
                                          planId: widget.plan.id!,
                                          expectedRevision: revision,
                                          destinationWeekId: nextWeek.id,
                                        ),
                                      ),
                                ),
                              if (supplied.isEmpty && nextWeek == null)
                                TrainingBoundaryOption(
                                  icon: LucideIcons.layersPlus,
                                  title: 'Create block',
                                  detail:
                                      blockName == null
                                          ? 'Start a new phase of training.'
                                          : 'Start a new block after '
                                              '$blockName.',
                                  onTap: createBlock,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
      );
    } finally {
      _boundaryShowing = false;
    }
  }

  /// Corrects when a logged workout started and how long it took. Sets and
  /// exercises are edited in place like a draft's.
  Future<void> _editWorkoutTime() async {
    if (_timerAction != null || _isNavigating || _isSaving) return;
    final session = _getOrCreateSession();
    if (!session.isCompleted) return;
    final edited = await showWorkoutTimeDialog(
      context,
      start: session.startedAt ?? session.date,
      durationSeconds: session.durationSeconds ?? 0,
    );
    if (edited == null || !mounted) return;
    final current = _getOrCreateSession();
    if (!current.isCompleted || current.id != session.id) return;
    _updateSession(
      current.copyWith(
        date: edited.start,
        startedAt: current.startedAt == null ? null : edited.start,
        durationSeconds: edited.durationSeconds,
      ),
    );
    // Records compare against workouts logged before this one.
    _recordCache = null;
    await _autoSave();
  }

  /// Deletes this log from History, Stats and records, then leaves: the log
  /// is what the screen was showing, so it returns to where it came from.
  /// Progress is left alone, the same as deleting the log anywhere else.
  Future<void> _deleteLoggedWorkout() async {
    if (_timerAction != null || _isNavigating || _isSaving) return;
    SetEntryTable.closeKeypad();
    final session = _getOrCreateSession();
    final id = session.id;
    if (!session.isCompleted || id == null) return;
    final provider = context.read<WorkoutSessionProvider>();
    final deleted = await WorkoutDialogs.showDeleteLoggedWorkoutDialog(
      context,
      planName: session.planName,
      date: session.date,
      delete: () async {
        // An autosave still in flight would write the log back afterwards.
        final pending = _saveFuture;
        if (pending != null) await pending;
        await provider.deleteSession(id);
      },
    );
    if (!deleted || !mounted) return;
    // Edits that never saved belong to the deleted log.
    setState(() {
      _isNavigating = true;
      _hasUnsavedChanges = false;
      _draftRevision++;
      _saveError = null;
    });
    Navigator.pop(context);
  }

  void _deleteExercise(int exerciseIndex) async {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final confirmed = await WorkoutDialogs.showDeleteExerciseDialog(
      context,
      exerciseName: ExerciseCatalog.label(exercise.name, exercise.exerciseId),
      carriesOver: !session.isCompleted && _activeSlot,
    );

    if (confirmed && mounted) {
      final updatedExercises = List<Exercise>.from(session.exercises);
      updatedExercises.removeAt(exerciseIndex);
      _updateSession(session.copyWith(exercises: updatedExercises));
      await _autoSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    navigationStateChanged();
    if (_weeks.isEmpty) {
      return Scaffold(
        appBar: AppHeader(
          title: Text(widget.plan.name),
          leading: AppBackButton(onPressed: () => Navigator.pop(context)),
        ),
        body: const Center(child: Text('This workout is no longer available.')),
      );
    }
    final session = _getOrCreateSession();
    if (_saveError != null) _shownSaveError = _saveError;
    _celebratedRecords ??= _recordSetsIn(session);
    final liveRecords = _liveRecords(session);
    final accent = accentColor(context);

    final planProvider = context.watch<WorkoutPlanProvider>();
    final plans = planProvider.plans;
    final currentPlanIndex = _currentPlanIndex(plans);
    final activePlan =
        currentPlanIndex >= 0 ? plans[currentPlanIndex] : widget.plan;
    final ValueChanged<double>? onNextPlan =
        currentPlanIndex >= 0 && currentPlanIndex < plans.length - 1
            ? (velocity) => _switchPlan(
              plans[currentPlanIndex + 1],
              currentPlanIndex + 1,
              velocity,
            )
            : null;
    final ValueChanged<double>? onPreviousPlan =
        currentPlanIndex > 0
            ? (velocity) => _switchPlan(
              plans[currentPlanIndex - 1],
              currentPlanIndex - 1,
              velocity,
            )
            : null;
    // Arriving by a plan switch, this page lets the workout it replaces show
    // through its body until it has landed, so the leaving log is seen going
    // as this one comes in over it. The header and the bars are opaque.
    final arrival = _PlanSwitchArrival.maybeOf(context);
    final arriving = arrival?.arriving ?? false;
    // Everything in the body that belongs to this plan's workout moves as
    // one page: the notices and the log.
    Widget page(Widget child) => _PlanLogTransition(
      motion: _log,
      arrival: arriving ? arrival!.animation : kAlwaysCompleteAnimation,
      arrivingFrom:
          arriving
              ? arrival!.direction *
                  AppMotion.swipeShift(MediaQuery.sizeOf(context).width)
              : 0,
      leaving: _leaving,
      child: child,
    );
    final planColor = planColorOf(activePlan.planColor, context);
    final timerBase = Theme.of(context).textTheme.bodySmall!;
    final timerStyle = AppTypography.figures(
      fontSize: timerBase.fontSize,
      fontWeight: FontWeight.w600,
      height: timerBase.height,
    );
    final titleStyle = Theme.of(context).textTheme.headlineSmall!;
    final textScaler = MediaQuery.textScalerOf(context);
    // Give the two-line title breathing room without returning to the tall
    // header. Grow with accessibility text while keeping the same padding.
    final toolbarHeight = (textScaler.scale(titleStyle.fontSize!) *
                (titleStyle.height ?? 1) +
            textScaler.scale(timerStyle.fontSize!) * (timerStyle.height ?? 1) +
            AppSpacing.xs +
            AppSpacing.sm * 2)
        .clamp(kToolbarHeight + AppSpacing.sm, double.infinity);

    return PopScope(
      // A logged workout can be edited too, so unsaved edits (a failed
      // autosave, an entry still open) leave through the save flow.
      canPop:
          session.isCompleted &&
          !_hasUnsavedChanges &&
          !_isNavigating &&
          !_isSaving &&
          _timerAction == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: AbsorbPointer(
        absorbing: _isNavigating || _timerAction != null,
        child: Scaffold(
          backgroundColor:
              arriving ? Colors.transparent : backgroundColor(context),
          appBar: AppHeader(
            toolbarHeight: toolbarHeight,
            titleSpacing: AppSpacing.sm,
            leading: AppBackButton(
              onPressed: _handleBack,
              enabled: !_isSaving && _timerAction == null && !_isNavigating,
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A swipe here moves the log too; the title holds still and
                // changes in place when the plan does.
                PlanSwipeRegion(
                  onNextPlan: onNextPlan,
                  onPreviousPlan: onPreviousPlan,
                  onDragProgress: _updatePlanSwipe,
                  onDragCancel: _settlePlanSwipe,
                  child: _PlanHeader(
                    plan: activePlan,
                    color: planColor,
                    heroTag:
                        activePlan.id == widget.plan.id ? widget.heroTag : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _SessionMeta(
                  label: _contextLabel,
                  session: session,
                  now: _now,
                  timerStyle: timerStyle,
                ),
              ],
            ),
            actions: [
              if (!session.isCompleted) ...[
                _TimerButton(
                  running: session.isTimerRunning,
                  // Once the clock has run, the header drops to icons so the
                  // clock, Finish and the title can share one row; large text
                  // on a narrow phone needs the room before that.
                  compact:
                      session.hasStarted ||
                      (MediaQuery.sizeOf(context).width < 400 &&
                          textScaler.scale(1) > 1.5),
                  onPressed:
                      _isSaving ||
                              _timerAction != null ||
                              !_canUseTimer(session)
                          ? null
                          : _toggleTimer,
                ),
                // Nothing to finish before Start, so Finish waits for it.
                if (session.hasStarted)
                  _FinishButton(
                    // Large text on a narrow phone needs the label's room
                    // for the title, so Finish falls back to its icon.
                    compact:
                        MediaQuery.sizeOf(context).width < 400 &&
                        textScaler.scale(1) > 1.3,
                    onPressed:
                        !_isSaving &&
                                _timerAction == null &&
                                _canUseTimer(session)
                            ? _stopWorkout
                            : null,
                  )
                else
                  const SizedBox(width: AppSpacing.xs),
                PopupMenuButton<String>(
                  tooltip: 'Workout actions',
                  icon: Icon(
                    LucideIcons.ellipsisVertical,
                    color: textSecondaryColor(context),
                  ),
                  onSelected: (value) {
                    if (value == 'discard') _discardCurrentWorkout();
                  },
                  itemBuilder:
                      (context) => [
                        PopupMenuItem(
                          value: 'discard',
                          height: 48,
                          child: Text(
                            'Discard workout',
                            style: TextStyle(color: errorColor(context)),
                          ),
                        ),
                      ],
                ),
              ] else
                PopupMenuButton<String>(
                  tooltip: 'Workout actions',
                  icon: Icon(
                    LucideIcons.ellipsisVertical,
                    color: textSecondaryColor(context),
                  ),
                  onSelected: (value) {
                    if (value == 'time') _editWorkoutTime();
                    if (value == 'delete') _deleteLoggedWorkout();
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'time',
                          height: 48,
                          child: Text('Edit date and duration'),
                        ),
                        if (session.id != null)
                          PopupMenuItem(
                            value: 'delete',
                            height: 48,
                            child: Text(
                              'Delete workout',
                              style: TextStyle(color: errorColor(context)),
                            ),
                          ),
                      ],
                ),
            ],
            bottom: _buildPlanTabBar(
              accent,
              plans,
              currentPlanIndex,
              previousIndex: arriving ? arrival!.fromIndex : null,
            ),
          ),
          bottomNavigationBar: _buildWeekNavBar(accent),
          body: Column(
            children: [
              if (_progressError)
                page(
                  TrainingProgressNotice(
                    icon: LucideIcons.circleAlert,
                    isError: true,
                    message: "Progress didn't load.",
                    actionLabel: 'Try again',
                    onAction: _prepareEntry,
                  ),
                ),
              if (!_progressError &&
                  session.isCompleted &&
                  _progress?.activeWeekId == _currentWeek)
                page(
                  _progress?.state == WorkoutProgressState.awaitingBoundary
                      ? TrainingProgressNotice(
                        icon: LucideIcons.flagTriangleRight,
                        message: 'Block complete.',
                        actionLabel: 'Choose next week',
                        onAction: _maybeBoundaryPrompt,
                      )
                      : TrainingProgressNotice(
                        icon: LucideIcons.circleCheck,
                        message: 'Workout logged.',
                        actionLabel: 'Continue',
                        onAction: _continueCompleted,
                      ),
                ),

              // The log's progress line, for work in flight: saving,
              // starting or pausing the clock, logging, changing blocks. It
              // opens only for work still going after a beat, so a save
              // done within a frame or two never shoves the log. It stays in
              // place while the log moves, so a slow save before a plan
              // switch still shows it.
              Opacity(
                opacity: _handedOver ? 0 : 1,
                child: PatientProgress(
                  fold: true,
                  child:
                      _isSaving || (_timerAction != null && !_confirmingFinish)
                          ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: ActionProgress(
                                _timerAction ?? 'Saving workout',
                              ),
                            ),
                          )
                          : null,
                ),
              ),
              // Folds open and closed rather than shoving the log; it keeps
              // the last message while it folds away after a retry.
              Opacity(
                opacity: _handedOver ? 0 : 1,
                child: Collapsible(
                  open: _saveError != null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_shownSaveError ?? ''),
                          ),
                        ),
                        TextButton(
                          onPressed: _isSaving ? null : _autoSave,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ExerciseReorderScope(
                  items: [
                    for (final exercise in session.exercises)
                      ExerciseReorderItem(
                        name: ExerciseCatalog.label(
                          exercise.name,
                          exercise.exerciseId,
                        ),
                        detail: switch (exercise.sets.length) {
                          0 => 'No sets',
                          1 => '1 set',
                          final count => '$count sets',
                        },
                      ),
                  ],
                  onReorder: _dragExercise,
                  child: PlanSwipeRegion(
                    onNextPlan: onNextPlan,
                    onPreviousPlan: onPreviousPlan,
                    onDragProgress: _updatePlanSwipe,
                    onDragCancel: _settlePlanSwipe,
                    child: page(
                      CustomScrollView(
                        key: ValueKey(_currentWeek),
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        slivers: [
                          // One gutter keeps the exercise tables aligned as a log.
                          // No top inset, and the first exercise drops its own:
                          // its title sits snug under the plan tabs' rule.
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.sm,
                            ),
                            // Holding an exercise's name moves it, through
                            // the ExerciseReorderScope around the log.
                            sliver: SliverList.builder(
                              itemCount: session.exercises.length + 1,
                              itemBuilder: (context, index) {
                                if (index == session.exercises.length) {
                                  return TextButton.icon(
                                    key: const ValueKey('add_exercise_button'),
                                    onPressed: _addEmptyExercise,
                                    icon: const Icon(
                                      LucideIcons.plus,
                                      size: 18,
                                    ),
                                    label: const Text('Add exercise'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: accent,
                                      minimumSize: const Size.fromHeight(48),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: AppRadius.button,
                                      ),
                                    ),
                                  );
                                }

                                final exercise = session.exercises[index];

                                return Container(
                                  // Numeric edits replace the exercise snapshot;
                                  // retain the row and its active keypad across them.
                                  key: ValueKey((
                                    _currentWeek,
                                    index,
                                    exercise.name,
                                  )),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: hairlineColor(context),
                                      ),
                                    ),
                                  ),
                                  child: ExerciseCard(
                                    exercise: exercise,
                                    exerciseIndex: index,
                                    first: index == 0,
                                    reorderable: true,
                                    onMoveUp:
                                        index > 0
                                            ? () =>
                                                _moveExercise(index, index - 1)
                                            : null,
                                    onMoveDown:
                                        index < session.exercises.length - 1
                                            ? () =>
                                                _moveExercise(index, index + 1)
                                            : null,
                                    accent: accent,
                                    previousSets: _previousFor(
                                      ExerciseCatalog.identity(
                                        exercise.name,
                                        exercise.exerciseId,
                                      ),
                                    ),
                                    onSetChanged: _changeSetValues,
                                    onSetRpeChanged: _changeSetRpe,
                                    recordSetIndexes:
                                        liveRecords[index] ?? const <int>{},
                                    onEntryFinished: () {
                                      if (!mounted) return;
                                      _celebrateNewRecords();
                                      _autoSave();
                                    },
                                    onAddSet: (i) => _addSet(i),
                                    onDeleteSet:
                                        (i, setIndex) =>
                                            _deleteSet(i, setIndex),
                                    onAddNote: _addExerciseNote,
                                    onRename: _showExerciseRenameDialog,
                                    onReplace:
                                        session.isCompleted
                                            ? null
                                            : _replaceExercise,
                                    onDeleteExercise: _deleteExercise,
                                  ),
                                );
                              },
                            ),
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: SetEntryTable.keyboardHeight,
                            builder:
                                (context, height, _) => SliverToBoxAdapter(
                                  child: SizedBox(height: height),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The plan switcher under the app bar.
  ///
  /// Every tab used to carry a 2px bottom border, which made the "active"
  /// indicator indistinguishable from a baseline rule that stopped mid-screen.
  /// Now the bar owns one continuous hairline, and the only mark is a 2px
  /// underline sized to the active tab's label.
  ///
  /// The mark is the global accent, not the plan's own colour. A plan's colour
  /// identifies it in a *set* — the home grid, the dashboard's plan list — where
  /// several plans are on screen at once and hue is what tells them apart. In
  /// here you are inside one plan, so that job is already done by the title, and
  /// colouring every tab its own hue only fights the accent everywhere else on
  /// the screen.
  PreferredSizeWidget? _buildPlanTabBar(
    Color accent,
    List<WorkoutPlan> plans,
    int selectedIndex, {
    int? previousIndex,
  }) {
    if (plans.isEmpty) {
      return null;
    }

    const double barHeight = 48;

    return PreferredSize(
      preferredSize: const Size.fromHeight(barHeight),
      child: UnderlineTabStrip(
        rule: StripRule.bottom,
        height: barHeight,
        color: accent,
        selectedIndex: selectedIndex,
        controller: _planTabs,
        // Arriving by a switch, the underline slides over from the plan
        // switched away from, where the replaced strip had it.
        previousIndex: previousIndex,
        tabs: [
          for (var index = 0; index < plans.length; index++)
            UnderlineTabData(
              label: plans[index].name,
              onTap:
                  index == selectedIndex
                      ? null
                      : () => _switchPlan(plans[index], index),
            ),
        ],
      ),
    );
  }

  /// Fixed block and Add week controls frame the scrolling week tabs.
  Widget _buildWeekNavBar(Color accent) => SafeArea(
    top: false,
    child: TrainingBlockStrip(
      blocks: _blocks,
      weeksByBlock: _weeksByBlock,
      selectedWeekId: _currentWeek,
      enabled: !_isSaving && !_isNavigating && _timerAction == null,
      canAddWeek: _canAddWeek,
      activeWeekId: _progress?.activeWeekId,
      onSelectWeek: _onWeekChanged,
      onSelectBlock: _selectBlock,
      onEditBlock: _editBlock,
      onReorderBlocks: _reorderBlocks,
      onAddWeek: _addWeek,
      onDeleteWeek: widget.plan.id == null ? null : _showWeekActions,
      onCreateBlock: _createBlock,
    ),
  );
}

class _PlanHeader extends StatelessWidget {
  final WorkoutPlan plan;

  /// The active plan's resolved identity-marker colour.
  final Color color;
  final String? heroTag;

  const _PlanHeader({required this.plan, required this.color, this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${plan.name} plan marker',
          child: Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.micro,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: PlanTitleHero(
            tag: heroTag,
            text: plan.name,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: textPrimaryColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Logs the workout. Labelled, because a bare check in a header reads as
/// "save" as often as "finish".
class _FinishButton extends StatelessWidget {
  final bool compact;
  final VoidCallback? onPressed;

  const _FinishButton({required this.compact, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: accentColor(context),
      disabledForegroundColor: textSecondaryColor(context),
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : AppSpacing.md),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
    );
    const icon = Icon(LucideIcons.check, size: 18);
    return Tooltip(
      message: 'Finish workout',
      child: Semantics(
        button: true,
        label: 'Finish workout',
        enabled: onPressed != null,
        onTap: onPressed,
        excludeSemantics: true,
        child:
            compact
                ? TextButton(
                  key: const ValueKey('finish-workout'),
                  onPressed: onPressed,
                  style: style,
                  child: icon,
                )
                : TextButton.icon(
                  key: const ValueKey('finish-workout'),
                  onPressed: onPressed,
                  style: style,
                  icon: icon,
                  label: const Text('Finish'),
                ),
      ),
    );
  }
}

/// Start, pause or resume the session clock. A fresh log gets the one
/// labelled, filled action in the header, since Start is what it is waiting
/// for. Once the clock has run the control shrinks to a square: filled to
/// resume, outlined to pause, so Finish reads as the next move.
class _TimerButton extends StatelessWidget {
  final bool running;
  final bool compact;
  final VoidCallback? onPressed;

  const _TimerButton({
    required this.running,
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final filled = !running;
    final style = TextButton.styleFrom(
      foregroundColor: filled ? onAccentColor(context) : accentColor(context),
      // The quiet header action is a neutral fill, not an outline.
      backgroundColor:
          filled ? accentFillColor(context) : controlFillColor(context),
      disabledForegroundColor: textSecondaryColor(context),
      disabledBackgroundColor: controlFillColor(context),
      side: BorderSide.none,
      minimumSize: compact ? const Size.square(40) : const Size(64, 36),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      padding:
          compact
              ? EdgeInsets.zero
              : const EdgeInsets.only(
                left: AppSpacing.md - AppSpacing.xxs,
                right: AppSpacing.md + AppSpacing.xxs,
              ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
    );
    final icon = Icon(
      running ? LucideIcons.pause : LucideIcons.play,
      size: compact ? 18 : 16,
    );
    final label =
        running
            ? 'Pause workout'
            : compact
            ? 'Resume workout'
            : 'Start workout';
    if (compact) {
      return Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          enabled: onPressed != null,
          onTap: onPressed,
          excludeSemantics: true,
          child: TextButton(onPressed: onPressed, style: style, child: icon),
        ),
      );
    }
    return Semantics(
      button: true,
      label: label,
      child: TextButton.icon(
        onPressed: onPressed,
        style: style,
        icon: icon,
        label: const Text('Start'),
      ),
    );
  }
}

/// The header's second line: where this log sits in the training block, then
/// the session clock. Before Start there is nothing to time, so the clock is
/// left out rather than reading 00:00 next to an untouched log.
class _SessionMeta extends StatelessWidget {
  final String label;
  final WorkoutSession session;
  final ValueListenable<DateTime> now;
  final TextStyle timerStyle;

  const _SessionMeta({
    required this.label,
    required this.session,
    required this.now,
    required this.timerStyle,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final where = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final hasTime = session.hasStarted || (session.durationSeconds ?? 0) > 0;
    if (!hasTime) return where;
    const gap = AppSpacing.sm;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The block and week come first: on a narrow phone the clock scales
        // down a touch rather than cutting the week number off.
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final labelWidth = painter.width;
        painter.dispose();
        final clockWidth = (constraints.maxWidth - labelWidth - gap).clamp(
          constraints.maxWidth * .25,
          constraints.maxWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: where),
            const SizedBox(width: gap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: clockWidth),
              child: ValueListenableBuilder<DateTime>(
                valueListenable: now,
                builder:
                    (context, now, _) => _SessionClock(
                      elapsed: formatDuration(session.elapsedSeconds(now)),
                      session: session,
                      style: timerStyle,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The session clock, set inline after the block and week. It is read-only, so
/// it gets no ground: a running clock leads with an accent dot in primary ink,
/// a paused one with the pause glyph and a finished log with a timer, both in
/// secondary ink.
class _SessionClock extends StatelessWidget {
  final String elapsed;
  final WorkoutSession session;
  final TextStyle style;

  const _SessionClock({
    required this.elapsed,
    required this.session,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final running = session.isTimerRunning;
    final accent = accentColor(context);
    final ink =
        running ? textPrimaryColor(context) : textSecondaryColor(context);
    final glyphSize = MediaQuery.textScalerOf(context).scale(12);
    final Widget glyph =
        running
            ? Container(
              width: glyphSize / 2,
              height: glyphSize / 2,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            )
            : Icon(
              session.isCompleted ? LucideIcons.timer : LucideIcons.pause,
              size: glyphSize,
              color: ink,
            );
    return Semantics(
      label:
          session.isCompleted
              ? 'Recorded duration $elapsed'
              : running
              ? 'Elapsed time $elapsed'
              : 'Paused at $elapsed',
      // One text run, so the time sits on the subtitle's baseline.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(alignment: PlaceholderAlignment.middle, child: glyph),
              const WidgetSpan(
                child: SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              ),
              TextSpan(text: elapsed),
            ],
          ),
          key: const ValueKey('workout_elapsed_time'),
          maxLines: 1,
          style: style.copyWith(color: ink),
        ),
      ),
    );
  }
}

/// The plan switch, as a trade between two pages of one book. The header,
/// the plan tabs and the week bar hold still; only the log moves.
///
/// The workout being switched away from starts its log leaving the moment
/// the switch is chosen, from wherever the finger left it and at the hand's
/// speed ([_LogMotion.leave]), before the save that has to come first. Once
/// that save is done, this route pushes the chosen plan's workout over it.
/// That page is opaque where it holds still, but its body lets the replaced
/// page show through until it has landed ([_PlanSwitchArrival]), so the old
/// log is seen going as the new one comes in over it from the other side:
/// [AppMotion.swipeShift] over [AppMotion.enter] on [AppMotion.curve], fading
/// in from 30% of the way as a page trade does ([PageSwitchTransition]). The
/// two logs are never joined, so a save that takes a frame or a fifth of a
/// second only changes when the new log starts, never how it looks.
///
/// Once the switch has landed the page is an ordinary one: Back, the
/// platform's back gestures (Android's predictive back, iOS's edge swipe) and
/// the pop transition all come from the theme, exactly as for the workout it
/// replaced, and it lets go of that route. Under reduced motion the switch
/// lands at once.
class _PlanSwitchRoute extends MaterialPageRoute<void> {
  /// +1 when the chosen plan comes after the current one, so its log enters
  /// from the right; -1 when it comes before.
  final double direction;

  /// The plan tab the switch left, for the underline to slide from.
  final int fromIndex;

  /// Where the replaced page's plan tabs stood scrolled.
  final double tabOffset;

  /// The workout being switched away from, until the switch has landed.
  /// Only the push needs it; held any longer, each switch would keep the
  /// disposed workout before it alive, and that one the one before it.
  Route<dynamic>? _replacing;
  final bool reduceMotion;

  /// True until the switch has landed.
  bool _switching = true;

  _PlanSwitchRoute({
    required super.builder,
    required this.direction,
    required this.fromIndex,
    required this.tabOffset,
    required Route<dynamic>? replacing,
    required this.reduceMotion,
  }) : _replacing = replacing;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : AppMotion.enter;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : super.reverseTransitionDuration;

  // The platform's transitions would also move the outgoing workout aside;
  // here it stays where it is while the new one arrives over it. Any other
  // page under this one (Home) still takes part as usual.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      previousRoute != _replacing && super.canTransitionFrom(previousRoute);

  @override
  TickerFuture didPush() {
    final pushed = super.didPush();
    pushed.whenCompleteOrCancel(() {
      _switching = false;
      _replacing = null;
    });
    return pushed;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // One tree shape before and after the switch lands, so the workout keeps
    // its state: the platform's transition sits still while the log comes
    // in, and the arrival sits still for everything after.
    final switching = _switching;
    return super.buildTransitions(
      context,
      switching ? kAlwaysCompleteAnimation : animation,
      secondaryAnimation,
      _PlanSwitchArrival(
        animation: switching ? animation : kAlwaysCompleteAnimation,
        arriving: switching,
        direction: direction,
        fromIndex: fromIndex,
        tabOffset: tabOffset,
        child: child,
      ),
    );
  }
}

/// What a workout arriving by a plan switch needs from its route: how far
/// its log has come in, from which side, and where the replaced page's plan
/// tabs stood. Only [arriving] changes for the page, once, when it lands.
class _PlanSwitchArrival extends InheritedWidget {
  /// The arrival, 0 to 1 over [AppMotion.enter]; complete once landed.
  final Animation<double> animation;

  /// True until the switch has landed.
  final bool arriving;
  final double direction;
  final int fromIndex;
  final double tabOffset;

  const _PlanSwitchArrival({
    required this.animation,
    required this.arriving,
    required this.direction,
    required this.fromIndex,
    required this.tabOffset,
    required super.child,
  });

  static _PlanSwitchArrival? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PlanSwitchArrival>();

  // Rebuilt on every frame of the push with the same animation, which the
  // log follows by itself; the page only rebuilds when it lands.
  @override
  bool updateShouldNotify(_PlanSwitchArrival oldWidget) =>
      arriving != oldWidget.arriving || animation != oldWidget.animation;
}

/// How faint the log gets as a swipe carries it toward another plan: half,
/// so it reads as a page being moved aside, still legible if let go.
const double _swipeFadeFloor = 0.5;

/// The share of the width at which a swipe has faded the log to the floor.
const double _swipeFadeReach = 0.4;

/// How far the log moves for each pixel the finger drags past the first or
/// last plan, where there is nothing to go to.
const double _edgeFollow = 0.05;

/// The workout log's own sideways motion among the plans, in logical pixels:
/// following a plan swipe one to one and fading as it goes, rubber-banding
/// at the first and last plan, springing back when let go, and leaving when
/// the plan changes. [_PlanLogTransition] applies it.
class _LogMotion {
  _LogMotion(TickerProvider vsync)
    : offset = AnimationController.unbounded(vsync: vsync),
      leaving = AnimationController(vsync: vsync, duration: AppMotion.enter);

  /// How far the log has moved sideways.
  final AnimationController offset;

  /// How far through leaving the log is, 0 to 1 over the length of the
  /// trade; it clears out in the first part ([PageSwitchTransition.leavingFade]).
  final AnimationController leaving;

  late final Listenable listenable = Listenable.merge([offset, leaving]);

  /// How far the log moves for each pixel the finger drags.
  double _follow = 1;

  /// Whether the log is travelling toward another plan, and so fades.
  bool _fades = false;

  /// The spring's natural rate. A critically damped spring thrown toward its
  /// end faster than this many times the distance overshoots it once.
  static final double _springRate = math.sqrt(
    AppMotion.settle.stiffness / AppMotion.settle.mass,
  );

  /// A tenth of a pixel is rest; the spring's default tolerance would keep
  /// ticking through invisible fractions of one.
  static const Tolerance _rest = Tolerance(distance: 0.1, velocity: 1);

  /// The log's opacity for a page [width] wide.
  double opacity(double width) {
    var opacity = 1 - PageSwitchTransition.leavingFade.transform(leaving.value);
    if (_fades && width > 0) {
      final travelled = offset.value.abs() / (width * _swipeFadeReach);
      opacity *= 1 - (1 - _swipeFadeFloor) * math.min(travelled, 1);
    }
    return opacity;
  }

  /// Follows a drag [distance] pixels from where it began. [towardPlan] says
  /// there is a plan to go to that way: the log then moves with the finger
  /// and fades. Past the first or last plan it barely moves, so the edge
  /// reads as an edge.
  void follow(double distance, {required bool towardPlan}) {
    _fades = towardPlan;
    _follow = towardPlan ? 1 : _edgeFollow;
    final moved = distance * _follow;
    offset.value =
        towardPlan ? moved : moved.clamp(-AppMotion.shift, AppMotion.shift);
  }

  /// Springs back to rest, carrying the finger's release [velocity] so a
  /// flick and a slow let-go settle differently, as the hand did. Critically
  /// damped, so it never overshoots; the opacity comes back with it.
  void settle(double velocity) {
    if (leaving.value > 0) {
      leaving.animateBack(
        0,
        duration: AppMotion.standard,
        curve: AppMotion.curve,
      );
    }
    final from = offset.value;
    if (from == 0 && velocity == 0) {
      offset.value = 0;
      return;
    }
    // Content held at the end of its travel had stopped following the
    // finger, so it has no speed of its own away from rest.
    var speed = velocity * _follow;
    if (!_fades && from.abs() >= AppMotion.shift && speed.sign == from.sign) {
      speed = 0;
    }
    offset
        .animateWith(
          SpringSimulation(AppMotion.settle, from, 0, speed, tolerance: _rest),
        )
        .whenComplete(() => offset.value = 0);
  }

  /// Leaves for the plan [direction] away (+1 the next), carrying on from
  /// wherever it is: by [distance] further, on the same spring as a settle
  /// so the finger's [velocity] carries it out, while it fades away within
  /// the first part of the trade.
  void leave({
    required double direction,
    required double velocity,
    required double distance,
  }) {
    _fades = true;
    _follow = 1;
    final from = offset.value;
    // Only speed already carrying the log out goes with it; a flick back
    // that still switched starts it from rest.
    final speed = velocity * direction < 0 ? velocity : 0.0;
    // Reaching further than a hard flick would overshoot keeps the log
    // going one way.
    final reach = math.max(distance, speed.abs() / _springRate);
    offset.animateWith(
      SpringSimulation(
        AppMotion.settle,
        from,
        from - direction * reach,
        speed,
        tolerance: _rest,
      ),
    );
    leaving.forward();
  }

  /// At rest at once, for reduced motion.
  void rest() {
    offset.value = 0;
    leaving.value = 0;
  }

  void dispose() {
    offset.dispose();
    leaving.dispose();
  }
}

/// Moves one part of a workout page (its log, or a notice above it) as the
/// page moves among the plans: its own [motion], and, while the page arrives
/// by a plan switch, coming in from [arrivingFrom] pixels aside and fading in
/// from 30% of the way. Only the transform and opacity change per frame; the
/// child is built once and passed through.
///
/// The arriving log is laid out, tappable and announced from its first
/// frame. A [leaving] log leaves the semantics tree; the page stops taking
/// taps then too, as it does for any navigation.
class _PlanLogTransition extends StatelessWidget {
  final _LogMotion motion;
  final Animation<double> arrival;
  final double arrivingFrom;
  final bool leaving;
  final Widget child;

  const _PlanLogTransition({
    required this.motion,
    required this.arrival,
    required this.arrivingFrom,
    required this.leaving,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // The outer boundary keeps each frame's move from repainting the header
    // and bars; the inner one keeps it from repainting the log, which moves
    // as one picture while both logs are on screen.
    return RepaintBoundary(
      child: ExcludeSemantics(
        excluding: leaving,
        child: AnimatedBuilder(
          animation: Listenable.merge([motion.listenable, arrival]),
          child: RepaintBoundary(child: child),
          builder: (context, child) {
            final arrived = arrival.value;
            return Opacity(
              opacity:
                  motion.opacity(width) *
                  PageSwitchTransition.arrivingFade.transform(arrived),
              alwaysIncludeSemantics: true,
              child: Transform.translate(
                offset: Offset(
                  motion.offset.value +
                      arrivingFrom * (1 - AppMotion.curve.transform(arrived)),
                  0,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}
