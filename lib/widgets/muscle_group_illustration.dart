import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Which side of the body a figure shows.
enum BodyView { front, back }

/// A code-drawn body map for exercise-category navigation: the figure in a
/// quiet neutral, the muscles a [group] trains in the accent.
///
/// It fills the box it is given, drawing the figure (or the front and back
/// pair) uniformly scaled to fit and centred, so callers size it with a
/// [SizedBox] or a tight parent; [aspectRatio] gives the drawing's own shape.
/// A group it doesn't know (a custom category) draws the figure with nothing
/// highlighted.
class MuscleGroupIllustration extends StatelessWidget {
  final String group;

  /// Front and back side by side, or only the group's [primaryView].
  final bool bothViews;

  /// The trained muscles. Defaults to the accent as ink.
  final Color? highlightColor;

  /// The figure itself. Defaults to a neutral that reads on any ground; the
  /// untrained muscles take a stronger step of the same colour.
  final Color? bodyColor;

  const MuscleGroupIllustration({
    super.key,
    required this.group,
    this.bothViews = true,
    this.highlightColor,
    this.bodyColor,
  });

  static const double _figureAspect = _boxWidth / _boxHeight;
  static const double _pairGap = 0.14;

  /// Width over height of the drawing.
  static double aspectRatio({required bool bothViews}) =>
      bothViews ? _figureAspect * (2 + _pairGap) : _figureAspect;

  /// The view that shows [group] best when only one figure fits.
  static BodyView primaryView(String group) =>
      group == 'Back' ? BodyView.back : BodyView.front;

  @override
  Widget build(BuildContext context) {
    final ratio = aspectRatio(bothViews: bothViews);
    // Translucent light ink on a dark ground reads fainter than the same
    // step of dark ink on a light one, so dark mode takes a little more.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final body =
        bodyColor ??
        textSecondaryColor(context).withValues(alpha: dark ? 0.26 : 0.2);
    // Its own layer, so the cards around it can scale on press and slide
    // between pages without repainting it.
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(88 * ratio, 88),
          painter: _MuscleGroupPainter(
            pixelRatio: MediaQuery.devicePixelRatioOf(context),
            group: group,
            views:
                bothViews
                    ? const [BodyView.front, BodyView.back]
                    : [primaryView(group)],
            bodyColor: body,
            muscleColor: _muscleTone(body, textPrimaryColor(context)),
            highlightColor: highlightColor ?? accentColor(context),
          ),
        ),
      ),
    );
  }

  /// The untrained muscles: the body colour, one step stronger. A
  /// translucent body doubles its own coverage, so the step holds on any
  /// ground; an opaque one leans toward the ink instead.
  static Color _muscleTone(Color body, Color ink) {
    if (body.a >= 0.9) return Color.lerp(body, ink, 0.22)!;
    return body.withValues(alpha: body.a * (2 - body.a));
  }
}

/// The design box every figure is drawn in, in design units.
const double _boxWidth = 79;
const double _boxHeight = 198;
const Rect _box = Rect.fromLTWH(10.5, 1.5, _boxWidth, _boxHeight);

class _MuscleGroupPainter extends CustomPainter {
  final String group;
  final List<BodyView> views;
  final Color bodyColor;
  final Color muscleColor;
  final Color highlightColor;

  /// Physical pixels per logical pixel, so the cached image is drawn 1:1.
  final double pixelRatio;

  const _MuscleGroupPainter({
    required this.group,
    required this.views,
    required this.bodyColor,
    required this.muscleColor,
    required this.highlightColor,
    required this.pixelRatio,
  });

