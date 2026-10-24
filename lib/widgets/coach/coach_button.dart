import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/coach_provider.dart';
import '../../screens/coach_screen.dart';
import '../../services/coach/coach_disclosure.dart';
import '../../theme/app_theme.dart';
import 'coach_disclosure_sheet.dart';

/// Lets the app shell show the Coach inside the Home tab, so the navigation
/// stays on screen. Without a host, the Coach opens as a pushed route.
class CoachHost extends InheritedWidget {
  final VoidCallback open;

  const CoachHost({required this.open, required super.child, super.key});

  static CoachHost? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CoachHost>();

  @override
  bool updateShouldNotify(CoachHost oldWidget) => false;
}

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
  final host = CoachHost.maybeOf(context);
  if (host != null) return host.open();
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

    return Semantics(
      label: 'Coach',
      button: true,
      child: Tooltip(
        message: 'Coach',
        excludeFromSemantics: true,
        child: InkWell(
          key: const ValueKey('coach-button'),
          onTap: () => openCoach(context),
          customBorder: const CircleBorder(),
          splashColor: accent.withAlpha(36),
          highlightColor: accent.withAlpha(18),
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentMutedColor(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.messageSquareText,
                  size: 19,
                  color: accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
