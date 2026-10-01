import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/plan_stats.dart';
import '../app_button.dart';
import 'plan_card.dart';

/// The top of the Plans tab: the workout the split's rotation points at, one
/// tap from starting, above a [footer] that is normally the week's progress.
///
/// This is the one place on the screen where a plan's colour goes beyond its
/// marker. It tints the card and sets the large day number behind the name, so
/// the next workout is recognisable from across the room. Everything drawn on
/// that tint is ink from the neutral scale, so legibility never depends on
/// which colour a plan was given.
class UpNextCard extends StatelessWidget {
  final WorkoutPlan plan;

  /// One-based position of [plan] in the split, and the split's length.
  final int day;
  final int dayCount;
  final PlanStat? stat;
  final VoidCallback onStart;
  final Widget footer;

  const UpNextCard({
    required this.plan,
    required this.day,
    required this.dayCount,
    required this.stat,
    required this.onStart,
    required this.footer,
    super.key,
  });

  /// Below this width the week sits under the workout rather than beside it.
  static const double _sideBySideWidth = 640;

  @override
  Widget build(BuildContext context) {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final planColor = planColorOf(plan.planColor, context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Opaque, so the tint is the same on every ground it could sit over.
    final tint = Color.alphaBlend(
      planColor.withValues(alpha: isDark ? 0.16 : 0.10),
      surface,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [tint, surface],
        ),
        border: Border.all(color: border, width: 1),
        borderRadius: AppRadius.card,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= _sideBySideWidth;
          final details = _details(context, planColor, sideBySide);
          final week = Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: footer,
          );

          if (!sideBySide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                Divider(height: 1, thickness: 1, color: border),
                week,
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: details),
                VerticalDivider(width: 1, thickness: 1, color: border),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [week],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _details(BuildContext context, Color planColor, bool sideBySide) {
    final textTheme = Theme.of(context).textTheme;
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final last = stat?.lastTrained;
    final exerciseNames = plan.exercises.map((e) => e.name).toList();

    return Stack(
      children: [
        // The day number as a watermark: large, faint, and cut off by the
        // card's edge. Decoration only; the same number is read out below.
        Positioned(
          top: -AppSpacing.xl,
          right: -AppSpacing.sm,
          child: ExcludeSemantics(
            child: Text(
              day.toString().padLeft(2, '0'),
              // A graphic, not reading text: scaled up with large text it
              // would cover the whole card.
              textScaler: TextScaler.noScaling,
              style: AppTypography.trainingData(
                fontSize: 120,
                fontWeight: FontWeight.w800,
                height: 1,
                color: planColor.withValues(alpha: isDark ? 0.12 : 0.09),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.zap, size: 14, color: planColor),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Up next',
                    style: textTheme.labelMedium?.copyWith(
                      color: textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'Day $day of $dayCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.trainingData(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                titleCase(plan.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.displaySmall?.copyWith(color: textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                exerciseNames.isEmpty
                    ? 'No exercises yet'
                    : exerciseNames.join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xxs,
                children: [
                  PlanVolumeSummary(plan: plan),
                  Text(
                    last == null
                        ? 'First time'
                        : 'Last done ${formatDaysAgo(last).toLowerCase()}',
                    style: textTheme.labelMedium?.copyWith(
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                // Full width on a phone, where it is the thumb's target; its
                // own width beside the week, where a full-width bar would run
                // half the screen.
                width: sideBySide ? null : double.infinity,
                child: AppButton.primary(
                  label: 'Start workout',
                  onPressed: onStart,
                  // AppButton's own icon row can't shrink its label, and on a
                  // narrow phone with large text the label is wider than the
                  // button. This one ellipsizes instead of overflowing.
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.play, size: 16),
                      SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          'Start workout',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