  /// Rendered maps, most recently used last. Each figure is composed in an
  /// offscreen layer, which the GPU would otherwise redo every frame the
  /// grid animates (Impeller keeps no raster cache); as an image it is drawn
  /// once and then only copied.
  static final Map<Object, ui.Image> _images = {};
  static const int _imageLimit = 24;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Fit the views, side by side, inside the box and centre them.
    final gap = _box.width * MuscleGroupIllustration._pairGap;
    final drawing = Size(
      _box.width * views.length + gap * (views.length - 1),
      _box.height,
    );
    final scale = math.min(
      size.width / drawing.width,
      size.height / drawing.height,
    );
    final target = Rect.fromLTWH(
      (size.width - drawing.width * scale) / 2,
      (size.height - drawing.height * scale) / 2,
      drawing.width * scale,
      drawing.height * scale,
    );
    final image = _imageFor(target.size, scale, gap);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      target,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  ui.Image _imageFor(Size target, double scale, double gap) {
    final key = (
      group,
      views.first,
      views.length,
      bodyColor,
      muscleColor,
      highlightColor,
      target,
      pixelRatio,
    );
    final cached = _images.remove(key);
    if (cached != null) return _images[key] = cached;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio * scale);
    final targets = _targets[group] ?? const <_Muscle>{};
    for (var i = 0; i < views.length; i++) {
      canvas.save();
      canvas.translate(i * (_box.width + gap) - _box.left, -_box.top);
      _paintFigure(canvas, _Figure.of(views[i]), targets, scale);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(1, (target.width * pixelRatio).ceil()),
      math.max(1, (target.height * pixelRatio).ceil()),
    );
    picture.dispose();
    _images[key] = image;
    // A frame already drawn keeps its own claim on an image, so disposing
    // the evicted handle never pulls one out from under the screen.
    while (_images.length > _imageLimit) {
      _images.remove(_images.keys.first)!.dispose();
    }
    return image;
  }

  void _paintFigure(
    Canvas canvas,
    _Figure figure,
    Set<_Muscle> targets,
    double scale,
  ) {
    // On-screen height decides how much separation the map can carry: a
    // hero figure shows every muscle head, a list-sized one only the muscles.
    final detailed = scale * _box.height >= 72;
    final gap =
        detailed
            ? (0.62 / scale).clamp(0.75, 1.3)
            : (0.45 / scale).clamp(1.3, 2.4);
    final bounds = _box.inflate(4);

    // Everything is composed in a layer clipped to the body: the body in its
    // neutral, then each muscle stamped over it with a clear ring. The rings
    // let the ground show through, so the map separates on any ground
    // without knowing its colour, and muscles may overshoot the outline.
    canvas.save();
    canvas.clipPath(figure.silhouette);
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = bodyColor);
    final fill = Paint()..blendMode = BlendMode.src;
    final ring =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = gap
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.clear;
    final cut =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = gap * 0.8
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.clear;
    for (final region in figure.regions) {
      final trained = targets.contains(region.muscle);
      fill.color = trained ? highlightColor : muscleColor;
      canvas.drawPath(region.path, fill);
      // Small, the untrained muscles read as one mass: separating them all
      // turns into noise, and only the trained ones need an edge.
      if (detailed || trained) canvas.drawPath(region.path, ring);
      final detail = region.detail;
      if (detailed && detail != null) {
        canvas.save();
        canvas.clipPath(region.path);
        canvas.drawPath(detail, cut);
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MuscleGroupPainter oldDelegate) =>
      group != oldDelegate.group ||
      !listEquals(views, oldDelegate.views) ||
      bodyColor != oldDelegate.bodyColor ||
      muscleColor != oldDelegate.muscleColor ||
      highlightColor != oldDelegate.highlightColor ||
      pixelRatio != oldDelegate.pixelRatio;
}

// ---------------------------------------------------------------------------
// Anatomy
// ---------------------------------------------------------------------------

enum _Muscle {
  traps,
  delts,
  pecs,
  biceps,
  triceps,
  forearms,
  lats,
  midBack,
  erectors,
  abs,
  obliques,
  glutes,
  quads,
  adductors,
  hamstrings,
  calves,
}

