import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/plan_colors.dart';
import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_plan.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../navigation/app_navigation_observer.dart';
import '../navigation/workout_destination.dart';
import '../providers/training_block_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../repositories/training_block_repository.dart';
import '../services/hive_service.dart';
import '../services/pr_tracking_service.dart';
import '../services/sync_service.dart';
import '../services/workout_progression_service.dart';
import '../services/workout_session_initializer.dart';
import '../services/workout_timer_notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/format.dart';
import '../utils/set_history.dart';
import '../utils/workout_context.dart';
import '../widgets/action_progress.dart';
import '../widgets/app_header.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/underline_tab_strip.dart';
import '../widgets/workout/exercise_card.dart';
import '../widgets/workout/plan_swipe_region.dart';
import '../widgets/workout/set_entry_table.dart';
import '../widgets/workout/training_block_dialogs.dart';
import '../widgets/workout/training_block_strip.dart';
import '../widgets/workout/training_boundary_sheet.dart';
import '../widgets/workout/workout_dialogs.dart';

class WorkoutScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final int planIndex;
  final WorkoutDestination? destination;
  final bool showLogConfirmationOnOpen;

  const WorkoutScreen({
    super.key,
    required this.plan,
    required this.planIndex,
    this.destination,
    this.showLogConfirmationOnOpen = false,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen>
    with SingleTickerProviderStateMixin, AppRouteParticipant<WorkoutScreen>
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
  int _currentWeekIndex = 0;
  final Map<String, WorkoutSession> _weekSessions = {};
  bool _hasUnsavedChanges = false;
  int _draftRevision = 0;
  Future<bool>? _saveFuture;
  bool _isNavigating = false;
  bool _isSaving = false;
  String? _saveError;
  String? _timerAction;
  bool _confirmingFinish = false;
  Timer? _ticker;
  WorkoutSessionProvider? _sessionProvider;
  bool _didShowInitialLogConfirmation = false;
  late final AnimationController _planSwipeOffset =
      AnimationController.unbounded(vsync: this);

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
  void dispose() {
    _ticker?.cancel();
    _now.dispose();
    _training.removeListener(_onTrainingChanged);
    if (_ownsTraining) _training.dispose();
    _sessionProvider?.removeListener(_reloadCurrentSession);
    _planSwipeOffset.dispose();
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
        if (saved != null && (saved.deletedAt != null || saved.isCompleted)) {
          // A synced deletion/completion must also survive Back's autosave.
          _weekSessions[_currentWeek] = saved;
          _hasUnsavedChanges = false;
          return true;
        }
        if (session.isCompleted) return true;
        if (!_hasUnsavedChanges && saved == null) return true;
        final hasSets = session.exercises.any((e) => e.sets.isNotEmpty);
        if (!hasSets && !_hasUnsavedChanges) return true;
        final revision = _draftRevision;
        final week = _currentWeek;
        // Keep the identity assigned by the first write for subsequent edits.
        session = session.copyWith(
          planId: widget.plan.id,
          planName: widget.plan.name,
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
    if (MediaQuery.disableAnimationsOf(context)) return;
    final plans = context.read<WorkoutPlanProvider>().plans;
    final index = _currentPlanIndex(plans);
    final canMove = distance < 0 ? index < plans.length - 1 : index > 0;
    // Follow the finger just enough to acknowledge the gesture without
    // pulling the workout table far from its reading position.
    _planSwipeOffset.value = (distance * (canMove ? 0.20 : 0.05)).clamp(
      -28.0,
      28.0,
    );
  }

  void _settlePlanSwipe() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _planSwipeOffset.value = 0;
      return;
    }
    _planSwipeOffset.animateTo(
      0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _switchPlan(WorkoutPlan plan, int index) async {
    final currentIndex = _currentPlanIndex(
      context.read<WorkoutPlanProvider>().plans,
    );
    if (index == currentIndex) return;
    final direction = index > currentIndex ? 1.0 : -1.0;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _planSwipeOffset.animateTo(
        -direction * 28,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    }
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 190);
    await _saveBeforeNavigation(
      () => Navigator.pushReplacement(
        context,
        PageRouteBuilder<void>(
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  WorkoutScreen(plan: plan, planIndex: index),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation.drive(
                Tween<double>(
                  begin: 0.78,
                  end: 1,
                ).chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: SlideTransition(
                position: animation.drive(
                  Tween(
                    begin: Offset(direction * 0.08, 0),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: child,
              ),
            );
          },
        ),
      ),
      leavesScreen: true,
    );
    if (mounted && !_isNavigating) _settlePlanSwipe();
  }

  Widget _animatedPlanContent(Widget child) => AnimatedBuilder(
    animation: _planSwipeOffset,
    builder:
        (context, child) => Transform.translate(
          offset: Offset(_planSwipeOffset.value, 0),
          child: child,
        ),
    child: child,
  );

  void _showPRDialog(List<PRResult> prs) {
    WorkoutDialogs.showPRDialog(context, prs);
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

  WorkoutSession _getOrCreateSession() {
    if (_weekSessions[_currentWeek] case final session?) return session;
    final session = WorkoutSessionInitializer.initialize(
      plan: widget.plan,
      week: _selectedWeek,
      existingSession: _savedSessionForWeek(_currentWeek),
      previousSession:
          widget.plan.id == null
              ? null
              : _training.source(widget.plan.id!, _currentWeek),
    );
    _weekSessions[_currentWeek] = session;
    return session;
  }

  void _updateSession(WorkoutSession session) {
    if (_getOrCreateSession().isCompleted ||
        _getOrCreateSession().deletedAt != null) {
      return;
    }
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
      final switchWorkout = await showDialog<bool>(
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
      final confirmed = await showDialog<bool>(
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
        _syncTicker(result.session);
        await _updateTimerNotification(
          WorkoutTimerNotificationService.instance.dismiss,
        );
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Workout logged')));
        if (result.personalRecords.isNotEmpty) {
          _showPRDialog(result.personalRecords);
        }
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
    return await showDialog<bool>(
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
    final clean = WorkoutSessionInitializer.initialize(
      plan: widget.plan,
      week: _selectedWeek,
    );
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
      onAdd: (name) {
        final currentSession = _getOrCreateSession();
        final normalizedName = name.trim().toLowerCase();
        if (currentSession.exercises.any(
          (exercise) => exercise.name.trim().toLowerCase() == normalizedName,
        )) {
          return;
        }
        final updatedExercises = List<Exercise>.from(currentSession.exercises);
        updatedExercises.add(Exercise(name: name, sets: [], note: null));
        _updateSession(currentSession.copyWith(exercises: updatedExercises));
        _autoSave();
      },
      onRemove: (name) {
        final currentSession = _getOrCreateSession();
        final normalizedName = name.toLowerCase();
        final updatedExercises =
            currentSession.exercises
                .where(
                  (exercise) => exercise.name.toLowerCase() != normalizedName,
                )
                .toList();
        _updateSession(currentSession.copyWith(exercises: updatedExercises));
        _autoSave();
      },
    );
  }

  void _showExerciseRenameDialog(int exerciseIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    WorkoutDialogs.showRenameExerciseDialog(
      context,
      currentName: exercise.name,
      onRename: (name) {
        final updatedExercises = List<Exercise>.from(session.exercises);
        updatedExercises[exerciseIndex] = Exercise(
          name: name,
          sets: exercise.sets,
          note: exercise.note,
        );
        _updateSession(session.copyWith(exercises: updatedExercises));
        _autoSave();
      },
    );
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
      final planSet = _getLastSetForExerciseInPlan(exercise.name);
      newSet = gym.Set(reps: planSet?.reps ?? 8, weight: planSet?.weight ?? 0);
    }

    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
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
      sets: updatedSets,
      note: exercise.note,
    );
    _updateSession(session.copyWith(exercises: updatedExercises));
    // Persist once entry closes, matching weight and rep edits.
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    final session = _getOrCreateSession();
    if (session.isCompleted) return;
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

  Future<T> _structureMutation<T>(Future<T> Function() write) async {
    if (_timerAction != null || !await _autoSave() || !mounted) {
      throw StateError('Save the workout before changing blocks.');
    }
    setState(() => _timerAction = 'Saving blocks');
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

  bool get _canAddWeek =>
      _progress?.state == WorkoutProgressState.awaitingBoundary &&
      _progress?.activeWeekId == _currentWeek;

  Future<void> _addWeek(String blockId) async {
    if (!_canAddWeek || blockId != _selectedWeek.blockId) return;
    if (!await _autoSave() || !mounted) return;
    await _maybeBoundaryPrompt();
  }

  Future<void> _renameBlock(String blockId) async {
    final block = _blocks.where((b) => b.id == blockId).firstOrNull;
    if (block == null) return;
    await TrainingBlockDialogs.rename(
      context,
      block,
      onSave:
          (name) => _structureMutation(
            () => _structure.renameBlock(widget.plan.splitId!, blockId, name),
          ),
    );
  }

  Future<void> _reorderBlocks() => TrainingBlockDialogs.reorder(
    context,
    _blocks,
    onSave:
        (ids) => _structureMutation(
          () => _structure.reorderBlocks(widget.plan.splitId!, ids),
        ),
  );

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
    final confirmed = await showDialog<bool>(
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
      await showModalBottomSheet<void>(
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
                                  icon: LucideIcons.plus,
                                  title: 'Add week',
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

  void _deleteExercise(int exerciseIndex) async {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final confirmed = await WorkoutDialogs.showDeleteExerciseDialog(
      context,
      exerciseName: exercise.name,
    );

    if (confirmed && mounted && !session.isCompleted) {
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
    final accent = accentColor(context);

    final planProvider = context.watch<WorkoutPlanProvider>();
    final plans = planProvider.plans;
    final currentPlanIndex = _currentPlanIndex(plans);
    final activePlan =
        currentPlanIndex >= 0 ? plans[currentPlanIndex] : widget.plan;
    final VoidCallback? onNextPlan =
        currentPlanIndex >= 0 && currentPlanIndex < plans.length - 1
            ? () =>
                _switchPlan(plans[currentPlanIndex + 1], currentPlanIndex + 1)
            : null;
    final VoidCallback? onPreviousPlan =
        currentPlanIndex > 0
            ? () =>
                _switchPlan(plans[currentPlanIndex - 1], currentPlanIndex - 1)
            : null;
    final planColor = planColorOf(activePlan.planColor, context);
    final timerBase = Theme.of(context).textTheme.bodySmall!;
    final timerStyle = AppTypography.figures(
      fontSize: timerBase.fontSize,
      fontWeight: timerBase.fontWeight,
      height: timerBase.height,
      color: textPrimaryColor(context),
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
      canPop:
          session.isCompleted &&
          !_isNavigating &&
          !_isSaving &&
          _timerAction == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: AbsorbPointer(
        absorbing: _isNavigating || _timerAction != null,
        child: Scaffold(
          backgroundColor: backgroundColor(context),
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
                PlanSwipeRegion(
                  onNextPlan: onNextPlan,
                  onPreviousPlan: onPreviousPlan,
                  onDragProgress: _updatePlanSwipe,
                  onDragCancel: _settlePlanSwipe,
                  child: _animatedPlanContent(
                    _PlanHeader(plan: activePlan, color: planColor),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                LayoutBuilder(
                  builder:
                      (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              _contextLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * .45,
                            ),
                            child: ValueListenableBuilder<DateTime>(
                              valueListenable: _now,
                              builder: (context, now, _) {
                                final elapsed = formatDuration(
                                  session.elapsedSeconds(now),
                                );
                                return Semantics(
                                  label:
                                      session.isCompleted
                                          ? 'Recorded duration $elapsed'
                                          : 'Elapsed time $elapsed',
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      elapsed,
                                      key: const ValueKey(
                                        'workout_elapsed_time',
                                      ),
                                      style: timerStyle,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                ),
              ],
            ),
            actions: [
              if (!session.isCompleted) ...[
                if (MediaQuery.sizeOf(context).width < 400 &&
                    textScaler.scale(1) > 1.5)
                  IconButton(
                    tooltip:
                        session.isTimerRunning
                            ? 'Pause workout'
                            : 'Start workout',
                    onPressed:
                        _isSaving ||
                                _timerAction != null ||
                                !_canUseTimer(session)
                            ? null
                            : _toggleTimer,
                    color: accent,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: Icon(
                      session.isTimerRunning
                          ? LucideIcons.pause
                          : LucideIcons.play,
                      size: 22,
                    ),
                  )
                else
                  Semantics(
                    button: true,
                    label:
                        session.isTimerRunning
                            ? 'Pause workout'
                            : 'Start workout',
                    child: TextButton(
                      onPressed:
                          _isSaving ||
                                  _timerAction != null ||
                                  !_canUseTimer(session)
                              ? null
                              : _toggleTimer,
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        minimumSize: const Size(64, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.button,
                        ),
                      ),
                      child: Text(session.isTimerRunning ? 'Pause' : 'Start'),
                    ),
                  ),
                IconButton(
                  tooltip: 'Finish workout',
                  onPressed:
                      session.hasStarted &&
                              !_isSaving &&
                              _timerAction == null &&
                              _canUseTimer(session)
                          ? _stopWorkout
                          : null,
                  color: accent,
                  disabledColor: textSecondaryColor(context),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(LucideIcons.check, size: 22),
                ),
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
              ],
            ],
            bottom: _buildPlanTabBar(accent, plans, currentPlanIndex),
          ),
          body: Column(
            children: [
              if (_progressError)
                TrainingProgressNotice(
                  icon: LucideIcons.circleAlert,
                  isError: true,
                  message: "Progress didn't load.",
                  actionLabel: 'Try again',
                  onAction: _prepareEntry,
                ),
              if (!_progressError &&
                  session.isCompleted &&
                  _progress?.activeWeekId == _currentWeek)
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

              if (_isSaving || (_timerAction != null && !_confirmingFinish))
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: ActionProgress(_timerAction ?? 'Saving workout'),
                ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_saveError!),
                        ),
                      ),
                      TextButton(
                        onPressed: _isSaving ? null : _autoSave,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: PlanSwipeRegion(
                  onNextPlan: onNextPlan,
                  onPreviousPlan: onPreviousPlan,
                  onDragProgress: _updatePlanSwipe,
                  onDragCancel: _settlePlanSwipe,
                  child: _animatedPlanContent(
                    CustomScrollView(
                      key: ValueKey(_currentWeek),
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      slivers: [
                        // One gutter keeps the exercise tables aligned as a log.
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          sliver: SliverReorderableList(
                            itemCount:
                                session.exercises.length +
                                (session.isCompleted ? 0 : 1),
                            onReorderItem: _reorderExercises,
                            proxyDecorator: (child, index, animation) {
                              return Material(
                                color: surfaceColor(context),
                                borderRadius: AppRadius.card,
                                child: child,
                              );
                            },
                            itemBuilder: (context, index) {
                              if (index == session.exercises.length) {
                                return TextButton.icon(
                                  key: const ValueKey('add_exercise_button'),
                                  onPressed: _addEmptyExercise,
                                  icon: const Icon(LucideIcons.plus, size: 18),
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
                                      color: borderColor(context),
                                    ),
                                  ),
                                ),
                                child: ExerciseCard(
                                  exercise: exercise,
                                  exerciseIndex: index,
                                  reorderable: !session.isCompleted,
                                  readOnly: session.isCompleted,
                                  onMoveUp:
                                      index > 0
                                          ? () => _reorderExercises(
                                            index,
                                            index - 1,
                                          )
                                          : null,
                                  onMoveDown:
                                      index < session.exercises.length - 1
                                          ? () => _reorderExercises(
                                            index,
                                            index + 1,
                                          )
                                          : null,
                                  accent: accent,
                                  previousSets: _previousFor(exercise.name),
                                  onSetChanged: _changeSetValues,
                                  onSetRpeChanged: _changeSetRpe,
                                  onEntryFinished: () {
                                    if (mounted) _autoSave();
                                  },
                                  onAddSet: (i) => _addSet(i),
                                  onDeleteSet:
                                      (i, setIndex) => _deleteSet(i, setIndex),
                                  onAddNote: _addExerciseNote,
                                  onRename: _showExerciseRenameDialog,
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
              _buildWeekNavBar(accent),
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
    int selectedIndex,
  ) {
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
      onSelectWeek: _onWeekChanged,
      onSelectBlock: _selectBlock,
      onRenameBlock: _renameBlock,
      onReorderBlocks: _reorderBlocks,
      onAddWeek: _addWeek,
      onCreateBlock: _createBlock,
    ),
  );
}

class _PlanHeader extends StatelessWidget {
  final WorkoutPlan plan;

  /// The active plan's resolved identity-marker colour.
  final Color color;

  const _PlanHeader({required this.plan, required this.color});

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
          child: Text(
            plan.name,
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
