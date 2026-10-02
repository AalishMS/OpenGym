import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'action_progress.dart';

/// Holds confirmation and retry state until the mutation has persisted.
class PersistenceDialog extends StatefulWidget {
  const PersistenceDialog({
    required this.title,
    required this.content,
    required this.actionLabel,
    required this.progressLabel,
    required this.failureMessage,
    required this.onPersist,
    this.destructive = false,
    this.startImmediately = false,
    super.key,
  });

  final String title;
  final Widget content;
  final String actionLabel;
  final String progressLabel;
  final String failureMessage;
  final Future<void> Function() onPersist;
  final bool destructive;
  final bool startImmediately;

  @override
  State<PersistenceDialog> createState() => _PersistenceDialogState();
}

class _PersistenceDialogState extends State<PersistenceDialog> {
  bool _busy = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _persist();
      });
    }
  }

  Future<void> _persist() async {
    if (_busy || _saved) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPersist();
      if (!mounted) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      // Let PopScope publish its updated canPop before dismissing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (error) {
      debugPrint('${widget.progressLabel} failed: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.failureMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.content,
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: errorColor(context)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _busy || _saved ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy || _saved ? null : _persist,
            style:
                widget.destructive
                    ? FilledButton.styleFrom(
                      backgroundColor: errorColor(context),
                      foregroundColor: onColor(errorColor(context)),
                    )
                    : null,
            child:
                _busy
                    ? ActionProgress(widget.progressLabel)
                    : Text(widget.actionLabel),
          ),
        ],
      ),
    );
  }
}