/// The muscles each catalog group trains.
const Map<String, Set<_Muscle>> _targets = {
  'Chest': {_Muscle.pecs},
  'Back': {_Muscle.lats, _Muscle.traps, _Muscle.midBack, _Muscle.erectors},
  'Shoulders': {_Muscle.delts},
  'Arms': {_Muscle.biceps, _Muscle.triceps, _Muscle.forearms},
  'Legs': {
    _Muscle.quads,
    _Muscle.adductors,
    _Muscle.calves,
    _Muscle.glutes,
    _Muscle.hamstrings,
  },
  'Core': {_Muscle.abs, _Muscle.obliques},
};

/// One muscle, both sides, with the lines that split its heads.
class _Region {
  final _Muscle muscle;
  final Path path;
  final Path? detail;

  _Region(this.muscle, List<List<_K>> shapes, [List<List<_K>> cuts = const []])
    : path = _mirrored(shapes, closed: true),
      detail = cuts.isEmpty ? null : _mirrored(cuts, closed: false);
}

class _Figure {
  final Path silhouette;

  /// In paint order: a later muscle lies over an earlier one, so shared
  /// borders are drawn by whichever muscle sits on top.
  final List<_Region> regions;

  const _Figure(this.silhouette, this.regions);

  static _Figure of(BodyView view) => switch (view) {
    BodyView.front => _front,
    BodyView.back => _back,
  };

  static final _Figure _front = _Figure(_silhouette, _frontRegions());
  static final _Figure _back = _Figure(_silhouette, _backRegions());
}

// Geometry is authored for the figure's left half of the page (x < 50) in a
// 100 x 200 design space and mirrored about x = 50. Points are knots of a
// centripetal Catmull-Rom spline; a corner knot breaks the curve.

class _K {
  final double x;
  final double y;
  final bool corner;

  const _K(this.x, this.y, [this.corner = false]);

  _K get mirrored => _K(100 - x, y, corner);
}

/// A limb's own coordinates: `u` runs from [from] (0) to [to] (1) along the
/// bone, `v` is the distance out from it, positive away from the body.
class _Frame {
  final Offset _origin;
  final Offset _axis;
  final Offset _out;

  _Frame(Offset from, Offset to)
    : _origin = from,
      _axis = to - from,
      _out = Offset(-(to - from).dy, (to - from).dx) / (to - from).distance;

  _K call(double u, double v, [bool corner = false]) {
    final p = _origin + _axis * u + _out * v;
    return _K(p.dx, p.dy, corner);
  }
}

final _Frame _arm = _Frame(const Offset(31.0, 44.0), const Offset(17.2, 104.0));
final _Frame _leg = _Frame(
  const Offset(40.5, 108.0),
  const Offset(42.6, 186.5),
);

Path _mirrored(List<List<_K>> shapes, {required bool closed}) {
  final path = Path();
  for (final shape in shapes) {
    path.addPath(_spline(shape, closed: closed), Offset.zero);
    path.addPath(
      _spline([for (final k in shape.reversed) k.mirrored], closed: closed),
      Offset.zero,
    );
  }
  return path;
}

/// A whole outline from its left half, which runs from a knot on the
/// midline to another one.
List<_K> _symmetric(List<_K> half) => [
  ...half,
  for (var i = half.length - 2; i >= 1; i--) half[i].mirrored,
];

Path _spline(List<_K> k, {required bool closed}) {
  final n = k.length;
  _K at(int i) => closed ? k[(i + n) % n] : k[i.clamp(0, n - 1)];
  final path = Path()..moveTo(k[0].x, k[0].y);
  final segments = closed ? n : n - 1;
  for (var i = 0; i < segments; i++) {
    final p0 = at(i - 1);
    final p1 = at(i);
    final p2 = at(i + 1);
    final p3 = at(i + 2);
    final startsSharp = p1.corner || (!closed && i == 0);
    final endsSharp = p2.corner || (!closed && i == n - 2);
    final c1 = startsSharp ? _third(p1, p2) : _control(p0, p1, p2);
    final c2 = endsSharp ? _third(p2, p1) : _control(p3, p2, p1);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.x, p2.y);
  }
  if (closed) path.close();
  return path;
}

