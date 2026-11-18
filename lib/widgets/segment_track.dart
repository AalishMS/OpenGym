import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';

/// One option in a [SegmentTrack].
class TrackSegment<T> {
  final T value;
  final String label;

  const TrackSegment({required this.value, required this.label});
}

/// A single-choice segmented control drawn as a filled track with the chosen
/// option as a rounded thumb inset inside it.
///
/// [SegmentedButton] can only square off the shared edges of its segments, so
/// a chosen middle segment comes out as a hard-edged slab in a rounded group.
/// Here the thumb keeps its own corners — concentric with the track's — and
/// slides between options instead of jumping.
class SegmentTrack<T> extends StatelessWidget {
  final List<TrackSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  const SegmentTrack({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  /// The gap between the track's edge and the thumb.
  static const double inset = 4;

  /// Track height; also each option's tap target.
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final index = segments.indexWhere((s) => s.value == selected);
    final count = segments.length;
    final duration = AppMotion.of(context, AppMotion.standard);
    final textStyle = Theme.of(context).textTheme.labelLarge;
    final ink = textPrimaryColor(context);
    final onThumb = onAccentColor(context);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: controlFillColor(context),
        borderRadius: AppRadius.button,
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: duration,
              curve: AppMotion.curve,
              alignment: Alignment(
                count == 1 ? 0 : -1 + 2 * index / (count - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.all(inset),
                  child: DecoratedBox(
                    key: const ValueKey('segment-thumb'),
                    decoration: BoxDecoration(
                      color: accentFillColor(context),
                      borderRadius: AppRadius.control,
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    inMutuallyExclusiveGroup: true,
                    child: TextButton(
                      onPressed: () {
                        if (i != index) onChanged(segments[i].value);
                      },
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, height),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: i == index ? onThumb : ink,
                        // The thumb is the selection; a pressed wash is all
                        // the feedback a tap needs.
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.button,
                        ),
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: duration,
                        style: (textStyle ?? const TextStyle()).copyWith(
                          color: i == index ? onThumb : ink,
                        ),
                        child: Text(
                          segments[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
