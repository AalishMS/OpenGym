import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/theme/app_theme.dart';

import 'support/hive_test_harness.dart';

/// Renders the History journal with realistic data in both themes. Run with
/// `--dart-define=HISTORY_PREVIEW=true` to also write PNGs to build/previews.
void main() {
  final hiveHarness = HiveTestHarness();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await hiveHarness.open();
  });
  tearDownAll(() => hiveHarness.close());
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  WorkoutSession session(
    String id,
    String name,
    DateTime date,
    Map<String, int> exercises, {
    int? duration,
    double weight = 60,
  }) => WorkoutSession(
    id: id,
    planName: name,
    date: date,
    splitId: 'a',
    weekNumber: 3,
    durationSeconds: duration,
    exercises: [
      for (final entry in exercises.entries)
        Exercise(
          name: entry.key,
          sets: [
            for (var i = 0; i < entry.value; i++)
              Set(reps: 8, weight: weight + i * 2.5),
          ],
        ),
    ],
  );

  testWidgets('journal renders in both themes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1100);
    addTearDown(tester.view.reset);
    const capture = bool.fromEnvironment('HISTORY_PREVIEW');
    if (capture) await _loadPreviewFonts();
    final sessions = [
      session(
        'a1',
        'Upper Body',
        DateTime(2026, 11, 3, 18),
        {
          'Bench Press': 4,
          'Barbell Row': 4,
          'Overhead Press': 3,
          'Lat Pulldown': 3,
        },
        duration: 3900,
        weight: 70,
      ),
      session('a2', 'Mobility', DateTime(2026, 11, 3, 7), {
        'Hip Flexor Stretch': 0,
      }),
      session(
        'a3',
        'Lower Body',
        DateTime(2026, 11, 1, 10),
        {
          'Back Squat': 5,
          'Romanian Deadlift': 4,
          'Leg Press': 3,
          'Walking Lunge': 3,
          'Calf Raise': 4,
        },
        duration: 4500,
        weight: 90,
      ),
      session('b1', 'Push Day', DateTime(2026, 10, 29, 18), {
        'Incline Bench Press': 4,
        'Dips': 3,
        'Lateral Raise': 4,
      }, duration: 2700),
      session(
        'b2',
        'Pull Day',
        DateTime(2026, 10, 27, 18),
        {'Deadlift': 3, 'Pull Up': 4},
        duration: 3000,
        weight: 100,
      ),
    ];
    for (final (brightness, scale) in [
      (Brightness.light, 1.0),
      (Brightness.dark, 1.0),
      (Brightness.light, 1.6),
    ]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MultiProvider(
          key: UniqueKey(),
          providers: [
            ChangeNotifierProvider<WorkoutSessionProvider>(
              create: (_) => _Sessions(sessions),
            ),
            ChangeNotifierProvider<SettingsProvider>(
              create: (_) => SettingsProvider(),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF008D8D), brightness),
            home: RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 1100),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const HistoryScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (capture) {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/previews/history').create(recursive: true);
          await File(
            'build/previews/history/history_${brightness.name}${scale == 1 ? '' : '_large'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> values;
  _Sessions(this.values);
  @override
  List<WorkoutSession> get sessions => values;
  @override
  String? get activeSplitId => 'a';
}

/// Serves the real Manrope weights from build/previews/fonts to google_fonts.
Future<void> _loadPreviewFonts() async {
  await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
    rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
  )).load();
  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'];
  final manifest = const StandardMessageCodec().encodeMessage({
    for (final weight in weights)
      'Manrope-$weight.ttf': [
        {'asset': 'Manrope-$weight.ttf'},
      ],
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final asset = utf8.decode(message!.buffer.asUint8List());
        if (asset == 'AssetManifest.bin') return manifest;
        if (asset.startsWith('Manrope-')) {
          return ByteData.sublistView(
            File('build/previews/fonts/$asset').readAsBytesSync(),
          );
        }
        return null;
      });
  for (final weight in [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
  ]) {
    GoogleFonts.manrope(fontWeight: weight);
  }
  await GoogleFonts.pendingFonts();
}
