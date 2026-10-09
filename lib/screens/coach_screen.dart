import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/coach_provider.dart';
import '../providers/split_provider.dart';
import '../providers/update_provider.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/coach/coach_chat_entry.dart';
import '../widgets/update_dialog.dart';
import 'coach_review_screen.dart';

const List<String> kCoachSuggestions = [
  'Build a 4-day upper/lower',
  'My squat has stalled',
  'Swap exercises for a sore shoulder',
];

/// The Coach chat, pushed from the Home header.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

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

  void _send([String? text]) {
    final coach = context.read<CoachProvider>();
    final message = text ?? _input.text;
    if (coach.sending || message.trim().isEmpty) return;
    if (text == null) _input.clear();
    coach.send(message);
  }

  Future<void> _review(CoachEntry entry) async {
    final coach = context.read<CoachProvider>();
    if (!coach.refreshStale(entry)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CoachReviewScreen(entry: entry)),
    );
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

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final splitName = context.watch<SplitProvider>().activeSplit?.name;
    final textTheme = Theme.of(context).textTheme;
    _followConversation(coach.entries.length + (coach.sending ? 1 : 0));

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
            child: Column(
              children: [
                if (coach.connectionNotice) const _ConnectionNotice(),
                Expanded(
                  child:
                      coach.isEmpty
                          ? _EmptyState(
                            onSuggestion: coach.sending ? null : _send,
                          )
                          : ListView.separated(
                            controller: _scroll,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount:
                                coach.entries.length + (coach.sending ? 1 : 0),
                            separatorBuilder:
                                (_, _) => const SizedBox(height: AppSpacing.lg),
                            itemBuilder: (context, index) {
                              if (index == coach.entries.length) {
                                return const _Thinking();
                              }
                              final entry = coach.entries[index];
                              return CoachChatEntry(
                                entry: entry,
                                onReview: () => _review(entry),
                                onAskAgain:
                                    coach.sending
                                        ? null
                                        : () => coach.askAgain(entry),
                                onRetry:
                                    coach.sending || entry.prompt == null
                                        ? null
                                        : () => _send(entry.prompt),
                                onCheckUpdates: _checkUpdates,
                              );
                            },
                          ),
                ),
                if (coach.lowRemaining != null)
                  _Remaining(remaining: coach.lowRemaining!),
                _InputBar(
                  controller: _input,
                  sending: coach.sending,
                  onSend:
                      coach.sending || _input.text.trim().isEmpty
                          ? null
                          : _send,
                ),
              ],
            ),
          ),
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
          color: surfaceColor(context),
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
  final ValueChanged<String>? onSuggestion;

  const _EmptyState({required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sparkles, size: 32, color: accentColor(context)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Ask the Coach',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                color: textPrimaryColor(context),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'It can build plans, adjust sets, and suggest swaps for this '
              'split. You review every change before it is saved.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final suggestion in kCoachSuggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed:
                        onSuggestion == null
                            ? null
                            : () => onSuggestion!(suggestion),
                    child: Text(suggestion),
                  ),
                ),
              ),
          ],
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
      label: 'The Coach is thinking',
      child: ExcludeSemantics(
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Thinking',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Remaining extends StatelessWidget {
  final int remaining;

  const _Remaining({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final label = switch (remaining) {
      0 => 'No Coach requests left today',
      1 => '1 Coach request left today',
      _ => '$remaining Coach requests left today',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: textSecondaryColor(context)),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback? onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final fill = accentFillColor(context);
    final enabled = onSend != null;
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
              minLines: 1,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend?.call(),
              decoration: const InputDecoration(
                hintText: 'Ask about your plans',
                counterText: '',
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
                                color: textSecondaryColor(context),
                              ),
                            )
                            : Icon(
                              LucideIcons.send,
                              size: 20,
                              color:
                                  enabled
                                      ? onAccentColor(context)
                                      : textSecondaryColor(context),
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
