import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import 'raised_card.dart';

/// An app-wide notice that floats over the top of the screen instead of
/// pushing every screen down.
///
/// It sits above the Navigator, so it is the thing on top and takes the dialog
/// radius. A raised card with a tinted icon badge, a short title and an
/// optional quieter detail line. It closes with its button or a swipe up; an
/// informational notice passes [autoDismissAfter] and leaves on its own, unless
/// a screen reader is navigating, where a notice that vanishes may never be
/// reached (the same rule [SnackBar] follows).
class FloatingNotice extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? detail;

  /// Tints the badge with the error tone instead of the accent.
  final bool isError;

  /// Called once, however the notice is closed: the button, a swipe, or the
  /// [autoDismissAfter] timer.
  final VoidCallback onDismiss;

  /// Closes the notice after this long. Null keeps it until the user closes
  /// it.
  final Duration? autoDismissAfter;

  const FloatingNotice({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.isError = false,
    required this.onDismiss,
    this.autoDismissAfter,
  });

  @override
  State<FloatingNotice> createState() => _FloatingNoticeState();
}

class _FloatingNoticeState extends State<FloatingNotice> {
  Timer? _autoDismiss;
  bool _dismissed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleAutoDismiss();
  }

  @override
  void didUpdateWidget(FloatingNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoDismissAfter != widget.autoDismissAfter) {
      _autoDismiss?.cancel();
      _autoDismiss = null;
      _scheduleAutoDismiss();
    }
  }

  void _scheduleAutoDismiss() {
    final after = widget.autoDismissAfter;
    if (after == null || MediaQuery.accessibleNavigationOf(context)) {
      _autoDismiss?.cancel();
      _autoDismiss = null;
      return;
    }
    _autoDismiss ??= Timer(after, _dismiss);
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _autoDismiss?.cancel();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final badgeGround =
        widget.isError ? controlFillColor(context) : accentMutedColor(context);
    final badgeInk =
        widget.isError ? errorColor(context) : accentOnMutedColor(context);
    final detail = widget.detail;

    return Dismissible(
      key: const ValueKey('floating-notice'),
      direction: DismissDirection.up,
      // The host removes the notice; no collapse animation is left to run.
      resizeDuration: null,
      onDismissed: (_) => _dismiss(),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: DecoratedBox(
          decoration: raisedDecoration(context, borderRadius: AppRadius.dialog),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: badgeGround,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 36,
                      child: Icon(widget.icon, size: 18, color: badgeInk),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: textTheme.titleMedium?.copyWith(
                            color: textPrimaryColor(context),
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (detail != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            detail,
                            style: textTheme.bodySmall?.copyWith(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: _dismiss,
                    icon: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: textSecondaryColor(context),
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

/// Where a [FloatingNotice] sits: just under the status bar, centred, and no
/// wider than a phone so it stays a card on tablets. Slides down and fades in,
/// and back out when [notice] goes null.
class FloatingNoticeHost extends StatelessWidget {
  final Widget? notice;

  const FloatingNoticeHost({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: AnimatedSwitcher(
              duration:
                  reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
              reverseDuration:
                  reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder:
                  (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, if (current != null) current],
                  ),
              transitionBuilder:
                  (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, -0.35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: ScaleTransition(
                        scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                    ),
                  ),
              child: notice,
            ),
          ),
        ),
      ),
    );
  }
}
