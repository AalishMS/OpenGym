import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/coach_provider.dart';
import '../providers/split_provider.dart';
import '../providers/update_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/coach/coach_chat_entry.dart';
import '../widgets/coach/coach_status_bar.dart';
import '../widgets/update_dialog.dart';
import 'coach_review_screen.dart';

/// A starting question for an empty chat, with what kind of help it asks for.
class CoachSuggestion {
  final String prompt;
  final String hint;

  const CoachSuggestion(this.prompt, this.hint);
}

const List<CoachSuggestion> kCoachSuggestions = [
  CoachSuggestion('Build a 4-day upper/lower', 'Start a new split'),
  CoachSuggestion('My squat has stalled', 'Look at your recent training'),
  CoachSuggestion('Swap exercises for a sore shoulder', 'Adjust your plans'),
];

/// The Coach chat. The app shell shows it inside the Home tab and passes
/// [onClose]; without it, the screen is a pushed route.
class CoachScreen extends StatefulWidget {
  final VoidCallback? onClose;

  const CoachScreen({this.onClose, super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _shownEntries = 0;

  @override
  void initState() {
    super.initState();
    final coach = context.read<CoachProvider>();
    coach.refreshStale();
    coach.checkConnection();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _send([String? text]) {
    final coach = context.read<CoachProvider>();
    final message = text ?? _input.text;
    if (coach.sending || coach.limitReached || message.trim().isEmpty) return;
    if (text == null) _input.clear();
    coach.send(message);
  }

  Future<void> _review(CoachEntry entry) async {
    final coach = context.read<CoachProvider>();
    if (!coach.refreshStale(entry)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CoachReviewScreen(entry: entry)),
    );
    // Applying returns to Home. As a pushed route, the review screen has
    // already popped this one; inside the shell, the Coach closes itself.
    if (!mounted) return;
    if (entry.proposal?.status == CoachProposalStatus.applied) {
      widget.onClose?.call();
    }
  }

  Future<void> _checkUpdates() async {
    final updates = context.read<UpdateProvider?>();
    if (updates == null) return;
    if (!updates.isUpdateAvailable && !updates.isBusy) {
      await updates.checkManually();
      if (!mounted) return;
    }
    if (updates.isUpdateAvailable || updates.isBusy) {
      await showUpdateDialog(context);
      return;
    }
    final failed = updates.status == UpdateStatus.failed;
    final ground = failed ? errorColor(context) : accentFillColor(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ground,
        content: Text(
          failed ? updates.error ?? 'Update check failed' : "You're up to date",
          style: TextStyle(
            color: failed ? onColor(ground) : onAccentColor(context),
          ),
        ),
      ),
    );
  }

  /// Keeps the newest message in view as the conversation grows.
  void _followConversation(int count) {
    if (count == _shownEntries) return;
    _shownEntries = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Space above an entry. A question opens a new turn, so it gets more room
  /// than the answer under it.
  double _gapAbove(CoachProvider coach, int index) {
    if (index == 0) return 0;
    final opensTurn =
        index < coach.entries.length &&
        coach.entries[index].role == CoachEntryRole.user;
    return opensTurn ? AppSpacing.xxl : AppSpacing.md;
  }

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final splitName = context.watch<SplitProvider>().activeSplit?.name;
    final planCount = context.watch<WorkoutPlanProvider?>()?.plans.length;
    final textTheme = Theme.of(context).textTheme;
    final quota = coach.quota;
    final locked = coach.limitReached;
    final busy = coach.sending || locked;
    _followConversation(coach.entries.length + (coach.sending ? 1 : 0));

    return Scaffold(
      backgroundColor: backgroundColor(context),
      // Inside the shell, its Scaffold already makes room for the keyboard.
      resizeToAvoidBottomInset: widget.onClose == null,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: widget.onClose == null ? 'Back' : 'Back to plans',
          onPressed: _close,
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Coach'),
            if (splitName != null)
              Text(
                splitName,
                style: textTheme.bodySmall?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            CoachStatusBar(model: coach.model, quota: quota),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: Breakpoints.expanded,
                  ),
                  child: Column(
                    children: [
                      if (coach.connectionNotice) const _ConnectionNotice(),
                      Expanded(
                        child:
                            coach.isEmpty
                                ? _EmptyState(
                                  splitName: splitName,
                                  planCount: planCount,
                                  onSuggestion: busy ? null : _send,
                                )
                                : ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.lg,
                                    AppSpacing.xl,
                                    AppSpacing.lg,
                                    AppSpacing.lg,
                                  ),
                                  itemCount:
                                      coach.entries.length +
                                      (coach.sending ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    final gap = EdgeInsets.only(
                                      top: _gapAbove(coach, index),
                                    );
                                    if (index == coach.entries.length) {
                                      return Padding(
                                        padding: gap,
                                        child: const _Thinking(),
                                      );
                                    }
                                    final entry = coach.entries[index];
                                    return Padding(
                                      padding: gap,
                                      child: CoachChatEntry(
                                        entry: entry,
                                        onReview: () => _review(entry),
                                        onAskAgain:
                                            busy
                                                ? null
                                                : () => coach.askAgain(entry),
                                        onRetry:
                                            busy || !coach.canRetry(entry)
                                                ? null
                                                : () => coach.retry(entry),
                                        onCheckUpdates: _checkUpdates,
                                        onSignIn: coach.signInAgain,
                                      ),
                                    );
                                  },
                                ),
                      ),
                      _InputBar(
                        controller: _input,
                        sending: coach.sending,
                        locked: locked,
                        resetsAt: quota?.resetsAt,
                        onSend:
                            busy || _input.text.trim().isEmpty ? null : _send,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice();

  @override
  Widget build(BuildContext context) {
    final secondary = textSecondaryColor(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor(context))),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.wifiOff, size: 18, color: secondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'The Coach needs a connection. Your plans still work offline.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textPrimaryColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? splitName;
  final int? planCount;
  final ValueChanged<String>? onSuggestion;

  const _EmptyState({
    required this.splitName,
    required this.planCount,
    required this.onSuggestion,
  });

  /// What the Coach will read, in plain words.
  String get _scope {
    final plans = switch (planCount) {
      null || 0 => 'your plans',
      1 => 'your 1 plan',
      final count => 'your $count plans',
    };
    final where = splitName == null ? '' : ' in $splitName';
    return 'The Coach reads $plans$where and your last four weeks of '
        'training. Nothing changes until you review and apply it.';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What should we work on?',
            style: textTheme.headlineMedium?.copyWith(
              color: textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_scope, style: textTheme.bodyMedium?.copyWith(color: secondary)),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Try asking',
            style: textTheme.labelMedium?.copyWith(color: secondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final suggestion in kCoachSuggestions)
            _SuggestionRow(
              suggestion: suggestion,
              onTap:
                  onSuggestion == null
                      ? null
                      : () => onSuggestion!(suggestion.prompt),
            ),
        ],
      ),
    );
  }
}

/// A suggestion as a plain row between hairlines: the question, what it helps
/// with, and an arrow.
class _SuggestionRow extends StatelessWidget {
  final CoachSuggestion suggestion;
  final VoidCallback? onTap;

