import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/app_header.dart';

Future<void> exportTrainingSafetyCopy(String? path) async {
  if (path == null) throw StateError('A safety copy is not available yet.');
  await Share.shareXFiles([
    XFile(path),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppHeader(
      title: Text('Data recovery'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your training data needs recovery',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Retry preparation, or export the safety copy before trying again.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : () => _run(widget.onRetry),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _run(widget.onExport),
                child: const Text('Export safety copy'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