Offset _third(_K from, _K to) =>
    Offset(from.x + (to.x - from.x) / 3, from.y + (to.y - from.y) / 3);

/// The Bezier handle leaving [p1] toward [p2], centripetal Catmull-Rom.
Offset _control(_K p0, _K p1, _K p2) {
  final d1 = math.sqrt(math.sqrt(_dist2(p0, p1)));
  final d2 = math.sqrt(math.sqrt(_dist2(p1, p2)));
  if (d1 < 1e-6 || d2 < 1e-6) return _third(p1, p2);
  final a = 2 * d1 * d1 + 3 * d1 * d2 + d2 * d2;
  final n = 3 * d1 * (d1 + d2);
  return Offset(
    (d1 * d1 * p2.x - d2 * d2 * p0.x + a * p1.x) / n,
    (d1 * d1 * p2.y - d2 * d2 * p0.y + a * p1.y) / n,
  );
}

double _dist2(_K a, _K b) =>
    (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y);

/// The body outline, shared by both views.
final Path _silhouette = _spline(
  _symmetric([
    // Head.
    const _K(50, 2.0),
    const _K(44.6, 3.1),
    const _K(41.7, 7.0),
    const _K(41.1, 11.2),
    const _K(40.3, 12.6),
    const _K(40.5, 15.6),
    const _K(41.5, 17.4),
    const _K(42.4, 20.6),
    const _K(44.0, 23.4),
    const _K(45.2, 25.2, true),
    // Neck and the trapezius slope.
    const _K(44.7, 28.2),
    const _K(44.0, 31.0),
    const _K(40.6, 33.2),
    const _K(35.4, 35.0),
    const _K(31.2, 36.4),
    // Deltoid cap and the outside of the arm.
    const _K(27.4, 38.0),
    const _K(24.8, 41.0),
    _arm(0.04, 7.4),
    _arm(0.13, 7.2),
    _arm(0.25, 5.2),
    _arm(0.37, 5.3),
    _arm(0.49, 4.7),
    _arm(0.585, 4.4),
    _arm(0.665, 5.3),
    _arm(0.76, 4.7),
    _arm(0.88, 3.4),
    _arm(1.0, 2.8),
    // Hand.
    _arm(1.05, 3.1),
    _arm(1.13, 3.3),
    _arm(1.21, 2.9),
    _arm(1.265, 1.6),
    _arm(1.28, 0.2),
    _arm(1.255, -1.0),
    _arm(1.205, -1.6),
    _arm(1.175, -1.9, true),
    _arm(1.14, -3.0),
    _arm(1.09, -3.4),
    _arm(1.03, -3.1),
    _arm(1.0, -2.8),
    // Inside of the arm, up to the armpit.
    _arm(0.9, -3.0),
    _arm(0.78, -4.2),
    _arm(0.665, -5.0),
    _arm(0.585, -4.1),
    _arm(0.47, -4.4),
    _arm(0.34, -5.0),
    _arm(0.22, -4.8),
    const _K(34.0, 52.8, true),
    // Flank, waist and hip.
    const _K(34.9, 57.5),
    const _K(35.2, 64.0),
    const _K(35.7, 71.0),
    const _K(36.1, 78.0),
    const _K(36.3, 84.0),
    const _K(36.0, 89.0),
    const _K(35.1, 94.0),
    const _K(34.0, 99.0),
    const _K(33.2, 104.5),
    // Outside of the leg.
    _leg(0.06, 7.4),
    _leg(0.16, 7.6),
    _leg(0.28, 6.9),
    _leg(0.40, 5.7),
    _leg(0.50, 4.9),
    _leg(0.56, 5.1),
    _leg(0.63, 5.9),
    _leg(0.71, 5.5),
    _leg(0.81, 4.3),
    _leg(0.90, 3.3),
    _leg(0.97, 2.9),
    // Foot.
    const _K(39.0, 188.5),
    const _K(38.4, 193.0),
    const _K(38.7, 196.8),
    const _K(40.4, 198.7),
    const _K(44.0, 199.0),
    const _K(46.5, 198.0),
    const _K(46.9, 194.5),
    const _K(46.3, 190.0),
    const _K(45.7, 186.2),
    // Inside of the leg, up to the crotch.
    _leg(0.94, -2.8),
    _leg(0.85, -3.3),
    _leg(0.75, -4.8),
    _leg(0.65, -6.2),
    _leg(0.57, -5.4),
    _leg(0.50, -4.6),
    _leg(0.43, -5.2),
    _leg(0.33, -5.6),
    _leg(0.20, -7.0),
    _leg(0.12, -8.3),
    const _K(50, 113.5, true),
  ]),
  closed: true,
);

