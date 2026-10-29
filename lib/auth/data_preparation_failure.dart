import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../services/training_recovery_snapshots.dart';
import '../theme/app_theme.dart';
import '../theme/spacing.dart';
import '../widgets/action_progress.dart';
import '../widgets/app_header.dart';

Future<XFile> trainingSafetyCopyFile(String? path) async {
  if (path == null) throw StateError('A safety copy is not available yet.');
  return XFile.fromData(
    Uint8List.fromList(utf8.encode(await TrainingRecoverySnapshots.read(path))),
    mimeType: 'application/json',
    name: 'opengym-training-safety.json',
  );
}

Future<void> exportTrainingSafetyCopy(String? path) async {
  await Share.shareXFiles([
    await trainingSafetyCopyFile(path),
  ], subject: 'OpenGym training safety copy');
}

/// Failed preparation never falls through into a partially migrated logger.
class DataPreparationFailure extends StatefulWidget {
  final Future<void> Function() onRetry;
  final Future<void> Function() onExport;

  const DataPreparationFailure({
    required this.onRetry,
    required this.onExport,
    super.key,
  });

  @override
  State<DataPreparationFailure> createState() => _DataPreparationFailureState();
}

class _DataPreparationFailureState extends State<DataPreparationFailure> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not finish. Your saved data is still on this device.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = accentColor(context);
    return Scaffold(
      appBar: const AppHeader(
        title: Text('Data recovery'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accentMutedColor(context),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Icon(
                          LucideIcons.databaseBackup,
                          size: 32,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Your training data needs recovery',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'OpenGym could not finish preparing your workouts. '
                    'Nothing has been deleted. Try again, or export a '
                    'safety copy first.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: textSecondaryColor(context),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ElevatedButton(
                    onPressed: _busy ? null : () => _run(widget.onRetry),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onExport),
                    icon: const Icon(LucideIcons.download, size: 18),
                    label: const Text('Export safety copy'),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const Center(child: ActionProgress('Working')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
