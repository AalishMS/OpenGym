import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/set.dart' as gym;
import '../../models/set_template.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/semantic_colors.dart';
import '../../utils/format.dart';

/// The set value's number style — the `70` and `8` in `70kg x 8`.
///
/// The set is the reason the workout screen exists, so the numbers are the
/// loudest thing on it. They used to be 15/w500 under a 14/bold exercise name —
/// a hair larger but visibly lighter, which read as subordinate to the title.
///
/// Shared with the plan editor so a prescribed set and a logged set are set in
/// the same voice. Changing it here changes both screens, which is the point:
/// the two used to drift.
TextStyle setValueStyle(BuildContext context) => GoogleFonts.jetBrainsMono(
      fontSize: 17,
      fontWeight: FontWeight.bold,
      height: 1.1,
      color: textPrimaryColor(context),
    );

/// The units and separators sitting around [setValueStyle] — `kg`, ` x `, and
/// the plan's target hint.
///
/// These are not data. Dropping them back is what lets `70` and `8` carry the
/// row without needing a bigger size still.
TextStyle setUnitStyle(BuildContext context) => GoogleFonts.jetBrainsMono(
      fontSize: 11,
      fontWeight: FontWeight.normal,
      color: textSecondaryColor(context),
    );

/// One `− +` stepper: two buttons sharing a square inner edge inside a single
/// hairline box, so the pair reads as one control rather than two pills.
///
/// Both the workout screen and the plan editor build their weight and reps
/// columns out of these. The box measures [kStepperBoxWidth], which is what lets
/// [SetHeaderRow] line its captions up with the boxes below.
class StepperBox extends StatelessWidget {
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final Color accent;

  const StepperBox({
    super.key,
    required this.onDecrement,
    required this.onIncrement,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.control,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            label: '−',
            onTap: onDecrement,
            accent: accent,
            borderRadius: AppRadius.leftCap,
          ),
          _ControlButton(
            label: '+',
            onTap: onIncrement,
            accent: accent,
            borderRadius: AppRadius.rightCap,
          ),
        ],
      ),
    );
  }
}

class SetRow extends StatelessWidget {
  final int setIndex;
  final gym.Set set;
  final int exerciseIndex;
  final Color accent;

  /// The plan's prescribed reps/weight for this set, if the plan has one.
  ///
  /// Rendered as a dim hint *beside* the live value while the set is untouched,
  /// and never written into the session — a planned weight must not become a PR
  /// or count towards volume.
  final SetTemplate? target;

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
    this.target,
    required this.onDecrementReps,
    required this.onIncrementReps,
    required this.onDecrementWeight,
    required this.onIncrementWeight,
    required this.onEdit,
  });

  /// The hint text, or null when there is nothing worth hinting at — no target,
  /// an empty target, or a set the user has already put a number on.
  ///
  /// Because it only shows on an untouched set, it can never share the row with
  /// a three-digit weight or an RPE: the live half is always the shortest it
  /// gets (`0kg x 0`), so the hint cannot be what forces [FittedBox] to shrink
  /// the numbers.
  String? get _targetHint {
    final t = target;
    if (t == null) return null;
    if (set.weight != 0 || set.reps != 0) return null;
    if (t.weight == 0 && t.reps == 0) return null;
    if (t.weight == 0) return '  → ${t.reps} reps';
    return '  → ${formatWeight(t.weight)}×${t.reps}';
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryColor(context);
    final numberStyle = setValueStyle(context);
    final unitStyle = setUnitStyle(context);
    final hint = _targetHint;

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
                        if (hint != null)
                          TextSpan(text: hint, style: unitStyle),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          StepperBox(
            onDecrement: onDecrementWeight,
            onIncrement: onIncrementWeight,
            accent: accent,
          ),
          const SizedBox(width: 4),
          StepperBox(
            onDecrement: onDecrementReps,
            onIncrement: onIncrementReps,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

/// Width of one stepper box (two 32px buttons + 1px border each side).
/// [SetHeaderRow] uses it to line its labels up with the boxes below.
const double kStepperBoxWidth = 66;

/// `WEIGHT` / `REPS` captions above the pair of [StepperBox]es in a set row.
///
/// Without these the two identical `− +` boxes are ambiguous — one card-level
/// header disambiguates both columns without repeating on every row.
class SetHeaderRow extends StatelessWidget {
  /// Width of the trailing column the rows below reserve past the second
  /// stepper, if any. The plan editor's rows end in a 28px delete button; the
  /// header has to reserve the same width or its captions sit 28px right of the
  /// boxes they label.
  final double trailingGap;

  const SetHeaderRow({super.key, this.trailingGap = 0});

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
          if (trailingGap > 0) SizedBox(width: trailingGap),
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
