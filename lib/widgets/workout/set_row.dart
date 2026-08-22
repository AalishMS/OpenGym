import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/set.dart' as gym;
import '../../theme/app_theme.dart';
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
            ),
            child: Text(
              '${setIndex + 1}',
              style: GoogleFonts.jetBrainsMono(fontSize: 9),
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
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: textPrimaryColor(context),
                    ),
                    children: [
                      TextSpan(
                          text: '${formatWeight(set.weight)}kg x ${set.reps}'),
                      if (set.rpe != null)
                        TextSpan(
                          text: ' @${set.rpe}',
                          style: TextStyle(color: rpeColor(set.rpe!)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: borderColor(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ControlButton(
                  label: '−',
                  onTap: onDecrementWeight,
                  accent: accent,
                ),
                _ControlButton(
                  label: '+',
                  onTap: onIncrementWeight,
                  accent: accent,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: borderColor(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ControlButton(
                  label: '−',
                  onTap: onDecrementReps,
                  accent: accent,
                ),
                _ControlButton(
                  label: '+',
                  onTap: onIncrementReps,
                  accent: accent,
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

  const _ControlButton({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.2),
        highlightColor: accent.withValues(alpha: 0.1),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              color: textPrimaryColor(context),
            ),
          ),
        ),
      ),
    );
  }
}
