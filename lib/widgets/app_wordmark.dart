import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// OpenGym's reusable brand signature.
class AppWordmark extends StatelessWidget {
  final double fontSize;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppWordmark({
    this.fontSize = 18,
    this.maxLines,
    this.overflow,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '> OpenGym',
      maxLines: maxLines,
      overflow: overflow,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: accentColor(context),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
