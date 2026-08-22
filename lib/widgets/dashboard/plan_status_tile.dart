import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/plan_stats.dart';

/// Per-plan status lines — last trained, session count, cumulative volume.
class PlanStatusTile extends StatelessWidget {
  final List<PlanStat> stats;
  final void Function(PlanStat) onOpen;

  const PlanStatusTile({
    required this.stats,
    required this.onOpen,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stat in stats)
          InkWell(
            onTap: () => onOpen(stat),
            splashColor: accent.withAlpha(40),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 2,
                    height: 22,
                    color: stat.plan.planColor != null
                        ? Color(stat.plan.planColor!)
                        : accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stat.plan.name.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                            letterSpacing: 0.02,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _subtitle(stat),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    stat.lastTrained != null
                        ? formatRelativeDay(stat.lastTrained!)
                        : 'NEVER',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: stat.lastTrained != null ? accent : textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _subtitle(PlanStat stat) {
    final parts = <String>['${stat.plan.exercises.length} EX'];
    if (stat.sessionCount > 0) {
      parts.add('${stat.sessionCount} SESSIONS');
      parts.add('${formatVolume(stat.volumeKg)} KG');
    }
    return parts.join('  ·  ');
  }
}
