import 'dart:async';

import 'package:flutter/gestures.dart';
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
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/fade_page_route.dart';
import '../utils/format.dart';
import '../utils/set_history.dart';
import '../widgets/underline_tab_strip.dart';
import '../widgets/workout/exercise_card.dart';
import '../widgets/workout/workout_dialogs.dart';

class WorkoutScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final int planIndex;

  const WorkoutScreen({super.key, required this.plan, required this.planIndex});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  List<int> _weeks = [1];
  int _currentWeekIndex = 0;
  final Map<int, WorkoutSession> _weekSessions = {};
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadWeeks();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
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
    _loadSessionForCurrentWeek();
  }

  void _loadSessionForCurrentWeek() {
    final week = _weeks[_currentWeekIndex];
    final existingSession = HiveService.getSessionForPlanAndWeek(
      widget.plan.name,
      week,
      widget.plan.splitId,
    );
    if (existingSession != null) {
      _weekSessions[week] = existingSession;
      _syncTicker(existingSession);
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
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
    await _autoSave();
    setState(() {
      _currentWeekIndex = newIndex;
    });
    _loadSessionForCurrentWeek();
  }

  Future<void> _addNewWeek() async {
    await _autoSave();
    final lastWeek = _weeks.last;
    setState(() {
      _weeks.add(lastWeek + 1);
      _currentWeekIndex = _weeks.length - 1;
    });
  }

  Future<void> _autoSave() async {
    var session = _getOrCreateSession();
    if (session.isCompleted) return;
    final hasSets = session.exercises.any((e) => e.sets.isNotEmpty);

    if (hasSets) {
      // Stamp identity so repeated autosaves upsert ONE row per (plan, week).
      // upsertSession assigns a UUID on first save and reuses it thereafter.
      session = session.copyWith(
        planId: widget.plan.id,
        planName: widget.plan.name,
        weekNumber: _currentWeek,
        splitId: widget.plan.splitId,
      );
      _weekSessions[_currentWeek] = session; // keep the id-stamped instance
      await context.read<WorkoutSessionProvider>().upsertSession(session);
    }
  }

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

  void _updateSession(WorkoutSession session) {
    if (_getOrCreateSession().isCompleted) return;
    _weekSessions[_currentWeek] = session;
    setState(() {});
  }

  Future<void> _toggleTimer() async {
    final current = _getOrCreateSession();
    if (current.isCompleted) return;
    final now = DateTime.now();

    if (current.isTimerRunning) {
      final paused = current.copyWith(
        timerStartedAt: null,
        durationSeconds: current.elapsedSeconds(now),
      );
      _weekSessions[_currentWeek] = paused;
      _syncTicker(paused);
      await context.read<WorkoutSessionProvider>().upsertSession(paused);
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
    _weekSessions[_currentWeek] = started;
    _syncTicker(started);
    await context.read<WorkoutSessionProvider>().upsertSession(started);
    if (mounted) setState(() {});
  }

  Future<void> _stopWorkout() async {
    final draft = _getOrCreateSession();
    if (draft.isCompleted || !draft.hasStarted) return;
    final duration = formatDuration(draft.elapsedSeconds());
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Log workout?'),
            content: Text('Record this workout with a duration of $duration?'),
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
    if (confirmed != true || !mounted) return;

    try {
      final provider = context.read<WorkoutSessionProvider>();
      final result = await WorkoutCompletionService.complete(
        draft,
        upsert: provider.upsertSession,
      );
      _weekSessions[_currentWeek] = result.session;
      _syncTicker(result.session);
      if (!mounted) return;
      setState(() {});
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
    final draft = _getOrCreateSession();
    if (draft.isCompleted || !await _confirmDiscard(draft) || !mounted) return;
    _ticker?.cancel();
    _ticker = null;
    if (draft.id != null) {
      await context.read<WorkoutSessionProvider>().deleteSession(draft.id!);
    }
    final clean = WorkoutSessionInitializer.initialize(
      plan: widget.plan,
      weekNumber: _currentWeek,
    );
    setState(() => _weekSessions[_currentWeek] = clean);
  }

  void _addEmptyExercise() {
    WorkoutDialogs.showAddExerciseDialog(
      context,
      onAdd: (name) {
        final session = _getOrCreateSession();
        final updatedExercises = List<Exercise>.from(session.exercises);
        updatedExercises.add(Exercise(name: name, sets: [], note: null));
        _updateSession(session.copyWith(exercises: updatedExercises));
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
    final lastSet = _getLastSetForExerciseInPlan(exercise.name);

    WorkoutDialogs.showAddSetDialog(
      context,
      lastSet: lastSet,
      onAdd: (newSet) {
        final updatedExercises = List<Exercise>.from(session.exercises);
        updatedExercises[exerciseIndex] = Exercise(
          name: exercise.name,
          sets: [...exercise.sets, newSet],
          note: exercise.note,
        );
        _updateSession(session.copyWith(exercises: updatedExercises));
        _autoSave();
      },
    );
  }

  void _editSet(int exerciseIndex, int setIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];

    WorkoutDialogs.showEditSetDialog(
      context,
      set: set,
      onSave: (updatedSet) {
        final updatedSets = List<gym.Set>.from(exercise.sets);
        updatedSets[setIndex] = updatedSet;
        final updatedExercises = List<Exercise>.from(session.exercises);
        updatedExercises[exerciseIndex] = Exercise(
          name: exercise.name,
          sets: updatedSets,
          note: exercise.note,
        );
        _updateSession(session.copyWith(exercises: updatedExercises));
        _autoSave();
      },
      onDelete: () {
        final updatedSets = List<gym.Set>.from(exercise.sets)
          ..removeAt(setIndex);
        final updatedExercises = List<Exercise>.from(session.exercises);
        updatedExercises[exerciseIndex] = Exercise(
          name: exercise.name,
          sets: updatedSets,
          note: exercise.note,
        );
        _updateSession(session.copyWith(exercises: updatedExercises));
        _autoSave();
      },
    );
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

  void _reorderExercises(int oldIndex, int newIndex) {
    final session = _getOrCreateSession();
    final exerciseCount = session.exercises.length;
    if (oldIndex < 0 || oldIndex >= exerciseCount) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= exerciseCount) return;
    final exercises = List<Exercise>.from(session.exercises);
    final exercise = exercises.removeAt(oldIndex);
    exercises.insert(newIndex, exercise);
    _updateSession(session.copyWith(exercises: exercises));
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

    if (confirmed) {
      final updatedExercises = List<Exercise>.from(session.exercises);
      updatedExercises.removeAt(exerciseIndex);
      _updateSession(session.copyWith(exercises: updatedExercises));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _getOrCreateSession();
    final accent = accentColor(context);
    final surface = surfaceColor(context);

    final planProvider = context.watch<WorkoutPlanProvider>();
    final plans = planProvider.plans;
    final activePlan = plans.firstWhere(
      (plan) => plan.id == widget.plan.id,
      orElse: () {
        if (widget.planIndex >= 0 && widget.planIndex < plans.length) {
          return plans[widget.planIndex];
        }
        return widget.plan;
      },
    );
    final planColor = planColorOf(activePlan.planColor, context);
    final elapsed = formatDuration(session.elapsedSeconds());
    final timerStyle = GoogleFonts.jetBrainsMono(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: textPrimaryColor(context),
    );
    final timerPainter = TextPainter(
      text: TextSpan(text: elapsed, style: timerStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    // The title starts after the standard leading slot and our title spacing.
    // Cap it at the timer's left edge so long names ellipsize before the two
    // independently positioned AppBar elements can touch.
    final planHeaderMaxWidth =
        MediaQuery.sizeOf(context).width / 2 -
        timerPainter.width / 2 -
        AppSpacing.md -
        kToolbarHeight -
        AppSpacing.sm;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        flexibleSpace: Stack(
          children: [
            Positioned.fill(
              child: headerFlexibleSpace(context, bottomInset: 48),
            ),
            Positioned.fill(
              bottom: 48,
              child: SafeArea(
                bottom: false,
                child: IgnorePointer(
                  child: Center(
                    child: Semantics(
                      liveRegion: !session.isCompleted,
                      label:
                          session.isCompleted
                              ? 'Recorded duration $elapsed'
                              : 'Elapsed time $elapsed',
                      child: Text(
                        elapsed,
                        key: const ValueKey('workout_elapsed_time'),
                        style: timerStyle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        toolbarHeight: 60,
        titleSpacing: AppSpacing.sm,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: accent),
          onPressed: () {
            _autoSave();
            Navigator.pop(context);
          },
        ),
        title: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: planHeaderMaxWidth.clamp(0, double.infinity),
          ),
          child: _PlanHeader(
            plan: activePlan,
            fallbackIndex: plans.indexWhere((plan) => plan.id == activePlan.id),
            color: planColor,
          ),
        ),
        actions: [
          if (!session.isCompleted) ...[
            Semantics(
              button: true,
              label: session.isTimerRunning ? 'Pause workout' : 'Start workout',
              child: IconButton(
                tooltip: session.isTimerRunning ? 'Pause' : 'Play',
                onPressed: _toggleTimer,
                icon: Icon(
                  session.isTimerRunning ? LucideIcons.pause : LucideIcons.play,
                  color: accent,
                ),
              ),
            ),
            Semantics(
              button: true,
              enabled: session.hasStarted,
              label: 'Stop and log workout',
              child: IconButton(
                tooltip: 'Stop',
                onPressed: session.hasStarted ? _stopWorkout : null,
                icon: Icon(LucideIcons.square, color: accent),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Workout actions',
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
        bottom: _buildPlanTabBar(accent, plans, activePlan),
      ),
      body: Column(
        children: [
          Expanded(
            child: _GestureClaimingContainer(
              onSwipeLeft:
                  _currentWeekIndex < _weeks.length - 1
                      ? () => _onWeekChanged(_currentWeekIndex + 1)
                      : null,
              onSwipeRight:
                  _currentWeekIndex > 0
                      ? () => _onWeekChanged(_currentWeekIndex - 1)
                      : null,
              child: IgnorePointer(
                ignoring: session.isCompleted,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    // State the gutter once, on the sliver, rather than as a
                    // margin per item: the rounded cards need clearance from the
                    // screen edges or their corners read as a clipping bug, and
                    // the + ADD EXERCISE tile inherits the same inset for free.
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      sliver: SliverReorderableList(
                        itemCount:
                            session.exercises.length +
                            (session.isCompleted ? 0 : 1),
                        onReorder: _reorderExercises,
                        proxyDecorator: (child, index, animation) {
                          return Material(
                            color: surfaceColor(context),
                            borderRadius: AppRadius.card,
                            child: child,
                          );
                        },
                        itemBuilder: (context, index) {
                          if (index == session.exercises.length) {
                            return InkWell(
                              key: const ValueKey('add_exercise_button'),
                              onTap: _addEmptyExercise,
                              borderRadius: AppRadius.button,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                decoration: BoxDecoration(
                                  color: surfaceColor(context),
                                  border: Border.all(color: accent, width: 1),
                                  borderRadius: AppRadius.button,
                                ),
                                child: Center(
                                  child: Text(
                                    'Add exercise',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(color: accent),
                                  ),
                                ),
                              ),
                            );
                          }

                          final exercise = session.exercises[index];

                          return ReorderableDelayedDragStartListener(
                            key: ObjectKey(exercise),
                            index: index,
                            child: Container(
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: surfaceColor(context),
                                border: Border.all(
                                  color: borderColor(context),
                                  width: 1,
                                ),
                                borderRadius: AppRadius.card,
                              ),
                              child: ExerciseCard(
                                exercise: exercise,
                                exerciseIndex: index,
                                accent: accent,
                                previousSets: previousExerciseSets(
                                  HiveService.getCompletedSessions(),
                                  exercise.name,
                                  splitId: widget.plan.splitId,
                                  planId: widget.plan.id,
                                  planName: widget.plan.name,
                                  beforeWeek: _currentWeek,
                                ),
                                onSetChanged: _changeSetValues,
                                onEntryFinished: () {
                                  if (mounted) _autoSave();
                                },
                                onAddSet: (i) => _addSet(i),
                                onEditSet:
                                    (i, setIndex) => _editSet(i, setIndex),
                                onAddNote: _addExerciseNote,
                                onRename: _showExerciseRenameDialog,
                                onDeleteExercise: _deleteExercise,
                              ),
                            ),
                          );
                        },
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
    WorkoutPlan activePlan,
  ) {
    if (plans.isEmpty) {
      return null;
    }

    const double barHeight = 48;
    final selectedIndex = plans.indexWhere((p) => p.id == activePlan.id);

    return PreferredSize(
      preferredSize: const Size.fromHeight(barHeight),
      child: UnderlineTabStrip(
        rule: StripRule.bottom,
        height: barHeight,
        color: accent,
        selectedIndex: selectedIndex >= 0 ? selectedIndex : widget.planIndex,
        tabs: [
          for (var index = 0; index < plans.length; index++)
            UnderlineTabData(
              // The index is the swipe order between plans, and it echoes the
              // [01] on the home cards.
              index: (index + 1).toString().padLeft(2, '0'),
              label: plans[index].name.toUpperCase(),
              onTap:
                  plans[index].id == activePlan.id
                      ? null
                      : () {
                        Navigator.pushReplacement(
                          context,
                          FadePageRoute(
                            page: WorkoutScreen(
                              plan: plans[index],
                              planIndex: index,
                            ),
                          ),
                        );
                      },
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
      color: surfaceColor(context),
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
                label: 'WEEK ${_weeks[index]}',
                // Routed through _onWeekChanged, same as a swipe: tapping used
                // to move the index without saving the week you were leaving or
                // loading the one you arrived at.
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
                      '+ WEEK ${_weeks.length + 1}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        letterSpacing: 0.04,
                        color: accent,
                      ),
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

class _GestureClaimingContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;

  const _GestureClaimingContainer({
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  @override
  State<_GestureClaimingContainer> createState() =>
      _GestureClaimingContainerState();
}

class _GestureClaimingContainerState extends State<_GestureClaimingContainer> {
  double _dragAccumulator = 0;
  double _totalDx = 0;
  double _totalDy = 0;
  bool _hasClaimedGesture = false;
  bool _isHorizontalGesture = false;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _ExposingHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _ExposingHorizontalDragGestureRecognizer
            >(() => _ExposingHorizontalDragGestureRecognizer(), (
              _ExposingHorizontalDragGestureRecognizer instance,
            ) {
              instance
                ..dragStartBehavior = DragStartBehavior.down
                ..supportedDevices = {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                };
              instance.onStart = (details) {
                _dragAccumulator = 0;
                _totalDx = 0;
                _totalDy = 0;
                _hasClaimedGesture = false;
                _isHorizontalGesture = false;
              };
              instance.onUpdate = (details) {
                _dragAccumulator += details.delta.dx;
                _totalDx += details.delta.dx;
                _totalDy += details.delta.dy;

                final totalMovement = _totalDx.abs() + _totalDy.abs();
                if (!_hasClaimedGesture && totalMovement > 10) {
                  if (_totalDy.abs() == 0) {
                    instance.resolve(GestureDisposition.accepted);
                    _hasClaimedGesture = true;
                    _isHorizontalGesture = true;
                  } else if (_totalDx.abs() / _totalDy.abs() > 1.5) {
                    instance.resolve(GestureDisposition.accepted);
                    _hasClaimedGesture = true;
                    _isHorizontalGesture = true;
                  } else if (_totalDy.abs() / _totalDx.abs() > 1.0) {
                    instance.resolve(GestureDisposition.rejected);
                    _hasClaimedGesture = true;
                    _isHorizontalGesture = false;
                  }
                }
              };
              instance.onEnd = (details) {
                if (_isHorizontalGesture && _dragAccumulator.abs() > 40) {
                  if (_dragAccumulator < 0 && widget.onSwipeLeft != null) {
                    widget.onSwipeLeft!();
                  } else if (_dragAccumulator > 0 &&
                      widget.onSwipeRight != null) {
                    widget.onSwipeRight!();
                  }
                }
                _dragAccumulator = 0;
              };
            }),
      },
      child: widget.child,
    );
  }
}

class _ExposingHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  @override
  void resolve(GestureDisposition disposition) {
    super.resolve(disposition);
  }
}

class _PlanHeader extends StatelessWidget {
  final WorkoutPlan plan;
  final int fallbackIndex;

  /// The active plan's resolved identity-marker colour.
  final Color color;

  const _PlanHeader({
    required this.plan,
    required this.fallbackIndex,
    required this.color,
  });

  int _currentPlanIndex(List<WorkoutPlan> plans) {
    final planKey = plan.key;
    if (planKey != null) {
      final keyIndex = plans.indexWhere(
        (candidate) => candidate.key == planKey,
      );
      if (keyIndex >= 0) return keyIndex;
    }

    final id = plan.id;
    if (id != null) {
      final idIndex = plans.indexWhere((candidate) => candidate.id == id);
      if (idIndex >= 0) return idIndex;
    }

    final identityIndex = plans.indexWhere(
      (candidate) => identical(candidate, plan),
    );
    if (identityIndex >= 0) return identityIndex;

    return fallbackIndex.clamp(0, plans.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final provider = context.read<WorkoutPlanProvider>();
        final plans = provider.plans;
        if (plans.isEmpty) return;
        final planIndex = _currentPlanIndex(plans);
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity!.abs() > 250) {
            if (details.primaryVelocity! < 0) {
              if (planIndex < plans.length - 1) {
                Navigator.pushReplacement(
                  context,
                  FadePageRoute(
                    page: WorkoutScreen(
                      plan: plans[planIndex + 1],
                      planIndex: planIndex + 1,
                    ),
                  ),
                );
              }
            } else {
              if (planIndex > 0) {
                Navigator.pushReplacement(
                  context,
                  FadePageRoute(
                    page: WorkoutScreen(
                      plan: plans[planIndex - 1],
                      planIndex: planIndex - 1,
                    ),
                  ),
                );
              }
            }
          }
        }
      },
      child: Row(
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
              plan.name.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
