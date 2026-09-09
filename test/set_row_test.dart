import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/semantic_colors.dart';
import 'package:gymapp/widgets/workout/set_entry_table.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Optional local font for readable visual QA; CI uses Flutter's test font.
    final fontPath = Platform.environment['OPENGYM_VISUAL_FONT'];
    if (fontPath != null) {
      final bytes = ByteData.sublistView(await File(fontPath).readAsBytes());
      final assets = {
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
          'Manrope-$weight.ttf': [
            {'asset': 'Manrope-$weight.ttf'},
          ],
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
          'JetBrainsMono-$weight.ttf': [
            {'asset': 'JetBrainsMono-$weight.ttf'},
          ],
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final key = utf8.decode(message!.buffer.asUint8List());
            if (key == 'AssetManifest.bin') {
              return const StandardMessageCodec().encodeMessage(assets);
            }
            if (assets.containsKey(key)) return bytes;
            return null;
          });
      for (final family in ['Ahem', 'Roboto']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });

  Widget host(
    List<SetEntry> entries,
    void Function(int, double, int) onChanged, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    bool showDetails = false,
    void Function(int, int?)? onRpeChanged,
    Color accentSeed = const Color(0xFF00BCD4),
  }) => MaterialApp(
    theme: buildTheme(accentSeed, brightness),
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
    home: Scaffold(
      appBar: AppBar(title: const Text('PUSH DAY')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SetEntryTable(
          exerciseName: 'Bench Press',
          sets: entries,
          onChanged: onChanged,
          onRpeChanged: onRpeChanged,
          onDetails: showDetails ? (_) {} : null,
        ),
      ),
    ),
  );

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('four columns align and entry fits compact and scaled screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          host(
            const [SetEntry(weight: 137.5, reps: 12, previous: '135 × 10')],
            (_, __, ___) {},
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (scale == 1) {
          expect(tester.getSize(find.bySemanticsLabel('Set 1 Kg')).height, 48);
          expect(
            tester.widget<Text>(find.text('135 × 10')).style!.fontSize,
            16,
          );
        }
        for (final pair in {'Kg': 'Set 1 Kg', 'Reps': 'Set 1 Reps'}.entries) {
          expect(
            tester.getCenter(find.text(pair.key, findRichText: true)).dx,
            closeTo(
              tester.getCenter(find.bySemanticsLabel(pair.value)).dx,
              0.1,
            ),
          );
          expect(
            tester.getSize(find.bySemanticsLabel(pair.value)).height,
            greaterThanOrEqualTo(48),
          );
        }
        await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(EditableText), findsNothing);
        expect(tester.testTextInput.isVisible, isFalse);
        final next = find.widgetWithText(TextButton, 'Next');
        final save = find.widgetWithText(TextButton, 'Save');
        expect(tester.getTopLeft(next).dy, tester.getTopLeft(save).dy);
        expect(tester.getCenter(next).dx, lessThan(tester.getCenter(save).dx));
        expect(
          tester.widget<TextButton>(next).style?.backgroundColor?.resolve({}),
          isNot(
            tester.widget<TextButton>(save).style?.backgroundColor?.resolve({}),
          ),
        );
        await tap(tester, 'Save');
      }
    }
  });

  testWidgets('RPE 10 stays on one line inside the 48 pixel details action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          host(
            const [SetEntry(weight: 100, reps: 10, rpe: 10)],
            (_, __, ___) {},
            scale: scale,
            showDetails: true,
          ),
        );
        await tester.pumpAndSettle();

        final effort = find.text('@10');
        final effortText = tester.widget<Text>(effort);
        final action = find.ancestor(
          of: effort,
          matching: find.byType(IconButton),
        );

        expect(effortText.maxLines, 1);
        expect(effortText.softWrap, isFalse);
        expect(tester.getSize(action), const Size(48, 48));
        expect(
          tester.getRect(action).contains(tester.getRect(effort).center),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'workout rows show a compact RPE field for every value, accent, and theme',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        for (final accent in SettingsProvider.accents) {
          for (var rpe = 1; rpe <= 10; rpe++) {
            await tester.pumpWidget(
              host(
                [SetEntry(weight: 137.5, reps: 12, rpe: rpe)],
                (_, __, ___) {},
                brightness: brightness,
                accentSeed: accent.seed,
                onRpeChanged: (_, __) {},
              ),
            );
            await tester.pumpAndSettle();

            final reps = find.bySemanticsLabel('Set 1 Reps');
            final effort = find.bySemanticsLabel('Set 1 RPE value $rpe');
            final effortText = find.descendant(
              of: effort,
              matching: find.text('@$rpe'),
            );
            final context = tester.element(effortText);

            expect(
              tester.getSize(reps).width,
              lessThan(tester.getSize(find.bySemanticsLabel('Set 1 Kg')).width),
            );
            expect(
              tester.widget<Text>(effortText).style!.color,
              rpeColor(rpe, context),
            );
            expect(
              tester.widget<Text>(effortText).style!.fontSize,
              Theme.of(context).textTheme.labelLarge!.fontSize,
            );
            expect(
              find.descendant(
                of: effort,
                matching: find.byWidgetPredicate(
                  (widget) => widget is Container && widget.decoration != null,
                ),
              ),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets(
    'replacement, decimals, delete, adjustment and next preserve each set',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      final entries = [
        const SetEntry(weight: 70, reps: 8, previous: '65 × 8'),
        const SetEntry(weight: 60, reps: 10),
      ];
      await tester.pumpWidget(
        host(entries, (i, weight, reps) {
          entries[i] = SetEntry(
            weight: weight,
            reps: reps,
            previous: entries[i].previous,
          );
        }),
      );
      await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
      await tester.pumpAndSettle();
      final adjustment = tester.getSize(
        find.widgetWithText(OutlinedButton, '+2.5'),
      );
      final digit = tester.getSize(find.widgetWithText(TextButton, '1'));
      expect(adjustment.width, lessThan(digit.width));
      expect(digit.width, greaterThan(90));
      for (final key in ['5', '0', '.', '2', '5']) {
        await tap(tester, key);
      }
      expect(entries[0].weight, 50.25);
      await tap(tester, '.');
      expect(entries[0].weight, 50.25);
      await tester.tap(find.bySemanticsLabel('Delete digit'));
      await tester.pumpAndSettle();
      expect(entries[0].weight, 50.2);
      await tap(tester, '+2.5');
      expect(entries[0].weight, 52.7);
      await tap(tester, '−2.5');
      expect(entries[0].weight, 50.2);
      await tap(tester, '+1');
      expect(entries[0].weight, 51.2);
      await tap(tester, '−1');
      expect(entries[0].weight, 50.2);
      await tap(tester, 'Next');
      expect(
        tester
            .widget<Semantics>(find.bySemanticsLabel('Set 1 Reps').last)
            .properties
            .selected,
        isTrue,
      );
      final decimal = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '.'),
      );
      expect(decimal.onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+2.5'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '+1'))
            .onPressed,
        isNotNull,
      );
      await tap(tester, '1');
      await tap(tester, '2');
      expect(entries[0].reps, 12);
      await tap(tester, '+1');
      expect(entries[0].reps, 13);
      await tap(tester, '−1');
      expect(entries[0].reps, 12);
      await tap(tester, 'Next');
      expect(
        tester
            .widget<Semantics>(find.bySemanticsLabel('Set 2 Kg').last)
            .properties
            .selected,
        isTrue,
      );
      await tap(tester, '8');
      await tap(tester, '0');
      await tap(tester, 'Next');
      await tap(tester, '6');
      final finalNext = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Next'),
      );
      expect(finalNext.onPressed, isNull);
      await tap(tester, 'Save');
      expect(entries[1].weight, 80);
      expect(entries[1].reps, 6);
      expect(entries[0].previous, '65 × 8');
      expect(find.text('Save'), findsNothing);
    },
  );

  testWidgets('save and back preserve edits without changing untouched sets', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      host(const [SetEntry(weight: 1, reps: 0)], (_, w, __) => changes.add(w)),
    );
    await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
    await tester.pumpAndSettle();
    await tap(tester, '−2.5');
    expect(changes.last, 0);
    await tap(tester, '9');
    await tap(tester, '9');
    await tap(tester, '9');
    await tap(tester, '9');
    expect(changes.last, 999);
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();
    expect(changes.last, 99);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    expect(changes.last, 99);
  });

  testWidgets('light and dark keypad visual review', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          const [
            SetEntry(weight: 50, reps: 8, previous: '47.5 × 8', rpe: 5),
            SetEntry(weight: 50, reps: 8, previous: '47.5 × 7', rpe: 8),
            SetEntry(weight: 47.5, reps: 10, rpe: 10),
          ],
          (_, __, ___) {},
          brightness: brightness,
          onRpeChanged: (_, __) {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Set 2 Kg'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/set-entry-${brightness.name}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await tap(tester, 'Save');
    }
  });

  testWidgets('workout keypad edits and clears RPE without changing values', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final entries = [
      const SetEntry(weight: 70, reps: 8, previous: '65 × 8', rpe: 7),
      const SetEntry(weight: 72.5, reps: 6, previous: '70 × 6'),
    ];
    final changes = <int?>[];
    await tester.pumpWidget(
      host(
        entries,
        (_, __, ___) {},
        onRpeChanged: (index, rpe) {
          entries[index] = SetEntry(
            weight: entries[index].weight,
            reps: entries[index].reps,
            previous: entries[index].previous,
            rpe: rpe,
          );
          changes.add(rpe);
        },
      ),
    );
    await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
    await tester.pumpAndSettle();
    expect(find.text('RPE'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Set 1 RPE 7'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('RPE 8'), findsNothing);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, '.')).onPressed,
      isNull,
    );
    for (final label in ['+2.5', '−2.5', '+1', '−1']) {
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    await tap(tester, '1');
    await tap(tester, '0');
    expect(changes, [1, 10]);
    await tap(tester, '9');
    expect(changes, [1, 10]);
    expect(entries[0].weight, 70);
    expect(entries[0].reps, 8);
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();
    expect(changes, [1, 10, 1]);
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();
    expect(changes, [1, 10, 1, null]);
    expect(find.bySemanticsLabel('Set 1 RPE, not set'), findsOneWidget);
    await tap(tester, '0');
    expect(changes, [1, 10, 1, null]);
    await tap(tester, 'Next');
    expect(
      tester
          .widget<Semantics>(find.bySemanticsLabel('Set 2 Kg').last)
          .properties
          .selected,
      isTrue,
    );
    expect(entries[1].weight, 72.5);
    expect(entries[1].reps, 6);
  });
}
