import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'app_wordmark.dart';
import 'guided_tour.dart';

/// Desktop sidebar navigation with the same destinations as [AppBottomNav].
class AppNavRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Map<int, GlobalKey> destinationKeys;

  /// The destination that carries an attention dot, such as Settings while an
  /// update is waiting.
  final int? badgedIndex;

  const AppNavRail({
    required this.currentIndex,
    required this.onTap,
    this.destinationKeys = const {},
    this.badgedIndex,
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
    final selectedLabel = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: accent,
      fontWeight: FontWeight.bold,
    );
    final unselectedLabel = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: textSecondary);
    // Keep icon identity stable when the shell rebuilds during the tour.
    final iconKeys = {
      for (final entry in destinationKeys.entries)
        entry.key: GlobalObjectKey(entry.value),
    };

    return SizedBox(
      width: 180,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: hairlineColor(context))),
        ),
        child: NavigationRail(
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,
          extended: true,
          minExtendedWidth: 180,
          backgroundColor: surfaceColor(context),
          indicatorColor: accent.withAlpha(20),
          selectedIconTheme: IconThemeData(color: accent, size: 20),
          unselectedIconTheme: IconThemeData(color: textSecondary, size: 20),
          selectedLabelTextStyle: selectedLabel,
          unselectedLabelTextStyle: unselectedLabel,
          leading: const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 22),
            child: AppWordmark(fontSize: 15),
          ),
          destinations: [
            for (var i = 0; i < _labels.length; i++)
              NavigationRailDestination(
                icon: _Selection(
                  selected: i == currentIndex,
                  builder:
                      (context, t) => IconTheme.merge(
                        data: IconThemeData(
                          color: Color.lerp(textSecondary, accent, t),
                        ),
                        child: _Badge(
                          visible: badgedIndex == i,
                          child: Icon(_icons[i], key: iconKeys[i]),
                        ),
                      ),
                ),
                label: GuidedTourTarget(
                  key: destinationKeys[i],
                  additionalTarget: iconKeys[i],
                  child: _Selection(
                    selected: i == currentIndex,
                    builder:
                        (context, t) => Text(
                          _labels[i],
                          style: TextStyle.lerp(
                            unselectedLabel,
                            selectedLabel,
                            t,
                          ),
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Eases a destination's icon colour, or its label's colour and weight,
/// between selected and not over [AppMotion.standard], in step with the
/// rail's indicator, rather than snapping as the rail would. It starts at
/// rest, so the rail never animates on arrival. The values it paints at rest
/// are the rail's own selected and unselected styles.
class _Selection extends StatelessWidget {
  final bool selected;
  final Widget Function(BuildContext context, double t) builder;

  const _Selection({required this.selected, required this.builder});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.curve,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// The attention dot fades in and out over [AppMotion.quick] rather than
/// popping, keeping the badge's own size and place.
class _Badge extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _Badge({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    final ground = accentFillColor(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.curve,
      child: child,
      builder:
          (context, t, child) => Badge(
            isLabelVisible: t > 0,
            smallSize: 7,
            backgroundColor: ground.withValues(alpha: ground.a * t),
            child: child,
          ),
    );
  }
}
