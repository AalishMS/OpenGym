import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/coach_provider.dart';
import '../../screens/coach_screen.dart';
import '../../services/coach/coach_disclosure.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'coach_disclosure_sheet.dart';

/// Opens the Coach, asking for the first-use disclosure once per user and
/// disclosure version.
Future<void> openCoach(BuildContext context) async {
  final userId = context.read<CoachProvider>().userId;
  if (userId == null) return;
  if (!await CoachDisclosure.isAccepted(userId)) {
    if (!context.mounted) return;
    if (!await showCoachDisclosureSheet(context)) return;
    await CoachDisclosure.accept(userId);
  }
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const CoachScreen()));
}

/// The Home header's entry point. Hidden in offline-only builds and while
/// signed out.
class CoachButton extends StatelessWidget {
  const CoachButton({super.key});

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider?>();
    if (coach == null || !coach.available) return const SizedBox.shrink();
    final accent = accentColor(context);

    return Tooltip(
      message: 'Ask the Coach to build or change your plans',
      child: InkWell(
        key: const ValueKey('coach-button'),
        onTap: () => openCoach(context),
        borderRadius: AppRadius.control,
        splashColor: accent.withAlpha(36),
        highlightColor: accent.withAlpha(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            heightFactor: 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: raisedSurfaceColor(context),
                border: Border.all(color: borderColor(context)),
                borderRadius: AppRadius.control,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.sparkles, size: 16, color: accent),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Coach',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: textPrimaryColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
