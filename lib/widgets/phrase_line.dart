import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/spacing.dart';

/// Short phrases on one line, separated by middle dots, that wrap only
/// between phrases.
///
/// `5 exercises · 17 sets` never splits a number from its unit at large text.
/// Each phrase is measured against the full line first; its dot follows only
/// when both fit, so a dot never squeezes the phrase it trails into breaking
/// mid-word, and a phrase that fills its line is set apart by the break
/// instead. The dots are decoration, so screen readers hear only the phrases.
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
            _Separated(
              phrase: phrases[index],
              separator: ExcludeSemantics(child: Text(' · ', style: style)),
            ),
      ],
    );
  }
}

/// A phrase and the separator that trails it.
class _Separated extends MultiChildRenderObjectWidget {
  _Separated({required Widget phrase, required Widget separator})
    : super(children: [phrase, separator]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSeparated();
}

class _SeparatedParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays the phrase out at the full width, then places the separator after it
/// on its baseline only if both fit; otherwise the separator is not painted.
class _RenderSeparated extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SeparatedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SeparatedParentData> {
  bool _showSeparator = true;

  RenderBox get _phrase => firstChild!;
  RenderBox get _separator => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SeparatedParentData) {
      child.parentData = _SeparatedParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _phrase.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _phrase.getMaxIntrinsicWidth(height) +
      _separator.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _phrase.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _phrase.getMaxIntrinsicHeight(width);

  /// Where each child sits, and the size they make together.
  ({Offset phrase, Offset separator, Size size, bool show}) _arrange(
    Size phrase,
    Size separator,
    double? phraseBaseline,
    double? separatorBaseline,
    double maxWidth,
  ) {
    final show = phrase.width + separator.width <= maxWidth;
    if (!show) {
      return (
        phrase: Offset.zero,
        separator: Offset(phrase.width, 0),
        size: phrase,
        show: false,
      );
    }
    // Share the phrase's first baseline, so the dot sits on its line.
    final shift =
        (phraseBaseline ?? phrase.height) -
        (separatorBaseline ?? separator.height);
    final phraseTop = math.max(0.0, -shift);
    final separatorTop = math.max(0.0, shift);
    return (
      phrase: Offset(0, phraseTop),
      separator: Offset(phrase.width, separatorTop),
      size: Size(
        phrase.width + separator.width,
        math.max(phraseTop + phrase.height, separatorTop + separator.height),
      ),
      show: true,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final phrase = _phrase.getDryLayout(
      BoxConstraints(maxWidth: constraints.maxWidth),
    );
    final separator = _separator.getDryLayout(const BoxConstraints());
    final arranged = _arrange(
      phrase,
      separator,
      null,
      null,
      constraints.maxWidth,
    );
    return constraints.constrain(arranged.size);
  }

  @override
  void performLayout() {
    _phrase.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    _separator.layout(const BoxConstraints(), parentUsesSize: true);
    final arranged = _arrange(
      _phrase.size,
      _separator.size,
      _phrase.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true),
      _separator.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true),
      constraints.maxWidth,
    );
    _showSeparator = arranged.show;
    (_phrase.parentData! as _SeparatedParentData).offset = arranged.phrase;
    (_separator.parentData! as _SeparatedParentData).offset =
        arranged.separator;
    size = constraints.constrain(arranged.size);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final offset = (_phrase.parentData! as _SeparatedParentData).offset;
    final distance = _phrase.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance + offset.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(
      _phrase,
      offset + (_phrase.parentData! as _SeparatedParentData).offset,
    );
    if (_showSeparator) {
      context.paintChild(
        _separator,
        offset + (_separator.parentData! as _SeparatedParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final data = _phrase.parentData! as _SeparatedParentData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest:
          (result, transformed) =>
              _phrase.hitTest(result, position: transformed),
    );
  }
}
