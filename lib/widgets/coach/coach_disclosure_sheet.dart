import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// First-use disclosure. Resolves to true only when the user confirmed their
/// age and chose `Continue`.
Future<bool> showCoachDisclosureSheet(BuildContext context) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: surfaceColor(context),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    isScrollControlled: true,
    builder: (_) => const CoachDisclosureSheet(),
  );
  return accepted ?? false;
}

class CoachDisclosureSheet extends StatefulWidget {
  const CoachDisclosureSheet({super.key});

  @override
  State<CoachDisclosureSheet> createState() => _CoachDisclosureSheetState();
}

class _CoachDisclosureSheetState extends State<CoachDisclosureSheet> {
  bool _adult = false;

  static const List<String> _points = [
    'The Coach sees this split\'s plans and a summary of your recent '
        'training. It doesn\'t see your workout or set notes.',
    'Google processes what you send to answer it.',
    'During this free test, Google may use what you send to improve its '
        'products, and people at Google may read it. Don\'t include personal '
        'details in your messages.',
    'The Coach isn\'t medical advice. Stop if something hurts, and see a '
        'professional for pain that is sharp or doesn\'t go away.',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primary = textPrimaryColor(context);
    final secondary = textSecondaryColor(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Before you use the Coach',
                style: textTheme.titleLarge?.copyWith(color: primary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final point in _points)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        '•',
                        style: textTheme.bodyMedium?.copyWith(
                          color: accentColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        point,
                        style: textTheme.bodyMedium?.copyWith(color: secondary),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            CheckboxListTile(
              key: const ValueKey('coach-age-checkbox'),
              value: _adult,
              onChanged: (value) => setState(() => _adult = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: accentFillColor(context),
              checkColor: onAccentColor(context),
              checkboxShape: const RoundedRectangleBorder(
                borderRadius: AppRadius.badge,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.button,
              ),
              title: Text(
                "I'm 18 or older",
                style: textTheme.bodyLarge?.copyWith(color: primary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _adult ? () => Navigator.of(context).pop(true) : null,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
