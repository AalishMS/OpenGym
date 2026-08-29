import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';

/// Opens the update prompt. Safe to call when one is already on screen.
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    // Downloading is cancellable from inside the dialog, so a stray tap on the
    // barrier must not orphan a download the user can no longer see.
    barrierDismissible: false,
    routeSettings: const RouteSettings(name: '/update'),
    builder: (_) => const UpdateDialog(),
  );
}

/// The prompt that offers a new release, then shows the download.
///
/// One dialog covers offer → download → install → failure so the user never
/// watches a dialog vanish and another appear in its place.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateProvider>();
    final accent = accentColor(context);
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final error = errorColor(context);

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
    final size = formatBytes(release.apkSize);

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed ? 'Update failed' : 'Update available',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: failed ? error : accent),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    release.displayVersion,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ),
                if (size.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    size,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            if (failed) ...[
              const SizedBox(height: 12),
              Text(
                updates.error ?? 'The update could not be installed.',
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: error),
              ),
            ] else if (release.changelog.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Changelog(
                text: release.changelog,
                border: border,
                textSecondary: textSecondary,
              ),
            ],
            if (status == UpdateStatus.downloading ||
                status == UpdateStatus.installing) ...[
              const SizedBox(height: 16),
              _Progress(
                status: status,
                progress: updates.progress,
                accent: accent,
                border: border,
                textSecondary: textSecondary,
              ),
            ],
            const SizedBox(height: 16),
            _Actions(
              updates: updates,
              accent: accent,
              textSecondary: textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The release body, rendered as plain monospace text.
///
/// GitHub sends markdown, but the app has no markdown renderer and the terminal
/// aesthetic reads `- item` lists correctly as-is. Height is capped so a chatty
/// release note cannot push the buttons off screen.
class _Changelog extends StatelessWidget {
  const _Changelog({
    required this.text,
    required this.border,
    required this.textSecondary,
  });

  final String text;
  final Color border;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: border, width: 1),
        borderRadius: AppRadius.card,
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            height: 1.5,
            color: textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.status,
    required this.progress,
    required this.accent,
    required this.border,
    required this.textSecondary,
  });

  final UpdateStatus status;
  final double progress;
  final Color accent;
  final Color border;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final installing = status == UpdateStatus.installing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppRadius.micro,
          child: LinearProgressIndicator(
            // Indeterminate while the installer is in charge: there is no
            // percentage to report and a frozen bar would look stalled.
            value: installing ? null : progress,
            minHeight: 4,
            backgroundColor: border,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          installing
              ? 'Opening the installer...'
              : 'Downloading... ${(progress * 100).round()}%',
          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: textSecondary),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.updates,
    required this.accent,
    required this.textSecondary,
  });

  final UpdateProvider updates;
  final Color accent;
  final Color textSecondary;

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '> Update action failed: $e',
            style: GoogleFonts.jetBrainsMono(
              color: onColor(errorColor(context)),
            ),
          ),
          backgroundColor: errorColor(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = updates.status;

    // The installer owns the screen from here; offering buttons would only
    // invite a second install attempt.
    if (status == UpdateStatus.installing) {
      return const SizedBox.shrink();
    }

    if (status == UpdateStatus.downloading) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => _runAction(context, updates.cancelUpdate),
          child: Text(
            '[CANCEL]',
            style: GoogleFonts.jetBrainsMono(color: textSecondary),
          ),
        ),
      );
    }

    final failed = status == UpdateStatus.failed;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            updates.dismiss();
          },
          child: Text(
            failed ? '[CLOSE]' : '[LATER]',
            style: GoogleFonts.jetBrainsMono(color: textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => _runAction(context, updates.startUpdate),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentFillColor(context),
            foregroundColor: onAccentColor(context),
          ),
          child: Text(
            failed ? '[RETRY]' : '[UPDATE]',
            style: GoogleFonts.jetBrainsMono(),
          ),
        ),
      ],
    );
  }
}
