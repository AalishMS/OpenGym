import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/set.dart' as gym;
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/semantic_colors.dart';
import '../../utils/format.dart';

class SetRow extends StatelessWidget {
  final int setIndex;
  final gym.Set set;
  final int exerciseIndex;
  final Color accent;
  final VoidCallback onDecrementReps;
  final VoidCallback onIncrementReps;
  final VoidCallback onDecrementWeight;
  final VoidCallback onIncrementWeight;
  final VoidCallback onEdit;

  const SetRow({
    super.key,
    required this.setIndex,
    required this.set,
    required this.exerciseIndex,
    required this.accent,
    required this.onDecrementReps,
    required this.onIncrementReps,
    required this.onDecrementWeight,
    required this.onIncrementWeight,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);

    // The set is the reason the screen exists, so the numbers are the loudest
    // thing on it. They used to be 15/w500 under a 14/bold exercise name — a
    // hair larger but visibly lighter, which read as subordinate to the title.
    final numberStyle = GoogleFonts.jetBrainsMono(
      fontSize: 17,
      fontWeight: FontWeight.bold,
      height: 1.1,
      color: textPrimary,
    );
    // The unit and the separator are not data. Dropping them back is what lets
    // `70` and `8` carry the row without needing a bigger size still.
    final unitStyle = GoogleFonts.jetBrainsMono(
      fontSize: 11,
      fontWeight: FontWeight.normal,
      color: textSecondary,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor(context)),
              borderRadius: AppRadius.badge,
            ),
            child: Text(
              '${setIndex + 1}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              splashColor: accent.withValues(alpha: 0.2),
              highlightColor: accent.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                // One datum, one line. Left to wrap, a three-digit weight with
                // an RPE dropped its `@8` onto a second line on a narrow phone
                // and pushed every row below it down. scaleDown gives up a
                // little size in that case instead, and nothing at all on a
                // screen where the run already fits.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    softWrap: false,
                    text: TextSpan(
                      style: numberStyle,
                      children: [
                        TextSpan(text: formatWeight(set.weight)),
                        TextSpan(text: 'kg', style: unitStyle),
                        TextSpan(text: ' x ', style: unitStyle),
                        TextSpan(text: '${set.reps}'),
                        if (set.rpe != null)
                          TextSpan(
                            // An annotation on the set, not a third number.
                            text: ' @${set.rpe}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              color: rpeColor(set.rpe!),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: borderColor(context)),
              borderRadius: AppRadius.control,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ControlButton(
                  label: '−',
                  onTap: onDecrementWeight,
                  accent: accent,
                  borderRadius: AppRadius.leftCap,
                ),
                _ControlButton(
                  label: '+',
                  onTap: onIncrementWeight,
                  accent: accent,
                  borderRadius: AppRadius.rightCap,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: borderColor(context)),
              borderRadius: AppRadius.control,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ControlButton(
                  label: '−',
                  onTap: onDecrementReps,
                  accent: accent,
                  borderRadius: AppRadius.leftCap,
                ),
                _ControlButton(
                  label: '+',
                  onTap: onIncrementReps,
                  accent: accent,
                  borderRadius: AppRadius.rightCap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Width of one stepper box (two 32px buttons + 1px border each side).
/// [SetHeaderRow] uses it to line its labels up with the boxes below.
const double kStepperBoxWidth = 66;

/// `WEIGHT` / `REPS` captions above [SetRow]'s two identical stepper boxes.
///
/// Without these the pair of `− +` boxes is ambiguous — one card-level header
/// disambiguates both columns without repeating on every row.
class SetHeaderRow extends StatelessWidget {
  const SetHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.jetBrainsMono(
      fontSize: 8,
      color: textSecondaryColor(context),
      letterSpacing: 0.1,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Spacer(),
          SizedBox(
            width: kStepperBoxWidth,
            child: Text('WEIGHT', textAlign: TextAlign.center, style: style),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: kStepperBoxWidth,
            child: Text('REPS', textAlign: TextAlign.center, style: style),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accent;

  /// Which outer corners this segment caps off. The two buttons share a square
  /// inner edge so the pair reads as one control, not two pills.
  final BorderRadius? borderRadius;

  const _ControlButton({
    required this.label,
    required this.onTap,
    required this.accent,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: accent.withValues(alpha: 0.2),
        highlightColor: accent.withValues(alpha: 0.1),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 15,
              // A control, not a value: at 16/primary the two stepper boxes
              // were the second-loudest thing in the row, right behind the
              // numbers they adjust. The outline is what marks them tappable.
              color: textSecondaryColor(context),
            ),
          ),
        ),
      ),
    );
  }
}
