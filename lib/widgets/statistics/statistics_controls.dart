import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Equal-width segments in one track, for a short, fixed set of options such
/// as a time range. Every option stays in view and the track spans its parent.
class SegmentedPills<T> extends StatelessWidget {
  /// Track height; the whole height of a segment is its tap target.
  static const double height = 48;
  static const double _inset = AppSpacing.xs;

  final List<T> values;
  final T selected;
  final String Function(T) labelFor;

  /// The spoken label, when [labelFor] is an abbreviation such as `4W`.
  final String Function(T)? semanticLabelFor;
  final ValueChanged<T> onSelected;
  final String keyPrefix;

  const SegmentedPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    required this.keyPrefix,
    this.semanticLabelFor,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 13);
    return Container(
      // Wide layouts keep the segments a comfortable size rather than
      // stretching each one across a third of the page.
      // The border sits outside the segments' own 48px.
      constraints: const BoxConstraints(minHeight: height + 2, maxWidth: 480),
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border.all(color: borderColor(context)),
        // Concentric with the segments: their radius plus the inset.
        borderRadius: AppRadius.button,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final value in values)
              Expanded(
                child: Semantics(
                  key: ValueKey('$keyPrefix-$value'),
                  button: true,
                  selected: value == selected,
                  label: (semanticLabelFor ?? labelFor)(value),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: value == selected ? null : () => onSelected(value),
                    borderRadius: AppRadius.button,
                    child: Padding(
                      padding: const EdgeInsets.all(_inset - 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color:
                              value == selected
                                  ? accentFillColor(context)
                                  : null,
                          borderRadius: AppRadius.chip,
                        ),
                        child: Text(
                          labelFor(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: style?.copyWith(
                            fontWeight: FontWeight.w600,
                            color:
                                value == selected
                                    ? onAccentColor(context)
                                    : textSecondaryColor(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single scrolling row of pills, for options too many or too long to share
/// a track. The edge with more pills behind it fades, so the row reads as
/// scrollable instead of cut off.
class ScrollingPills<T> extends StatefulWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelFor;
  final ValueChanged<T> onSelected;
  final String keyPrefix;

  /// Start scrolled to the end, for rows whose latest option comes last.
  final bool startAtEnd;

  const ScrollingPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    required this.keyPrefix,
    this.startAtEnd = false,
  });

  @override
  State<ScrollingPills<T>> createState() => _ScrollingPillsState<T>();
}

class _ScrollingPillsState<T> extends State<ScrollingPills<T>> {
  static const double _fade = 24;

  bool _fadeStart = false;
  bool _fadeEnd = false;

  bool _update(ScrollMetrics metrics) {
    final start = metrics.pixels > metrics.minScrollExtent + 1;
    final end = metrics.pixels < metrics.maxScrollExtent - 1;
    if (start != _fadeStart || end != _fadeEnd) {
      setState(() {
        _fadeStart = start;
        _fadeEnd = end;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 13);
    final row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: widget.startAtEnd,
      child: Row(
        children: [
          for (final (index, value) in widget.values.indexed) ...[
            if (index > 0) const SizedBox(width: AppSpacing.sm),
            _Pill(
              key: ValueKey('${widget.keyPrefix}-$value'),
              label: widget.labelFor(value),
              selected: value == widget.selected,
              style: style,
              onTap: () => widget.onSelected(value),
            ),
          ],
        ],
      ),
    );
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => _update(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _update(notification.metrics),
        child: ShaderMask(
          // Alpha-only mask under dstIn: black keeps a pixel, transparent
          // fades it. These stops are opacity, not colours.
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final stop = bounds.width == 0 ? 0.0 : _fade / bounds.width;
            return LinearGradient(
              colors: [
                _fadeStart ? Colors.transparent : Colors.black,
                Colors.black,
                Colors.black,
                _fadeEnd ? Colors.transparent : Colors.black,
              ],
              stops: [0, stop, 1 - stop, 1],
            ).createShader(bounds);
          },
          child: row,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final TextStyle? style;
  final VoidCallback onTap;

  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    // The visible pill is compact; the tap target keeps the full 48px.
    child: InkWell(
      onTap: selected ? null : onTap,
      borderRadius: AppRadius.chip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          widthFactor: 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs + AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: selected ? accentFillColor(context) : null,
              border: Border.all(
                color:
                    selected ? accentFillColor(context) : borderColor(context),
              ),
              borderRadius: AppRadius.chip,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: style?.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    selected
                        ? onAccentColor(context)
                        : textPrimaryColor(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
