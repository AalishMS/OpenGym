import 'package:flutter/material.dart';

import '../../services/coach/coach_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/breakpoints.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// The time the quota resets, in the device's time zone ("1:45 PM").
String coachResetTime(BuildContext context, DateTime resetsAt) =>
    TimeOfDay.fromDateTime(resetsAt.toLocal()).format(context);

/// The model the Coach is on and today's requests, on the app bar's ground
/// under the Coach's title. Both come from the proxy's last answer, so they are unknown until a user's
/// first message.
class CoachStatusBar extends StatelessWidget {
  final String? model;
  final CoachQuota? quota;

  const CoachStatusBar({required this.model, required this.quota, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final quota = this.quota;

    final Widget content;
    if (model == null && quota == null) {
      content = Text(
        'The model and your daily limit show after your first message.',
        style: textTheme.bodySmall?.copyWith(color: secondary),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: _ModelLabel(model: model)),
              if (quota != null) ...[
                const SizedBox(width: AppSpacing.md),
                _UsageLabel(quota: quota),
              ],
            ],
          ),
          if (quota != null && quota.limit > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _UsageMeter(quota: quota),
          ],
        ],
      );
    }

    return Container(
      key: const ValueKey('coach-status'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: content,
        ),
      ),
    );
  }
}

class _ModelLabel extends StatelessWidget {
  final String? model;

  const _ModelLabel({required this.model});

  @override
  Widget build(BuildContext context) {
    final secondary = textSecondaryColor(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Semantics(
      label: 'Currently on ${model ?? 'an unreported model'}',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Currently on ',
                style: style?.copyWith(color: secondary),
              ),
              TextSpan(
                text: model ?? 'not reported yet',
                style:
                    model == null
                        ? style?.copyWith(color: secondary)
                        : AppTypography.trainingData(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimaryColor(context),
                        ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _UsageLabel extends StatelessWidget {
  final CoachQuota quota;

  const _UsageLabel({required this.quota});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final spent = quota.remaining == 0;
    final figures = AppTypography.trainingData(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: spent ? errorColor(context) : textPrimaryColor(context),
    );
    final label = '${quota.remaining} of ${quota.limit} left today';
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Text.rich(
          key: const ValueKey('coach-usage'),
          TextSpan(
            children: [
              TextSpan(text: '${quota.remaining}', style: figures),
              TextSpan(
                text: ' of ${quota.limit} left today',
                style: style?.copyWith(color: textSecondaryColor(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One segment per request, filled while it is still available. Limits too
/// large to count at a glance draw as one bar.
class _UsageMeter extends StatelessWidget {
  static const int maxSegments = 30;

  final CoachQuota quota;

  const _UsageMeter({required this.quota});

  @override
  Widget build(BuildContext context) {
    final fill = accentFillColor(context);
    final track = accentMutedColor(context);
    const height = 4.0;

    if (quota.limit > maxSegments) {
      return ClipRRect(
        borderRadius: AppRadius.micro,
        child: SizedBox(
          height: height,
          child: LinearProgressIndicator(
            value: quota.remaining / quota.limit,
            color: fill,
            backgroundColor: track,
          ),
        ),
      );
    }
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var index = 0; index < quota.limit; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: index < quota.remaining ? fill : track,
                  borderRadius: AppRadius.micro,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
