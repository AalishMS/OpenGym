import 'package:flutter/material.dart';

import '../../theme/radii.dart';

class ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  const ArrowButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.badge,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.badge,
        splashColor: accent.withValues(alpha: 0.2),
        highlightColor: accent.withValues(alpha: 0.1),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(
                color: Theme.of(context).colorScheme.outline, width: 1),
            borderRadius: AppRadius.badge,
          ),
          child: Icon(icon,
              size: 16, color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}
