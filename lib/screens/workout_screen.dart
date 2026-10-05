import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../data/plan_colors.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/hive_service.dart';
import '../services/pr_tracking_service.dart';
import '../services/workout_session_initializer.dart';
import '../services/workout_completion_service.dart';
import '../services/workout_timer_notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/format.dart';
import '../utils/set_history.dart';
import '../widgets/underline_tab_strip.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/action_progress.dart';
import '../widgets/workout/exercise_card.dart';
import '../widgets/workout/plan_swipe_region.dart';
import '../widgets/workout/workout_dialogs.dart';

class WorkoutScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final int planIndex;
  final int? initialWeekNumber;
  final WorkoutSession? initialSession;
  final bool showLogConfirmationOnOpen;

  const WorkoutScreen({
    super.key,
    required this.plan,
    required this.planIndex,
    this.initialWeekNumber,
    this.initialSession,
    this.showLogConfirmationOnOpen = false,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen>
    with SingleTickerProviderStateMixin {
  List<int> _weeks = [1];
  int _currentWeekIndex = 0;
  final Map<int, WorkoutSession> _weekSessions = {};
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
    _loadWeeks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sessionProvider =
          context.read<WorkoutSessionProvider>()
            ..addListener(_reloadCurrentSession);
      if (widget.showLogConfirmationOnOpen && !_didShowInitialLogConfirmation) {
        _didShowInitialLogConfirmation = true;
        _stopWorkout();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sessionProvider?.removeListener(_reloadCurrentSession);
    _planSwipeOffset.dispose();
    super.dispose();
  }

  void _reloadCurrentSession() {
    // A provider notification may belong to an older write still in flight.
    if (!mounted || _hasUnsavedChanges || _isSaving || _timerAction != null) {
      return;
    }
    final saved = _savedSessionForWeek(_currentWeek);
    if (saved == null) return;
    _weekSessions[_currentWeek] = saved;
    _syncTicker(saved);
    setState(() {});
  }

  void _loadWeeks() {
    final planSessions = HiveService.getSessionsForPlan(
      widget.plan.name,
      widget.plan.splitId,
    );
    final existingWeeks = HiveService.getWeeksForPlan(
      widget.plan.name,
      widget.plan.splitId,
    );
    if (existingWeeks.isEmpty) {
      _weeks = [1];
    } else {
      _weeks = existingWeeks;
      final drafts = planSessions.where((session) => !session.isCompleted);
      if (drafts.isEmpty) {
        final maxWeek = _weeks.reduce((a, b) => a > b ? a : b);
        if (!_weeks.contains(maxWeek + 1)) _weeks.add(maxWeek + 1);
        _currentWeekIndex = _weeks.length - 1;
      } else {
        final draft = drafts.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
        _currentWeekIndex = _weeks.indexOf(draft.weekNumber);
      }
    }
    final initialSession = widget.initialSession;
    if (initialSession != null) {
      if (!_weeks.contains(initialSession.weekNumber)) {
        _weeks.add(initialSession.weekNumber);
        _weeks.sort();
      }
      _weekSessions[initialSession.weekNumber] = initialSession;
    }
    final requestedWeek =
        initialSession?.weekNumber ?? widget.initialWeekNumber;
    if (requestedWeek != null && _weeks.contains(requestedWeek)) {
      _currentWeekIndex = _weeks.indexOf(requestedWeek);
    }
    _loadSessionForCurrentWeek();
  }

  void _loadSessionForCurrentWeek() {
    final week = _weeks[_currentWeekIndex];
    final existingSession = _savedSessionForWeek(week);
    if (existingSession != null) {
      _weekSessions[week] = existingSession;
      _syncTicker(existingSession);
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  WorkoutSession? _savedSessionForWeek(int week) {
    final selected = _weekSessions[week];
    // A renamed plan or another session in the same week must not replace the
    // draft selected from Dashboard when provider notifications arrive.
    if (selected != null) {
      final id = selected.id;
      return id == null ? selected : HiveService.getSessionById(id) ?? selected;
    }
    return HiveService.getSessionForPlanAndWeek(
      widget.plan.name,
      week,
      widget.plan.splitId,
    );
  }

  void _syncTicker(WorkoutSession session) {
    if (session.isTimerRunning) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  gym.Set? _getLastSetForExerciseInPlan(String exerciseName) {
    final currentWeek = _weeks[_currentWeekIndex];
    if (currentWeek > 1) {
      final prevWeekSession = HiveService.getSessionForPlanAndWeek(
        widget.plan.name,
        currentWeek - 1,
        widget.plan.splitId,
      );
      if (prevWeekSession != null) {
        for (var exercise in prevWeekSession.exercises) {
          if (exercise.name.toLowerCase() == exerciseName.toLowerCase() &&
              exercise.sets.isNotEmpty) {
            return exercise.sets.last;
          }
        }
      }
    }
    return HiveService.getLastSetForExercise(exerciseName, widget.plan.splitId);
  }

  Future<void> _onWeekChanged(int newIndex) async {
    await _saveBeforeNavigation(() {
      setState(() => _currentWeekIndex = newIndex);
      _loadSessionForCurrentWeek();
    });
  }

  Future<void> _addNewWeek() async {
    await _saveBeforeNavigation(() {
      final lastWeek = _weeks.last;
      setState(() {
        _weeks.add(lastWeek + 1);
        _currentWeekIndex = _weeks.length - 1;
      });
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
        if (session.isCompleted) return true;
        final hasSets = session.exercises.any((e) => e.sets.isNotEmpty);
        if (!hasSets && !_hasUnsavedChanges) return true;
        final revision = _draftRevision;
        final week = _currentWeek;
        // Keep the identity assigned by the first write for subsequent edits.
        session = session.copyWith(
          planId: widget.plan.id,
          planName: widget.plan.name,
          weekNumber: week,
          splitId: widget.plan.splitId,
        );
        _weekSessions[week] = session;
        await provider.upsertSession(session);
        if (revision == _draftRevision) {
          _hasUnsavedChanges = false;
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

  Future<void> _handleBack() =>
      _saveBeforeNavigation(() => Navigator.pop(context), leavesScreen: true);

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
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 190);
    await _saveBeforeNavigation(
      () => Navigator.pushReplacement(
        context,
        PageRouteBuilder<void>(
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (context, animation, secondaryAnimation) =>
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
    builder: (context, child) => Transform.translate(
      offset: Offset(_planSwipeOffset.value, 0),
      child: child,
    ),
    child: child,
  );

  void _showPRDialog(List<PRResult> prs) {
    WorkoutDialogs.showPRDialog(context, prs);
  }

  int get _currentWeek => _weeks[_currentWeekIndex];

  WorkoutSession _getOrCreateSession() {
    if (_weekSessions.containsKey(_currentWeek)) {
      return _weekSessions[_currentWeek]!;
    }

    final existingSession = HiveService.getSessionForPlanAndWeek(
      widget.plan.name,
      _currentWeek,
      widget.plan.splitId,
    );
    final previousSession =
        _currentWeek > 1
            ? HiveService.getSessionForPlanAndWeek(
              widget.plan.name,
              _currentWeek - 1,
              widget.plan.splitId,
            )
            : null;
    final session = WorkoutSessionInitializer.initialize(
      plan: widget.plan,
      weekNumber: _currentWeek,
      existingSession: existingSession,
      previousSession: previousSession,
    );
    _weekSessions[_currentWeek] = session;
    return session;
  }

  /// All persisted sessions plus any in-memory drafts whose latest edits may
  /// not have been flushed to Hive yet. Deduplicates by session id so the
  /// in-memory copy wins when both exist.
  List<WorkoutSession> _sessionsWithDrafts() {
    final persisted = HiveService.getSessions();
    final draftIds = <String>{};
    final merged = <WorkoutSession>[];
    for (final draft in _weekSessions.values) {
      if (draft.id != null) draftIds.add(draft.id!);
      merged.add(draft);
    }
    for (final session in persisted) {
      if (session.id == null || !draftIds.contains(session.id)) {
        merged.add(session);
      }
    }
    return merged;
  }

  void _updateSession(WorkoutSession session) {
    if (_getOrCreateSession().isCompleted) return;
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
    final week = _currentWeek;
    final now = DateTime.now();

    if (current.isTimerRunning) {
      final paused = current.copyWith(
        timerStartedAt: null,
        durationSeconds: current.elapsedSeconds(now),
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

    final other = HiveService.getRunningSession(excludingId: current.id);
    if (other != null) {
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Another workout is running'),
              content: Text(
                '${other.planName}, Week ${other.weekNumber} has an active timer. '
                'Pause or stop it before starting this workout.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      return;
    }

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
        final result = await WorkoutCompletionService.complete(
          draft,
          upsert: provider.upsertSession,
        );
        _weekSessions[_currentWeek] = result.session;
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
      weekNumber: _currentWeek,
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

  void _showWeekOptionsMenu(BuildContext context, int index, int week) {
    WorkoutDialogs.showWeekOptionsMenu(
      context,
      onRename: () => _renameWeek(index, week),
      onDelete: () => _deleteWeek(index),
    );
  }

  void _renameWeek(int index, int week) {
    WorkoutDialogs.showRenameWeekDialog(
      context,
      currentWeek: week,
      onRename: (newWeek) async {
        final otherWeeks = List<int>.from(_weeks)..removeAt(index);
        if (otherWeeks.contains(newWeek)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '> Week number already exists',
                style: GoogleFonts.jetBrainsMono(),
              ),
              backgroundColor: errorColor(context),
            ),
          );
          return;
        }
        setState(() {
          _weeks[index] = newWeek;
        });
        await HiveService.renameSessionWeek(
          widget.plan.name,
          week,
          newWeek,
          widget.plan.splitId,
        );
      },
    );
  }

  void _deleteWeek(int index) async {
    final week = _weeks[index];
    final saved =
        _weekSessions[week] ??
        HiveService.getSessionForPlanAndWeek(
          widget.plan.name,
          week,
          widget.plan.splitId,
        );
    if (saved != null && !saved.isCompleted) {
      if (index == _currentWeekIndex) {
        await _discardCurrentWorkout();
      } else if (await _confirmDiscard(saved) && saved.id != null && mounted) {
        await context.read<WorkoutSessionProvider>().deleteSession(saved.id!);
        _weekSessions.remove(week);
      }
      return;
    }
    if (_weeks.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '> Cannot delete the last week',
            style: GoogleFonts.jetBrainsMono(),
          ),
          backgroundColor: errorColor(context),
        ),
      );
      return;
    }

    final confirmed = await WorkoutDialogs.showDeleteWeekDialog(
      context,
      week: week,
    );

    if (confirmed) {
      await HiveService.deleteSessionForPlanAndWeek(
        widget.plan.name,
        week,
        widget.plan.splitId,
      );
      setState(() {
        _weeks.removeAt(index);
        if (_currentWeekIndex >= _weeks.length) {
          _currentWeekIndex = _weeks.length - 1;
        } else if (_currentWeekIndex > index) {
          _currentWeekIndex -= 1;
        }
      });
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
    final elapsed = formatDuration(session.elapsedSeconds());
    final timerStyle = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: textPrimaryColor(context),
    );
    final titleStyle = Theme.of(context).textTheme.headlineSmall!;
    final textScaler = MediaQuery.textScalerOf(context);
    final toolbarHeight = (textScaler.scale(titleStyle.fontSize!) *
                (titleStyle.height ?? 1) +
            textScaler.scale(timerStyle.fontSize!) * (timerStyle.height ?? 1) +
            AppSpacing.xs +
            AppSpacing.lg * 2)
        .clamp(80.0, double.infinity);

    return PopScope(
      canPop: session.isCompleted && !_isNavigating,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: AbsorbPointer(
        absorbing: _isNavigating || _timerAction != null,
        child: Scaffold(
          backgroundColor: backgroundColor(context),
          appBar: AppBar(
            backgroundColor: backgroundColor(context),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            toolbarHeight: toolbarHeight,
            titleSpacing: AppSpacing.sm,
            leading: IconButton(
              tooltip: 'Back',
              icon: Icon(
                LucideIcons.arrowLeft,
                color: textSecondaryColor(context),
              ),
              onPressed: _handleBack,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Week $_currentWeek',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      flex: 2,
                      child: Semantics(
                        label:
                            session.isCompleted
                                ? 'Recorded duration $elapsed'
                                : 'Elapsed time $elapsed',
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            elapsed,
                            key: const ValueKey('workout_elapsed_time'),
                            style: timerStyle,
                          ),
                        ),
                      ),
                    ),
                  ],
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
                        _isSaving || _timerAction != null ? null : _toggleTimer,
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
                          _isSaving || _timerAction != null
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
                      session.hasStarted && !_isSaving && _timerAction == null
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
                  child: _animatedPlanContent(CustomScrollView(
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
                              key: ValueKey((_currentWeek, index, exercise.name)),
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
                                        ? () =>
                                            _reorderExercises(index, index - 1)
                                        : null,
                                onMoveDown:
                                    index < session.exercises.length - 1
                                        ? () =>
                                            _reorderExercises(index, index + 1)
                                        : null,
                                accent: accent,
                                previousSets: previousExerciseSets(
                                  _sessionsWithDrafts(),
                                  exercise.name,
                                  splitId: widget.plan.splitId,
                                  planId: widget.plan.id,
                                  planName: widget.plan.name,
                                  beforeWeek: _currentWeek,
                                  includeDrafts: true,
                                ),
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
                    ],
                  )),
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

  /// The week switcher above the bottom edge — the plan switcher's twin.
  ///
  /// It used to be a row of filled pills, which said "toggle" where the strip
  /// above it said "tab". Same control, same language now: an underline in the
  /// accent. The week number is its own ordinal, so these tabs carry no index
  /// prefix.
  Widget _buildWeekNavBar(Color accent) {
    return Container(
      // The ground reaches into the safe-area inset; only the tabs stop short
      // of it, so there is no bare strip of background under the bar.
      color: backgroundColor(context),
      child: SafeArea(
        top: false,
        child: UnderlineTabStrip(
          rule: StripRule.top,
          height: 48,
          color: accent,
          selectedIndex: _currentWeekIndex,
          tabs: [
            for (var index = 0; index < _weeks.length; index++)
              UnderlineTabData(
                label: 'Week ${_weeks[index]}',
                // Save the departing week before loading the selected one.
                onTap:
                    index == _currentWeekIndex
                        ? null
                        : () => _onWeekChanged(index),
                onLongPress:
                    () => _showWeekOptionsMenu(context, index, _weeks[index]),
              ),
          ],
          trailing: Semantics(
            button: true,
            label: 'Add week',
            child: InkWell(
              onTap: _addNewWeek,
              borderRadius: AppRadius.chip,
              child: SizedBox(
                height: 48,
                child: Padding(
                  // Week labels sit slightly above the strip's centre to make
                  // room for their underline. Match that optical baseline
                  // while keeping the full 48px add-week tap target.
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Center(
                    child: Text(
                      '+ Week ${_weeks.last + 1}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
