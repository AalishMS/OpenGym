import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'app_wordmark.dart';

/// Desktop sidebar navigation. The active item uses a restrained accent rail
/// and quiet tint while preserving the same destinations as [AppBottomNav].
class AppNavRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double width;

  const AppNavRail({
    required this.currentIndex,
    required this.onTap,
    this.width = 180,
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

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(right: BorderSide(color: borderColor(context))),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 22, 16, 22),
              child: AppWordmark(fontSize: 15),
            ),
            for (int i = 0; i < _labels.length; i++)
              _RailItem(
                icon: _icons[i],
                label: _labels[i],
                active: i == currentIndex,
                accent: accent,
                inactiveColor: textSecondary,
                onTap: () => onTap(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : inactiveColor;
    return Semantics(
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: active ? accent.withAlpha(20) : null,
            border: Border(
              left: BorderSide(
                color: active ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
