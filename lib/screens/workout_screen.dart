import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/hive_service.dart';
import '../services/pr_tracking_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/fade_page_route.dart';
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

  @override
  void initState() {
    super.initState();
    _loadWeeks();
  }

  void _loadWeeks() {
    final existingWeeks = HiveService.getWeeksForPlan(widget.plan.name);
    if (existingWeeks.isEmpty) {
      _weeks = [1];
    } else {
      _weeks = existingWeeks;
      int maxWeek = _weeks.reduce((a, b) => a > b ? a : b);
      if (!_weeks.contains(maxWeek + 1)) {
        _weeks.add(maxWeek + 1);
      }
    }
    _currentWeekIndex = _weeks.length - 1;
    _loadSessionForCurrentWeek();
  }

  void _loadSessionForCurrentWeek() {
    final week = _weeks[_currentWeekIndex];
    final existingSession =
        HiveService.getSessionForPlanAndWeek(widget.plan.name, week);
    if (existingSession != null) {
      _weekSessions[week] = existingSession;
    }
  }

  gym.Set? _getLastSetForExerciseInPlan(String exerciseName) {
    final currentWeek = _weeks[_currentWeekIndex];
    if (currentWeek > 1) {
      final prevWeekSession = HiveService.getSessionForPlanAndWeek(
        widget.plan.name,
        currentWeek - 1,
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
    return HiveService.getLastSetForExercise(exerciseName);
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
    final hasSets = session.exercises.any((e) => e.sets.isNotEmpty);

    if (hasSets) {
      final prs = PRTrackingService.checkForNewPRs(session.exercises);

      // Stamp identity so repeated autosaves upsert ONE row per (plan, week).
      // upsertSession assigns a UUID on first save and reuses it thereafter.
      session = session.copyWith(
        planId: widget.plan.id,
        planName: widget.plan.name,
        weekNumber: _currentWeek,
      );
      _weekSessions[_currentWeek] = session; // keep the id-stamped instance
      await context.read<WorkoutSessionProvider>().upsertSession(session);

      if (prs.isNotEmpty && mounted) {
        _showPRDialog(prs);
      }
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

    final prevWeek = _currentWeek - 1;
    if (prevWeek >= 1) {
      final prevSession = HiveService.getSessionForPlanAndWeek(
        widget.plan.name,
        prevWeek,
      );
      if (prevSession != null &&
          prevSession.exercises.any((e) => e.sets.isNotEmpty)) {
        return WorkoutSession(
          date: DateTime.now(),
          planName: widget.plan.name,
          exercises: prevSession.exercises
              .map((prevExercise) => Exercise(
                    name: prevExercise.name,
                    sets: prevExercise.sets
                        .map((s) => gym.Set(
                              reps: s.reps,
                              weight: s.weight,
                              rpe: s.rpe,
                              note: s.note,
                            ))
                        .toList(),
                    note: prevExercise.note,
                  ))
              .toList(),
          weekNumber: _currentWeek,
        );
      }
    }

    return WorkoutSession(
      date: DateTime.now(),
      planName: widget.plan.name,
      exercises: widget.plan.exercises
          .map((template) => Exercise(
                name: template.name,
                sets: List.generate(
                  template.sets,
                  (_) => gym.Set(reps: 0, weight: 0),
                ),
                note: null,
              ))
          .toList(),
      weekNumber: _currentWeek,
    );
  }

  void _updateSession(WorkoutSession session) {
    _weekSessions[_currentWeek] = session;
    setState(() {});
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

  void _incrementReps(int exerciseIndex, int setIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];

    final updatedSets = List<gym.Set>.from(exercise.sets);
    updatedSets[setIndex] = gym.Set(
      reps: set.reps + 1,
      weight: set.weight,
      rpe: set.rpe,
      note: set.note,
    );

    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      sets: updatedSets,
      note: exercise.note,
    );

    _updateSession(session.copyWith(exercises: updatedExercises));
    _autoSave();
  }

  void _decrementReps(int exerciseIndex, int setIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];

    if (set.reps <= 0) return;

    final updatedSets = List<gym.Set>.from(exercise.sets);
    updatedSets[setIndex] = gym.Set(
      reps: set.reps - 1,
      weight: set.weight,
      rpe: set.rpe,
      note: set.note,
    );

    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      sets: updatedSets,
      note: exercise.note,
    );

    _updateSession(session.copyWith(exercises: updatedExercises));
    _autoSave();
  }

  void _incrementWeight(int exerciseIndex, int setIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];

    final updatedSets = List<gym.Set>.from(exercise.sets);
    updatedSets[setIndex] = gym.Set(
      reps: set.reps,
      weight: set.weight + 2.5,
      rpe: set.rpe,
      note: set.note,
    );

    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      sets: updatedSets,
      note: exercise.note,
    );

    _updateSession(session.copyWith(exercises: updatedExercises));
    _autoSave();
  }

  void _decrementWeight(int exerciseIndex, int setIndex) {
    final session = _getOrCreateSession();
    final exercise = session.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];

    if (set.weight <= 0) return;

    final updatedSets = List<gym.Set>.from(exercise.sets);
    updatedSets[setIndex] = gym.Set(
      reps: set.reps,
      weight: set.weight - 2.5,
      rpe: set.rpe,
      note: set.note,
    );

    final updatedExercises = List<Exercise>.from(session.exercises);
    updatedExercises[exerciseIndex] = Exercise(
      name: exercise.name,
      sets: updatedSets,
      note: exercise.note,
    );

    _updateSession(session.copyWith(exercises: updatedExercises));
    _autoSave();
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final session = _getOrCreateSession();
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
              content: Text('> Week number already exists',
                  style: GoogleFonts.jetBrainsMono()),
              backgroundColor: errorColor(context),
            ),
          );
          return;
        }
        setState(() {
          _weeks[index] = newWeek;
        });
        await HiveService.renameSessionWeek(widget.plan.name, week, newWeek);
      },
    );
  }

  void _deleteWeek(int index) async {
    final week = _weeks[index];
    if (_weeks.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> Cannot delete the last week',
              style: GoogleFonts.jetBrainsMono()),
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
      await HiveService.deleteSessionForPlanAndWeek(widget.plan.name, week);
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
    final settings = context.watch<SettingsProvider>();
    final accent = settings.accentColor;
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
    final planColor =
        activePlan.planColor != null ? Color(activePlan.planColor!) : accent;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        toolbarHeight: 60,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: accent),
          onPressed: () {
            _autoSave();
            Navigator.pop(context);
          },
        ),
        title: _PlanHeader(
          planName: activePlan.name,
          planIndex: widget.planIndex,
          planColor: planColor,
        ),
        bottom: _buildPlanTabBar(accent, plans, activePlan),
      ),
      body: Column(
        children: [
          Expanded(
            child: _GestureClaimingContainer(
              onSwipeLeft: _currentWeekIndex < _weeks.length - 1
                  ? () => _onWeekChanged(_currentWeekIndex + 1)
                  : null,
              onSwipeRight: _currentWeekIndex > 0
                  ? () => _onWeekChanged(_currentWeekIndex - 1)
                  : null,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  // State the gutter once, on the sliver, rather than as a
                  // margin per item: the rounded cards need clearance from the
                  // screen edges or their corners read as a clipping bug, and
                  // the + ADD EXERCISE tile inherits the same inset for free.
                  SliverPadding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    sliver: SliverReorderableList(
                      itemCount: session.exercises.length + 1,
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
                          return ReorderableDelayedDragStartListener(
                            key: const ValueKey('add_exercise_button'),
                            index: index,
                            child: InkWell(
                              onTap: _addEmptyExercise,
                              borderRadius: AppRadius.button,
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                decoration: BoxDecoration(
                                  border: Border.all(color: accent, width: 1),
                                  borderRadius: AppRadius.button,
                                ),
                                child: Center(
                                  child: Text(
                                    '[+ ADD EXERCISE]',
                                    style: GoogleFonts.jetBrainsMono(
                                        color: accent),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        final exercise = session.exercises[index];

                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(index),
                          index: index,
                          child: Container(
                            margin:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: surfaceColor(context),
                              border: Border.all(
                                  color: borderColor(context), width: 1),
                              borderRadius: AppRadius.card,
                            ),
                            child: ExerciseCard(
                              exercise: exercise,
                              exerciseIndex: index,
                              accent: accent,
                              onIncrementReps: _incrementReps,
                              onDecrementReps: _decrementReps,
                              onIncrementWeight: _incrementWeight,
                              onDecrementWeight: _decrementWeight,
                              onAddSet: (i) => _addSet(i),
                              onEditSet: (i, setIndex) =>
                                  _editSet(i, setIndex),
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
          _buildWeekNavBar(planColor, accent),
        ],
      ),
    );
  }

  /// The plan switcher under the app bar.
  ///
  /// Every tab used to carry a 2px bottom border, which made the "active"
  /// indicator indistinguishable from a baseline rule that stopped mid-screen,
  /// and the selected tab was a solid slab in the *global* accent while the
  /// title directly above it was drawn in the plan's own colour. Now the bar
  /// owns one continuous hairline, and the only mark is a 2px underline in the
  /// active plan's colour, sized to its label.
  PreferredSizeWidget? _buildPlanTabBar(
    Color accent,
    List<WorkoutPlan> plans,
    WorkoutPlan activePlan,
  ) {
    if (plans.isEmpty) {
      return null;
    }

    const double barHeight = 44;
    final selectedIndex = plans.indexWhere((p) => p.id == activePlan.id);

    return PreferredSize(
      preferredSize: const Size.fromHeight(barHeight),
      child: UnderlineTabStrip(
        rule: StripRule.bottom,
        height: barHeight,
        selectedIndex: selectedIndex >= 0 ? selectedIndex : widget.planIndex,
        tabs: [
          for (var index = 0; index < plans.length; index++)
            UnderlineTabData(
              // The index is the swipe order between plans, and it echoes the
              // [01] on the home cards.
              index: (index + 1).toString().padLeft(2, '0'),
              label: plans[index].name.toUpperCase(),
              // Each tab resolves its own colour, so a red plan no longer gets
              // a purple tab while its title above is red.
              color: plans[index].planColor != null
                  ? Color(plans[index].planColor!)
                  : accent,
              onTap: plans[index].id == activePlan.id
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
  /// It used to be a row of filled pills in the global accent, which said
  /// "toggle" where the strip above it said "tab", and coloured the current week
  /// with the app's accent rather than the plan you are actually inside. Same
  /// control, same language now: an underline in the plan's colour. The week
  /// number is its own ordinal, so these tabs carry no index prefix.
  Widget _buildWeekNavBar(Color planColor, Color accent) {
    return Container(
      // The ground reaches into the safe-area inset; only the tabs stop short
      // of it, so there is no bare strip of background under the bar.
      color: surfaceColor(context),
      child: SafeArea(
        top: false,
        child: UnderlineTabStrip(
          rule: StripRule.top,
          selectedIndex: _currentWeekIndex,
          tabs: [
            for (var index = 0; index < _weeks.length; index++)
              UnderlineTabData(
                label: 'WEEK ${_weeks[index]}',
                color: planColor,
                // Routed through _onWeekChanged, same as a swipe: tapping used
                // to move the index without saving the week you were leaving or
                // loading the one you arrived at.
                onTap: index == _currentWeekIndex
                    ? null
                    : () => _onWeekChanged(index),
                onLongPress: () =>
                    _showWeekOptionsMenu(context, index, _weeks[index]),
              ),
          ],
          trailing: InkWell(
            onTap: _addNewWeek,
            borderRadius: AppRadius.chip,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: accent),
                borderRadius: AppRadius.chip,
              ),
              child: Text(
                '[+ WEEK ${_weeks.length + 1}]',
                style:
                    GoogleFonts.jetBrainsMono(fontSize: 10, color: accent),
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
      gestures: {
        _ExposingHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                _ExposingHorizontalDragGestureRecognizer>(
          () => _ExposingHorizontalDragGestureRecognizer(),
          (_ExposingHorizontalDragGestureRecognizer instance) {
            instance
              ..dragStartBehavior = DragStartBehavior.down
              ..supportedDevices = {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse
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
          },
        ),
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
  final String planName;
  final int planIndex;
  final Color planColor;

  const _PlanHeader({
    required this.planName,
    required this.planIndex,
    required this.planColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final provider = context.read<WorkoutPlanProvider>();
        final plans = provider.plans;
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
      child: Text(
        planName.toUpperCase(),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: planColor,
        ),
      ),
    );
  }
}
