import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/set.dart' as gym;
import '../../theme/app_theme.dart';

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
                      TextSpan(text: '${set.weight}kg x ${set.reps}'),
                      if (set.rpe != null)
                        TextSpan(
                          text: ' @${set.rpe}',
                          style: TextStyle(color: _rpeColor(set.rpe!)),
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

Color _rpeColor(int rpe) {
  if (rpe <= 2) return Colors.grey;
  if (rpe <= 4) return Colors.lightBlue;
  if (rpe <= 6) return Colors.green;
  if (rpe <= 8) return Colors.amber;
  if (rpe == 9) return Colors.orange;
  return Colors.red;
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
