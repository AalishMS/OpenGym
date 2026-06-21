import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/settings_provider.dart';
import '../models/workout_session.dart';
import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../services/pr_tracking_service.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<SettingsProvider>().accentColor;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: Text(
          '> WORKOUT HISTORY',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 16, fontWeight: FontWeight.bold, color: accent),
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
                session: session,
                index: index,
                onDelete: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => Dialog(
                      backgroundColor: surfaceColor(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                        side: BorderSide(color: borderColor(context), width: 1),
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
                                  color: textSecondaryColor(context)),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text('[CANCEL]',
                                      style: GoogleFonts.jetBrainsMono(
                                          color: textSecondaryColor(context))),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    provider.deleteSession(index);
                                    Navigator.pop(ctx);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: errorColor(context),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text('[DELETE]',
                                      style: GoogleFonts.jetBrainsMono()),
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
                      builder: (_) => EditSessionScreen(
                        session: session,
                        sessionIndex: index,
                      ),
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
    final prs = PRTrackingService.checkForNewPRs(session.exercises);
    final hasPR = prs.isNotEmpty;
    final accent = context.watch<SettingsProvider>().accentColor;
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
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: accent),
                        ),
                        child: Text(
                          '${session.date.day}/${session.date.month}/${session.date.year}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: accent),
                        ),
                      ),
                      if (hasPR) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                          ),
                          child: Text(
                            '[PR]',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10, color: Colors.black),
                          ),
                        ),
                      ],
                      const Spacer(),
                      InkWell(
                        onTap: widget.onEdit,
                        splashColor: accent.withValues(alpha: 0.2),
                        highlightColor: accent.withValues(alpha: 0.1),
                        child: Text('[EDIT]',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10, color: accent)),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: widget.onDelete,
                        splashColor: errorColor(context).withValues(alpha: 0.2),
                        highlightColor:
                            errorColor(context).withValues(alpha: 0.1),
                        child: Text('[DEL]',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10, color: errorColor(context))),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: textSecondaryColor(context),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.planName.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'WEEK ${session.weekNumber}  •  ${session.exercises.length} EXERCISES  •  $totalSets SETS  •  ${totalVolume}KG',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10, color: textSecondaryColor(context)),
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
      WorkoutSession session, Color accent, Color border, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...session.exercises.map((exercise) =>
              _ExerciseSection(exercise: exercise, accent: accent)),
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
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              if (exercise.note != null)
                Text('[NOTE]',
                    style:
                        GoogleFonts.jetBrainsMono(fontSize: 10, color: accent)),
            ],
          ),
          if (exercise.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                exercise.note!,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: textSecondaryColor(context)),
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
                        fontSize: 10, color: textSecondaryColor(context)),
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
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: borderColor(context)),
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
  final int sessionIndex;

  const EditSessionScreen({
    super.key,
    required this.session,
    required this.sessionIndex,
  });

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
    context
        .read<WorkoutSessionProvider>()
        .updateSession(widget.sessionIndex, _session);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('> Workout updated!', style: GoogleFonts.jetBrainsMono()),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<SettingsProvider>().accentColor;
    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: Text(
          '> EDIT WORKOUT',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 16, fontWeight: FontWeight.bold, color: accent),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: accent),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          InkWell(
            onTap: _save,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text('[ SAVE ]',
                  style: GoogleFonts.jetBrainsMono(color: accent)),
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
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'EXERCISES',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 12, fontWeight: FontWeight.bold, color: accent),
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
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: accent),
                          ),
                          child: Text(
                            '[${index + 1}]',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10, color: accent),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            exercise.name.toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        InkWell(
                          onTap: () => _removeExercise(index),
                          splashColor:
                              errorColor(context).withValues(alpha: 0.2),
                          highlightColor:
                              errorColor(context).withValues(alpha: 0.1),
                          child: Text('[DEL]',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10, color: errorColor(context))),
                        ),
                      ],
                    ),
                    if (exercise.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          exercise.note!,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: textSecondaryColor(context)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    ...exercise.sets.asMap().entries.map((setEntry) {
                      final setIndex = setEntry.key;
                      final set = setEntry.value;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              'SET ${setIndex + 1}:',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: textSecondaryColor(context)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${set.weight}KG x ${set.reps}REPS',
                              style: GoogleFonts.jetBrainsMono(fontSize: 10),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () =>
                                  _showEditSetDialog(index, setIndex, set),
                              splashColor: accent.withValues(alpha: 0.2),
                              highlightColor: accent.withValues(alpha: 0.1),
                              child: Text('[EDIT]',
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10, color: accent)),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _showAddSetDialog(index, exercise),
                      splashColor: accent.withValues(alpha: 0.2),
                      highlightColor: accent.withValues(alpha: 0.1),
                      child: Text('[ + ADD SET ]',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: accent)),
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

  void _showAddSetDialog(int exerciseIndex, Exercise exercise) {
    final accent = context.read<SettingsProvider>().accentColor;
    final weightController = TextEditingController();
    final repsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor(context), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> ADD SET',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 16, fontWeight: FontWeight.bold, color: accent),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: weightController,
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: repsController,
                decoration: const InputDecoration(labelText: 'Reps'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final weight = double.tryParse(weightController.text);
                      final reps = int.tryParse(repsController.text);
                      if (weight != null && reps != null) {
                        final newSet = gym.Set(reps: reps, weight: weight);
                        final updatedExercises =
                            List<Exercise>.from(_session.exercises);
                        updatedExercises[exerciseIndex] = Exercise(
                          name: exercise.name,
                          sets: [...exercise.sets, newSet],
                          note: exercise.note,
                        );
                        setState(() {
                          _session =
                              _session.copyWith(exercises: updatedExercises);
                        });
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    child: Text('[ADD]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditSetDialog(int exerciseIndex, int setIndex, gym.Set set) {
    final accent = context.read<SettingsProvider>().accentColor;
    final weightController = TextEditingController(text: set.weight.toString());
    final repsController = TextEditingController(text: set.reps.toString());
    final noteController = TextEditingController(text: set.note ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor(context), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> EDIT SET',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 16, fontWeight: FontWeight.bold, color: accent),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: weightController,
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: repsController,
                decoration: const InputDecoration(labelText: 'Reps'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      final exercises = List<Exercise>.from(_session.exercises);
                      final exercise = exercises[exerciseIndex];
                      final sets = List<gym.Set>.from(exercise.sets)
                        ..removeAt(setIndex);
                      exercises[exerciseIndex] = Exercise(
                          name: exercise.name, sets: sets, note: exercise.note);
                      setState(() {
                        _session = _session.copyWith(exercises: exercises);
                      });
                      Navigator.pop(ctx);
                    },
                    child: Text('[DELETE]',
                        style: GoogleFonts.jetBrainsMono(
                            color: errorColor(context))),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                                color: textSecondaryColor(context))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final weight = double.tryParse(weightController.text);
                          final reps = int.tryParse(repsController.text);
                          if (weight != null && reps != null) {
                            final exercises =
                                List<Exercise>.from(_session.exercises);
                            final exercise = exercises[exerciseIndex];
                            final sets = List<gym.Set>.from(exercise.sets);
                            sets[setIndex] = gym.Set(
                              reps: reps,
                              weight: weight,
                              rpe: set.rpe,
                              note: noteController.text.isNotEmpty
                                  ? noteController.text
                                  : null,
                            );
                            exercises[exerciseIndex] = Exercise(
                                name: exercise.name,
                                sets: sets,
                                note: exercise.note);
                            setState(() {
                              _session =
                                  _session.copyWith(exercises: exercises);
                            });
                            Navigator.pop(ctx);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                        ),
                        child:
                            Text('[SAVE]', style: GoogleFonts.jetBrainsMono()),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
