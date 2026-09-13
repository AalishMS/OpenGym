import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'app_wordmark.dart';

/// Desktop sidebar navigation with the same destinations as [AppBottomNav].
class AppNavRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppNavRail({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  static const _icons = [
    LucideIcons.layoutDashboard,
    LucideIcons.clipboardList,
    LucideIcons.history,
    LucideIcons.trendingUp,
    LucideIcons.settings2,
  ];

  static const _labels = ['Dashboard', 'Plans', 'History', 'Stats', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);

    return SizedBox(
      width: 180,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: borderColor(context))),
        ),
        child: NavigationRail(
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,
          extended: true,
          minExtendedWidth: 180,
          backgroundColor: surfaceColor(context),
          indicatorColor: accent.withAlpha(20),
          selectedIconTheme: IconThemeData(color: accent, size: 16),
          unselectedIconTheme: IconThemeData(color: textSecondary, size: 16),
          selectedLabelTextStyle: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: accent, fontWeight: FontWeight.bold),
          unselectedLabelTextStyle: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: textSecondary),
          leading: const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 22),
            child: AppWordmark(fontSize: 15),
          ),
          destinations: [
            for (var i = 0; i < _labels.length; i++)
              NavigationRailDestination(
                icon: Icon(_icons[i]),
                label: Text(_labels[i]),
              ),
          ],
        ),
      ),
    );
  }
}
