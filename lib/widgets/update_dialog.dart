import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/radii.dart';
import 'app_button.dart';

typedef ReleasePageLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchReleasePage(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens the update prompt. Safe to call when one is already on screen.
Future<void> showUpdateDialog(
  BuildContext context, {
  ReleasePageLauncher? openRelease,
}) {
  return showDialog<void>(
    context: context,
    // Downloading is cancellable from inside the dialog, so a stray tap on the
    // barrier must not orphan a download the user can no longer see.
    barrierDismissible: false,
    routeSettings: const RouteSettings(name: '/update'),
    builder: (_) => UpdateDialog(openRelease: openRelease),
  );
}

/// Turns a GitHub release body into a short, readable list for the prompt.
/// Full notes remain available through the release link.
List<String> releaseHighlights(String markdown, {int limit = 4}) {
  if (limit <= 0) return const [];

  final highlights = <String>[];
  for (final rawLine in markdown.split(RegExp(r'\r?\n'))) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    line =
        line
            .replaceFirst(RegExp(r'^[-*+]\s+'), '')
            .replaceFirst(RegExp(r'^\d+[.)]\s+'), '')
            .replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '')
            .replaceAllMapped(
              RegExp(r'\[([^\]]+)\]\([^\)]+\)'),
              (match) => match.group(1)!,
            )
            .replaceAll(RegExp(r'[*_`]'), '')
            .trim();

    if (line.isEmpty || Uri.tryParse(line)?.hasAbsolutePath == true) continue;
    highlights.add(line);
    if (highlights.length == limit) break;
  }
  return highlights;
}

/// The prompt that offers a new release, then shows download and install state.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({this.openRelease, super.key});

  final ReleasePageLauncher? openRelease;

  Future<void> _openRelease(BuildContext context, ReleaseInfo release) async {
    try {
      final opened = await (openRelease ?? _launchReleasePage)(
        release.releasePageUri,
      );
      if (!opened && context.mounted) {
        _showError(context, 'Could not open GitHub. Try again in a moment.');
      }
    } catch (_) {
      if (context.mounted) {
        _showError(context, 'Could not open GitHub. Try again in a moment.');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    final ground = errorColor(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: onColor(ground))),
        backgroundColor: ground,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateProvider>();
    final release = updates.release;
    final status = updates.status;

    // INSTALLATION_DONE and a dismissal both land on idle. Close rather than
    // sit here showing a stale offer.
    if (status == UpdateStatus.idle || release == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = Navigator.of(context, rootNavigator: false);
        if (nav.canPop()) nav.pop();
      });
      return const SizedBox.shrink();
    }

    final failed = status == UpdateStatus.failed;
    final media = MediaQuery.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: surfaceColor(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: borderColor(context), width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: media.size.height - media.viewInsets.vertical - 48,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReleaseHeader(release: release, failed: failed),
              if (failed) ...[
                const SizedBox(height: 20),
                _FailureMessage(
                  message:
                      updates.error ?? 'The update could not be installed.',
                ),
              ] else ...[
                const SizedBox(height: 24),
                _Highlights(changelog: release.changelog),
              ],
              const SizedBox(height: 20),
              Semantics(
                link: true,
                child: SizedBox(
                  width: double.infinity,
                  child: AppButton.secondary(
                    label: 'View release on GitHub',
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    onPressed: () => _openRelease(context, release),
                  ),
                ),
              ),
              if (status == UpdateStatus.downloading ||
                  status == UpdateStatus.installing) ...[
                const SizedBox(height: 20),
                _Progress(status: status, progress: updates.progress),
              ],
              const SizedBox(height: 20),
              _Actions(updates: updates, showError: _showError),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReleaseHeader extends StatelessWidget {
  const _ReleaseHeader({required this.release, required this.failed});

  final ReleaseInfo release;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final error = errorColor(context);
    final size = formatBytes(release.apkSize);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 76,
          decoration: BoxDecoration(
            color: failed ? error : accent,
            borderRadius: AppRadius.micro,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                failed ? 'Update needs attention' : 'A new build is ready',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: failed ? error : textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                failed
                    ? 'Nothing was changed. You can retry when ready.'
                    : 'Update OpenGym to get the latest improvements.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetadataChip(label: release.displayVersion),
                  if (size.isNotEmpty) _MetadataChip(label: size),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.chip,
      ),
      child: Text(
        label,
        style: AppTypography.trainingData(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textSecondaryColor(context),
        ),
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.changelog});

  final String changelog;

  @override
  Widget build(BuildContext context) {
    final highlights = releaseHighlights(changelog);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("What's changed", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (highlights.isEmpty)
          Text(
            'Release notes are available on GitHub.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: textSecondaryColor(context),
            ),
          )
        else
          ...highlights.map(
            (highlight) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: accentColor(context),
                        borderRadius: AppRadius.micro,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      highlight,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FailureMessage extends StatelessWidget {
  const _FailureMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: errorColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: errorColor(context)),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.status, required this.progress});

  final UpdateStatus status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final installing = status == UpdateStatus.installing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                installing ? 'Opening installer' : 'Downloading update',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            if (!installing)
              Text(
                '${(progress * 100).round()}%',
                style: AppTypography.trainingData(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondaryColor(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: AppRadius.micro,
          child: LinearProgressIndicator(
            value: installing ? null : progress,
            minHeight: 5,
            backgroundColor: borderColor(context),
            valueColor: AlwaysStoppedAnimation<Color>(accentColor(context)),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.updates, required this.showError});

  final UpdateProvider updates;
  final void Function(BuildContext context, String message) showError;

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        showError(context, 'The update action failed. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = updates.status;

    // The installer owns the screen from here; offering buttons would invite a
    // second install attempt.
    if (status == UpdateStatus.installing) return const SizedBox.shrink();

    if (status == UpdateStatus.downloading) {
      return Align(
        alignment: Alignment.centerRight,
        child: AppButton.text(
          label: 'Cancel download',
          onPressed: () => _runAction(context, updates.cancelUpdate),
        ),
      );
    }

    final failed = status == UpdateStatus.failed;
    return Row(
      children: [
        Expanded(
          child: AppButton.text(
            label: failed ? 'Close' : 'Later',
            onPressed: () {
              Navigator.pop(context);
              updates.dismiss();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppButton.primary(
            label: failed ? 'Try again' : 'Update now',
            onPressed: () => _runAction(context, updates.startUpdate),
          ),
        ),
      ],
    );
  }
}
