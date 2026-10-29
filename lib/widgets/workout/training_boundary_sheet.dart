import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../action_progress.dart';

/// One way forward once a workout finishes its block's planned weeks.
class TrainingBoundaryOption {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  const TrainingBoundaryOption({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });
}

/// The boundary choice: the first option is the natural next step and carries
/// the accent; the rest sit beside it as plain outlined choices.
class TrainingBoundarySheet extends StatelessWidget {
  final String message;
  final List<TrainingBoundaryOption> options;
  final String? staleMessage;
  final String? error;
  final bool saving;
  final VoidCallback? onDismiss;

  const TrainingBoundarySheet({
    super.key,
    required this.message,
    required this.options,
    required this.onDismiss,
    this.staleMessage,
    this.error,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accentMutedColor(context),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm + 2),
                  child: Icon(
                    LucideIcons.flagTriangleRight,
                    size: 20,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Choose next week',
                    style: textTheme.titleLarge?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            staleMessage ?? message,
            style: textTheme.bodyMedium?.copyWith(
              color: textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (staleMessage == null)
            for (final (index, option) in options.indexed) ...[
              _BoundaryOptionCard(
                option: option,
                recommended: index == 0,
                enabled: !saving,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          if (saving)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Center(child: ActionProgress('Saving your choice')),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.circleAlert,
                      size: 16,
                      color: errorColor(context),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        error!,
                        style: textTheme.bodySmall?.copyWith(
                          color: errorColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: TextButton(
              onPressed: saving ? null : onDismiss,
              child: const Text('Not now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundaryOptionCard extends StatelessWidget {
  final TrainingBoundaryOption option;
  final bool recommended;
  final bool enabled;

  const _BoundaryOptionCard({
    required this.option,
    required this.recommended,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    final onTap = enabled ? option.onTap : null;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: recommended ? accentMutedColor(context) : surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.button,
          side: BorderSide(
            color: recommended ? accent : borderColor(context),
            width: recommended ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: accent.withAlpha(36),
          highlightColor: accent.withAlpha(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(
                    option.icon,
                    size: 20,
                    color: onTap == null ? textSecondary : accent,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color:
                                onTap == null
                                    ? textSecondary
                                    : textPrimaryColor(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          option.detail,
                          style: textTheme.bodySmall?.copyWith(
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line notice above the workout log with the action that resolves it.
class TrainingProgressNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  const TrainingProgressNotice({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = isError ? errorColor(context) : accentColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor(context),
          borderRadius: AppRadius.card,
          border: Border.all(color: borderColor(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: tone),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Semantics(
                  liveRegion: isError,
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
