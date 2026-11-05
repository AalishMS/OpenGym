import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/plan_colors.dart';
import '../models/workout_session.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/format.dart';

/// A slim strip above the navigation that leads back to the workout in
/// progress, so leaving it to check History or Stats is never a dead end.
///
/// It paints the plan's colour as a marker and ticks the session clock while
/// the timer runs. The whole strip is one tap target.
class ActiveWorkoutBar extends StatefulWidget {
  final WorkoutSession session;
  final VoidCallback onTap;

  const ActiveWorkoutBar({
    required this.session,
    required this.onTap,
    super.key,
  });

  @override
  State<ActiveWorkoutBar> createState() => _ActiveWorkoutBarState();
}

class _ActiveWorkoutBarState extends State<ActiveWorkoutBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ActiveWorkoutBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.session.isTimerRunning) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final running = session.isTimerRunning;
    final planId = session.planId;
    final plan = planId == null ? null : HiveService.getPlanById(planId);
    final marker = planColorOf(plan?.planColor, context);
    final primary = textPrimaryColor(context);
    final secondary = textSecondaryColor(context);
    final elapsed = formatDuration(session.elapsedSeconds());
    final status = running ? 'Workout in progress' : 'Workout paused';
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '$status, ${session.planName}, $elapsed. Resume workout',
      excludeSemantics: true,
      child: Material(
        color: surfaceColor(context),
        child: InkWell(
          key: const ValueKey('active-workout-bar'),
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor(context))),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: marker,
                    borderRadius: AppRadius.micro,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Icon(
                  running ? LucideIcons.timer : LucideIcons.pause,
                  size: 18,
                  color: marker,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(color: secondary),
                      ),
                      Text(
                        session.planName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  elapsed,
                  style: AppTypography.figures(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: running ? primary : secondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(LucideIcons.chevronRight, size: 18, color: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
