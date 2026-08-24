// Derives the OpenGym launcher artwork from the pixel-art source.
//
//   flutter test tool/generate_app_icon.dart
//   flutter pub run flutter_launcher_icons
//
// Source: logo/pixel_dumbbell.jpg - a 2048px square, cyan ground, charcoal
// dumbbell in the upper middle, "OPEN GYM" wordmark across the lower third.
//
// Two things this script exists to fix. First, the wordmark has to go: an
// Android adaptive icon only guarantees the centre 66% survives the launcher's
// mask, and the text sits well outside it, so it would be clipped mid-letter.
// The launcher prints the app label under the icon anyway. Second, with the
// text gone the dumbbell is no longer centred, so it gets re-centred on its own
// bounding box rather than inheriting the lockup's balance.
//
// The wordmark is removed by finding it, not by a hardcoded crop: rows are
// profiled for non-background content, which yields three bands (dumbbell,
// "OPEN", "GYM"), and only the topmost is kept. That way retouching the source
// doesn't silently shift the crop.
//
// Three assets come out, and they are not interchangeable:
//
//   applogo.png             full icon on the cyan ground, for iOS and
//                           pre-API-26 Android. Carries no baked rounded rect
//                           and no shadow - both platforms apply their own
//                           mask, and a baked frame is what double-framed the
//                           previous icon inside the launcher's circle.
//   applogo_foreground.png  adaptive foreground, transparent, inset to the
//                           safe zone. The launcher scales this to the full
//                           108dp canvas, so the padding must be in the file.
//   applogo_monochrome.png  Android 13+ themed icon. The silhouette in solid
//                           white; the system supplies the tint.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const String _source = 'logo/pixel_dumbbell.jpg';

/// Below this distance from the sampled ground colour a pixel is background.
/// Generous because JPEG ringing around hard pixel-art edges smears the ground.
const double _keyLow = 42;

/// Above this distance a pixel is fully opaque subject. Between the two the
/// alpha ramps, which keeps the block edges from turning into a jagged fringe.
const double _keyHigh = 96;

/// Mark spans this share of the full icon. iOS masks only the corners, so a
/// centred subject clears the squircle comfortably here.
const double _fullFraction = 0.74;

/// Share of the canvas the mark spans in the adaptive layers.
///
/// Close to full bleed on purpose. flutter_launcher_icons wraps these drawables
/// in `<inset android:inset="16%">` in mipmap-anydpi-v26/ic_launcher.xml, which
/// on its own already lands the art in the 66% safe zone (108dp x 0.68 = 73dp).
/// Insetting here as well would compound the two - at 0.60 the dumbbell came
/// out spanning 41% of the 108dp canvas and read as lost in the ground.
///
/// Not 1.0 either: the source bounding box is tight to the plate tips, and the
/// safe region is a *circle* of 72dp. At full bleed the tips would sit ~37dp
/// from centre against a 36dp radius and a circular mask could shave them.
/// 0.88 puts them at ~32dp, clear of the mask with margin for parallax.
const double _adaptiveFraction = 0.88;

// ---------------------------------------------------------------------------
// A decoded, straight-alpha RGBA buffer we can index by pixel.
// ---------------------------------------------------------------------------

