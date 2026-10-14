import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// The standard header for every screen except Home.
///
/// A thin wrapper around [AppBar]: the look (page-colour ground, permanent
/// bottom hairline, no tint on scroll, neutral back, accent actions) comes
/// from `AppBarTheme`, so don't override colours here.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;
  final double? titleSpacing;
  final PreferredSizeWidget? bottom;

  const AppHeader({
    this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
    this.titleSpacing,
    this.bottom,
    super.key,
  });

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
      bottom: bottom,
    );
  }
}

/// The one back control: a neutral [LucideIcons.arrowLeft] with a *Back*
/// tooltip. Pass [onPressed] for screens with their own leave flow (unsaved
/// changes, an in-sheet step back); without it, the route is popped.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final bool enabled;

  const AppBackButton({
    this.onPressed,
    this.tooltip = 'Back',
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      color: textPrimaryColor(context),
      icon: const Icon(LucideIcons.arrowLeft),
      onPressed:
          enabled ? (onPressed ?? () => Navigator.maybePop(context)) : null,
    );
  }
}