  const _SuggestionRow({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final accent = accentColor(context);
    final secondary = textSecondaryColor(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Semantics(
        button: true,
        enabled: enabled,
        child: InkWell(
          onTap: onTap,
          splashColor: accent.withAlpha(36),
          highlightColor: accent.withAlpha(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.prompt,
                        style: textTheme.titleMedium?.copyWith(
                          color:
                              enabled ? textPrimaryColor(context) : secondary,
                        ),
                      ),
                      Text(
                        suggestion.hint,
                        style: textTheme.bodySmall?.copyWith(color: secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                ExcludeSemantics(
                  child: Icon(
                    LucideIcons.arrowUpRight,
                    size: 18,
                    color: enabled ? accent : secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'The Coach is reading your plans',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CoachSpeakerLabel(),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentColor(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Reading your plans',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;

  /// Today's requests are used up, until [resetsAt] if the proxy said when.
  final bool locked;
  final DateTime? resetsAt;
  final VoidCallback? onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.locked,
    required this.resetsAt,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final fill = accentFillColor(context);
    final secondary = textSecondaryColor(context);
    final enabled = onSend != null;
    final resetsAt = this.resetsAt;
    final hint =
        !locked
            ? 'Ask about your plans'
            : resetsAt == null
            ? 'Daily limit reached'
            : 'Daily limit reached. Back at '
                '${coachResetTime(context, resetsAt)}';
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('coach-input'),
              controller: controller,
              enabled: !locked,
              minLines: 1,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend?.call(),
              decoration: InputDecoration(
                hintText: hint,
                counterText: '',
                prefixIcon:
                    locked
                        ? Icon(LucideIcons.lock, size: 16, color: secondary)
                        : null,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox.square(
            dimension: 48,
            child: Material(
              color: enabled ? fill : surfaceColor(context),
              borderRadius: AppRadius.button,
              child: InkWell(
                key: const ValueKey('coach-send'),
                onTap: onSend,
                borderRadius: AppRadius.button,
                child: Semantics(
                  button: true,
                  enabled: enabled,
                  label: sending ? 'Sending' : 'Send',
                  child: Center(
                    child:
                        sending
                            ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: secondary,
                              ),
                            )
                            : Icon(
                              LucideIcons.arrowUp,
                              size: 20,
                              color:
                                  enabled ? onAccentColor(context) : secondary,
                            ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
