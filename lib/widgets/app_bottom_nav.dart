import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav({required this.currentIndex, required this.onTap, super.key});

  static const _icons = [
    LucideIcons.clipboardList,
    LucideIcons.history,
    LucideIcons.trendingUp,
    LucideIcons.settings2,
  ];

  static const _labels = ['PLANS', 'HISTORY', 'STATS', 'SETTINGS'];

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(4, (i) {
            final active = i == currentIndex;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icons[i], size: 18, color: active ? accent : textSecondary),
                      const SizedBox(height: 3),
                      Text(
                        _labels[i],
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          letterSpacing: 0.08,
                          color: active ? accent : textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