class _Bitmap {
  _Bitmap(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;

  static Future<_Bitmap> decodeFile(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return _Bitmap(data!.buffer.asUint8List(), image.width, image.height);
  }

  int _offset(int x, int y) => (y * width + x) * 4;

  int r(int x, int y) => bytes[_offset(x, y)];
  int g(int x, int y) => bytes[_offset(x, y) + 1];
  int b(int x, int y) => bytes[_offset(x, y) + 2];

  double distanceFrom(int x, int y, List<int> rgb) {
    final dr = r(x, y) - rgb[0];
    final dg = g(x, y) - rgb[1];
    final db = b(x, y) - rgb[2];
    return math.sqrt((dr * dr + dg * dg + db * db).toDouble());
  }

  /// The ground colour, averaged over all four corners so a slight gradient or
  /// JPEG blocking in any one of them cannot skew it.
  List<int> sampleGround({int patch = 48}) {
    var sr = 0, sg = 0, sb = 0, n = 0;
    for (final origin in [
      [0, 0],
      [width - patch, 0],
      [0, height - patch],
      [width - patch, height - patch],
    ]) {
      for (var y = origin[1]; y < origin[1] + patch; y++) {
        for (var x = origin[0]; x < origin[0] + patch; x++) {
          sr += r(x, y);
          sg += g(x, y);
          sb += b(x, y);
          n++;
        }
      }
    }
    return [sr ~/ n, sg ~/ n, sb ~/ n];
  }
}

// ---------------------------------------------------------------------------
// Locating the dumbbell
// ---------------------------------------------------------------------------

class _Band {
  const _Band(this.top, this.bottom);
  final int top;
  final int bottom;
  int get height => bottom - top + 1;
}

/// Contiguous row ranges holding subject pixels. A row needs more than
/// [minRun] subject pixels to count, which ignores stray JPEG speckle.
List<_Band> _contentBands(_Bitmap bmp, List<int> ground, {int minRun = 8}) {
  final bands = <_Band>[];
  int? start;
  for (var y = 0; y < bmp.height; y++) {
    var count = 0;
    for (var x = 0; x < bmp.width; x++) {
      if (bmp.distanceFrom(x, y, ground) > _keyHigh) count++;
    }
    final occupied = count > minRun;
    if (occupied && start == null) {
      start = y;
    } else if (!occupied && start != null) {
      bands.add(_Band(start, y - 1));
      start = null;
    }
  }
  if (start != null) bands.add(_Band(start, bmp.height - 1));
  return bands;
}

/// Horizontal extent of subject pixels within [band].
List<int> _horizontalExtent(_Bitmap bmp, List<int> ground, _Band band) {
  var left = bmp.width, right = -1;
  for (var y = band.top; y <= band.bottom; y++) {
    for (var x = 0; x < bmp.width; x++) {
      if (bmp.distanceFrom(x, y, ground) > _keyHigh) {
        if (x < left) left = x;
        if (x > right) right = x;
      }
    }
  }
  return [left, right];
}

// ---------------------------------------------------------------------------
// Keying
// ---------------------------------------------------------------------------

/// Crops [rect] out of [bmp] and lifts the ground to transparency.
///
/// RGB is premultiplied by the computed alpha because [ui.decodeImageFromPixels]
/// treats `rgba8888` as premultiplied; handing it straight alpha would leave a
/// bright halo on the partial edge pixels.
Future<ui.Image> _keyed(
  _Bitmap bmp,
  List<int> ground,
  int left,
  int top,
  int w,
  int h, {
  bool asWhite = false,
}) async {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final sx = left + x;
      final sy = top + y;
      final d = bmp.distanceFrom(sx, sy, ground);
      final t = ((d - _keyLow) / (_keyHigh - _keyLow)).clamp(0.0, 1.0);
      final a = (t * 255).round();
      final i = (y * w + x) * 4;
      if (asWhite) {
        out[i] = a;
        out[i + 1] = a;
        out[i + 2] = a;
      } else {
        out[i] = (bmp.r(sx, sy) * t).round();
        out[i + 1] = (bmp.g(sx, sy) * t).round();
        out[i + 2] = (bmp.b(sx, sy) * t).round();
      }
      out[i + 3] = a;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      out, w, h, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

/// Draws [mark] centred in a [size] square, scaled so its longer side spans
/// [fraction] of the canvas. [ground] fills the canvas first when given.
Future<void> _write(
  String path,
  ui.Image mark, {
  required int size,
  required double fraction,
  ui.Color? ground,
}) async {
  final side = size.toDouble();
  final bounds = ui.Rect.fromLTWH(0, 0, side, side);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, bounds);

  if (ground != null) {
    canvas.drawRect(bounds, ui.Paint()..color = ground);
  }

  final longest = math.max(mark.width, mark.height).toDouble();
  final scale = (side * fraction) / longest;
  final w = mark.width * scale;
  final h = mark.height * scale;

  canvas.drawImageRect(
    mark,
    ui.Rect.fromLTWH(0, 0, mark.width.toDouble(), mark.height.toDouble()),
    ui.Rect.fromLTWH((side - w) / 2, (side - h) / 2, w, h),
    // Medium, not none: this is a downscale, and nearest-neighbour would drop
    // whole source rows and chew the block edges. The art stays chunky because
    // each source block is still many pixels wide at output size.
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );

  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!.buffer.asUint8List());
  stdout.writeln('  wrote $path (${size}x$size)');
}

String _hex(List<int> rgb) =>
    '#${rgb.map((c) => c.toRadixString(16).padLeft(2, '0')).join()}'
        .toUpperCase()
        .replaceFirst('#', '#');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('derive OpenGym launcher artwork from $_source', () async {
    final bmp = await _Bitmap.decodeFile(_source);
    stdout.writeln('source ${bmp.width}x${bmp.height}');

    final ground = bmp.sampleGround();
    stdout.writeln('ground ${_hex(ground)}  rgb$ground');

    final bands = _contentBands(bmp, ground);
    stdout.writeln('content bands (top..bottom):');
    for (final band in bands) {
      stdout.writeln('  ${band.top}..${band.bottom}  h=${band.height}');
    }
    expect(bands, isNotEmpty, reason: 'no subject found against the ground');

    // Topmost band is the dumbbell; everything below it is the wordmark.
    final subject = bands.first;
    final extent = _horizontalExtent(bmp, ground, subject);
    final left = extent[0];
    final right = extent[1];
    stdout.writeln('dumbbell bbox  x $left..$right  y '
        '${subject.top}..${subject.bottom}');

    final w = right - left + 1;
    final h = subject.height;
    final colour = await _keyed(bmp, ground, left, subject.top, w, h);
    final white =
        await _keyed(bmp, ground, left, subject.top, w, h, asWhite: true);

    final groundColour =
        ui.Color.fromARGB(255, ground[0], ground[1], ground[2]);

    stdout.writeln('outputs:');
    await _write('logo/applogo.png', colour,
        size: 1024, fraction: _fullFraction, ground: groundColour);
    await _write('logo/applogo_foreground.png', colour,
        size: 1024, fraction: _adaptiveFraction);
    await _write('logo/applogo_monochrome.png', white,
        size: 1024, fraction: _adaptiveFraction);

    // How the masked adaptive icon will actually read on a launcher. The
    // effective fraction folds in the 16%-per-side inset the generated
    // ic_launcher.xml adds, so this previews the composited result rather than
    // the raw foreground layer.
    const previewFraction = _adaptiveFraction * 0.68;
    await _write('build/icon_preview/adaptive_144.png', colour,
        size: 144, fraction: previewFraction, ground: groundColour);
    await _write('build/icon_preview/adaptive_512.png', colour,
        size: 512, fraction: previewFraction, ground: groundColour);
    await _write('build/icon_preview/full_144.png', colour,
        size: 144, fraction: _fullFraction, ground: groundColour);
    // The monochrome layer is white on transparent, so it is only inspectable
    // over a dark ground - which is also how a themed launcher composites it.
    await _write('build/icon_preview/monochrome_on_dark.png', white,
        size: 512,
        fraction: previewFraction,
        ground: const ui.Color(0xFF1A1A1A));

    stdout.writeln('\nadaptive_icon_background: ${_hex(ground)}');
  });
}
