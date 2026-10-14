import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/spacing.dart';

/// A saved figure that can be read but not changed, such as a logged set's
/// weight or reps.
///
/// It has no ground and no border on purpose: anything with a ground in this
/// app reads as tappable, so a read-only value is a plain bold figure. Put it
/// in a table ruled with square single-edge hairlines so it reads as a record.
class ReadOnlyValue extends StatelessWidget {
  final String text;

  /// What the value is, for example *Set 1 weight*.
  final String? semanticsLabel;

  /// The spoken value. Defaults to [text], which can be too terse to say alone
  /// (a weight without its unit, say).
  final String? semanticsValue;

  /// Drawn after the figure, for example a PR badge.
  final Widget? trailing;

  const ReadOnlyValue(
    this.text, {
    this.semanticsLabel,
    this.semanticsValue,
    this.trailing,
    super.key,
  });

  static TextStyle style(BuildContext context) => AppTypography.figures(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: textPrimaryColor(context),
  );

  @override
  Widget build(BuildContext context) {
    final figure = Text(text, style: style(context));
    return Semantics(
      label: semanticsLabel,
      value: semanticsValue ?? text,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.all(AppSpacing.xs),
        alignment: Alignment.center,
        child:
            trailing == null
                ? figure
                : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    figure,
                    const SizedBox(width: AppSpacing.xs),
                    trailing!,
                  ],
                ),
      ),
    );
  }
}
