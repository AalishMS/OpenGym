import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/plan_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';

/// The ten plan colours as swatches, shared by the plan editor and Home's
/// *Change color* dialog so a plan's colour is picked the same way wherever
/// it is changed.
///
/// Each swatch is the tone the slot resolves to in the current mode, so what
/// you tap is what gets painted. Selection is matched by slot, not by value,
/// so a plan saved before the palette was solved still shows as selected.
class PlanColorPicker extends StatelessWidget {
  final int? selectedColor;
  final ValueChanged<int> onChanged;

  /// False while a save is in flight: the swatches stay visible but don't
  /// take taps.
  final bool enabled;

  const PlanColorPicker({
    required this.selectedColor,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  static const double _swatch = 48;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // One row when all ten fit, otherwise two even rows of five, spread
        // edge to edge so the grid lines up with what sits above and below
        // instead of leaving a ragged 6 + 4. Narrower than five swatches (a
        // dialog on a small phone), it wraps rather than overflowing.
        final fits =
            ((constraints.maxWidth + AppSpacing.sm) / (_swatch + AppSpacing.sm))
                .floor();
        final perRow =
            fits >= kPlanColors.length
                ? kPlanColors.length
                : (kPlanColors.length / 2).ceil();
        if (fits < perRow) {
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var slot = 0; slot < kPlanColors.length; slot++)
                _buildSwatch(context, slot),
            ],
          );
        }
        return Column(
          children: [
            for (
              var start = 0;
              start < kPlanColors.length;
              start += perRow
            ) ...[
              if (start > 0) const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (
                    var slot = start;
                    slot < start + perRow && slot < kPlanColors.length;
                    slot++
                  )
                    _buildSwatch(context, slot),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSwatch(BuildContext context, int slot) {
    final colorValue = kPlanColors[slot];
    final color = planSwatch(slot, context);
    final selected =
        selectedColor != null && planSlotOf(selectedColor!) == slot;
    final onTap = enabled ? () => onChanged(colorValue) : null;
    // The InkWell carries the tap and focus actions, so a keyboard can reach
    // every swatch; the label names the colour.
    return Semantics(
      label: kPlanColorNames[slot],
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.quick),
          width: _swatch,
          height: _swatch,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
            borderRadius: AppRadius.button,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.badge,
            ),
            child:
                selected
                    ? Icon(LucideIcons.check, size: 18, color: onColor(color))
                    : null,
          ),
        ),
      ),
    );
  }
}
