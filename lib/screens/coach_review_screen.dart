import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/coach_provider.dart';
import '../services/coach/coach_applier.dart';
import '../services/coach/proposal_diff.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/spacing.dart';
import '../widgets/action_progress.dart';
import '../widgets/coach/coach_diff_card.dart';

/// The diff for one proposal, with `Discard` and `Apply`.
class CoachReviewScreen extends StatelessWidget {
  final CoachEntry entry;

  const CoachReviewScreen({required this.entry, super.key});

  Future<void> _apply(BuildContext context) async {
    final coach = context.read<CoachProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final CoachApplyOutcome outcome;
    try {
      outcome = await coach.apply(entry);
    } catch (_) {
      if (!context.mounted) return;
      final ground = errorColor(context);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: ground,
          content: Text(
            'Could not apply the changes. Try again.',
            style: TextStyle(color: onColor(ground)),
          ),
        ),
      );
      return;
    }
    switch (outcome) {
      case CoachApplied():
        navigator.popUntil((route) => route.isFirst);
        messenger.showSnackBar(const SnackBar(content: Text('Plans updated')));
      case CoachApplyStale():
        // The chat's card now offers to ask again with the latest plans.
        navigator.pop();
    }
  }

  void _discard(BuildContext context) {
    context.read<CoachProvider>().discard(entry);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final applying = context.watch<CoachProvider>().applying;
    final item = entry.proposal!;
    final textTheme = Theme.of(context).textTheme;
    final plans = [
      for (final plan in item.diff.plans)
        if (plan.kind != DiffKind.unchanged) plan,
    ];
    final newSplit = item.proposal.newSplitName;

    return PopScope(
      canPop: !applying,
      child: Scaffold(
        backgroundColor: backgroundColor(context),
        appBar: AppBar(title: const Text('Review changes')),
        bottomNavigationBar: _ReviewBar(
          applying: applying,
          onDiscard: applying ? null : () => _discard(context),
          onApply: applying ? null : () => _apply(context),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  newSplit == null
                      ? '${item.splitName} · ${item.summary}'
                      : 'New split: $newSplit · ${item.summary}',
                  style: textTheme.titleMedium?.copyWith(
                    color: textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  newSplit == null
                      ? 'Nothing is saved until you apply. Logged workouts '
                          "aren't changed."
                      : 'Applying creates this split and switches to it. '
                          "Your other splits aren't changed.",
                  style: textTheme.bodySmall?.copyWith(
                    color: textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final plan in plans) ...[
                  CoachPlanDiffCard(plan: plan),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewBar extends StatelessWidget {
  final bool applying;
  final VoidCallback? onDiscard;
  final VoidCallback? onApply;

  const _ReviewBar({
    required this.applying,
    required this.onDiscard,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElevatedButton(
                  key: const ValueKey('coach-apply'),
                  onPressed: onApply,
                  child:
                      applying
                          ? const ActionProgress('Applying')
                          : const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