/// The front view, in paint order.
List<_Region> _frontRegions() => [
  // Upper trapezius, the slope between neck and shoulder.
  _Region(_Muscle.traps, [
    [
      const _K(44.4, 29.4, true),
      const _K(42.0, 30.4),
      const _K(36.0, 32.4),
      const _K(30.4, 34.2),
      const _K(27.0, 36.2, true),
      const _K(31.6, 37.8, true),
      const _K(37.2, 36.6),
      const _K(41.8, 35.4),
      const _K(44.4, 34.6, true),
    ],
  ]),
  // Biceps, with the brachialis split off along the outside.
  _Region(
    _Muscle.biceps,
    [
      [
        _arm(0.12, -3.6, true),
        _arm(0.13, 0.5),
        _arm(0.24, 4.0),
        _arm(0.34, 7.0),
        _arm(0.47, 6.6),
        _arm(0.495, 4.6, true),
        _arm(0.565, 0.8),
        _arm(0.545, -2.5),
        _arm(0.52, -6.2, true),
        _arm(0.40, -6.4),
        _arm(0.26, -6.0),
        _arm(0.17, -5.4),
      ],
    ],
    [
      [_arm(0.29, 7.0), _arm(0.36, 4.6), _arm(0.44, 3.4), _arm(0.55, 2.0)],
    ],
  ),
  // Forearm flexors and brachioradialis.
  _Region(
    _Muscle.forearms,
    [
      [
        _arm(0.47, 7.0, true),
        _arm(0.515, 4.6),
        _arm(0.59, 0.8),
        _arm(0.62, -2.5),
        _arm(0.645, -6.5, true),
        _arm(0.78, -6.6),
        _arm(0.90, -5.6),
        _arm(0.955, -4.6, true),
        _arm(0.965, 0.0),
        _arm(0.955, 4.6, true),
        _arm(0.85, 6.6),
        _arm(0.66, 7.6),
      ],
    ],
    [
      [
        _arm(0.51, 3.4),
        _arm(0.60, 2.2),
        _arm(0.72, 1.0),
        _arm(0.86, 0.4),
        _arm(0.99, 0.4),
      ],
    ],
  ),
  // Anterior and lateral deltoid.
  _Region(
    _Muscle.delts,
    [
      [
        const _K(37.0, 38.6, true),
        const _K(33.6, 37.4),
        const _K(29.6, 36.6),
        const _K(25.6, 37.4),
        const _K(21.6, 41.0),
        const _K(20.0, 47.0),
        _arm(0.2, 8.0),
        _arm(0.28, 6.5),
        _arm(0.315, 3.6, true),
        _arm(0.2, 1.2),
        const _K(33.0, 51.0),
        const _K(34.0, 46.0),
        const _K(35.4, 41.6),
      ],
    ],
    [
      [
        const _K(31.2, 35.6),
        const _K(28.8, 41.0),
        const _K(26.6, 46.6),
        _arm(0.2, 3.8),
        _arm(0.32, 3.4),
      ],
    ],
  ),
  // The edge of the lats, under the armpit.
  _Region(_Muscle.lats, [
    [
      const _K(35.4, 54.6, true),
      const _K(33.6, 57.6),
      const _K(33.4, 64.0),
      const _K(34.0, 70.0),
      const _K(35.4, 74.0, true),
      const _K(38.4, 69.4),
      const _K(39.0, 63.0),
      const _K(38.4, 57.6),
    ],
  ]),
  // Pectorals.
  _Region(_Muscle.pecs, [
    [
      const _K(50, 39.6, true),
      const _K(45.6, 38.8),
      const _K(40.8, 38.6),
      const _K(37.0, 39.2),
      const _K(34.8, 41.6),
      const _K(33.2, 45.0),
      const _K(32.4, 48.6, true),
      const _K(34.2, 52.6),
      const _K(37.2, 56.8),
      const _K(41.4, 59.6),
      const _K(45.4, 60.7),
      const _K(48.4, 60.5),
      const _K(50, 59.8, true),
    ],
  ]),
  // External obliques.
  _Region(_Muscle.obliques, [
    [
      const _K(38.6, 60.6, true),
      const _K(42.6, 62.6),
      const _K(44.0, 70.0),
      const _K(44.2, 80.0),
      const _K(45.0, 90.0),
      const _K(46.8, 101.8, true),
      const _K(42.0, 100.0),
      const _K(37.4, 97.6),
      const _K(33.4, 95.8, true),
      const _K(34.4, 86.0),
      const _K(34.6, 78.0),
      const _K(35.8, 73.6),
      const _K(37.2, 69.6),
      const _K(37.8, 64.0),
    ],
  ]),
  // Rectus abdominis and its tendinous lines.
  _Region(
    _Muscle.abs,
    [
      [
        const _K(50, 62.2, true),
        const _K(45.6, 62.2),
        const _K(43.2, 63.6),
        const _K(42.8, 70.0),
        const _K(43.0, 80.0),
        const _K(43.8, 90.0),
        const _K(45.2, 98.0),
        const _K(47.6, 103.6),
        const _K(50, 105.0, true),
      ],
    ],
    [
      [const _K(41.5, 70.6), const _K(45.6, 69.6), const _K(50, 69.2)],
      [const _K(41.5, 78.0), const _K(45.6, 77.2), const _K(50, 77.0)],
      [const _K(41.5, 85.6), const _K(45.6, 85.0), const _K(50, 84.8)],
    ],
  ),
  // Quadriceps: vastus lateralis, the rectus femoris spindle, vastus medialis.
  _Region(
    _Muscle.quads,
    [
      [
        const _K(32.0, 97.4),
        const _K(36.4, 99.4),
        const _K(40.6, 101.8),
        const _K(44.0, 104.2),
        const _K(46.8, 106.8),
        _leg(0.2, -9.0),
        _leg(0.38, -7.0),
        _leg(0.50, -5.2, true),
        _leg(0.48, -3.0),
        _leg(0.46, -1.0),
        _leg(0.455, 1.0),
        _leg(0.465, 3.0),
        _leg(0.485, 5.0, true),
        _leg(0.40, 8.0),
        _leg(0.2, 9.5),
        _leg(0.05, 9.5),
      ],
    ],
    [
      [
        _leg(-0.08, 2.0),
        _leg(0.0, 2.8),
        _leg(0.16, 4.4),
        _leg(0.32, 3.4),
        _leg(0.46, 0.6),
        _leg(0.52, 0.2),
      ],
      [
        _leg(-0.08, -0.4),
        _leg(0.02, -1.0),
        _leg(0.16, -1.8),
        _leg(0.32, -1.4),
        _leg(0.46, 0.6),
        _leg(0.52, 1.0),
      ],
    ],
  ),
  // Adductors, the inner upper thigh.
  _Region(_Muscle.adductors, [
    [
      const _K(44.0, 105.4, true),
      const _K(47.6, 107.0),
      const _K(49.5, 109.2),
      const _K(49.8, 113.2),
      const _K(49.7, 116.5),
      _leg(0.2, -8.2),
      _leg(0.36, -7.0, true),
      _leg(0.24, -5.2),
      _leg(0.10, -3.8),
    ],
  ]),
  // Tibialis and peroneals outside the shin, the calf inside it.
  _Region(_Muscle.calves, [
    [
      _leg(0.535, 5.0, true),
      _leg(0.545, 2.2),
      _leg(0.56, 0.2),
      _leg(0.66, -0.6),
      _leg(0.78, -0.4),
      _leg(0.87, 0.6, true),
      _leg(0.84, 4.8),
      _leg(0.70, 7.4),
      _leg(0.56, 6.8),
    ],
    [
      _leg(0.545, -2.6, true),
      _leg(0.64, -1.9),
      _leg(0.76, -2.0),
      _leg(0.86, -2.6, true),
      _leg(0.80, -5.2),
      _leg(0.66, -7.6),
      _leg(0.54, -7.0),
    ],
  ]),
];

