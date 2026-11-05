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

  /// The destination that carries an attention dot, such as Settings while an
  /// update is waiting.
  final int? badgedIndex;
  const AppBottomNav({
    required this.currentIndex,
    required this.onTap,
    this.destinationKeys = const {},
    this.badgedIndex,
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

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final slots = _labels.length;
    final selected = currentIndex.clamp(0, slots - 1);

    final bar = NavigationBarTheme(
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
            size: 22,
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
                icon: Badge(
                  isLabelVisible: badgedIndex == i,
                  smallSize: 7,
                  backgroundColor: accentFillColor(context),
                  child: Icon(_icons[i]),
                ),
                label: _labels[i],
              ),
            ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: Stack(
        children: [
          bar,
          // A short accent rule riding the top hairline marks the selected
          // tab, so selection never rests on colour alone. Directional, so it
          // follows the destinations in right-to-left layouts too.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedAlign(
                key: const ValueKey('bottom-nav-indicator'),
                duration:
                    reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: AlignmentDirectional(
                  slots == 1 ? 0 : -1 + 2 * selected / (slots - 1),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / slots,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: AppRadius.micro,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
