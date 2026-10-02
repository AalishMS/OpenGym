import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import 'guided_tour.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Map<int, GlobalKey> destinationKeys;
  const AppBottomNav({
    required this.currentIndex,
    required this.onTap,
    this.destinationKeys = const {},
    super.key,
  });

  static const _icons = [
    LucideIcons.house,
    LucideIcons.history,
    LucideIcons.trendingUp,
    LucideIcons.settings2,
  ];

  static const _labels = ['Home', 'History', 'Stats', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 68,
          backgroundColor: backgroundColor(context),
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? accent : textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 18,
              color: selected ? accent : textSecondary,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (var i = 0; i < _labels.length; i++)
              GuidedTourTarget(
                key: destinationKeys[i],
                // Enclose the icon and label without outlining the entire
                // edge-to-edge navigation slot or its system safe area.
                padding: const EdgeInsets.symmetric(
                  horizontal: -AppSpacing.sm,
                  vertical: -AppSpacing.xs,
                ),
                borderRadius: AppRadius.button,
                child: NavigationDestination(
                  icon: Icon(_icons[i]),
                  label: _labels[i],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
