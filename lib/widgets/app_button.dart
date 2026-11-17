import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';

enum AppButtonKind { primary, tonal, secondary, text, destructive }

/// Shared labelled action with consistent hierarchy and interaction states.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final Widget? icon;
  final Widget? child;

  const AppButton.primary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    super.key,
  }) : kind = AppButtonKind.primary;

  /// The accent's quiet wash with accent ink: a frequent action that should
  /// be findable without competing with the primary one.
  const AppButton.tonal({
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    super.key,
  }) : kind = AppButtonKind.tonal;

  const AppButton.secondary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    super.key,
  }) : kind = AppButtonKind.secondary;

  const AppButton.text({
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    super.key,
  }) : kind = AppButtonKind.text;

  const AppButton.destructive({
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    super.key,
  }) : kind = AppButtonKind.destructive;

  @override
  Widget build(BuildContext context) {
    final content =
        child ??
        (icon == null
            ? Text(label)
            : Row(
              mainAxisSize: MainAxisSize.min,
              children: [icon!, const SizedBox(width: 8), Text(label)],
            ));

    switch (kind) {
      case AppButtonKind.primary:
        return ElevatedButton(onPressed: onPressed, child: content);
      case AppButtonKind.tonal:
        return ElevatedButton(
          onPressed: onPressed,
          style: tonalButtonStyle(context),
          child: content,
        );
      case AppButtonKind.secondary:
        return OutlinedButton(onPressed: onPressed, child: content);
      case AppButtonKind.text:
        return TextButton(onPressed: onPressed, child: content);
      case AppButtonKind.destructive:
        final error = errorColor(context);
        // The secondary ground with error ink: destructive by colour, not by
        // a red box drawn round it.
        return OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: error,
            disabledForegroundColor: textSecondaryColor(context),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return error.withAlpha(31);
              }
              if (states.contains(WidgetState.focused)) {
                return error.withAlpha(26);
              }
              if (states.contains(WidgetState.hovered)) {
                return error.withAlpha(20);
              }
              return null;
            }),
          ),
          child: content,
        );
    }
  }
}

/// The [AppButton.tonal] look, for buttons built directly.
ButtonStyle tonalButtonStyle(BuildContext context) {
  final wash = accentMutedColor(context);
  final ink = accentOnMutedColor(context);
  return ElevatedButton.styleFrom(
    backgroundColor: wash,
    foregroundColor: ink,
    iconColor: ink,
    disabledBackgroundColor: controlFillColor(context),
    disabledForegroundColor: textSecondaryColor(context),
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) return ink.withAlpha(31);
      if (states.contains(WidgetState.focused)) return ink.withAlpha(26);
      if (states.contains(WidgetState.hovered)) return ink.withAlpha(20);
      return null;
    }),
  );
}

/// Compact icon action. A tooltip is required so the control is named for
/// screen readers as well as pointer users.
class AppIconButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const AppIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      color: color,
      icon: Icon(icon),
    );
  }
}
