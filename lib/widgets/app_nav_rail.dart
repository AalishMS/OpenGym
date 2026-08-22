import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// Desktop sidebar navigation. A custom vertical rail (not Material's
/// [NavigationRail]) so it matches the app's flat terminal look — the active
/// item is marked by a left accent bar + tinted ground rather than Material's
/// rounded indicator pill. Mirrors [AppBottomNav]'s styling.
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

  static const _labels = ['DASHBOARD', 'PLANS', 'HISTORY', 'STATS', 'SETTINGS'];

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<SettingsProvider>().accentColor;
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
              child: Text(
                '> OPENGYM',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: accent,
                  letterSpacing: 0.06,
                ),
              ),
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
    return InkWell(
      onTap: onTap,
      child: Container(
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
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                letterSpacing: 0.08,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
