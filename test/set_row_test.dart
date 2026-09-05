import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/theme/app_theme.dart';
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
  }) => MaterialApp(
    theme: buildTheme(const Color(0xFF00BCD4), brightness),
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
        for (final pair in {'KG': 'Set 1 Kg', 'REPS': 'Set 1 Reps'}.entries) {
          expect(
            tester.getCenter(find.text(pair.key)).dx,
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
        await tap(tester, '[CLOSE]');
      }
    }
  });

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
      for (final key in ['5', '0', '.', '2', '5']) {
        await tap(tester, key);
      }
      expect(entries[0].weight, 50.25);
      await tap(tester, '.');
      expect(entries[0].weight, 50.25);
      await tap(tester, '[DEL]');
      expect(entries[0].weight, 50.2);
      await tap(tester, '[+2.5 KG]');
      expect(entries[0].weight, 52.7);
      await tap(tester, '[-2.5 KG]');
      expect(entries[0].weight, 50.2);
      await tap(tester, '[NEXT]');
      expect(find.text('SET 1 OF 2 · REPS'), findsOneWidget);
      final decimal = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '.'),
      );
      expect(decimal.onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '[+2.5 KG]'))
            .onPressed,
        isNull,
      );
      await tap(tester, '1');
      await tap(tester, '2');
      expect(entries[0].reps, 12);
      await tap(tester, '[NEXT]');
      expect(find.text('SET 2 OF 2 · KG'), findsOneWidget);
      await tap(tester, '8');
      await tap(tester, '0');
      await tap(tester, '[NEXT]');
      await tap(tester, '6');
      await tap(tester, '[DONE]');
      expect(entries[1].weight, 80);
      expect(entries[1].reps, 6);
      expect(entries[0].previous, '65 × 8');
      expect(find.text('[CLOSE]'), findsNothing);
    },
  );

  testWidgets('close and back preserve edits without changing untouched sets', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      host(const [SetEntry(weight: 1, reps: 0)], (_, w, __) => changes.add(w)),
    );
    await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
    await tester.pumpAndSettle();
    await tap(tester, '[-2.5 KG]');
    expect(changes.last, 0);
    await tap(tester, '9');
    await tap(tester, '9');
    await tap(tester, '9');
    await tap(tester, '9');
    expect(changes.last, 999);
    await tap(tester, '[DEL]');
    expect(changes.last, 99);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('[CLOSE]'), findsNothing);
    expect(changes.last, 99);
  });

  testWidgets('light and dark keypad visual review', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          const [
            SetEntry(weight: 50, reps: 8, previous: '47.5 × 8'),
            SetEntry(weight: 50, reps: 8, previous: '47.5 × 7'),
            SetEntry(weight: 47.5, reps: 10),
          ],
          (_, __, ___) {},
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Set 2 Kg'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['OPENGYM_VISUAL_FONT'] != null) {
        await tester.runAsync(() => GoogleFonts.pendingFonts());
        await tester.pumpAndSettle();
      }
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
      await tap(tester, '[CLOSE]');
    }
  });
}
