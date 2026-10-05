import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/set_entry_table.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (!const bool.fromEnvironment('CAPTURE_KEYPAD')) return;
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
  });

  testWidgets('compact keypad edits original fields and copies to next set', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    var entries = const [
      SetEntry(weight: 70, reps: 8, rpe: 7),
      SetEntry(
        weight: 60,
        reps: 6,
        previous: '55 × 6',
        annotation: 'Keep note',
      ),
    ];
    var finishes = 0;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(const Color(0xFF00BCD4), Brightness.dark),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                void change(
                  int index, {
                  double? weight,
                  int? reps,
                  int? rpe,
                  bool effort = false,
                }) {
                  update(() {
                    final previous = entries[index];
                    entries = List.of(entries);
                    entries[index] = SetEntry(
                      weight: weight ?? previous.weight,
                      reps: reps ?? previous.reps,
                      rpe: effort ? rpe : previous.rpe,
                      previous: previous.previous,
                      annotation: previous.annotation,
                    );
                  });
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Workout'),
                    SetEntryTable(
                      continuousLog: true,
                      sets: entries,
                      onChanged: (i, w, r) => change(i, weight: w, reps: r),
                      onRpeChanged:
                          (i, rpe) => change(i, rpe: rpe, effort: true),
                      onEntryFinished: () => finishes++,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Set 1 Kg'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height, closeTo(280, 1));
    expect(
      tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .every((barrier) => barrier.color == null),
      isTrue,
    );
    expect(find.textContaining('Previous:'), findsNothing);
    expect(find.text('70'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('70')).style!.backgroundColor,
      isNotNull,
    );
    final one = tester.getCenter(find.widgetWithText(TextButton, '1'));
    final two = tester.getCenter(find.widgetWithText(TextButton, '2'));
    final three = tester.getCenter(find.widgetWithText(TextButton, '3'));
    expect(one.dx, lessThan(two.dx));
    expect(two.dx, lessThan(three.dx));
    expect(tester.getCenter(find.text('+2.5')).dy, one.dy);
    expect(tester.getCenter(find.widgetWithText(TextButton, 'RPE')).dy, one.dy);
    if (const bool.fromEnvironment('CAPTURE_KEYPAD')) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/compact_keypad.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();
    final field = find.bySemanticsLabel('Set 1 Kg');
    final cursor = find.descendant(
      of: field,
      matching: find.byType(ColoredBox),
    );
    final firstColor = tester.widget<ColoredBox>(cursor).color;
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<ColoredBox>(cursor).color, isNot(firstColor));
    await tester.tap(find.widgetWithText(TextButton, '5'));
    await tester.pumpAndSettle();
    expect(entries[0].weight, 5);
    await tester.ensureVisible(find.bySemanticsLabel('Set 1 Reps'));
    await tester.tap(find.bySemanticsLabel('Set 1 Reps'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '9'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Copy'));
    await tester.pumpAndSettle();
    expect((entries[1].weight, entries[1].reps, entries[1].rpe), (5, 9, 7));
    expect(entries[1].previous, '55 × 6');
    expect(entries[1].annotation, 'Keep note');
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Copy'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(finishes, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching exercises leaves one keypad and structural edits close it',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      var second = const [SetEntry(weight: 60, reps: 8)];
      var finishes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder:
                  (context, update) => ListView(
                    children: [
                      SetEntryTable(
                        sets: const [SetEntry(weight: 70, reps: 10)],
                        onChanged: (_, _, _) {},
                        onEntryFinished: () => finishes++,
                      ),
                      SetEntryTable(
                        sets: second,
                        onChanged: (_, _, _) {},
                        onEntryFinished: () => finishes++,
                      ),
                      TextButton(
                        onPressed:
                            () => update(
                              () =>
                                  second = [
                                    ...second,
                                    const SetEntry(weight: 0, reps: 0),
                                  ],
                            ),
                        child: const Text('Add test set'),
                      ),
                    ],
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Set 1 Kg').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '5'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Set 1 Kg').last);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(finishes, 1);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.bySemanticsLabel('Set 1 Kg').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add test set'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
