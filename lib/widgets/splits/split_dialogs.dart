import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/split.dart' as gym;
import '../../providers/split_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

class SplitDialogs {
  SplitDialogs._();

  static Future<void> showCreate(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _SplitNameDialog(hostContext: context),
  );

  static Future<void> showManage(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _ManageSplitsDialog(hostContext: context),
  );
}

class _SplitNameDialog extends StatefulWidget {
  final BuildContext hostContext;
  final gym.Split? split;

  const _SplitNameDialog({required this.hostContext, this.split});

  @override
  State<_SplitNameDialog> createState() => _SplitNameDialogState();
}

class _SplitNameDialogState extends State<_SplitNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.split?.name,
  );
  String? _error;
  bool _saving = false;

  bool get _isRename => widget.split != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hostContext = widget.hostContext;
    final provider = hostContext.read<SplitProvider>();
    final error = provider.nameError(
      _controller.text,
      exceptId: widget.split?.id,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isRename) {
        await provider.renameSplit(widget.split!.id, _controller.text);
      } else {
        await provider.createSplit(_controller.text);
      }
      if (!mounted || !hostContext.mounted) return;
      Navigator.pop(context);
      _showSuccess(
        hostContext,
        _isRename ? 'Split renamed' : 'Split created and selected',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    return Dialog(
      backgroundColor: surfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: borderColor(context)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isRename ? 'Rename split' : 'New split',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: accent),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _isRename
                    ? 'Change this workspace name. Its plans and history stay together.'
                    : 'Start an empty training workspace with its own plans, history, and records.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const ValueKey('split-name-field'),
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                maxLength: 24,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  labelText: 'Split name',
                  helperText: '1–24 characters',
                  errorText: _error,
                  counterText: '',
                  border: const OutlineInputBorder(
                    borderRadius: AppRadius.field,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentFillColor(context),
                      foregroundColor: onAccentColor(context),
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.button,
                      ),
                    ),
                    child: Text(_isRename ? 'Save' : 'Create'),
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

class _ManageSplitsDialog extends StatelessWidget {
  final BuildContext hostContext;

  const _ManageSplitsDialog({required this.hostContext});

  @override
  Widget build(BuildContext context) {
    return Consumer<SplitProvider>(
      builder: (context, provider, _) {
        final accent = accentColor(context);
        final textSecondary = textSecondaryColor(context);
        return Dialog(
          backgroundColor: surfaceColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: borderColor(context)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage splits',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(color: accent),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${provider.splits.length} of ${SplitProvider.maxSplits} workspaces',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final split in provider.splits) ...[
                            _ManageSplitRow(
                              split: split,
                              isActive: split.id == provider.activeSplitId,
                              canDelete: provider.splits.length > 1,
                              onRename:
                                  () => showDialog<void>(
                                    context: context,
                                    builder:
                                        (_) => _SplitNameDialog(
                                          hostContext: hostContext,
                                          split: split,
                                        ),
                                  ),
                              onDelete:
                                  () => showDialog<void>(
                                    context: context,
                                    builder:
                                        (_) => _DeleteSplitDialog(
                                          hostContext: hostContext,
                                          split: split,
                                        ),
                                  ),
                            ),
                            if (split != provider.splits.last)
                              const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ManageSplitRow extends StatelessWidget {
  final gym.Split split;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ManageSplitRow({
    required this.split,
    required this.isActive,
    required this.canDelete,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final border = borderColor(context);
    final textPrimary = textPrimaryColor(context);
    return Container(
      decoration: BoxDecoration(
        color: isActive ? accentMutedColor(context) : backgroundColor(context),
        border: Border.all(color: isActive ? accent : border),
        borderRadius: AppRadius.button,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: isActive ? accent : border,
              borderRadius: AppRadius.micro,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  split.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: textPrimary),
                ),
                if (isActive)
                  Text(
                    'Active',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: accent),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Rename ${split.name}',
            onPressed: onRename,
            icon: Icon(LucideIcons.pencil, size: 17, color: textPrimary),
          ),
          IconButton(
            tooltip:
                canDelete
                    ? 'Delete ${split.name}'
                    : 'The last split cannot be deleted',
            onPressed: canDelete ? onDelete : null,
            icon: Icon(
              LucideIcons.trash2,
              size: 17,
              color: errorColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteSplitDialog extends StatefulWidget {
  final BuildContext hostContext;
  final gym.Split split;

  const _DeleteSplitDialog({required this.hostContext, required this.split});

  @override
  State<_DeleteSplitDialog> createState() => _DeleteSplitDialogState();
}

class _DeleteSplitDialogState extends State<_DeleteSplitDialog> {
  String? _replacementId;
  String? _error;
  bool _deleting = false;

  Future<void> _delete(SplitProvider provider, bool isActive) async {
    final hostContext = widget.hostContext;
    final replacement = isActive ? _replacementId : provider.activeSplitId;
    if (replacement == null) {
      setState(() => _error = 'Select the split to use next.');
      return;
    }
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await provider.deleteSplit(widget.split.id, replacement);
      if (!mounted || !hostContext.mounted) return;
      Navigator.pop(context);
      _showSuccess(hostContext, 'Split permanently deleted');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SplitProvider>();
    final isActive = provider.activeSplitId == widget.split.id;
    final replacements =
        provider.splits.where((split) => split.id != widget.split.id).toList();
    final usage = provider.usageFor(widget.split.id);
    final error = errorColor(context);
    final textSecondary = textSecondaryColor(context);

    return Dialog(
      backgroundColor: surfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: borderColor(context)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete split?',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: error),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Deleting ${widget.split.name} removes ${usage.plans} '
                '${usage.plans == 1 ? 'plan' : 'plans'} and ${usage.sessions} '
                '${usage.sessions == 1 ? 'session' : 'sessions'}. '
                'This cannot be undone.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: textSecondary,
                ),
              ),
              if (isActive) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Select replacement',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final split in replacements) ...[
                  _ReplacementRow(
                    split: split,
                    selected: split.id == _replacementId,
                    onTap:
                        () => setState(() {
                          _replacementId = split.id;
                          _error = null;
                        }),
                  ),
                  if (split != replacements.last)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _deleting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed:
                        _deleting || (isActive && _replacementId == null)
                            ? null
                            : () => _delete(provider, isActive),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: error,
                      foregroundColor: onColor(error),
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.button,
                      ),
                    ),
                    child: const Text('Delete'),
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

class _ReplacementRow extends StatelessWidget {
  final gym.Split split;
  final bool selected;
  final VoidCallback onTap;

  const _ReplacementRow({
    required this.split,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    return Semantics(
      label: 'Use ${split.name} next',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color:
                selected ? accentMutedColor(context) : backgroundColor(context),
            border: Border.all(color: selected ? accent : borderColor(context)),
            borderRadius: AppRadius.button,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  split.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textPrimaryColor(context),
                  ),
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 18, color: accent)
              else
                Text(
                  'Select',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: textSecondaryColor(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showSuccess(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: onAccentColor(context)),
      ),
      backgroundColor: accentFillColor(context),
    ),
  );
}

String _friendlyError(Object error) {
  if (error is ArgumentError && error.message != null) {
    return error.message.toString();
  }
  if (error is StateError) return error.message;
  return 'Could not update splits. Try again.';
}
