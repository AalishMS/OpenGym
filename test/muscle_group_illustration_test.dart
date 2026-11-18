import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/muscle_group_illustration.dart';

import 'support/test_fonts.dart';

const _known = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core'];
const _unknown = ['Custom', '', 'chest'];

/// Tight boxes the picker uses, plus extreme shapes and near-empty ones.
const _boxes = [
  Size(160, 104),
  Size(28, 40),
  Size(36, 52),
  Size(400, 40),
  Size(12, 300),
  Size(6, 6),
  Size(1, 1),
  Size(0.5, 2),
];

/// Not a theme colour, so a pixel of it can only be the highlight.
const _probe = Color(0xFFFF00FF);

Widget _host(Brightness brightness, Widget child) => MaterialApp(
  theme: buildTheme(const Color(0xFF14B8A6), brightness),
  home: Align(alignment: Alignment.topLeft, child: child),
);

/// Renders [child] and returns its raw RGBA pixels with the image width.
Future<(ByteData, int)> _pixels(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    _host(Brightness.light, RepaintBoundary(key: key, child: child)),
  );
  final result = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = (await image.toByteData())!;
    final width = image.width;
    image.dispose();
    return (data, width);
  });
  return result!;
}

/// Where the highlight landed: its pixel count and rightmost column.
Future<({int count, int maxX, int width})> _highlight(
  WidgetTester tester,
  String group, {
  required bool bothViews,
}) async {
  final (data, width) = await _pixels(
    tester,
    SizedBox(
      width: 160,
      height: 104,
      child: MuscleGroupIllustration(
        group: group,
        bothViews: bothViews,
        highlightColor: _probe,
      ),
    ),
  );
  var count = 0;
  var maxX = -1;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i) == 255 &&
        data.getUint8(i + 1) == 0 &&
        data.getUint8(i + 2) == 255 &&
        data.getUint8(i + 3) == 255) {
      count++;
      final x = (i ~/ 4) % width;
      if (x > maxX) maxX = x;
    }
  }
  return (count: count, maxX: maxX, width: width);
}

void main() {
  setUpAll(loadTestFonts);

  group('MuscleGroupIllustration', () {
    for (final brightness in Brightness.values) {
      for (final bothViews in [true, false]) {
        testWidgets('paints every group in tight boxes '
            '(${brightness.name}, bothViews: $bothViews)', (tester) async {
          for (final group in [..._known, ..._unknown]) {
            for (final box in _boxes) {
              await tester.pumpWidget(
                _host(
                  brightness,
                  SizedBox.fromSize(
                    size: box,
                    child: MuscleGroupIllustration(
                      group: group,
                      bothViews: bothViews,
                    ),
                  ),
                ),
              );
              expect(tester.takeException(), isNull, reason: '$group, $box');
              final paint = find.descendant(
                of: find.byType(MuscleGroupIllustration),
                matching: find.byType(CustomPaint),
              );
              expect(tester.getSize(paint), box, reason: '$group, $box');
            }
          }
        });
      }
    }

    testWidgets('paints with caller colours, translucent or opaque', (
      tester,
    ) async {
      for (final body in [
        const Color(0x33808080),
        const Color(0xFF808080),
        const Color(0x00000000),
      ]) {
        for (final bothViews in [true, false]) {
          await tester.pumpWidget(
            _host(
              Brightness.dark,
              SizedBox(
                width: 160,
                height: 104,
                child: MuscleGroupIllustration(
                  group: 'Legs',
                  bothViews: bothViews,
                  bodyColor: body,
                  highlightColor: _probe,
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('highlights every known group, paired and alone', (
      tester,
    ) async {
      for (final group in _known) {
        for (final bothViews in [true, false]) {
          final hit = await _highlight(tester, group, bothViews: bothViews);
          expect(hit.count, greaterThan(20), reason: '$group, $bothViews');
        }
      }
    });

    testWidgets('highlights nothing for a group it does not know', (
      tester,
    ) async {
      for (final group in _unknown) {
        for (final bothViews in [true, false]) {
          final hit = await _highlight(tester, group, bothViews: bothViews);
          expect(hit.count, 0, reason: '"$group", $bothViews');
        }
      }
    });

    testWidgets('front-only groups leave the back figure plain', (
      tester,
    ) async {
      for (final group in ['Chest', 'Core']) {
        final hit = await _highlight(tester, group, bothViews: true);
        expect(hit.count, greaterThan(0));
        expect(hit.maxX, lessThan(hit.width / 2), reason: group);
      }
    });

    testWidgets('fills its box, scaled to fit and centred', (tester) async {
      final (data, width) = await _pixels(
        tester,
        const SizedBox(
          width: 200,
          height: 100,
          child: MuscleGroupIllustration(group: 'Custom', bothViews: false),
        ),
      );
      final height = data.lengthInBytes ~/ 4 ~/ width;
      var minX = width, maxX = -1, minY = height, maxY = -1;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          if (data.getUint8((y * width + x) * 4 + 3) == 0) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      // The figure is taller than wide, so height is the limit: it spans
      // the box top to bottom and sits in the middle horizontally.
      expect(minY, lessThanOrEqualTo(4));
      expect(maxY, greaterThanOrEqualTo(height - 5));
      expect((minX + maxX) / 2, closeTo(width / 2, 2));
      final figureWidth =
          height * MuscleGroupIllustration.aspectRatio(bothViews: false);
      expect(maxX - minX, closeTo(figureWidth, 6));
    });

    testWidgets('takes the drawing shape when unconstrained', (tester) async {
      for (final bothViews in [true, false]) {
        await tester.pumpWidget(
          _host(
            Brightness.light,
            MuscleGroupIllustration(group: 'Arms', bothViews: bothViews),
          ),
        );
        final size = tester.getSize(find.byType(MuscleGroupIllustration));
        expect(
          size.width / size.height,
          closeTo(
            MuscleGroupIllustration.aspectRatio(bothViews: bothViews),
            1e-9,
          ),
        );
      }
    });

    test('aspectRatio describes a standing figure and a pair of them', () {
      final single = MuscleGroupIllustration.aspectRatio(bothViews: false);
      final pair = MuscleGroupIllustration.aspectRatio(bothViews: true);
      expect(single, inExclusiveRange(0.3, 0.6));
      expect(pair, greaterThan(single * 2));
      expect(pair, lessThan(single * 2.5));
    });

    test('primaryView turns to the back only for Back', () {
      expect(MuscleGroupIllustration.primaryView('Back'), BodyView.back);
      for (final group in [..._known.where((g) => g != 'Back'), ..._unknown]) {
        expect(
          MuscleGroupIllustration.primaryView(group),
          BodyView.front,
          reason: group,
        );
      }
    });
  });
}
