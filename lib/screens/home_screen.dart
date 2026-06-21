import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/settings_provider.dart';
import '../models/workout_plan.dart';
import '../models/exercise_template.dart';
import '../data/plan_colors.dart';
import '../theme/app_theme.dart';
import 'create_plan_screen.dart';
import 'edit_plan_screen.dart';
import 'workout_screen.dart';
import '../services/sample_data_seeder.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final accent = settings.accentColor;
    final bg = backgroundColor(context);
    final border = borderColor(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, accent, border),
            Expanded(
              child: Consumer<WorkoutPlanProvider>(
                builder: (context, provider, child) {
                  if (provider.plans.isEmpty) {
                    return _buildEmptyState(context, provider, accent);
                  }
                  return _buildPlanSection(context, provider, accent);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildNewPlanButton(context, accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, Color border) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            '> OPENGYM',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, WorkoutPlanProvider provider, Color accent) {
    final textSecondary = textSecondaryColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '> NO PLANS FOUND',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first workout plan',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () async {
                await SampleDataSeeder.seedSampleData();
                provider.loadPlans();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('> Sample data loaded!',
                          style:
                              GoogleFonts.jetBrainsMono(color: Colors.black)),
                      backgroundColor: accent,
                    ),
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent, width: 1),
              ),
              child: Text('[ LOAD SAMPLE DATA ]',
                  style: GoogleFonts.jetBrainsMono()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSection(
      BuildContext context, WorkoutPlanProvider provider, Color accent) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: provider.plans.length,
      itemBuilder: (context, index) =>
          _buildPlanCard(context, provider.plans[index], index, accent),
    );
  }

  Widget _buildPlanCard(
      BuildContext context, WorkoutPlan plan, int index, Color accent) {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final planColor = plan.planColor != null ? Color(plan.planColor!) : accent;

    final exerciseNames = plan.exercises.map((e) => e.name).toList();
    final previewLines = exerciseNames.take(3).toList();

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WorkoutScreen(plan: plan, planIndex: index),
          ),
        );
      },
      onLongPress: () => _showPlanOptions(context, plan, index, accent),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 2, color: planColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '[${(index + 1).toString().padLeft(2, '0')}]',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: textSecondary,
                        letterSpacing: 0.08,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan.name.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                        letterSpacing: 0.04,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    ...previewLines.map((name) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '· $name',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: textSecondary,
                          letterSpacing: 0.02,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                    if (exerciseNames.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '+${exerciseNames.length - 3} more',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textSecondary.withAlpha(128),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '${plan.exercises.length} EXERCISES',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: planColor,
                        letterSpacing: 0.06,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewPlanButton(BuildContext context, Color accent) {
    final textSecondary = textSecondaryColor(context);
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreatePlanScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withAlpha(60)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 12, color: textSecondary),
            const SizedBox(width: 8),
            Text(
              '[+ NEW PLAN]',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                letterSpacing: 0.1,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlanOptions(
      BuildContext context, WorkoutPlan plan, int index, Color accent) {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> ${plan.name}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select action:',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _buildActionButton(
                label: '[COLOR] Change plan color',
                onTap: () {
                  Navigator.pop(ctx);
                  _showColorPickerDialog(context, plan, index, accent);
                },
                accent: accent,
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                label: '[COPY] Duplicate plan',
                onTap: () {
                  Navigator.pop(ctx);
                  final copyPlan = WorkoutPlan(
                    name: '${plan.name} (Copy)',
                    exercises: plan.exercises
                        .map(
                            (e) => ExerciseTemplate(name: e.name, sets: e.sets))
                        .toList(),
                    planColor: plan.planColor,
                  );
                  context.read<WorkoutPlanProvider>().addPlan(copyPlan);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('> Plan copied!',
                          style:
                              GoogleFonts.jetBrainsMono(color: Colors.black)),
                      backgroundColor: accent,
                    ),
                  );
                },
                accent: accent,
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                label: '[EDIT] Modify plan',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          EditPlanScreen(plan: plan, planIndex: index),
                    ),
                  );
                },
                accent: accent,
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                label: '[DELETE] Remove plan',
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<WorkoutPlanProvider>().deletePlan(index);
                },
                accent: Colors.red,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('[CANCEL]',
                    style: GoogleFonts.jetBrainsMono(color: textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPickerDialog(
      BuildContext context, WorkoutPlan plan, int planIndex, Color accent) {
    int? selectedColor = plan.planColor;
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: border, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '> ${plan.name} — COLOR',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SELECT PLAN COLOR',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kPlanColors.map((colorValue) {
                        final color = Color(colorValue);
                        final isSelected = selectedColor == colorValue;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => selectedColor = colorValue);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(
                                color: isSelected ? accent : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? Icon(Icons.check, size: 18,
                                    color: color.computeLuminance() > 0.5
                                        ? Colors.black
                                        : Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('[CANCEL]',
                              style: GoogleFonts.jetBrainsMono(color: textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final updated = WorkoutPlan(
                              name: plan.name,
                              exercises: plan.exercises,
                              planColor: selectedColor,
                            );
                            context.read<WorkoutPlanProvider>().updatePlan(planIndex, updated);
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: Text('[SAVE]', style: GoogleFonts.jetBrainsMono()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton(
      {required String label,
      required VoidCallback onTap,
      required Color accent}) {
    return InkWell(
      onTap: onTap,
      splashColor: accent.withAlpha(51),
      highlightColor: accent.withAlpha(26),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: accent, width: 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(fontSize: 12, color: accent),
        ),
      ),
    );
  }
}
