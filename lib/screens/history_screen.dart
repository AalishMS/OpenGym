import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/workout_session_provider.dart';
import '../models/workout_session.dart';
import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../services/pr_tracking_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../utils/set_history.dart';
import '../widgets/workout/set_entry_table.dart';
import '../widgets/workout/workout_dialogs.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: Text(
          'WORKOUT HISTORY',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textPrimaryColor(context)),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<WorkoutSessionProvider>(
        builder: (context, provider, child) {
          if (provider.sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '> NO SESSIONS FOUND',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      color: textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete a workout to see it here',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: provider.sessions.length,
            itemBuilder: (context, index) {
              final session = provider.sessions[index];
              return _SessionCard(
                key: ValueKey(
                  session.id ?? session.key ?? 'session-index-$index',
                ),
                session: session,
                index: index,
                onDelete: () {
                  showDialog(
                    context: context,
                    builder:
                        (ctx) => Dialog(
                          backgroundColor: surfaceColor(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.card,
                            side: BorderSide(
                              color: borderColor(context),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '> DELETE WORKOUT?',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: errorColor(context),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'This will permanently delete this workout session.',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 12,
                                    color: textSecondaryColor(context),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text(
                                        '[CANCEL]',
                                        style: GoogleFonts.jetBrainsMono(
                                          color: textSecondaryColor(context),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () {
                                        provider.deleteSession(session.id!);
                                        Navigator.pop(ctx);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: errorColor(context),
                                        foregroundColor: onColor(
                                          errorColor(context),
                                        ),
                                      ),
                                      child: Text(
                                        '[DELETE]',
                                        style: GoogleFonts.jetBrainsMono(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                  );
                },
                onEdit: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditSessionScreen(session: session),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatefulWidget {
  final WorkoutSession session;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _SessionCard({
    super.key,
    required this.session,
    required this.index,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final prs = PRTrackingService.checkForNewPRs(
      session.exercises,
      session.splitId,
    );
    final hasPR = prs.isNotEmpty;
    final accent = accentColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final error = errorColor(context);

    int totalSets = 0;
    int totalVolume = 0;
    for (var exercise in session.exercises) {
      totalSets += exercise.sets.length;
      for (var set in exercise.sets) {
        totalVolume += (set.weight * set.reps).round();
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: border, width: 1),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            // Top-only: the header sits above the expandable body, so its
            // splash follows the card's top corners and stops square below.
            borderRadius: AppRadius.cardTop,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: accent),
                          borderRadius: AppRadius.chip,
                        ),
                        child: Text(
                          '${session.date.day}/${session.date.month}/${session.date.year}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: accent,
                          ),
                        ),
                      ),
                      if (hasPR) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            // A PR is the log's one celebratory event — the
                            // "good" end of the semantic ramp, solved per mode,
                            // not a hand-picked amber that only worked on dark.
                            color: successColor(context),
                            borderRadius: AppRadius.badge,
                          ),
                          child: Text(
                            '[PR]',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: onColor(successColor(context)),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'Session actions',
                        onSelected: (value) {
                          if (value == 'edit') widget.onEdit();
                          if (value == 'delete') widget.onDelete();
                        },
                        itemBuilder:
                            (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                height: 48,
                                child: Text(
                                  '[EDIT]',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: accent,
                                    letterSpacing: 0.06,
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                height: 48,
                                child: Text(
                                  '[DELETE]',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: error,
                                    letterSpacing: 0.06,
                                  ),
                                ),
                              ),
                            ],
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _isExpanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        color: textSecondaryColor(context),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.planName.toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'WEEK ${session.weekNumber}  •  ${session.exercises.length} EXERCISES  •  $totalSets SETS  •  ${totalVolume}KG',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            _buildExpandedContent(session, accent, border, textSecondary),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(
    WorkoutSession session,
    Color accent,
    Color border,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...session.exercises.map(
            (exercise) => _ExerciseSection(exercise: exercise, accent: accent),
          ),
        ],
      ),
    );
  }
}

class _ExerciseSection extends StatelessWidget {
  final Exercise exercise;
  final Color accent;

  const _ExerciseSection({required this.exercise, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (exercise.note != null)
                Text(
                  '[NOTE]',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: accent),
                ),
            ],
          ),
          if (exercise.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                exercise.note!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: textSecondaryColor(context),
                ),
              ),
            ),
          const SizedBox(height: 8),
          ...exercise.sets.asMap().entries.map((entry) {
            final setIndex = entry.key;
            final set = entry.value;
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Row(
                children: [
                  Text(
                    'SET ${setIndex + 1}:',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${set.weight}KG x ${set.reps}REPS',
                    style: GoogleFonts.jetBrainsMono(fontSize: 10),
                  ),
                  if (set.rpe != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor(context)),
                        borderRadius: AppRadius.chip,
                      ),
                      child: Text(
                        'RPE ${set.rpe}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 8),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class EditSessionScreen extends StatefulWidget {
  final WorkoutSession session;

  const EditSessionScreen({super.key, required this.session});

  @override
  State<EditSessionScreen> createState() => _EditSessionScreenState();
}

class _EditSessionScreenState extends State<EditSessionScreen> {
  late WorkoutSession _session;
  late TextEditingController _planNameController;

  @override
  void initState() {
    super.initState();
    _session = widget.session.copyWith();
    _planNameController = TextEditingController(text: _session.planName);
  }

  @override
  void dispose() {
    _planNameController.dispose();
    super.dispose();
  }

  void _removeExercise(int index) {
    setState(() {
      final exercises = List<Exercise>.from(_session.exercises);
      exercises.removeAt(index);
      _session = _session.copyWith(exercises: exercises);
    });
  }

  void _save() {
    _session = _session.copyWith(planName: _planNameController.text);
    context.read<WorkoutSessionProvider>().updateSession(_session);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '> Workout updated!',
          style: GoogleFonts.jetBrainsMono(color: onAccentColor(context)),
        ),
        backgroundColor: accentFillColor(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        flexibleSpace: headerFlexibleSpace(context),
        title: Text(
          '> EDIT WORKOUT',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: accent,
          ),
        ),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: accent),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          InkWell(
            onTap: _save,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text(
                '[SAVE]',
                style: GoogleFonts.jetBrainsMono(color: accent),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _planNameController,
            decoration: const InputDecoration(
              labelText: 'Plan Name',
              border: OutlineInputBorder(borderRadius: AppRadius.field),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'EXERCISES',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          ..._session.exercises.asMap().entries.map((entry) {
            final index = entry.key;
            final exercise = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: surfaceColor(context),
                border: Border.all(color: borderColor(context), width: 1),
                borderRadius: AppRadius.card,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: accent),
                            borderRadius: AppRadius.badge,
                          ),
                          child: Text(
                            '[${index + 1}]',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            exercise.name.toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _removeExercise(index),
                          splashColor: errorColor(
                            context,
                          ).withValues(alpha: 0.2),
                          highlightColor: errorColor(
                            context,
                          ).withValues(alpha: 0.1),
                          child: Text(
                            '[DEL]',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: errorColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (exercise.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          exercise.note!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: textSecondaryColor(context),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SetEntryTable(
                      exerciseName: exercise.name,
                      sets: _entriesFor(exercise),
                      onChanged: (setIndex, weight, reps) {
                        final current = _session.exercises[index];
                        final sets = List<gym.Set>.of(current.sets);
                        final old = sets[setIndex];
                        sets[setIndex] = gym.Set(
                          weight: weight,
                          reps: reps,
                          rpe: old.rpe,
                          note: old.note,
                        );
                        _replaceSets(index, sets);
                      },
                      onDetails:
                          (setIndex) => _showEditSetDialog(
                            index,
                            setIndex,
                            exercise.sets[setIndex],
                          ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _showAddSetDialog(index, exercise),
                      splashColor: accent.withValues(alpha: 0.2),
                      highlightColor: accent.withValues(alpha: 0.1),
                      child: Text(
                        '[+ ADD SET]',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  List<SetEntry> _entriesFor(Exercise exercise) {
    final previous = previousExerciseSets(
      context.read<WorkoutSessionProvider>().sessions.where(
        (session) => session.date.isBefore(_session.date),
      ),
      exercise.name,
      splitId: _session.splitId,
      planId: _session.planId,
      planName: _session.planName,
    );
    return [
      for (var i = 0; i < exercise.sets.length; i++)
        SetEntry(
          weight: exercise.sets[i].weight,
          reps: exercise.sets[i].reps,
          previous:
              i < previous.length && previous[i].reps > 0
                  ? '${entryWeight(previous[i].weight)} × ${previous[i].reps}'
                  : null,
          annotation: exercise.sets[i].note,
          rpe: exercise.sets[i].rpe,
        ),
    ];
  }

  void _replaceSets(int index, List<gym.Set> sets) {
    final exercises = List<Exercise>.of(_session.exercises);
    final old = exercises[index];
    exercises[index] = Exercise(name: old.name, sets: sets, note: old.note);
    setState(() => _session = _session.copyWith(exercises: exercises));
  }

  void _showAddSetDialog(int exerciseIndex, Exercise exercise) {
    WorkoutDialogs.showAddSetDialog(
      context,
      onAdd: (set) {
        _replaceSets(exerciseIndex, [
          ..._session.exercises[exerciseIndex].sets,
          set,
        ]);
      },
    );
  }

  void _showEditSetDialog(int exerciseIndex, int setIndex, gym.Set set) {
    WorkoutDialogs.showEditSetDialog(
      context,
      set: set,
      onSave: (updated) {
        final sets = List<gym.Set>.of(_session.exercises[exerciseIndex].sets);
        sets[setIndex] = updated;
        _replaceSets(exerciseIndex, sets);
      },
      onDelete: () {
        final sets = List<gym.Set>.of(_session.exercises[exerciseIndex].sets)
          ..removeAt(setIndex);
        _replaceSets(exerciseIndex, sets);
      },
    );
  }
}