/// The back view, in paint order.
List<_Region> _backRegions() => [
  // Infraspinatus and teres, on the shoulder blade.
  _Region(_Muscle.midBack, [
    [
      const _K(34.0, 41.0),
      const _K(40.0, 41.6),
      const _K(44.0, 48.0),
      const _K(44.0, 56.0),
      const _K(38.0, 58.0),
      const _K(33.6, 56.0),
      const _K(31.6, 50.0),
    ],
  ]),
  // Lats.
  _Region(_Muscle.lats, [
    [
      const _K(46.0, 54.0),
      const _K(41.8, 56.8),
      const _K(38.0, 57.6),
      const _K(35.0, 56.2),
      const _K(33.6, 55.4, true),
      const _K(33.4, 60.0),
      const _K(33.6, 70.0),
      const _K(34.2, 80.0),
      const _K(34.4, 88.0),
      const _K(34.6, 94.0, true),
      const _K(38.6, 93.8),
      const _K(42.0, 93.4),
      const _K(45.0, 91.0, true),
      const _K(49.0, 80.0),
      const _K(49.0, 62.0),
    ],
  ]),
  // Erector spinae, either side of the spine.
  _Region(_Muscle.erectors, [
    [
      const _K(50, 58.0, true),
      const _K(48.4, 62.0),
      const _K(46.6, 70.0),
      const _K(44.8, 78.0),
      const _K(43.6, 86.0),
      const _K(43.4, 93.0),
      const _K(44.8, 98.6),
      const _K(47.4, 101.2),
      const _K(50, 102.0, true),
    ],
  ]),
  // Trapezius, upper to lower.
  _Region(_Muscle.traps, [
    [
      const _K(50, 28.6, true),
      const _K(47.2, 29.0),
      const _K(44.6, 29.6),
      const _K(42.0, 30.6),
      const _K(36.0, 32.8),
      const _K(30.6, 34.8),
      const _K(27.6, 36.8, true),
      const _K(31.8, 38.6, true),
      const _K(36.0, 40.2),
      const _K(39.6, 42.6),
      const _K(41.8, 46.6),
      const _K(43.0, 53.0),
      const _K(44.6, 60.6),
      const _K(46.6, 68.4),
      const _K(48.4, 75.0),
      const _K(50, 79.6, true),
    ],
  ]),
  // Triceps: lateral and long heads.
  _Region(
    _Muscle.triceps,
    [
      [
        const _K(34.4, 53.6, true),
        const _K(32.8, 48.6),
        const _K(31.0, 45.0),
        _arm(0.10, 1.0),
        _arm(0.2, 4.0),
        _arm(0.30, 7.0),
        _arm(0.46, 6.6),
        _arm(0.535, 4.2, true),
        _arm(0.56, 1.4),
        _arm(0.56, -1.6),
        _arm(0.535, -4.0, true),
        _arm(0.45, -6.4),
        _arm(0.30, -6.4),
        _arm(0.18, -5.8),
      ],
    ],
    [
      [_arm(0.16, 0.8), _arm(0.30, 0.6), _arm(0.44, 0.0), _arm(0.6, -0.6)],
    ],
  ),
  // Forearm extensors.
  _Region(
    _Muscle.forearms,
    [
      [
        _arm(0.545, 6.8, true),
        _arm(0.57, 4.0),
        _arm(0.595, 1.6),
        _arm(0.605, -1.0),
        _arm(0.595, -3.6),
        _arm(0.58, -6.6, true),
        _arm(0.78, -6.6),
        _arm(0.90, -5.6),
        _arm(0.955, -4.6, true),
        _arm(0.965, 0.0),
        _arm(0.955, 4.6, true),
        _arm(0.85, 6.6),
        _arm(0.66, 7.6),
      ],
    ],
    [
      [_arm(0.55, 4.8), _arm(0.64, 2.6), _arm(0.78, 1.2), _arm(0.99, 0.4)],
    ],
  ),
  // Rear and lateral deltoid.
  _Region(
    _Muscle.delts,
    [
      [
        const _K(35.6, 40.0, true),
        const _K(32.0, 37.6),
        const _K(28.0, 36.4),
        const _K(24.0, 38.4),
        const _K(21.0, 43.0),
        _arm(0.18, 8.0),
        _arm(0.27, 6.6),
        _arm(0.315, 3.6, true),
        _arm(0.22, 1.2),
        _arm(0.13, -1.0),
        const _K(32.4, 45.6),
        const _K(34.4, 42.4),
      ],
    ],
    [
      [
        const _K(29.6, 37.0),
        const _K(27.6, 43.0),
        _arm(0.18, 4.0),
        _arm(0.315, 3.6),
      ],
    ],
  ),
  // Hamstrings: biceps femoris outside, semitendinosus inside.
  _Region(
    _Muscle.hamstrings,
    [
      [
        _leg(0.12, 9.4, true),
        _leg(0.12, -8.8, true),
        _leg(0.28, -7.6),
        _leg(0.40, -6.0),
        _leg(0.49, -3.2, true),
        _leg(0.41, 0.4, true),
        _leg(0.49, 4.0, true),
        _leg(0.42, 7.6),
        _leg(0.25, 9.6),
      ],
    ],
    [
      [_leg(0.16, 0.8), _leg(0.28, 0.6), _leg(0.41, 0.4)],
    ],
  ),
  // Calves: both gastrocnemius heads over the soleus.
  _Region(
    _Muscle.calves,
    [
      [
        _leg(0.505, 3.4, true),
        _leg(0.52, 6.6),
        _leg(0.66, 7.6),
        _leg(0.80, 5.6),
        _leg(0.88, 3.0),
        _leg(0.905, 0.6, true),
        _leg(0.88, -2.0),
        _leg(0.80, -5.6),
        _leg(0.66, -7.6),
        _leg(0.53, -6.6),
        _leg(0.505, -3.4, true),
        _leg(0.535, 0.2, true),
      ],
    ],
    [
      [_leg(0.535, 0.2), _leg(0.62, 0.3), _leg(0.73, 0.3)],
      [
        _leg(0.66, 7.0),
        _leg(0.735, 3.6),
        _leg(0.73, 0.3),
        _leg(0.775, -3.4),
        _leg(0.70, -7.0),
      ],
    ],
  ),
  // Gluteus medius.
  _Region(_Muscle.glutes, [
    [
      const _K(33.0, 95.2, true),
      const _K(36.6, 95.2),
      const _K(40.4, 95.6),
      const _K(43.2, 97.2, true),
      const _K(39.6, 100.6),
      const _K(35.4, 104.0),
      const _K(33.0, 105.6, true),
    ],
  ]),
  // Gluteus maximus.
  _Region(_Muscle.glutes, [
    [
      const _K(50, 100.6, true),
      const _K(44.8, 99.6),
      const _K(39.6, 100.4),
      const _K(35.4, 102.6),
      const _K(32.2, 106.0),
      const _K(31.6, 112.0),
      const _K(32.6, 117.4),
      const _K(35.6, 121.0),
      const _K(40.6, 123.2),
      const _K(46.4, 123.4),
      const _K(50, 121.4, true),
    ],
  ]),
];
