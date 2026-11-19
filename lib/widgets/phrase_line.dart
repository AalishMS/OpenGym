import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Short phrases on one line, separated by middle dots, that wrap only
/// between phrases.
///
/// `5 exercises · 17 sets` never splits a number from its unit at large text,
/// and a break leaves the dot at the end of the line instead of leading the
/// next. The dots are decoration, so screen readers hear only the phrases.
class PhraseLine extends StatelessWidget {
  final List<Widget> phrases;

  /// The style of the dots; usually the phrases' own.
  final TextStyle? style;

  const PhraseLine({required this.phrases, this.style, super.key});

  /// The common case: every phrase is plain text in [style].
  PhraseLine.text(List<String> phrases, {TextStyle? style, Key? key})
    : this(
        phrases: [for (final phrase in phrases) Text(phrase, style: style)],
        style: style,
        key: key,
      );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < phrases.length; index++)
          if (index == phrases.length - 1)
            phrases[index]
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: phrases[index]),
                ExcludeSemantics(child: Text(' · ', style: style)),
              ],
            ),
      ],
    );
  }
}
