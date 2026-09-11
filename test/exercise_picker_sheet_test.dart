import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/spacing.dart';
import 'package:gymapp/widgets/exercise_picker_sheet.dart';

class _PickerHarness extends StatefulWidget {
  final List<String> initialNames;

  const _PickerHarness({this.initialNames = const []});

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  late final List<String> names = List<String>.from(widget.initialNames);

  void _showPicker() {
    showExercisePickerSheet(
      context,
      selectedExerciseNames: names,
      onAdd: (name) => setState(() => names.add(name)),
      onRemove:
          (name) => setState(
            () => names.removeWhere(
              (selected) => selected.toLowerCase() == name.toLowerCase(),
            ),
          ),
      selectionOwner: 'test workout',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: _showPicker,
          child: const Text('Open picker'),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<GlobalKey> pumpPicker(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    double keyboardInset = 0,
    Brightness brightness = Brightness.light,
    List<String> initialNames = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00A2FF), brightness),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                viewInsets: EdgeInsets.only(bottom: keyboardInset),
              ),
              child: RepaintBoundary(key: captureKey, child: child!),
            ),
        home: _PickerHarness(initialNames: initialNames),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    return captureKey;
  }

  testWidgets('adapts to narrow width, large text, and keyboard insets', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      size: const Size(320, 700),
      textScale: 1.5,
      keyboardInset: 240,
    );

    expect(find.text('Add exercises'), findsOneWidget);
    expect(find.text('Selected (0)'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.text('Done')).dy, lessThan(700 - 240));
  });

  testWidgets('selected exercise highlight stays clear of row dividers', (
    tester,
  ) async {
    await pumpPicker(tester, initialNames: const ['Bench Press']);
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();

    final selectedRow = find.ancestor(
      of: find.text('Bench Press'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color != null,
      ),
    );
    final container = tester.widget<Container>(selectedRow.first);

    expect(
      container.margin,
      const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    );
  });

  testWidgets('renders picker states for visual inspection', (tester) async {
    final output = Platform.environment['OPENGYM_PICKER_PREVIEW_DIR'];

    Future<void> capture(GlobalKey key, String name) async {
      if (output == null) return;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    var key = await pumpPicker(
      tester,
      initialNames: const ['Bench Press', 'Cable Halo'],
    );
    await capture(key, 'picker-groups-light');

    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    await capture(key, 'picker-category-light');

    await tester.enterText(find.byType(TextField), 'row');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await capture(key, 'picker-search-light');

    await tester.tap(find.text('Selected (2)'));
    await tester.pumpAndSettle();
    await capture(key, 'picker-selected-light');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    key = await pumpPicker(
      tester,
      brightness: Brightness.dark,
      initialNames: const ['Bench Press', 'Cable Halo'],
    );
    await capture(key, 'picker-groups-dark');
    expect(tester.takeException(), isNull);
  });
}
