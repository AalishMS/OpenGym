import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// The shared frame every dashboard tile sits in: 1px hairline box, a
/// `> TITLE` header separated by a rule, and an optional muted caption on the
/// right of the header.
class DashboardPanel extends StatelessWidget {
  final String title;
  final Widget child;

  /// Small right-aligned caption in the header (e.g. a count or range).
  final String? caption;

  /// Interactive header affordance (e.g. `[RESUME]`), placed after [caption].
  final Widget? action;

  const DashboardPanel({
    required this.title,
    required this.child,
    this.caption,
    this.action,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderColor(context);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: border, width: 1),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '> $title',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor(context),
                      letterSpacing: 0.06,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: textSecondaryColor(context),
                      letterSpacing: 0.06,
                    ),
                  ),
                if (action != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  action!,
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Placeholder line for a panel with nothing to show yet.
class DashboardEmptyLine extends StatelessWidget {
  final String message;

  const DashboardEmptyLine(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        color: textSecondaryColor(context),
      ),
    );
  }
}
