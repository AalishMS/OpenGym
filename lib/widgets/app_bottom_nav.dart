import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
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
    final label = Theme.of(context).textTheme.labelSmall;

    final slots = _labels.length;
    final selected = currentIndex.clamp(0, slots - 1);

    final bar = NavigationBarTheme(
      data: NavigationBarThemeData(
        height: 68,
        backgroundColor: backgroundColor(context),
        indicatorColor: Colors.transparent,
        // Colour and weight come from each destination's [_Selection], which
        // eases them in step with the rule; the bar itself would snap them.
        labelTextStyle: const WidgetStatePropertyAll(TextStyle()),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
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
              child: _Selection(
                selected: i == selected,
                selectedColor: accent,
                unselectedColor: textSecondary,
                selectedLabel: label?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabel: label?.copyWith(
                  color: textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                child: NavigationDestination(
                  icon: _Badge(
                    visible: badgedIndex == i,
                    child: Icon(_icons[i]),
                  ),
                  label: _labels[i],
                ),
              ),
            ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: hairlineColor(context))),
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
                duration: AppMotion.of(context, AppMotion.standard),
                curve: AppMotion.curve,
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

/// Eases one destination's icon and label colour and label weight between
/// selected and not, over the same [AppMotion.standard] and curve as the rule
/// sliding above it, so the whole selection moves as one. It starts at rest,
/// so the bar never animates on arrival. The bar's own theme leaves colour
/// and weight unset, so these inherited values are what paint.
class _Selection extends StatelessWidget {
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final TextStyle? selectedLabel;
  final TextStyle? unselectedLabel;
  final Widget child;

  const _Selection({
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.selectedLabel,
    required this.unselectedLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.curve,
      child: child,
      builder:
          (context, t, child) => IconTheme.merge(
            data: IconThemeData(
              color: Color.lerp(unselectedColor, selectedColor, t),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle.lerp(unselectedLabel, selectedLabel, t),
              child: child!,
            ),
          ),
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
