import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/plan_stats.dart';
import 'package:gymapp/widgets/dashboard/plan_status_tile.dart';
import 'package:gymapp/widgets/history/workout_details_widgets.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';
import 'package:gymapp/widgets/workout/set_entry_table.dart';

import 'support/hive_test_harness.dart';

const _capture = bool.fromEnvironment('UI_REVIEW_CAPTURE');

void main() {
  final harness = HiveTestHarness();
  final boundary = GlobalKey();
  final plan = WorkoutPlan(
    id: 'readable-plan',
    name: 'Push day',
    exercises: [
      ExerciseTemplate(
        name: 'Bench press',
        sets: 3,
        setTargets: [
          SetTemplate(weight: 100.25, reps: 8),
          SetTemplate(weight: 105.5, reps: 10),
          SetTemplate(weight: 110, reps: 12),
        ],
      ),
    ],
  );

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await harness.open();
    if (_capture) {
      final assets = <String, ByteData>{};
      for (final family in ['Manrope', 'JetBrainsMono']) {
        final bytes = ByteData.sublistView(
          File(
            'build/previews/${family == 'Manrope' ? 'manrope' : 'jetbrainsmono'}.ttf',
          ).readAsBytesSync(),
        );
        for (final weight in [
          'Regular',
          'Medium',
          'SemiBold',
          'Bold',
          'ExtraBold',
        ]) {
          assets['$family-$weight.ttf'] = bytes;
        }
      }
      await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      )).load();
      await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final manifest = const StandardMessageCodec().encodeMessage({
        for (final asset in assets.keys)
          asset: [
            {'asset': asset},
          ],
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final asset = utf8.decode(message!.buffer.asUint8List());
            return asset == 'AssetManifest.bin' ? manifest : assets[asset];
          });
      for (final weight in [
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w800,
      ]) {
        GoogleFonts.manrope(fontWeight: weight);
        GoogleFonts.jetBrainsMono(fontWeight: weight);
      }
      await GoogleFonts.pendingFonts();
    }
  });
  tearDownAll(harness.close);

  Widget host(
    Widget body,
    double scale, {
    Brightness brightness = Brightness.dark,
  }) => MaterialApp(
    theme: buildTheme(const Color(0xFF00A2FF), brightness),
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 41, vertical: 16),
        child: body,
      ),
    ),
  );

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/numeric_accessibility/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void readable(WidgetTester tester, Finder text, double scale) {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final span = paragraph.text as TextSpan;
    final size = span.style!.fontSize!;
    expect(paragraph.textScaler.scale(size), closeTo(size * scale, .01));
    final transform = paragraph.getTransformTo(null);
    expect(transform.storage[0], closeTo(1, .001));
    expect(transform.storage[5], closeTo(1, .001));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.height, greaterThanOrEqualTo(size * scale));
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    expect(paragraph.size.width, greaterThanOrEqualTo(painter.width - .01));
    painter.dispose();
  }

  void target(WidgetTester tester, Finder control) {
    final size = tester.getSize(control);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  }

  for (final width in [320.0, 1280.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final brightness in Brightness.values) {
        final label = '${width.toInt()}_${scale}_${brightness.name}';
        testWidgets('numeric controls are readable and reachable at $label', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, width < 600 ? 640 : 900);
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          final exercise = Exercise(
            name: 'Bench press',
            sets: [gym.Set(weight: 999.99, reps: 999, rpe: 10, note: 'PR')],
          );
          final session = WorkoutSession(
            planName: plan.name,
            date: DateTime(2026, 9, 28),
            exercises: [exercise],
            isCompleted: true,
          );
          final days = <WorkoutSession>[];
          await tester.pumpWidget(
            host(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SetEntryTable(
                    sets: const [
                      SetEntry(
                        weight: 999.99,
                        reps: 999,
                        previous: '997.5 × 999',
                        rpe: 10,
                        annotation: 'PR',
                      ),
                    ],
                    onChanged: (_, __, ___) {},
                    onDelete: (_) {},
                    onRpeChanged: (_, __) {},
                  ),
                  WorkoutExerciseDetails(exercise: exercise, weightUnit: 'kg'),
                  TrainingSnapshot(
                    plans: [plan],
                    sessions: [session],
                    now: DateTime(2026, 10, 2),
                    onOpenLastWorkout: days.add,
                  ),
                  PlanStatusTile(
                    stats: PlanStat.compute([plan], [session]),
                    onOpen: (_) {},
                  ),
                ],
              ),
              scale,
              brightness: brightness,
            ),
          );
          await tester.pumpAndSettle();
          final weight = find.bySemanticsLabel('Set 1 Kg');
          final reps = find.bySemanticsLabel('Set 1 Reps');
          for (final field in [
            weight,
            reps,
            find.bySemanticsLabel('Set 1 RPE value 10'),
          ]) {
            target(tester, field);
            await tester.ensureVisible(field);
            await tester.pumpAndSettle();
          }
          readable(
            tester,
            find.descendant(of: weight, matching: find.text('999.99')),
            scale,
          );
          readable(
            tester,
            find.descendant(of: reps, matching: find.text('999')),
            scale,
          );
          readable(
            tester,
            find.descendant(
              of: find.byType(SetEntryTable),
              matching: find.text('PR'),
            ),
            scale,
          );
          for (var day = 0; day < 7; day++) {
            target(tester, find.byKey(ValueKey('training-day-$day')));
          }
          final day = find.byKey(const ValueKey('training-day-0'));
          await tester.ensureVisible(day);
          await tester.tap(day);
          expect(days, [session]);
          final row = find.descendant(
            of: find.byType(PlanStatusTile),
            matching: find.byType(InkWell),
          );
          target(tester, row);
          final saved = find.descendant(
            of: find.byType(WorkoutExerciseDetails),
            matching: find.text('1000.0'),
          );
          readable(tester, saved, scale);
          await tester.ensureVisible(saved);
          await snapshot(tester, '${label}_saved_days');
          await tester.ensureVisible(weight);
          await snapshot(tester, '${label}_table');
          await tester.tap(weight);
          await tester.pumpAndSettle();
          final active = find.bySemanticsLabel('Set 1 Kg').last;
          expect(
            tester.getSemantics(active).getSemanticsData().value,
            '999.99 kilograms',
          );
          expect(
            tester.widget<Semantics>(active).properties.liveRegion,
            isTrue,
          );
          readable(
            tester,
            find.descendant(of: active, matching: find.text('999.99')),
            scale,
          );
          target(tester, active);
          target(tester, find.bySemanticsLabel('Set 1 Reps').last);
          for (final text in ['+2.5', '−2.5', '+1', '−1']) {
            target(tester, find.widgetWithText(TextButton, text));
            readable(
              tester,
              find.descendant(
                of: find.widgetWithText(TextButton, text),
                matching: find.text(text),
              ),
              scale,
            );
          }
          await snapshot(tester, '${label}_keypad_top');
          final save = find.descendant(
            of: find.bySemanticsLabel('Hide keypad'),
            matching: find.byType(TextButton),
          );
          await tester.ensureVisible(save);
          await snapshot(tester, '${label}_keypad_bottom');
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });

        testWidgets('plan prescription scales and wraps at $label', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, width < 600 ? 640 : 900);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(const Color(0xFF00A2FF), brightness),
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
              home: PlanEditorScreen.edit(plan),
            ),
          );
          await tester.pumpAndSettle();
          final summary = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.textSpan?.toPlainText().contains('8–12') == true,
          );
          expect(summary, findsOneWidget);
          await tester.ensureVisible(summary);
          final paragraph = tester.renderObject<RenderParagraph>(summary);
          expect(paragraph.textScaler.scale(13), closeTo(13 * scale, .01));
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.getTransformTo(null).storage[0], closeTo(1, .001));
          await snapshot(tester, '${label}_prescription');
          await tester.tap(find.text('Bench press'));
          await tester.pumpAndSettle();
          target(tester, find.bySemanticsLabel('Set 1 Kg'));
          target(tester, find.bySemanticsLabel('Set 1 Reps'));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'hardware typing validates values, announces changes, and stays scoped',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final changes = <(double, int)>[];
      final rpes = <int?>[];
      var finishes = 0;
      await tester.pumpWidget(
        host(
          SetEntryTable(
            sets: const [SetEntry(weight: 70, reps: 8, rpe: 7)],
            onChanged: (_, weight, reps) => changes.add((weight, reps)),
            onRpeChanged: (_, rpe) => rpes.add(rpe),
            onEntryFinished: () => finishes++,
          ),
          1,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
      await tester.pumpAndSettle();
      Future<void> key(LogicalKeyboardKey value, {String? character}) async {
        await tester.sendKeyEvent(value, character: character);
        await tester.pumpAndSettle();
      }

      await key(LogicalKeyboardKey.numpad5);
      await key(LogicalKeyboardKey.numpad0);
      await key(LogicalKeyboardKey.numpadDecimal);
      await key(LogicalKeyboardKey.digit2, character: '2');
      await key(LogicalKeyboardKey.digit5, character: '5');
      await key(LogicalKeyboardKey.digit9, character: '9');
      expect(changes.last, (50.25, 8));
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Set 1 Kg').last)
            .getSemanticsData()
            .value,
        '50.25 kilograms',
      );
      await key(LogicalKeyboardKey.backspace);
      expect(changes.last, (50.2, 8));
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.digit1, character: '1');
      await key(LogicalKeyboardKey.period, character: '.');
      await key(LogicalKeyboardKey.digit2, character: '2');
      expect(changes.last, (50.2, 12));
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Set 1 Reps').last)
            .getSemanticsData()
            .value,
        '12 repetitions',
      );
      await tester.tap(find.text('RPE').last);
      await tester.pumpAndSettle();
      await key(LogicalKeyboardKey.digit1, character: '1');
      await key(LogicalKeyboardKey.digit0, character: '0');
      await key(LogicalKeyboardKey.digit1, character: '1');
      expect(rpes, [1, 10]);
      await key(LogicalKeyboardKey.delete);
      expect(rpes.last, isNull);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Set 1 RPE'))
            .getSemanticsData()
            .value,
        'Not set',
      );
      await key(LogicalKeyboardKey.escape);
      expect(find.byType(BottomSheet), findsNothing);
      expect(finishes, 1);
      final count = changes.length;
      await key(LogicalKeyboardKey.digit9, character: '9');
      expect(changes.length, count);
      await tester.tap(find.bySemanticsLabel('Set 1 Reps'));
      await tester.pumpAndSettle();
      await key(LogicalKeyboardKey.digit6, character: '6');
      await key(LogicalKeyboardKey.numpadEnter);
      expect(find.byType(BottomSheet), findsNothing);
      expect(finishes, 2);
      semantics.dispose();
    },
  );
}
