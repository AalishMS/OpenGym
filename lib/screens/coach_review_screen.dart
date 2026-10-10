import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/coach_provider.dart';
import '../services/coach/coach_applier.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/spacing.dart';
import '../widgets/action_progress.dart';
import '../widgets/coach/coach_diff_card.dart';

/// The diff for one proposal. Every change has a checkbox, so the user can
/// apply some changes and skip the rest, or `Discard` the lot.
class CoachReviewScreen extends StatefulWidget {
  final CoachEntry entry;

  const CoachReviewScreen({required this.entry, super.key});

  @override
  State<CoachReviewScreen> createState() => _CoachReviewScreenState();
}

class _CoachReviewScreenState extends State<CoachReviewScreen> {
  CoachEntry get entry => widget.entry;

  Future<void> _apply() async {
    final coach = context.read<CoachProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final CoachApplyOutcome outcome;
    try {
      outcome = await coach.apply(entry);
    } catch (_) {
      if (!mounted) return;
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

  void _discard() {
    context.read<CoachProvider>().discard(entry);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final applying = context.watch<CoachProvider>().applying;
    final item = entry.proposal!;
    final selection = item.selection;
    final kept = selection.keptCount;
    final total = selection.changes.length;
    final problems = selection.problems;
    final canApply = !applying && kept > 0 && problems.isEmpty;

    return PopScope(
      canPop: !applying,
      child: Scaffold(
        backgroundColor: backgroundColor(context),
        appBar: AppBar(title: const Text('Review changes')),
        bottomNavigationBar: _ReviewBar(
          applying: applying,
          applyLabel:
              selection.keepsAll || kept == 0
                  ? 'Apply'
                  : 'Apply $kept of $total',
          message:
              problems.isNotEmpty
                  ? problems.first
                  : kept == 0
                  ? 'Select at least one change to apply.'
                  : null,
          isProblem: problems.isNotEmpty,
          onDiscard: applying ? null : _discard,
          onApply: canApply ? _apply : null,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _ReviewHeader(
                  item: item,
                  kept: kept,
                  total: total,
                  onToggleAll:
                      applying
                          ? null
                          : () => setState(
                            () => selection.setAllKept(kept != total),
                          ),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final plan in selection.plans) ...[
                  CoachPlanReviewCard(
                    plan: plan,
                    selection: selection,
                    onChanged: applying ? null : () => setState(() {}),
                  ),
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

class _ReviewHeader extends StatelessWidget {
  final CoachProposalItem item;
  final int kept;
  final int total;
  final VoidCallback? onToggleAll;

  const _ReviewHeader({
    required this.item,
    required this.kept,
    required this.total,
    required this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final newSplit = item.proposal.newSplitName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          newSplit ? 'New split' : 'Changes to your split',
          style: textTheme.labelLarge?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          header: true,
          child: Text(
            item.splitName,
            style: textTheme.titleLarge?.copyWith(
              color: textPrimaryColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          newSplit
              ? 'Choose the exercises to keep. Applying creates this split '
                  "and switches to it. Your other splits aren't changed."
              : 'Choose the changes to keep. Nothing is saved until you '
                  "apply, and logged workouts aren't changed.",
          style: textTheme.bodyMedium?.copyWith(color: secondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                '$kept of $total ${total == 1 ? 'change' : 'changes'} '
                'selected',
                style: textTheme.labelLarge?.copyWith(
                  color: textPrimaryColor(context),
                ),
              ),
            ),
            TextButton(
              onPressed: onToggleAll,
              child: Text(kept == total ? 'Clear all' : 'Select all'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReviewBar extends StatelessWidget {
  final bool applying;
  final String applyLabel;

  /// Why `Apply` is off, shown over the buttons.
  final String? message;
  final bool isProblem;
  final VoidCallback? onDiscard;
  final VoidCallback? onApply;

  const _ReviewBar({
    required this.applying,
    required this.applyLabel,
    required this.message,
    required this.isProblem,
    required this.onDiscard,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final messageColor =
        isProblem ? errorColor(context) : textSecondaryColor(context);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        if (isProblem) ...[
                          Icon(
                            LucideIcons.circleAlert,
                            size: 16,
                            color: messageColor,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            message,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: messageColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
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
                              : Text(applyLabel),
                    ),
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
