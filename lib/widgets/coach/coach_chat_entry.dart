import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/coach_provider.dart';
import '../../services/coach/coach_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// One chat line. The user's messages sit on the right on a raised surface;
/// the Coach's replies sit on the left, on the page, with their proposal card.
class CoachChatEntry extends StatelessWidget {
  final CoachEntry entry;
  final VoidCallback? onReview;
  final VoidCallback? onAskAgain;
  final VoidCallback? onRetry;
  final VoidCallback? onCheckUpdates;

  const CoachChatEntry({
    required this.entry,
    this.onReview,
    this.onAskAgain,
    this.onRetry,
    this.onCheckUpdates,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return switch (entry.role) {
      CoachEntryRole.user => _UserBubble(text: entry.text),
      CoachEntryRole.coach => _CoachReply(
        entry: entry,
        onReview: onReview,
        onAskAgain: onAskAgain,
      ),
      CoachEntryRole.failure => _FailureNotice(
        entry: entry,
        onRetry: onRetry,
        onCheckUpdates: onCheckUpdates,
      ),
    };
  }
}

class _UserBubble extends StatelessWidget {
  final String text;

  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: raisedSurfaceColor(context),
            border: Border.all(color: borderColor(context)),
            borderRadius: AppRadius.card,
          ),
          child: Semantics(
            label: 'You said',
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: textPrimaryColor(context)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoachReply extends StatelessWidget {
  final CoachEntry entry;
  final VoidCallback? onReview;
  final VoidCallback? onAskAgain;

  const _CoachReply({required this.entry, this.onReview, this.onAskAgain});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final proposal = entry.proposal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.text.isNotEmpty)
          Semantics(
            label: 'Coach said',
            child: Text(
              entry.text,
              style: textTheme.bodyLarge?.copyWith(
                color: textPrimaryColor(context),
              ),
            ),
          ),
        if (entry.planUnusable) ...[
          if (entry.text.isNotEmpty) const SizedBox(height: AppSpacing.sm),
          Text(
            "The Coach suggested a plan that couldn't be used. Try asking "
            'again, maybe more simply.',
            style: textTheme.bodyMedium?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ],
        if (proposal != null) ...[
          const SizedBox(height: AppSpacing.md),
          CoachProposalCard(
            item: proposal,
            onReview: onReview,
            onAskAgain: onAskAgain,
          ),
        ],
      ],
    );
  }
}

/// "Push Pull Legs · 2 plans changed, 1 added" with `Review`, or the stale
/// prompt with `Ask again`.
class CoachProposalCard extends StatelessWidget {
  final CoachProposalItem item;
  final VoidCallback? onReview;
  final VoidCallback? onAskAgain;

  const CoachProposalCard({
    required this.item,
    this.onReview,
    this.onAskAgain,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final (status, action) = switch (item.status) {
      CoachProposalStatus.pending => (
        null,
        TextButton(onPressed: onReview, child: const Text('Review')),
      ),
      CoachProposalStatus.applied => ('Applied', null),
      CoachProposalStatus.discarded => ('Discarded', null),
      CoachProposalStatus.stale => (
        'Plans changed. Ask again with the latest?',
        TextButton(onPressed: onAskAgain, child: const Text('Ask again')),
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.clipboardList,
            size: 20,
            color: accentColor(context),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.splitName} · ${item.summary}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: textPrimaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (status != null)
                  Text(
                    status,
                    style: textTheme.bodySmall?.copyWith(color: secondary),
                  ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: AppSpacing.sm), action],
        ],
      ),
    );
  }
}

class _FailureNotice extends StatelessWidget {
  final CoachEntry entry;
  final VoidCallback? onRetry;
  final VoidCallback? onCheckUpdates;

  const _FailureNotice({
    required this.entry,
    this.onRetry,
    this.onCheckUpdates,
  });

  @override
  Widget build(BuildContext context) {
    final kind = entry.failure;
    final retryable = switch (kind) {
      CoachFailureKind.noConnection ||
      CoachFailureKind.busy ||
      CoachFailureKind.unavailable ||
      CoachFailureKind.upstream => true,
      _ => false,
    };
    final error = errorColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: error),
        borderRadius: AppRadius.card,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 18, color: error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                entry.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textPrimaryColor(context),
                ),
              ),
            ),
          ),
          if (kind == CoachFailureKind.updateRequired && onCheckUpdates != null)
            TextButton(
              onPressed: onCheckUpdates,
              child: const Text('Check for updates'),
            )
          else if (retryable && onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
